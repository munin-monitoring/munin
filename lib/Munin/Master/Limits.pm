package Munin::Master::Limits;

use warnings;
use strict;

use Exporter;

our (@ISA, @EXPORT);
@ISA    = qw ( Exporter );
@EXPORT = qw ( limits_startup limits_main );

use POSIX qw ( strftime WNOHANG );
use Getopt::Long;
use Time::HiRes;
use Text::Balanced qw ( extract_bracketed );
use Scalar::Util qw( looks_like_number );
use File::Spec;
use Munin::Common::Logger;
use Munin::Common::Defaults;
use Munin::Master::Config;
# Parens = load, import nothing. Utils' @EXPORT includes
# print_version_and_exit, which would collide with the specific one below
# (and its generic "munin version ..." text is wrong for munin-limits
# anyway). The single real Utils call is fully-qualified at its use site.
use Munin::Master::Utils ();
use RRDs;

use Munin::Master::Update;

my $DEBUG          = 0;
my $VERBOSE        = 0;
my $do_usage       = 0;
my $do_version     = 0;
my @limit_hosts    = ();
my @limit_services = ();
my @limit_contacts = ();
my @always_send    = ();
my $screen         = 0;
my $force          = 0;
my $force_run_as_root = 0;

# PL3 deviation: these template strings are data, not code — breaking them would harm readability
my %default_text = (
    "default" =>
        '${var:group} :: ${var:host} :: ${var:graph_title}${if:cfields \n\tCRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields \n\tWARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields \n\tUNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields \n\tOKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}\n',
    "nagios" =>
        '${var:host}\t${var:graph_title}\t${var:worstid}\t${strtrunc:350 ${if:cfields CRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields WARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields UNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields OKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}}',
    "old-nagios" =>
        '${var:host}\t${var:plugin}\t${var:worstid}\t${strtrunc:350 ${var:graph_title}:${if:cfields CRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields WARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields UNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields OKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}}',
);


# CLI/config entry point for the standalone script. Restored from the
# pre-SQL rewrite: script/munin-limits calls this before limits_main and
# the rewrite had dropped it, breaking the script at startup.
sub limits_startup {
    my ($args) = @_;
    local @ARGV = @{$args};

    my $conffile = "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf";

    $do_usage = 1 unless GetOptions(
        "host=s"        => \@limit_hosts,
        "service=s"     => \@limit_services,
        "contact=s"     => \@limit_contacts,
        "config=s"      => \$conffile,
        "debug"         => \$DEBUG,
        "verbose"       => \$VERBOSE,
        "screen"        => \$screen,
        "force!"        => \$force,
        "always-send=s" => \@always_send,
        "force-run-as-root!" => \$force_run_as_root,
        "version!"      => \$do_version,
        "help"          => \$do_usage,
    );

    print_usage_and_exit()   if $do_usage;
    print_version_and_exit() if $do_version;

    if ($DEBUG || $screen) {
        my %log;
        $log{output} = 'screen' if $screen;
        $log{level}  = 'debug'  if $DEBUG;
        Munin::Common::Logger::configure(%log);
    }

    Munin::Master::Utils::exit_if_run_by_super_user() unless $force_run_as_root;

    @always_send = qw{ok warning critical unknown} if $force;

    # Everything below runs off SQL, but get_dbh() and the fork decision
    # read dbdir/fork/max_processes from the config singleton.
    my $globconfig = Munin::Master::Config->instance();
    my $config = $globconfig->{config};
    $config->parse_config_from_file($conffile);
}


sub print_usage_and_exit {
    print "Usage: $0 [options]

Options:
    --help          View this message.
    --debug         View debug messages.
    --screen        Send log messages to the screen (STDERR).
    --always-send <severity list>
                    Send messages to contacts even if state has
                    not changed since the last run. The list is a
                    space or comma separated list of severities.
                    Choose from one or more of \"critical\",
                    \"warning\", \"unknown\" and \"ok\".
    --force         Alias for \"--always-send ok,warning,critical,unknown\".
    --service <service>     Limit notified services to <service>.
    --host <host>           Limit notified hosts to <host>.
    --contact <contact>     Limit notified contacts to <contact>.
    --config <file> Use <file> as configuration file.
                    [$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf]

";
    exit 0;
}


sub print_version_and_exit {
    print "munin-limits $Munin::Common::Defaults::MUNIN_VERSION\n";
    exit 0;
}


# Three phases, cleanly separated:
#
#   1. Work list:  per-host list of services having threshold-ed ds,
#                  built in memory. The dbh is closed before returning --
#                  no handle may be open when phase 2 forks.
#   2. Evaluation: per-host (Parallel::ForkManager, or inline when
#                  fork=0). Each child opens its own R/W dbh, evaluates
#                  ds thresholds, writes state (alarm, num_unknowns,
#                  prev_alarm, eval_value, extinfo), closes. NO
#                  notification logic in children.
#   3. Delivery:   serial tail in the master. Reads results FROM the DB
#                  (state IS the transport between phases), builds
#                  messages, resolves contacts, delivers -- contacts
#                  serialized, one mailer per contact, sequential.
#
# The DB is the only channel between phases: it works identically when
# phase 2 runs inline (fork=0, as tests do) and when it forks.
sub limits_main {
    $SIG{PIPE} = 'IGNORE';

    my $update_time = Time::HiRes::time;
    INFO "Starting limits";

    my $work = _build_work_list();
    _evaluate_limits($work);
    _deliver_notifications($work);

    _close_pipes();

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));
    INFO "Limits finished ($update_time sec)";
}


# Phase 1: per-host work list, in memory. Opens one handle, threads it,
# closes it -- fork() in phase 2 must see no open handle.
sub _build_work_list {
    my $dbh = Munin::Master::Update::get_dbh();

    # Hosts having services with at least one DS with warning or critical
    my $sth = $dbh->prepare_cached(q{
        SELECT DISTINCT n.name AS node_name, g.path AS group_path,
               s.id AS service_id, s.name AS service_name
        FROM service s
        INNER JOIN node n ON n.id = s.node_id
        INNER JOIN grp g ON g.id = n.grp_id
        INNER JOIN ds d ON d.service_id = s.id
        INNER JOIN ds_attr da ON da.id = d.id
        WHERE da.name IN ('warning', 'critical')
          AND da.value IS NOT NULL
          AND da.value != ''
        ORDER BY n.name, s.name
    });
    $sth->execute();

    my %by_node;
    while (my ($node_name, $group_path, $service_id, $service_name) = $sth->fetchrow_array) {
        next if @limit_hosts    && !grep { $_ eq $node_name } @limit_hosts;
        next if @limit_services && !grep { $_ eq $service_name } @limit_services;
        push @{$by_node{$node_name}{services}}, {
            service_id   => $service_id,
            service_name => $service_name,
        };
        $by_node{$node_name}{group_path} //= $group_path;
    }

    $dbh->disconnect();

    return [
        map {
            { node_name => $_, %{$by_node{$_}} }
        } sort keys %by_node
    ];
}


# Phase 2: per-host threshold evaluation. Children write state only.
sub _evaluate_limits {
    my ($work) = @_;

    return unless @{$work};

    my $config = Munin::Master::Config->instance()->{config};
    my $max_processes = $config->{max_processes} || 16;

    # Do NOT fork if not set (tests run inline with fork=0)
    unless ($config->{fork}) {
        my $dbh = Munin::Master::Update::get_dbh();
        _process_host($dbh, $_) for @{$work};
        $dbh->disconnect();
        return;
    }

    use Parallel::ForkManager;

    my $pm = Parallel::ForkManager->new($max_processes);

    # Handle child process failures
    my $nb_workers_failed = 0;
    $pm->run_on_finish(
        sub {
            my ($pid, $exit_code) = @_;

            $exit_code = 0 unless defined $exit_code;
            INFO "limits host worker pid:$pid, exit_code:$exit_code";

            $nb_workers_failed++ if $exit_code;
        }
    );

    HOST_LOOP:
    for my $host (@{$work}) {
        my $host_pid = $pm->start($host);
        next HOST_LOOP if $host_pid;

        # Child: own handle, no notifications, results via the DB
        my $res = eval {
            my $dbh = Munin::Master::Update::get_dbh();
            _process_host($dbh, $host);
            $dbh->disconnect();
            1;
        };
        WARN "limits evaluation failed for $host->{node_name}: $@" unless $res;

        $pm->finish($res ? 0 : 1);    # never returns in the child
    }

    $pm->wait_all_children;
}


# Evaluate thresholds for every service of one host
sub _process_host {
    my ($dbh, $host) = @_;

    for my $svc (@{$host->{services}}) {
        _process_service(
            $dbh, $svc->{service_id}, $svc->{service_name},
            $host->{node_name}, $host->{group_path}
        );
    }
}


# Evaluate thresholds for a single service. Writes state; builds no
# messages -- the serial tail rebuilds everything from the DB.
sub _process_service {
    my ($dbh, $service_id, $service_name, $node_name, $group_path) = @_;

    DEBUG "processing service: $service_name";

    # All DS of this service
    my $sth_ds = $dbh->prepare_cached(q{
        SELECT d.id, d.name, d.type
        FROM ds d
        WHERE d.service_id = ? AND d.deleted = 0
        ORDER BY d.ordr
    });
    $sth_ds->execute($service_id);

    my @ds;
    while (my ($ds_id, $ds_name, $ds_type) = $sth_ds->fetchrow_array) {
        push @ds, [$ds_id, $ds_name, $ds_type];
    }

    # ds_attr and override fetched ONCE per service, not per ds/check:
    # the dominant DBI bucket was ~60k single-row attr fetches per run.
    my (%attrs, %overrides);
    if (@ds) {
        my $in = join ',', ('?') x scalar @ds;
        my @ids = map { $_->[0] } @ds;

        my $sth_attr = $dbh->prepare_cached("SELECT id, name, value FROM ds_attr WHERE id IN ($in)");
        $sth_attr->execute(@ids);
        while (my ($id, $k, $v) = $sth_attr->fetchrow_array) {
            $attrs{$id}{$k} = $v;
        }

        my $sth_ov = $dbh->prepare_cached("SELECT ds_id, name, value FROM override WHERE ds_id IN ($in)");
        $sth_ov->execute(@ids);
        while (my ($id, $k, $v) = $sth_ov->fetchrow_array) {
            $overrides{$id}{$k} = $v;
        }
    }

    for my $d (@ds) {
        my ($ds_id, $ds_name, $ds_type) = @$d;
        my %merged = %{$attrs{$ds_id} // {}};
        @merged{keys %{$overrides{$ds_id} // {}}} = values %{$overrides{$ds_id} // {}};

        _process_ds($dbh, $ds_id, $ds_name, $ds_type, \%merged);
    }

    $dbh->commit();
}


# Evaluate thresholds for a single DS and upsert state.
# State columns are the phase-2 -> phase-3 transport:
#   alarm       current evaluation result
#   prev_alarm  alarm before this evaluation (edge detection:
#               alarm != prev_alarm == state just changed)
#   eval_value  the evaluated value shown in messages
#   extinfo     threshold-violation detail shown in messages
sub _process_ds {
    my ($dbh, $ds_id, $ds_name, $ds_type, $attrs) = @_;

    my $warn_str = $attrs->{warning};
    my $crit_str = $attrs->{critical};

    # Skip if no thresholds
    return unless defined $warn_str || defined $crit_str;

    # --------------------------------------------------------------------
    # CDEF fields: compute value via RRDs::xport.
    #
    # WHY COMPUTE HERE (at limits time)?
    # - Update phase is time-critical (must finish in update_rate)
    # - Limits phase is async, less time-sensitive
    # - Only services with CDEF thresholds pay the xport cost
    # - RRDs::xport auto-flushes rrdcached (FETCH implies flush)
    #
    # WHAT WE STORE:
    # - state.last_value: computed CDEF value (for HTML/graph display)
    # - state.alarm: threshold evaluation result (ok/warning/critical)
    # - This makes CDEF values queryable like any other DS
    # --------------------------------------------------------------------
    my $value;
    my $is_cdef = defined $attrs->{cdef} && $attrs->{cdef} ne '';
    if ($is_cdef) {
        $value = _compute_cdef_value($dbh, $ds_id, $attrs->{cdef});
        # Store computed value immediately so HTML/graphs can show it
        # even if threshold evaluation hasn't run yet
        if (defined $value) {
            my $sth_store = $dbh->prepare_cached(q{
                UPDATE state SET last_value = ?, last_epoch = ?
                WHERE ds_id = ?
            });
            $sth_store->execute(sprintf('%.6f', $value), time(), $ds_id);
        }
    }

    # Parse thresholds
    my ($warn, $crit) = _parse_thresholds($warn_str, $crit_str);
    return unless defined $warn || defined $crit;

    # Read state from SQL (single row per ds; selectrow_array finishes the
    # cursor so the next prepare_cached sees no active statement)
    my ($last_epoch, $last_value, $prev_epoch, $prev_value, $old_state, $old_num_unknowns)
        = $dbh->selectrow_array(q{
        SELECT last_epoch, last_value, prev_epoch, prev_value, alarm, num_unknowns
        FROM state WHERE ds_id = ?
    }, undef, $ds_id);

    $old_state       //= 'ok';
    $old_num_unknowns //= 0;

    # Compute current value for non-CDEF fields
    my $heartbeat = 600;
    unless (defined $value) {  # Skip if already computed (CDEF case)
        if (!defined $last_value || $last_value eq 'U') {
            $value = 'U';
        } elsif (time > $last_epoch + $heartbeat) {
            $value = 'U';
        } elsif (!$ds_type || $ds_type eq 'GAUGE') {
            $value = $last_value;
        } elsif (!defined $prev_value || $prev_value eq 'U') {
            $value = 'U';
        } elsif ($last_epoch == $prev_epoch || $last_epoch > $prev_epoch + $heartbeat) {
            $value = 'U';
        } elsif ($ds_type eq 'ABSOLUTE') {
            $value = $last_value / ($last_epoch - $prev_epoch);
        } elsif ($ds_type eq 'COUNTER' && $last_value < $prev_value) {
            $value = 'U';
        } else {
            $value = ($last_value - $prev_value) / ($last_epoch - $prev_epoch);
        }
    }

    # De-taint
    if (!defined $value || $value eq 'U') {
        $value = 'unknown';
    } elsif (looks_like_number($value)) {
        $value = sprintf '%.6f', $value;
    } else {
        $value = 'unknown';
    }

    # Evaluate thresholds
    my $new_state = 'ok';
    my $new_num_unknowns = 0;
    my $extinfo = '';

    my $unknown_limit = defined $attrs->{unknown_limit} ? $attrs->{unknown_limit} : 3;

    if ($value eq 'unknown') {
        $new_state = 'unknown';
        $extinfo = $attrs->{extinfo} // 'Value is unknown.';
        if ($old_state ne 'unknown') {
            $new_num_unknowns = $old_num_unknowns + 1;
            if ($old_num_unknowns < $unknown_limit) {
                $new_state = $old_state;
                $extinfo = $attrs->{extinfo} // '';
            }
        } else {
            $new_num_unknowns = $old_num_unknowns;
        }
    } elsif (defined $crit) {
        my $crange = ($crit->[0] // '') . ':' . ($crit->[1] // '');
        if ((defined $crit->[0] && $value < $crit->[0]) ||
            (defined $crit->[1] && $value > $crit->[1])) {
            $new_state = 'critical';
            $extinfo = defined $attrs->{extinfo}
                ? "$value (not in $crange): $attrs->{extinfo}"
                : "Value is $value. Critical range ($crange) exceeded";
        }
    }

    if ($new_state eq 'ok' && defined $warn && $value ne 'unknown') {
        my $wrange = ($warn->[0] // '') . ':' . ($warn->[1] // '');
        if ((defined $warn->[0] && $value < $warn->[0]) ||
            (defined $warn->[1] && $value > $warn->[1])) {
            $new_state = 'warning';
            $extinfo = defined $attrs->{extinfo}
                ? "$value (not in $wrange): $attrs->{extinfo}"
                : "Value is $value. Warning range ($wrange) exceeded";
        }
    }

    # Single upsert (was: NOT-EXISTS insert + blind UPDATE, two round
    # trips per ds). prev_alarm records the pre-evaluation alarm so the
    # serial tail can detect edges without any IPC.
    my $sth_upsert = $dbh->prepare_cached(q{
        INSERT INTO state (ds_id, alarm, num_unknowns, prev_alarm, eval_value, extinfo)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (ds_id) DO UPDATE SET
            alarm        = excluded.alarm,
            num_unknowns = excluded.num_unknowns,
            prev_alarm   = excluded.prev_alarm,
            eval_value   = excluded.eval_value,
            extinfo      = excluded.extinfo
    });
    $sth_upsert->execute(
        $ds_id, $new_state, $new_num_unknowns,
        $old_state, $value, $extinfo,
    );
}


# Parse warning/critical strings into [low, high] arrays
sub _parse_thresholds {
    my ($warn_str, $crit_str) = @_;
    my ($warn, $crit);

    if (defined $crit_str && $crit_str =~ /^\s*([-+\d.]*):([-+\d.]*)\s*$/) {
        $crit = [undef, undef];
        $crit->[0] = $1 if length $1;
        $crit->[1] = $2 if length $2;
    } elsif (defined $crit_str && $crit_str =~ /^\s*([-+\d.]+)\s*$/) {
        $crit = [undef, $1];
    }

    if (defined $warn_str && $warn_str =~ /^\s*([-+\d.]*):([-+\d.]*)\s*$/) {
        $warn = [undef, undef];
        $warn->[0] = $1 if length $1;
        $warn->[1] = $2 if length $2;
    } elsif (defined $warn_str && $warn_str =~ /^\s*([-+\d.]+)\s*$/) {
        $warn = [undef, $1];
    }

    return ($warn, $crit);
}


my %contact_pipes;
my %contact_pids;    # contact name => pid of its notification command

# ========================================================================
# CDEF VALUE COMPUTATION
# ========================================================================
#
# WHY COMPUTE CDEFs HERE (at limits time)?
#
# 1. UPDATE PHASE IS TIME-CRITICAL:
#    munin-update must complete within update_rate (typically 5 min).
#    Adding RRDs::xport calls would risk timeouts.
#
# 2. LIMITS PHASE IS ASYNC:
#    munin-limits runs separately, can take longer.
#    It's the right place for derived value computation.
#
# 3. COST PROPORTIONAL:
#    Only services with CDEF thresholds pay the xport cost.
#    Most CDEFs have no thresholds, so no overhead.
#
# 4. RRDCACHED COMPATIBILITY:
#    RRDs::xport auto-flushes rrdcached (FETCH implies flush).
#    So we always get fresh data even if update just wrote.
#
# 5. STORE FOR HTML/GRAPHS:
#    Computed value is stored in state.last_value.
#    HTML and graph modules can display it without recomputing.
#
# ========================================================================

sub _compute_cdef_value {
    my ($dbh, $ds_id, $cdef_expr) = @_;
    my $dbdir = Munin::Master::Update::get_param('dbdir', $dbh);

    # --------------------------------------------------------------------
    # Get RRD file and source DS names for this CDEF.
    # --------------------------------------------------------------------
    my ($ds_name, $rrd_file) = $dbh->selectrow_array(q{
        SELECT d.name, r.file
        FROM ds d
        INNER JOIN ds_rrd r ON r.ds_id = d.id
        WHERE d.id = ?
    }, undef, $ds_id);
    return unless defined $rrd_file;
    $rrd_file = File::Spec->catfile($dbdir, $rrd_file);
    return unless -f $rrd_file;

    # Get all DS in same service (for source DS lookup). Soft-deleted
    # fields are included on purpose: a CDEF that references one keeps
    # working against its last known data.
    my $sth_svc = $dbh->prepare_cached(q{
        SELECT d.id, d.name, r.file as rrd_file, r.field as rrd_field
        FROM ds d
        INNER JOIN ds_rrd r ON r.ds_id = d.id
        WHERE d.service_id = (SELECT service_id FROM ds WHERE id = ?)
    });
    $sth_svc->execute($ds_id);
    my %rrd_files;   # munin_name => rrd_path
    my %rrd_fields;  # munin_name => rrd_ds_name
    while (my ($id, $name, $file, $field) = $sth_svc->fetchrow_array) {
        if ($file) {
            $rrd_files{$name} = File::Spec->catfile($dbdir, $file);
            $rrd_fields{$name} = $field;  # may be undef
        }
    }

    # --------------------------------------------------------------------
    # Parse CDEF expression to find source DS names.
    #
    # CDEFs are RPN: "in,out,+" = push in, push out, add.
    # We identify DS names (alphanumeric) vs operators (symbols).
    # --------------------------------------------------------------------
    my @tokens = split(/,/, $cdef_expr);
    my %seen_defs;
    my @xport_args = (
        '--start', 'now-3600',
        '--end',   'now+120',
        '--step',  '60',
    );

    # RRDtool CDEF keywords (not DS names)
    my %keywords = map { $_ => 1 } qw(
        GT GE LT LE EQ NE IF MIN MAX LIMIT DUP POP EXC
        SIN COS LOG EXP FLOOR CEIL ABS UNKN INF NEGINF
        PREV NOW TIME LTIME
    );

    for my $tok (@tokens) {
        next if $seen_defs{$tok};
        next if $tok =~ /^[-+]?[\d.]+$/;  # Number
        next if $tok =~ /^[<>=!+*\/\-]/;   # Operator
        next if $keywords{uc $tok};         # RRD keyword

        # Looks like a DS name -- add DEF if we have its RRD
        if (defined $rrd_files{$tok}) {
            my $rrd_field = $rrd_fields{$tok} // $tok;
            push @xport_args, "DEF:${tok}=$rrd_files{$tok}:$rrd_field:AVERAGE"
                unless $seen_defs{$tok}++;
        }
    }

    # Add CDEF and XPORT for the computed field
    push @xport_args, "CDEF:result=$cdef_expr";
    push @xport_args, 'XPORT:result';

    # --------------------------------------------------------------------
    # Execute xport.
    #
    # RRDs::xport uses FETCH internally, which auto-flushes rrdcached.
    # See rrd_client.c: "FlushVersion" in FETCH response.
    # --------------------------------------------------------------------
    DEBUG "_compute_cdef_value: RRDs::xport(@xport_args)";
    my ($start, $end, $step, $nb, $cols, $vals) = RRDs::xport(@xport_args);

    if (my $err = RRDs::error) {
        WARN "RRDs::xport failed for $ds_name: $err";
        return;
    }

    # --------------------------------------------------------------------
    # Extract last non-NaN value.
    # --------------------------------------------------------------------
    for my $i (reverse 0..$#$vals) {
        my $val = $vals->[$i][0];
        if (defined $val) {
            DEBUG "_compute_cdef_value: $ds_name = $val";
            return $val;
        }
    }

    return;
}


# Phase 3: serial notification delivery. Reads evaluated state FROM the
# DB -- phase 2 children are long gone by now. Contacts are serialized:
# one mailer per contact, messages written sequentially to its pipe.
sub _deliver_notifications {
    my ($work) = @_;

    my $dbh = Munin::Master::Update::get_dbh();

    for my $host (@{$work}) {
        for my $svc (@{$host->{services}}) {
            my ($service, $stats) = _read_service_state(
                $dbh, $svc, $host
            );
            next unless $service;

            _generate_service_message($dbh, $service, $stats);
        }
    }

    # Ledger upserts above run in this handle's transaction (AutoCommit=0):
    # commit them, or disconnect rolls the whole delivery back.
    $dbh->commit();
    $dbh->disconnect();
}


# Rebuild the per-service message context from state rows. Mirrors what
# the evaluation used to hand over in memory; state_changed and
# recovered are derived from the prev_alarm edge column.
sub _read_service_state {
    my ($dbh, $svc, $host) = @_;

    my ($service_id, $service_name) = @{$svc}{qw(service_id service_name)};

    # Service context from SQL (single row)
    my ($host_alias, $graph_title, $contacts) = $dbh->selectrow_array(q{
        SELECT
            MAX(CASE WHEN na.name = 'notify_alias' THEN na.value END) AS host_alias,
            MAX(CASE WHEN sa.name = 'graph_title' THEN sa.value END) AS graph_title,
            MAX(CASE WHEN sa.name = 'contacts' THEN sa.value END) AS contacts
        FROM service s
        INNER JOIN node n ON n.id = s.node_id
        LEFT JOIN service_attr sa ON sa.id = s.id AND sa.name = 'graph_title'
        LEFT JOIN node_attr na ON na.id = n.id AND na.name = 'notify_alias'
        WHERE s.id = ?
    }, undef, $service_id);

    $host_alias  //= $host->{node_name};
    $graph_title //= $service_name;
    $contacts    //= '';

    # Evaluated DS of this service. eval_value IS NOT NULL marks rows the
    # limits evaluation actually wrote (the update phase leaves it NULL);
    # the ds_attr EXISTS clause keeps the universe identical to the work
    # list -- ds whose thresholds were removed since last run drop out.
    my $sth = $dbh->prepare_cached(q{
        SELECT d.name, st.alarm, st.prev_alarm, st.eval_value, st.extinfo
        FROM ds d
        INNER JOIN state st ON st.ds_id = d.id
        WHERE d.service_id = ?
          AND d.deleted = 0
          AND st.eval_value IS NOT NULL
          AND EXISTS (
              SELECT 1 FROM ds_attr da
              WHERE da.id = d.id
                AND da.name IN ('warning', 'critical')
                AND da.value IS NOT NULL AND da.value != ''
          )
        ORDER BY d.ordr
    });
    $sth->execute($service_id);

    my %service = (
        _service_id  => $service_id,
        group       => $host->{group_path},
        host        => $host_alias,
        plugin      => $service_name,
        graph_title => $graph_title,
        contacts    => $contacts,
        worst       => 'OK',
        worstid     => 0,
        state_changed => 0,
        recovered   => {},
    );
    my %stats = (critical => [], warning => [], unknown => [], ok => [], foks => []);

    my $any = 0;
    while (my ($ds_name, $alarm, $prev_alarm, $eval_value, $extinfo) = $sth->fetchrow_array) {
        $any = 1;

        $alarm     //= 'ok';
        $prev_alarm //= 'ok';
        $eval_value //= 'unknown';
        $extinfo   //= '';

        my $existing = $service{fields} // '';
        $service{fields} = "$existing $ds_name";
        $service{$ds_name} = {
            state   => $alarm,
            label   => $ds_name,
            value   => $eval_value,
            extinfo => $extinfo,
        };

        push @{$stats{$alarm}}, $ds_name;

        if ($alarm ne $prev_alarm) {
            $service{state_changed} = 1;
            if ($prev_alarm ne 'ok' && $alarm eq 'ok') {
                $service{recovered}{$ds_name} = 1;
                push @{$stats{foks}}, $ds_name;
            }
        }

        if ($alarm eq 'critical') {
            $service{worst} = 'CRITICAL';
            $service{worstid} = 2;
        } elsif ($alarm eq 'warning' && $service{worstid} < 2) {
            $service{worst} = 'WARNING';
            $service{worstid} = 1;
        } elsif ($alarm eq 'unknown' && $service{worstid} == 0) {
            $service{worst} = 'UNKNOWN';
            $service{worstid} = 3;
        }
    }

    return unless $any;

    $service{cfields}  = join ' ', @{$stats{critical}};
    $service{wfields}  = join ' ', @{$stats{warning}};
    $service{ufields}  = join ' ', @{$stats{unknown}};
    $service{fofields} = join ' ', @{$stats{foks}};
    $service{ofields}  = join ' ', @{$stats{ok}};
    $service{fofields} //= $service{ofields};
    $service{numcfields}  = scalar @{$stats{critical}};
    $service{numwfields}  = scalar @{$stats{warning}};
    $service{numufields}  = scalar @{$stats{unknown}};
    $service{numfofields} = scalar @{$stats{foks}};
    $service{numofields}  = scalar @{$stats{ok}};

    return (\%service, \%stats);
}


# Send notifications for service state changes -- all tracking in SQL.
# Runs serially in the master: the pipes below are per-contact and every
# message is written in order, so delivery is deterministic.
sub _generate_service_message {
    my ($dbh, $service, $stats) = @_;

    # Get contacts for this service from SQL
    my @contacts;
    if ($service->{contacts}) {
        @contacts = split /\s+/, $service->{contacts};
    }
    # Also check global default contacts from param table
    unless (@contacts) {
        my $global = Munin::Master::Update::get_param('contacts', $dbh);
        @contacts = split /\s+/, $global if $global;
    }
    return unless @contacts;

    for my $contact_name (@contacts) {
        next if $contact_name eq 'none';
        next if @limit_contacts && !grep { $_ eq $contact_name } @limit_contacts;

        # Read contact from SQL (single row)
        my ($contact_id) = $dbh->selectrow_array(
            'SELECT id FROM contact WHERE name = ?', undef, $contact_name);
        unless ($contact_id) {
            WARN "Missing contact: $contact_name; skipping";
            next;
        }

        # Read contact attrs from SQL
        my $sth_ca = $dbh->prepare_cached('SELECT name, value FROM contact_attr WHERE id = ?');
        $sth_ca->execute($contact_id);
        my %ca;
        while (my ($k, $v) = $sth_ca->fetchrow_array) {
            $ca{$k} = $v;
        }

        my $cmd = $ca{command};
        unless (defined $cmd) {
            WARN "Missing command for contact $contact_name; skipping";
            next;
        }

        # Determine always_send
        my $always_send;
        if (@always_send) {
            $always_send = \@always_send;
        } else {
            $always_send = [split /[,\s]+/, ($ca{always_send} // 'critical,warning')];
        }
        $always_send = _validate_severities($always_send);

        # Check if notification needed
        my $obsess = 0;
        for my $level (@$always_send) {
            $obsess += scalar @{$stats->{$level}} if $stats->{$level};
        }
        next unless $service->{state_changed} || $obsess;

        INFO "state of $service->{group}::$service->{host}::$service->{plugin} has changed to $service->{worst}, notifying $contact_name";

        # Read send ledger from SQL (single row)
        my ($notif_id, $num_messages) = $dbh->selectrow_array(q{
            SELECT id, num_messages FROM notification_tracking
            WHERE contact_id = ? AND service_id = ?
        }, undef, $contact_id, $service->{_service_id});

        # A state transition always gets through and resets the counter
        # (a new alarm deserves a fresh message budget). Repeats of the
        # current state are throttled by max_messages.
        my $state_changed = $service->{state_changed};
        my $max_messages = $ca{max_messages} // 0;
        if (!$state_changed) {
            if ($max_messages && $num_messages && $num_messages >= $max_messages) {
                DEBUG "Max messages reached for $contact_name on $service->{plugin}";
                next;
            }
        }

        # Expand message template
        my $pretxt = $ca{text} // $default_text{$contact_name} // $default_text{default};
        my $txt = _message_expand($service, $pretxt);
        $txt =~ s/\\n/\n/g;
        $txt =~ s/\\t/\t/g;

        $cmd = _message_expand($service, $cmd);
        $cmd =~ s/^\s*[|><]+//;

        # Open pipe if needed -- track in SQL, pipe handle in %contact_pipes
        my $pipe = $contact_pipes{$contact_name};
        if (!defined $pipe) {
            pipe(my $r, my $w) or WARN "Failed to open pipe for $contact_name: $!";
            my $pid = fork();
            defined $pid or WARN "Failed fork for $contact_name: $!";
            if ($pid) {
                close $r;
                $pipe = $w;
                $contact_pipes{$contact_name}   = $pipe;
                $contact_pids{$contact_name}    = $pid;
            } else {
                close $w;
                open(STDIN, '<&', $r);
                close(STDOUT);
                exec($cmd) or WARN "Failed exec for $contact_name: $!";
                exit 127;    # exec failed: make it visible via exit status
            }
        }

        DEBUG "sending message to $contact_name: \"$txt\"";
        if (!print $pipe $txt, "\n") {
            WARN "Writing to pipe for $contact_name failed: $!";
            close $pipe;
            _reap_command($contact_name, delete $contact_pids{$contact_name});
            delete $contact_pipes{$contact_name};
        }

        # Update the send ledger. service_id MUST be part of the key:
        # without it the ON CONFLICT never matches (NULLs don't collide
        # in the unique index), rows grow unbounded, and throttling
        # never accumulates. Transitions reset the counter; repeats
        # increment it.
        my $new_count = $state_changed ? 1 : ($num_messages // 0) + 1;
        $dbh->do(q{
            INSERT INTO notification_tracking (contact_id, service_id, severity, sent_at, num_messages)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (contact_id, service_id) DO UPDATE SET
                num_messages = excluded.num_messages,
                sent_at = excluded.sent_at,
                severity = excluded.severity
        }, undef, $contact_id, $service->{_service_id}, $service->{worst}, time(), $new_count);
    }
}

sub _close_pipes {
    for my $name (keys %contact_pipes) {
        my $pipe = $contact_pipes{$name};
        if ($pipe) {
            DEBUG "Closing pipe for $name";
            close $pipe or WARN "Failed to close pipe for $name: $!";
        }
    }
    %contact_pipes = ();

    # Close write ends first (done above) so children see EOF and exit;
    # then reap them, reporting commands that failed.
    for my $name (sort keys %contact_pids) {
        _reap_command($name, delete $contact_pids{$name});
    }
}

# Wait briefly for a notification command to finish, and report failures.
# Without this the child is never reaped: it lingers as a zombie under the
# limits process, and a command that died silently looks like one that
# delivered the notification.
sub _reap_command {
    my ($name, $pid) = @_;
    return unless $pid;

    for (1 .. 100) {
        my $kid = waitpid($pid, WNOHANG);
        if ($kid == $pid) {
            ## no critic qw(Variables::ProhibitPunctuationVars)
            # $? is Perl's only channel for waitpid() exit status; there
            # is no non-punctuation equivalent to suppress to instead.
            my $status = $?;
            my $detail = $status & 127
                ? "signal " . ($status & 127)
                  . (($status & 128) ? " (core dumped)" : "")
                : "exit code " . ($status >> 8);
            WARN "notification command for $name exited with $detail"
                if $status != 0;
            return;
        }
        return if $kid == -1;    # not ours anymore (already reaped)
        Time::HiRes::sleep(0.01);
    }
    WARN "notification command for $name (pid $pid) still running; not reaped";
}


# Validate severity list. Constant membership set -- this ran hundreds of
# thousands of times per suite pass with a nested grep.
my %VALID_SEVERITY = map { $_ => 1 } qw(ok warning critical unknown);
sub _validate_severities {
    my ($list) = @_;
    return [ grep { $VALID_SEVERITY{$_} } @$list ];
}


# Template expansion engine
sub _message_expand {
    my ($hash, $text) = @_;
    my @res;

    while (defined $text && length $text) {
        if ($text =~ /^([^\$]+|)(?:\$(\{.*)|)$/) {
            push @res, $1;
            $text = $2;
        }

        my @bracket = extract_bracketed($text, '{}');
        if (!defined $bracket[0]) {
            $text = $bracket[1];
            next;
        }

        if ($bracket[0] =~ /^\{var:(\S+)\}$/) {
            $bracket[0] = $hash->{$1} // '';
        }
        elsif ($bracket[0] =~ /^\{loop<([^>]+)>:\s*(\S+)\s(.+)\}$/) {
            my $delimiter = $1;
            my $field = $2;
            my $template = $3;
            my $fields = $hash->{$field} // '';
            my @expanded;
            if ($fields) {
                for my $sub (split /\s+/, $fields) {
                    if ($hash->{$sub}) {
                        push @expanded, _message_expand($hash->{$sub}, $template);
                    }
                }
            }
            $bracket[0] = join($delimiter, @expanded);
        }
        elsif ($bracket[0] =~ /^\{if:(\S+)\s(.+)\}$/) {
            my $field = $1;
            my $template = $2;
            if ($hash->{$field} && $hash->{$field} ne '') {
                $bracket[0] = _message_expand($hash, $template);
            } else {
                $bracket[0] = '';
            }
        }
        elsif ($bracket[0] =~ /^\{strtrunc:(\d+)\s(.+)\}$/) {
            my $len = $1;
            my $template = $2;
            my $expanded = _message_expand($hash, $template);
            $bracket[0] = substr($expanded, 0, $len);
        }
        else {
            $bracket[0] = '';
        }

        push @res, $bracket[0];
        $text = $bracket[1];
    }

    return join '', @res;
}


1;

__END__

=head1 NAME

Munin::Master::Limits - Evaluate thresholds and send notifications

=head1 SYNOPSIS

  use Munin::Master::Limits;
  limits_main();

=head1 DESCRIPTION

Three phases: an in-memory per-host work list, per-host threshold
evaluation (optionally parallel) writing results to the state table,
and a serial notification tail that rebuilds messages from those state
rows. The state table is the only channel between phases -- no IPC, no
staging files.

All data is read from SQL. No Perl config tree walking.
Config is imported into SQL at startup by Update.pm.

=cut
