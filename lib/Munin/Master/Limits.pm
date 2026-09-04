package Munin::Master::Limits;

use warnings;
use strict;

use Exporter;

our (@ISA, @EXPORT);
@ISA    = qw ( Exporter );
@EXPORT = qw ( limits_main );

use POSIX qw ( strftime );
use Getopt::Long;
use Time::HiRes;
use Text::Balanced qw ( extract_bracketed );
use Scalar::Util qw( looks_like_number );
use Munin::Common::Logger;

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

my %default_text = (
    "default" =>
        '${var:group} :: ${var:host} :: ${var:graph_title}${if:cfields \n\tCRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields \n\tWARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields \n\tUNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields \n\tOKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}\n',
    "nagios" =>
        '${var:host}\t${var:graph_title}\t${var:worstid}\t${strtrunc:350 ${if:cfields CRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields WARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields UNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields OKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}}',
    "old-nagios" =>
        '${var:host}\t${var:plugin}\t${var:worstid}\t${strtrunc:350 ${var:graph_title}:${if:cfields CRITICALs:${loop<,>:cfields  ${var:label} is ${var:value} (outside range [${var:crange}])${if:extinfo : ${var:extinfo}}}.}${if:wfields WARNINGs:${loop<,>:wfields  ${var:label} is ${var:value} (outside range [${var:wrange}])${if:extinfo : ${var:extinfo}}}.}${if:ufields UNKNOWNs:${loop<,>:ufields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}${if:fofields OKs:${loop<,>:fofields  ${var:label} is ${var:value}${if:extinfo : ${var:extinfo}}}.}}',
);


sub limits_main {
    $SIG{PIPE} = 'IGNORE';

    my $update_time = Time::HiRes::time;
    INFO "[INFO] Starting limits (inline)";

    _process_limits();

    _close_pipes();

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));
    INFO "[INFO] Limits finished ($update_time sec)";
}


# Find all services with warning/critical defined, evaluate each
sub _process_limits {
    my $dbh = Munin::Master::Update::get_dbh();

    # Find all services that have at least one DS with warning or critical
    my $sth = $dbh->prepare(q{
        SELECT DISTINCT s.id, s.name, s.path, n.name AS node_name, g.path AS group_path
        FROM service s
        INNER JOIN node n ON n.id = s.node_id
        INNER JOIN grp g ON g.id = n.grp_id
        INNER JOIN ds d ON d.service_id = s.id
        INNER JOIN ds_attr da ON da.id = d.id
        WHERE da.name IN ('warning', 'critical')
          AND da.value IS NOT NULL
          AND da.value != ''
    });
    $sth->execute();

    while (my ($service_id, $service_name, $service_path, $node_name, $group_path) = $sth->fetchrow_array) {
        _process_service($dbh, $service_id, $service_name, $node_name, $group_path);
    }
}


# Evaluate thresholds for a single service
sub _process_service {
    my ($dbh, $service_id, $service_name, $node_name, $group_path) = @_;

    DEBUG "[DEBUG] processing service: $service_name";

    # Read service context from SQL
    my $sth_ctx = $dbh->prepare(q{
        SELECT
            MAX(CASE WHEN na.name = 'notify_alias' THEN na.value END) AS host_alias,
            MAX(CASE WHEN sa.name = 'graph_title' THEN sa.value END) AS graph_title,
            MAX(CASE WHEN sa.name = 'contacts' THEN sa.value END) AS contacts
        FROM service s
        INNER JOIN node n ON n.id = s.node_id
        LEFT JOIN service_attr sa ON sa.id = s.id AND sa.name = 'graph_title'
        LEFT JOIN node_attr na ON na.id = n.id AND na.name = 'notify_alias'
        WHERE s.id = ?
    });
    $sth_ctx->execute($service_id);
    my ($host_alias, $graph_title, $contacts) = $sth_ctx->fetchrow_array;

    $host_alias //= $node_name;
    $graph_title //= $service_name;
    $contacts   //= '';

    # Build service hash for message_expand (read from SQL, not config tree)
    my %service = (
        group      => $group_path,
        host       => $host_alias,
        plugin     => $service_name,
        graph_title => $graph_title,
        contacts   => $contacts,
        worst      => 'OK',
        worstid    => 0,
        state_changed => 0,
        recovered  => {},
    );

    # Process each DS in this service
    my $sth_ds = $dbh->prepare(q{
        SELECT d.id, d.name, d.type
        FROM ds d
        WHERE d.service_id = ?
        ORDER BY d.ordr
    });
    $sth_ds->execute($service_id);

    my %stats = (critical => [], warning => [], unknown => [], ok => [], foks => []);

    while (my ($ds_id, $ds_name, $ds_type) = $sth_ds->fetchrow_array) {
        my $result = _process_ds($dbh, $ds_id, $ds_name, $ds_type, \%service);
        next unless defined $result;

        my ($state, $value, $extinfo) = @$result;

        $service{fields} = ($service{fields} // '') . " $ds_name";
        $service{$ds_name} = {
            state  => $state,
            label  => $ds_name,
            value  => $value,
            extinfo => $extinfo,
        };

        push @{$stats{$state}}, $ds_name;
        if ($state eq 'ok' && $service{recovered}{$ds_name}) {
            push @{$stats{foks}}, $ds_name;
        }

        if ($state eq 'critical') {
            $service{worst} = 'CRITICAL';
            $service{worstid} = 2;
        } elsif ($state eq 'warning' && $service{worstid} < 2) {
            $service{worst} = 'WARNING';
            $service{worstid} = 1;
        } elsif ($state eq 'unknown' && $service{worstid} == 0) {
            $service{worst} = 'UNKNOWN';
            $service{worstid} = 3;
        }
    }

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

    # Send notifications
    _generate_service_message(\%service, \%stats);
}


# Evaluate thresholds for a single DS
sub _process_ds {
    my ($dbh, $ds_id, $ds_name, $ds_type, $service) = @_;

    # Read DS attrs from SQL
    my $sth_attr = $dbh->prepare('SELECT name, value FROM ds_attr WHERE id = ?');
    $sth_attr->execute($ds_id);
    my %attrs;
    while (my ($k, $v) = $sth_attr->fetchrow_array) {
        $attrs{$k} = $v;
    }

    my $warn_str = $attrs{warning};
    my $crit_str = $attrs{critical};

    # Skip if no thresholds
    return unless defined $warn_str || defined $crit_str;

    # Skip CDEF fields
    return if defined $attrs{cdef} && $attrs{cdef} ne '';

    # Parse thresholds
    my ($warn, $crit) = _parse_thresholds($warn_str, $crit_str);
    return unless defined $warn || defined $crit;

    # Read state from SQL
    my $sth_state = $dbh->prepare(q{
        SELECT last_epoch, last_value, prev_epoch, prev_value, alarm, num_unknowns
        FROM state WHERE id = ? AND type = 'ds'
    });
    $sth_state->execute($ds_id);
    my ($last_epoch, $last_value, $prev_epoch, $prev_value, $old_state, $old_num_unknowns) = $sth_state->fetchrow_array;

    $old_state       //= 'ok';
    $old_num_unknowns //= 0;

    # Compute current value
    my $heartbeat = 600;
    my $value;
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

    my $unknown_limit = defined $attrs{unknown_limit} ? $attrs{unknown_limit} : 3;

    if ($value eq 'unknown') {
        $new_state = 'unknown';
        $extinfo = $attrs{extinfo} // 'Value is unknown.';
        if ($old_state ne 'unknown') {
            if ($old_num_unknowns < $unknown_limit) {
                $new_state = $old_state;
                $extinfo = $attrs{extinfo} // '';
                $new_num_unknowns = $old_num_unknowns + 1;
            }
        } else {
            $new_num_unknowns = $old_num_unknowns;
        }
    } elsif (defined $crit) {
        my $crange = ($crit->[0] // '') . ':' . ($crit->[1] // '');
        if ((defined $crit->[0] && $value < $crit->[0]) ||
            (defined $crit->[1] && $value > $crit->[1])) {
            $new_state = 'critical';
            $extinfo = defined $attrs{extinfo}
                ? "$value (not in $crange): $attrs{extinfo}"
                : "Value is $value. Critical range ($crange) exceeded";
        }
    }

    if ($new_state eq 'ok' && defined $warn) {
        my $wrange = ($warn->[0] // '') . ':' . ($warn->[1] // '');
        if ((defined $warn->[0] && $value < $warn->[0]) ||
            (defined $warn->[1] && $value > $warn->[1])) {
            $new_state = 'warning';
            $extinfo = defined $attrs{extinfo}
                ? "$value (not in $wrange): $attrs{extinfo}"
                : "Value is $value. Warning range ($wrange) exceeded";
        }
    }

    # Track state change
    if ($new_state ne $old_state) {
        $service->{state_changed} = 1;
        if ($old_state eq 'ok' && $new_state ne 'ok') {
            # nothing
        } elsif ($new_state eq 'ok' && $old_state ne 'ok') {
            $service->{recovered}{$ds_name} = 1;
        }
    }

    # Write alarm to SQL
    my $sth_ins = $dbh->prepare(q{
        INSERT INTO state (id, type, alarm, num_unknowns)
        SELECT ?, 'ds', ?, ?
        WHERE NOT EXISTS (SELECT 1 FROM state WHERE id = ? AND type = 'ds')
    });
    $sth_ins->execute($ds_id, $new_state, $new_num_unknowns, $ds_id, 'ds');

    my $sth_upt = $dbh->prepare('UPDATE state SET alarm = ?, num_unknowns = ? WHERE id = ? AND type = 'ds'');
    $sth_upt->execute($new_state, $new_num_unknowns, $ds_id);

    return [$new_state, $value, $extinfo];
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


# Send notifications for service state changes
sub _generate_service_message {
    my ($service, $stats) = @_;

    my $dbh = Munin::Master::Update::get_dbh();

    # Get contacts for this service
    my @contacts = split /\s+/, ($service->{contacts} // '');
    return unless @contacts;

    # Also get global default contacts
    my $global_contacts = Munin::Master::Update::get_param('contacts');
    if ($global_contacts && !@contacts) {
        @contacts = split /\s+/, $global_contacts;
    }

    for my $contact_name (@contacts) {
        next if $contact_name eq 'none';

        if (@limit_contacts && !grep { $_ eq $contact_name } @limit_contacts) {
            next;
        }

        # Read contact from SQL
        my $sth_c = $dbh->prepare('SELECT id FROM contact WHERE name = ?');
        $sth_c->execute($contact_name);
        my ($contact_id) = $sth_c->fetchrow_array;
        unless ($contact_id) {
            WARN "[WARNING] Missing contact: $contact_name; skipping";
            next;
        }

        # Read contact attrs from SQL
        my $sth_ca = $dbh->prepare('SELECT name, value FROM contact_attr WHERE id = ?');
        $sth_ca->execute($contact_id);
        my %ca;
        while (my ($k, $v) = $sth_ca->fetchrow_array) {
            $ca{$k} = $v;
        }

        my $cmd = $ca{command};
        unless (defined $cmd) {
            WARN "[WARNING] Missing command for contact $contact_name; skipping";
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

        INFO "[INFO] state of $service->{group}::$service->{host}::$service->{plugin} has changed to $service->{worst}, notifying $contact_name";

        # Expand message template
        my $pretxt = $ca{text} // $default_text{$contact_name} // $default_text{default};
        my $txt = _message_expand($service, $pretxt);
        $txt =~ s/\\n/\n/g;
        $txt =~ s/\\t/\t/g;

        $cmd = _message_expand($service, $cmd);
        $cmd =~ s/^\s*[|><]+//;

        # Open pipe and send
        my $pipe = $contact_pipes{$contact_name};
        if (!defined $pipe) {
            pipe(my $r, my $w) or WARN "[WARNING] Failed to open pipe for $contact_name: $!";
            my $pid = fork();
            defined $pid or WARN "[WARNING] Failed fork for $contact_name: $!";
            if ($pid) {
                close $r;
                $pipe = $w;
                $contact_pipes{$contact_name} = $pipe;
            } else {
                close $w;
                open(STDIN, '<&', $r);
                close(STDOUT);
                exec($cmd) or WARN "[WARNING] Failed exec for $contact_name: $!";
                exit;
            }
        }

        DEBUG "[DEBUG] sending message to $contact_name: \"$txt\"";
        if (!print $pipe $txt, "\n") {
            WARN "[WARNING] Writing to pipe for $contact_name failed: $!";
            close $pipe;
            delete $contact_pipes{$contact_name};
        }
    }
}

my %contact_pipes;

sub _close_pipes {
    for my $name (keys %contact_pipes) {
        my $pipe = $contact_pipes{$name};
        if ($pipe) {
            DEBUG "[DEBUG] Closing pipe for $name";
            close $pipe or WARN "[WARNING] Failed to close pipe for $name: $!";
        }
    }
    %contact_pipes = ();
}


# Validate severity list
sub _validate_severities {
    my ($list) = @_;
    my @valid = qw(ok warning critical unknown);
    return [ grep { my $s = $_; grep { $_ eq $s } @valid } @$list ];
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

        my @a = extract_bracketed($text, '{}');
        if (!defined $a[0]) {
            $text = $a[1];
            next;
        }

        if ($a[0] =~ /^\{var:(\S+)\}$/) {
            $a[0] = $hash->{$1} // '';
        }
        elsif ($a[0] =~ /^\{loop<([^>]+)>:\s*(\S+)\s(.+)\}$/) {
            my $d = $1;
            my $f = $2;
            my $t = $3;
            my $fields = $hash->{$f} // '';
            my @r;
            if ($fields) {
                for my $sub (split /\s+/, $fields) {
                    if ($hash->{$sub}) {
                        push @r, _message_expand($hash->{$sub}, $t);
                    }
                }
            }
            $a[0] = join($d, @r);
        }
        elsif ($a[0] =~ /^\{if:(\S+)\s(.+)\}$/) {
            my $f = $1;
            my $t = $2;
            if ($hash->{$f} && $hash->{$f} ne '') {
                $a[0] = _message_expand($hash, $t);
            } else {
                $a[0] = '';
            }
        }
        elsif ($a[0] =~ /^\{strtrunc:(\d+)\s(.+)\}$/) {
            my $len = $1;
            my $t = $2;
            my $expanded = _message_expand($hash, $t);
            $a[0] = substr($expanded, 0, $len);
        }
        else {
            $a[0] = '';
        }

        push @res, $a[0];
        $text = $a[1];
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

All data is read from SQL. No Perl config tree walking.
Config is imported into SQL at startup by Update.pm.

=cut
