package Munin::Master::Utils;
# -*- cperl -*-

use strict;
use warnings;

use Carp;
use Exporter;
use English qw(-no_match_vars);
use Fcntl qw(:DEFAULT :flock);
use File::Path;
use IO::Handle;
use Munin::Common::Defaults;
use Munin::Master::Logger;
use Munin::Master::Config;
use Munin::Common::Config;
use Log::Log4perl qw(:easy);
use POSIX qw(strftime);
use POSIX qw(:sys_wait_h);
use Symbol qw(gensym);
use Data::Dumper;
use Storable;
use Scalar::Util qw(isweak weaken);

our (@ISA, @EXPORT);

@ISA = ('Exporter');
@EXPORT = (
	   'munin_nscasend',
	   'munin_createlock',
	   'munin_removelock',
	   'munin_runlock',
	   'munin_getlock',
	   'munin_readconfig_raw',
	   'munin_writeconfig',
	   'munin_writeconfig_storable',
	   'munin_read_storable',
	   'munin_write_storable',
	   'munin_delete',
	   'munin_overwrite',
	   'munin_dumpconfig',
	   'munin_dumpconfig_as_str',
	   'munin_readconfig_base',
	   'munin_readconfig_part',
	   'munin_configpart_revision',
	   'munin_draw_field',
	   'munin_get_bool',
	   'munin_get_bool_val',
	   'munin_get',
	   'munin_field_status',
	   'munin_service_status',
	   'munin_node_status',
	   'munin_category_status',
	   'munin_get_picture_filename',
	   'munin_get_picture_loc',
	   'munin_get_html_filename',
	   'munin_get_filename',
	   'munin_get_keypath',
	   'munin_graph_column_headers',
	   'munin_get_max_label_length',
	   'munin_get_field_order',
	   'munin_get_rrd_filename',
	   'munin_get_node_name',
	   'munin_get_orig_node_name',
	   'munin_get_parent_name',
	   'munin_get_node_fqn',
	   'munin_find_node_by_fqn',
	   'munin_get_node_loc',
	   'munin_get_node',
	   'munin_set_var_loc',
	   'munin_set_var_path',
	   'munin_set',
	   'munin_copy_node_toloc',
	   'munin_get_separated_node',
	   'munin_mkdir_p',
	   'munin_find_field',
	   'munin_find_field_for_limits',
	   'munin_get_parent',
	   'munin_get_children',
	   'munin_get_node_partialpath',
	   'munin_has_subservices',
	   'munin_get_host_path_from_string',
	   'print_version_and_exit',
	   'exit_if_run_by_super_user',
	   'look_for_child',
	   'wait_for_remaining_children',
	   );

my $VERSION = $Munin::Common::Defaults::MUNIN_VERSION;

my $nsca = new IO::Handle;
my $config = undef;
my $config_parts = {
	# config parts that might be loaded and reloaded at times
	'datafile' => {
		'timestamp' => 0,
		'config' => undef,
		'revision' => 0,
		'include_base' => 1,
	},
	'limits' => {
		'timestamp' => 0,
		'config' => undef,
		'revision' => 0,
		'include_base' => 1,
	},
	'htmlconf' => {
		'timestamp' => 0,
		'config' => undef,
		'revision' => 0,
		'include_base' => 0,
	},
};

my $configfile="$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf";

# Fields to copy when "aliasing" a field
my @COPY_FIELDS    = ("label", "draw", "type", "rrdfile", "fieldname", "info");

my @dircomponents = split('/',$0);
my $me = pop(@dircomponents);


sub munin_draw_field {
    my $hash   = shift;

    return 0 if munin_get_bool ($hash, "skipdraw", 0);
    return 0 if !munin_get_bool ($hash, "graph", 1);
    return defined $hash->{"label"};
}


sub munin_nscasend {
    my ($name,$service,$label,$level,$comment) = @_;

    if (!$nsca->opened)
    {
	open ($nsca ,'|-', "$config->{nsca} $config->{nsca_server} -c $config->{nsca_config} -to 60");
    }
    if ($label)
    {
	print $nsca "$name\t$service: $label\t$level\t$comment\n";
	DEBUG "To $nsca: $name;$service: $label;$level;$comment\n";
    }
    else
    {
	print $nsca "$name\t$service\t$level\t$comment\n";
	DEBUG "[DEBUG] To $nsca: $name;$service;$level;$comment\n";
    }
}


sub munin_createlock {
    # Create lock file, fail and die if not possible.
    my ($lockname) = @_;
    if (sysopen (LOCK,$lockname,O_WRONLY | O_CREAT | O_EXCL)) {
	DEBUG "[DEBUG] Creating lock : $lockname succeeded\n";
	print LOCK $$; # we want the pid inside for later use
	close LOCK;
	return 1;
    } else {
	LOGCROAK("Creating lock $lockname failed: $!\n");
    }
}


sub munin_removelock {
    # Remove lock or die trying.
    my ($lockname) = @_;

    unlink $lockname or
      LOGCROAK("[FATAL ERROR] Error deleting lock $lockname: $!\n");
}


sub munin_runlock {
    my ($lockname) = @_;
    unless (munin_getlock($lockname)) {
	LOGCROAK("[FATAL ERROR] Lock already exists: $lockname. Dying.\n");
    }
    return 1;
}


sub munin_getlock {
    my ($lockname) = @_;
    if (-f $lockname) {
	DEBUG "[DEBUG] Lock $lockname already exists, checking process";
	# Is the lockpid alive?

	# To check this is inteligent and so on.  It also makes for a
	# nice locking racing-condition.  BUT, since munin-* runs from
	# cron every 5 minutes this should not be a real threat.  This
	# ream of code should complete in less than 5 minutes.

	open my $LOCK, '<', $lockname or
	  LOGCROAK("Could not open $lockname for reading: $!\n");
	my $pid = <$LOCK>;
	$pid = '' if !defined($pid);
	close($LOCK) or LOGCROAK("Could not close $lockname: $!\n");
	
	DEBUG "[DEBUG] Lock contained pid '$pid'";
	
        # Make sure it's a proper pid
	if (defined($pid) and $pid =~ /^(\d+)$/ and $1 != 1) {
	    $pid = $1;
	    if (kill(0, $pid)) {
		DEBUG "[DEBUG] kill -0 $pid worked - it is still alive. Locking failed.";
	        return 0;
	    }
	    INFO "[INFO] Process $pid is dead, stealing lock, removing file";
	} else {
	    INFO "[INFO] PID in lock file is bogus.  Removing lock file";
	}
	munin_removelock($lockname);
    }
    DEBUG "[DEBUG] Creating new lock file $lockname";
    munin_createlock($lockname);
    return 1;
}


sub munin_delete {
    my ($config,$data) = @_;
    for my $domain (keys %{$data->{domain}}) {
	unless ($config->{domain}->{$domain}) {
	    DEBUG "[DEBUG] Removing domain: $domain";
	    delete ($data->{domain}->{$domain});
	    next;
	}
	for my $node (keys %{$data->{domain}->{$domain}->{node}}) {
	    unless ($config->{domain}->{$domain}->{node}->{$node}) {
		DEBUG "[DEBUG] Removing node from $domain: $node";
		delete ($data->{domain}->{$domain}->{node}->{$node});
	    }
	}
    }
    return ($data);
}


sub munin_overwrite {
    # copy from $overwrite OVER $config.

    my ($configfile,$overwrite) = @_;
    for my $key (keys %$overwrite) {
	next if substr($key,0,3) eq '#%#';
	if (ref $overwrite->{$key}) {
	    if (!defined $configfile->{$key}) {
		if (ref $overwrite->{$key} eq "HASH") {
		    $configfile->{$key}->{'#%#parent'} = $configfile; weaken($configfile->{$key}->{'#%#parent'});
		    $configfile->{$key}->{'#%#name'}   = $key;
		    munin_overwrite($configfile->{$key},$overwrite->{$key});
		} else {
		    $configfile->{$key} = $overwrite->{$key};
		}
	    } else {
		munin_overwrite($configfile->{$key},$overwrite->{$key});
	    }
	} else {
	    $configfile->{$key} = $overwrite->{$key};
	}
    }
    return ($configfile);
}

sub munin_readconfig_raw {
    my ($conf, $missingok) = @_;

    my $part = undef;

    $conf ||= $configfile;
    # try first to read storable version
    $part = munin_read_storable("$conf.storable");
    if (!defined $part) {
        if (! -r $conf and ! $missingok) {
            WARN "munin_readconfig: cannot open '$conf'";
            return;
        }
        if (open (my $CFG, '<', $conf)) {
            my @contents = <$CFG>;
            close ($CFG);
            $part = munin_parse_config (\@contents);
        }
    }

    return $part;
}


sub munin_parse_config
{
    my $lines    = shift;
    my $hash     = {};
    my $prefix   = "";
    my $prevline = "";

    foreach my $line (@{$lines})
    {
	chomp $line;
	if ($line =~ /#/) {
	    next if ($line =~ /^#/);
	    $line =~ s/(^|[^\\])#.*/$1/g;
	    $line =~ s/\\#/#/g;
	}
	next unless ($line =~ /\S/);  # And empty lines...
	if (length $prevline) {
	    $line = $prevline . $line;
	    $prevline = "";
	}
	if ($line =~ /\\\\$/) {
	    $line =~ s/\\\\$/\\/;
	} elsif ($line =~ /\\$/) {
	    ($prevline = $line) =~ s/\\$//;
	    next;
	}
	$line =~ s/\s+$//g;           # And trailing whitespace...
	$line =~ s/^\s+//g;           # And heading whitespace...

	if ($line =~ /^\.(\S+)\s+(.+)\s*$/) {
	    my ($var, $val) = ($1, $2);
	    $hash = munin_set_var_path ($hash, $var, $val);
	} elsif ($line =~ /^\s*\[([^\]]*)]\s*$/) {
	    $prefix = $1;
	    if ($prefix =~ /^([^:]+);([^:;]+)$/) {
		$prefix .= ":";
	    } elsif ($prefix =~ /^([^:;]+);$/) {
		$prefix .= "";
	    } elsif ($prefix =~ /^([^:;]+);([^:;]+):(.*)$/) {
		$prefix .= ".";
	    } elsif ($prefix =~ /^([^:;]+)$/) {
		(my $domain = $prefix) =~ s/^[^\.]+\.//;
		$prefix = "$domain;$prefix:";
	    } elsif ($prefix =~ /^([^:;]+):(.*)$/) {
		(my $domain = $prefix) =~ s/^[^\.]+\.//;
		$prefix = "$domain;$prefix.";
	    }
	} elsif ($line =~ /^\s*(\S+)\s+(.+)\s*$/) {
	    my ($var, $val) = ($1, $2);
	    $hash = munin_set_var_path ($hash, "$prefix$var", $val);
	} else {
	    warn "Malformed configuration line \"$line\".";
	}
    }
    return $hash;
}


sub munin_get_var_path
{
    my $hash = shift;
    my $var  = shift;
    my $val  = shift;

    DEBUG "DEBUG: Getting var \"$var\" = \"$val\"\n";
    if ($var =~ /^\s*([^;:]+);([^;:]+):(\S+)\s*$/)
    {
	my ($dom, $host, $rest) = ($1, $2, $3);
	my @sp = split (/\./, $rest);

	if (@sp == 3)
	{
	    return $hash->{domain}->{$dom}->{node}->{$host}->{client}->{$sp[0]}->{"$sp[1].$sp[2]"};
	}
	elsif (@sp == 2)
	{
	    return $hash->{domain}->{$dom}->{node}->{$host}->{client}->{$sp[0]}->{$sp[1]};
	}
	elsif (@sp == 1)
	{
	    return $hash->{domain}->{$dom}->{node}->{$host}->{$sp[0]};
	}
	else
	{
	    warn "munin_set_var_path: Malformatted variable path \"$var\".";
	}
    }
    elsif ($var =~ /^\s*([^;:]+);([^;:]+)\s*$/)
    {
	my ($dom, $rest) = ($1, $2);
	my @sp = split (/\./, $rest);

	if (@sp == 1)
	{
	    return $hash->{domain}->{$dom}->{$sp[0]};
	}
	else
	{
	    warn "munin_set_var_path: Malformatted variable path \"$var\".";
	}
    }
    elsif ($var =~ /^\s*([^;:\.]+)\s*$/)
    {
	return $hash->{$1};
    }
    else
    {
	warn "munin_set_var_path: Malformatted variable path \"$var\".";
    }

    return;
}


sub munin_find_field {
    # Starting at the (presumably the root) $hash make recursive calls
    # until for example graph_title or value is found, and then
    # continue recursing and itterating until all are found.
    #
    # Then we return a array of pointers into the $hash
    #
    # This function will not use REs as they are inordinately
    # expensive.  There is a munin_find_field_for_limits that will
    # match REs instead of whole strings.

    my ($hash, $field, $avoid) = @_;

    my $res = [];

    if (ref ($hash) eq "HASH") {
	foreach my $key (keys %{$hash}) {
	    next if substr($key,0,3) eq '#%#';
	    last if defined $avoid and $key eq $avoid;
	    # Always check $key eq $field first here, or we break
	    if ($key eq $field) {
		push @$res, $hash;
	    } elsif (ref ($hash->{$key}) eq "HASH") {
		push @$res, @{munin_find_field ($hash->{$key}, $field, $avoid)};
	    }
	}
    }

    return $res;
}


sub munin_find_field_for_limits {
    my ($hash, $field, $avoid) = @_;

    my $res = [];

    if (ref ($field) ne "Regexp") {
	$field = qr/^$field$/;
    }

    if (ref ($hash) eq "HASH") {
	foreach my $key (keys %{$hash}) {
	    next if substr($key,0,3) eq '#%#';
	    last if defined $avoid and $key eq $avoid;
	    if (ref ($hash->{$key}) eq "HASH") {
		push @$res, @{munin_find_field_for_limits ($hash->{$key}, $field, $avoid)};
	    } elsif ($key =~ $field) {
		push @$res, $hash;
	    }
	}
    }

    return $res;
}


sub munin_get_children {
    my $hash  = shift;
    my $res = [];

    return if (ref ($hash) ne "HASH");

    foreach my $key (keys %{$hash}) {
	next if substr($key,0,3) eq '#%#';
	if (defined $hash->{$key} and ref ($hash->{$key}) eq "HASH") {
	    push @$res, $hash->{$key};
	}
    }

    return $res;
}


sub munin_get_separated_node
{
    my $hash = shift;
    my $ret  = {};

    if (ref ($hash) eq "HASH") {
	foreach my $key (keys %$hash) {
	    next if substr($key,0,3) eq '#%#';
	    if (ref ($hash->{$key}) eq "HASH") {
		$ret->{$key} = munin_get_separated_node ($hash->{$key});
	    } else {
		$ret->{$key} = $hash->{$key};
	    }
	}
    } else {
	return;
    }

    return $ret;
}


sub munin_get_parent_name
{
    my $hash = shift;

    if (ref ($hash) eq "HASH" and defined $hash->{'#%#parent'}) {
	return munin_get_node_name ($hash->{'#%#parent'});
    } else { 
	return "none";
    }
}

sub munin_get_orig_node_name {
    my $hash = shift;

    if (ref ($hash) eq "HASH" and defined $hash->{'#%#name'}) {
		return (defined $hash->{'#%#origname'}) ? $hash->{'#%#origname'} : $hash->{'#%#name'};
    } else { 
	return;
    }
}

sub munin_get_node_name
{
    my $hash = shift;

    if (ref ($hash) eq "HASH" and defined $hash->{'#%#name'}) {
		return $hash->{'#%#name'};
    } else { 
	return;
    }
}


sub munin_get_node_fqn
{
    my $hash = shift;

    if (ref ($hash) eq "HASH") {
	my $fqn = "";
	if (defined $hash->{'#%#name'}) {
		$fqn = $hash->{'#%#name'};
	}
 	if (defined $hash->{'#%#parent'}) {
		# Recursively prepend the parent, concatenation with /
		$fqn = munin_get_node_fqn ($hash->{'#%#parent'}) . "/" . $fqn;
	}
	return $fqn;
    } else {
	return;
    }
}


sub munin_find_node_by_fqn {
    # The FQN should be relative to the point in the hash we're handed.
    my($hash,$fqn) = @_;

    my $here = $hash;

    my @path = split('/',$fqn);

    foreach my $pc (@path) {
	next if $pc eq 'root';
	if (exists $here->{$pc}) {
	    $here = $here->{$pc};
	} else {
	    confess "Could not find FQN $fqn!";
	}
    }
    return $here ;
}


sub munin_get_picture_loc {
    my $hash = shift;
    my $res = [];

    if (ref ($hash) ne "HASH") { # Not a hash node
    	return;
    }
    if (defined $hash->{'#%#origin'}) {
	$res = munin_get_picture_loc ($hash->{'#%#origin'});
    } elsif (defined $hash->{'#%#origparent'}){
        $res = munin_get_picture_loc ($hash->{'#%#origparent'});
        push @$res, munin_get_orig_node_name ($hash) if defined $res;
    } elsif (defined $hash->{'#%#parent'}) {
	    $res = munin_get_picture_loc ($hash->{'#%#parent'});
	    push @$res, munin_get_orig_node_name ($hash) if defined $res;
    }
    return $res;
}


sub munin_get_node_loc {
    my $hash = shift;
    my $res = [];

    if (ref ($hash) ne "HASH") { # Not a has node
        return;
    }
    if (defined $hash->{'#%#parent'}) {
        if(defined $hash->{'#%#origparent'}){
            $res = munin_get_node_loc ($hash->{'#%#origparent'});
        } else {
            $res = munin_get_node_loc ($hash->{'#%#parent'});
        }
        push @$res, munin_get_orig_node_name ($hash) if defined $res;
    }
    return $res;
}

sub munin_get_parent {
    my $hash = shift;

    if (ref ($hash) ne "HASH") { # Not a has node
    	return;
    }
    if (defined $hash->{'#%#parent'}) {
	return $hash->{'#%#parent'};
    } else {
	return;
    }
}


sub munin_get_node {
    # From the given point in the hash itterate deeper into the
    # has along the path given by the array in $loc.
    # 
    # If any part of the path in $loc is undefined we bail.
    my $hash = shift;
    my $loc  = shift;

    foreach my $tmpvar (@$loc) {
	if (! exists $hash->{$tmpvar} ) {
	    # Only complain on a blank key if is no key like that. Usually it
	    # shouln't, so it avoids a needless regexp in this highly used
	    # function
	    ERROR "[ERROR] munin_get_node: Cannot work on hash node '$tmpvar'" if ($tmpvar !~ /\S/);
	    return undef;
        }	
	$hash = $hash->{$tmpvar};
    }
    return $hash;
}

sub munin_set {
    my $hash = shift;
    my $var  = shift;
    my $val  = shift;

    return munin_set_var_loc ($hash, [$var], $val);
}


sub munin_set_var_loc
{
    my $hash = shift;
    my $loc  = shift;
    my $val  = shift;

    my $iloc = 0;

    # XXX -  Dirty breaking recursive function 
    # --> Using goto is BAD, but enough for now
START:

    # Find the next normal value (that doesn't begin with #%#)
    my $tmpvar = $loc->[$iloc++];
    $tmpvar = $loc->[$iloc++] while (defined $tmpvar and
				 substr($tmpvar,0,3) eq '#%#');

    if (index($tmpvar, " ") != -1) {
	ERROR "[ERROR] munin_set_var_loc: Cannot work on hash node \"$tmpvar\"";
	return;
    }
    if (scalar @$loc > $iloc) {
	if (!defined $hash->{$tmpvar} or !defined $hash->{$tmpvar}->{"#%#name"}) { 
            # Init the new node
	    $hash->{$tmpvar}->{"#%#parent"} = $hash; weaken($hash->{$tmpvar}->{"#%#parent"});
	    $hash->{$tmpvar}->{"#%#name"} = $tmpvar;
	}
	# Recurse
        $hash = $hash->{$tmpvar};
	goto START;
    } else {
        WARN "[WARNING] munin_set_var_loc: Setting unknown option '$tmpvar' at "
	    . munin_get_keypath($hash)
	    unless Munin::Common::Config::cl_is_keyword($tmpvar);

	# FIX - or not.

        $hash->{$tmpvar} = $val;
	return $hash;
    }
}


sub munin_get_node_partialpath
{
    my $hash = shift;
    my $var  = shift;
    my $ret  = undef;

    return if !defined $hash or ref ($hash) ne "HASH";

    my $root    = munin_get_root_node ($hash);
    my $hashloc = munin_get_node_loc ($hash);
    my $varloc  = undef;

    if ($var =~ /^\s*([^:]+):(\S+)\s*$/) {
	my ($leftstring, $rightstring) = ($1, $2);

	my @leftarr = split (/;/, $leftstring);
	my @rightarr = split (/\./, $rightstring);
	push @$varloc, @leftarr, @rightarr
    } elsif ($var =~ /^\s*([^;:.]+)\s*$/) {
	push @$varloc, $var;
    } elsif ($var =~ /^\s*([^.]+)\.([^:;]+)$/) {
	my ($leftstring, $rightstring) = ($1, $2);

	my @leftarr = split (/;/, $leftstring);
	my @rightarr = split (/\./, $rightstring);
	push @$varloc, @leftarr, @rightarr;
    } elsif ($var =~ /^\s*(\S+)\s*$/) {
	my @leftarr = split (/;/, $1);
	push @$varloc, @leftarr;
    } else {
	ERROR "[ERROR] munin_get_node_partialpath: Malformed variable path \"$var\".";
    }

    # We've got both parts of the loc (varloc and hashloc) -- let's figure out 
    # where they meet up.
    do {
	$ret = munin_get_node ($root, [@$hashloc, @$varloc]);
    } while (!defined $ret and pop @$hashloc);

    return $ret;
}


sub munin_set_var_path
{
    my $hash = shift;
    my $var  = shift;
    my $val  = shift;

    my $result = undef;

    DEBUG "[DEBUG] munin_set_var_path: Setting var \"$var\" = \"$val\"";

    if ($var =~ /^\s*([^:]+):(\S+)\s*$/) {
	my ($leftstring, $rightstring) = ($1, $2);

	my @leftarr = split (/;/, $leftstring);
	my @rightarr = split (/\./, $rightstring);
	$result = munin_set_var_loc ($hash, [@leftarr, @rightarr], $val);
    } elsif ($var =~ /^\s*([^;:\.]+)\s*$/) {
        $result = munin_set_var_loc ($hash, [$1], $val);
    } elsif ($var =~ /^\s*([^:;]+)$/) {
	my @leftarr = split (/\./, $1);
	$result = munin_set_var_loc ($hash, [@leftarr], $val);
    } elsif ($var =~ /^\s*(.+)\.([^\.:;]+)$/) {
	my ($leftstring, $rightstring) = ($1, $2);

	my @leftarr = split (/;/, $leftstring);
	my @rightarr = split (/\./, $rightstring);
	$result = munin_set_var_loc ($hash, [@leftarr, @rightarr], $val);
    } elsif ($var =~ /^\s*(\S+)\s*$/) {
	my @leftarr = split (/;/, $1);
	$result = munin_set_var_loc ($hash, [@leftarr], $val);
    } else {
	ERROR "Error: munin_set_var_path: Malformatted variable path \"$var\".";
    }

    if (!defined $result) {
	ERROR "Error: munin_set_var_path: Failed setting \"$var\" = \"$val\".";
    }

    return $hash;
}


sub munin_get_root_node
{
    my $hash = shift;

    return if ref ($hash) ne "HASH";

    while (defined $hash->{'#%#parent'}) {
	$hash = $hash->{'#%#parent'};
    }

    return $hash;
}


sub munin_writeconfig_loop {
    my ($hash,$fh,$pre) = @_;

    foreach my $key (keys %$hash) {
	next if substr($key,0,3) eq '#%#';
	my $path = (defined $pre ? join(';', ($pre, $key)) : $key);
	if (ref ($hash->{$key}) eq "HASH") {
	    munin_writeconfig_loop ($hash->{$key}, $fh, $path);
	} else {
	    next if !defined $pre and $key eq "version"; # Handled separately
	    next if !defined $hash->{$key} or !length $hash->{$key};
            (my $outstring = $hash->{$key}) =~ s/([^\\])#/$1\\#/g;
	    # Too much.  Can be seen in the file itself.
	    # DEBUG "[DEBUG] Writing: $path $outstring\n";
	    if ($outstring =~ /\\$/)
	    { # Backslash as last char has special meaning. Avoid it.
		print $fh "$path $outstring\\\n"; 
	    } else {
		print $fh "$path $outstring\n";
	    }
	}
    }
}

sub munin_read_storable {
	my ($storable_filename, $default) = @_;

	if (-e $storable_filename) {
		my $storable = eval { Storable::retrieve($storable_filename); };
		return $storable unless $@;

		# Didn't managed to read storable. 
		# Removing it as it is already torched anyway.
		unlink($storable_filename);
	}
	
	# return default if no better option
	return $default;
}

sub munin_write_storable {
	my ($storable_filename, $data) = @_;
	DEBUG "[DEBUG] about to write '$storable_filename'";

	# We don't need to write anything if there is nothing to write.
	return unless defined $data;

	my $storable_filename_tmp = $storable_filename . ".tmp.$$";

	# Write datafile.storable, in network order to be architecture indep
        Storable::nstore($data, $storable_filename_tmp);

	# Atomic commit
	rename ($storable_filename_tmp, $storable_filename);
}

sub munin_writeconfig_storable {
	my ($datafilename,$data) = @_;

	DEBUG "[DEBUG] Writing state to $datafilename";

	munin_write_storable($datafilename, $data);
}

sub munin_writeconfig {
    my ($datafilename,$data,$fh) = @_;

    DEBUG "[DEBUG] Writing state to $datafilename";

    my $is_fh_already_managed = defined $fh;
    if (! $is_fh_already_managed) {
	$fh = gensym();
	unless (open ($fh, ">", $datafilename)) {
	    LOGCROAK "Fatal error: Could not open \"$datafilename\" for writing: $!";
	}
    }
    
    # Write version
    print $fh "version $VERSION\n";
    # Write datafile
    munin_writeconfig_loop ($data, $fh);
    
    if (! $is_fh_already_managed) {
        DEBUG "[DEBUG] Closing filehandle \"$datafilename\"...\n";
        close ($fh);
    }
}

sub munin_dumpconfig_as_str {
    my ($config) = @_;

    local $Data::Dumper::Sortkeys = sub { [ sort grep {!/^#%#parent$/} keys %{$_[0]} ]; };
    local $Data::Dumper::Indent = 1;

    return Dumper $config;
}


sub munin_dumpconfig {
    my ($config) = @_;
    my $indent = $Data::Dumper::Indent;
    my $sorter = $Data::Dumper::Sortkeys;

    $Data::Dumper::Sortkeys =
      sub { [ sort grep {!/^#%#parent$/} keys %{$_[0]} ]; };
    $Data::Dumper::Indent = 1;

    print "##\n";
    print "## NOTE: #%#parent is hidden to make the print readable!\n";
    print "##\n";
    print Dumper $config;

    $Data::Dumper::Sortkeys = $sorter;
    $Data::Dumper::Indent = $indent;
}

sub munin_configpart_revision {
    my $what = shift;
    if (defined $what and defined $config_parts->{$what}) {
	return $config_parts->{$what}{revision};
    }
    my $rev = 0;
    foreach $what (keys %$config_parts) {
	$rev += $config_parts->{$what}{revision};
    }
    return $rev;
}

sub munin_readconfig_part {
    my $what = shift;
    my $missingok = shift;
    if (! defined $config_parts->{$what}) {
	ERROR "[ERROR] munin_readconfig_part with unknown part name ($what).";
	return undef;
    }
    # for now, we only really care about storable.
    # No reason to bother reading non-storable elements anyway.
    my $filename = "$config->{dbdir}/$what.storable";
    my $part = {};
    my $doupdate = 0;
    if (! -f $filename) {
	unless (defined $missingok and $missingok) {
		ERROR "[FATAL] munin_readconfig_part($what) - missing file";
		exit(1);
	}
	# missing ok, return last value if we have one, copy config if not
	unless (defined $config_parts->{$what}{config}) {
		# well, not if we shouldn't include the config
		if ($config_parts->{$what}{include_base}) {
			$doupdate = 1;
		}
	}
    } else {
    	my @stat = stat($filename);
	if ($config_parts->{$what}{timestamp} < $stat[9]) {
	    # could use _raw if we wanted to read non-storable fallback
	    $config_parts->{$what}{config} = undef; # Unalloc RAM for old config, since it will be overriden anyway.
	    $part = munin_read_storable($filename);
	    $config_parts->{$what}{timestamp} = $stat[9];
	    $doupdate = 1;
	}
    }
    if ($doupdate) {
	$part->{'#%#name'} = 'root';
	$part->{'#%#parent'} = undef;
	$part = munin_overwrite($part, $config) if ($config_parts->{$what}{include_base});
	$config_parts->{$what}{config} = $part;
	++$config_parts->{$what}{revision};
    }
    return $config_parts->{$what}{config};
}

sub munin_readconfig_base {
    my $conffile = shift;

    $conffile ||= $configfile;
    $config = munin_readconfig_raw($conffile);

    if (defined $config->{'includedir'}) {
	my $dirname = $config->{'includedir'};
	DEBUG "Includedir statement to include files in $dirname";

	my $DIR;
	opendir($DIR, $dirname) or
	    WARN "[Warning] Could not open includedir directory $dirname: $OS_ERROR\n";
	my @files = grep { ! /^\.|~$/ } readdir($DIR);
	closedir($DIR);

	@files = map { $_ = $dirname.'/'.$_; } (sort @files);

	foreach my $f (@files) {
	    INFO "Reading additional config from $f";

	    my $extra = munin_readconfig_raw ($f);
	    # let the new values overwrite what we already have
	    $config = munin_overwrite($config, $extra);
	}
    }

    # Some important defaults before we return...
    $config->{'dropdownlimit'} ||= $Munin::Common::Defaults::DROPDOWNLIMIT;
    $config->{'rundir'}        ||= $Munin::Common::Defaults::MUNIN_STATEDIR;
    $config->{'dbdir'}         ||= $Munin::Common::Defaults::MUNIN_DBDIR;
    $config->{'logdir'}        ||= $Munin::Common::Defaults::MUNIN_LOGDIR;
    $config->{'tmpldir'}       ||= "$Munin::Common::Defaults::MUNIN_CONFDIR/templates/";
    $config->{'staticdir'}     ||= "$Munin::Common::Defaults::MUNIN_CONFDIR/static/";
    $config->{'htmldir'}       ||= $Munin::Common::Defaults::MUNIN_HTMLDIR;
    $config->{'spooldir'}      ||= $Munin::Common::Defaults::MUNIN_SPOOLDIR;
    $config->{'#%#parent'}     = undef;
    $config->{'#%#name'}       = "root";

    return $config;
}


sub munin_get_html_filename {
    # Actually only used in M::M::HTMLOld

    my $hash    = shift;

    my $loc     = munin_get_node_loc ($hash);
    my $ret     = munin_get ($hash, 'htmldir');
    my $plugin  = "index";

    # Sanitise
    $ret =~ s/[^\w_\/"'\[\]\(\)+=-]\./_/g;
    $hash =~ s/[^\w_\/"'\[\]\(\)+=-]/_/g;
    @$loc = map { 
        my $l = $_;
        $l =~ s/\//_/g; 
        $l =~ s/^\./_/g;
        $l;
    } @$loc;
	
    if (defined $hash->{'graph_title'} and !munin_has_subservices ($hash)) {
        $plugin = pop @$loc or return;
    }
    
    if (@$loc) { # The rest is used as directory names...
        $ret .= "/" . join ('/', @$loc);
    }
    
    return "$ret/$plugin.html";
}


sub munin_get_picture_filename {
    my $hash    = shift;
    my $scale   = shift;
    my $sum     = shift;

    my $loc     = munin_get_picture_loc ($hash);
    my $ret     = munin_get ($hash, 'htmldir');

    # Sanitise
    $ret =~ s/[^\w_\/"'\[\]\(\)+=-]\./_/g;
    $hash =~ s/[^\w_\/"'\[\]\(\)+=-]/_/g;
    $scale =~ s/[^\w_\/"'\[\]\(\)+=-]/_/g;
    @$loc = map { 
        my $l = $_;
        $l =~ s/\//_/g; 
        $l =~ s/^\./_/g;
        $l;
    } @$loc;
	
    my $plugin = pop @$loc or return;
    my $node   = pop @$loc or return;

    if (@$loc) { # The rest is used as directory names...
	$ret .= "/" . join ('/', @$loc);
    }

    if (defined $sum and $sum) {
	    return "$ret/$node/$plugin-$scale-sum.png";
    } elsif (defined $scale) {
	    return "$ret/$node/$plugin-$scale.png";
    } else {
	    return "$ret/$node/$plugin.png";
    }
}


sub munin_path_to_loc
{
    my $path = shift;

    my $result = undef;

    if ($path =~ /^\s*([^:]+):(\S+)\s*$/) {
	my ($leftstring, $rightstring) = ($1, $2);

	my @leftarr = split (/;/, $leftstring);
	my @rightarr = split (/\./, $rightstring);
	$result = [@leftarr, @rightarr];
    } elsif ($path =~ /^\s*([^;:\.]+)\s*$/) {
        $result = [$1];
    } elsif ($path =~ /^\s*(.+)\.([^\.:;]+)$/) {
	my ($leftstring, $rightstring) = ($1, $2);

	my @leftarr = split (/;/, $leftstring);
	my @rightarr = split (/\./, $rightstring);
	$result = [@leftarr, @rightarr];
    } elsif ($path =~ /^\s*(\S+)\s*$/) {
	my @leftarr = split (/;/, $1);
	$result = [@leftarr];
    } else {
	ERROR "[ERROR] munin_path_to_loc: Malformatted variable path \"$path\".";
    }

    if (!defined $result) {
	ERROR "[ERROR] munin_path_to_loc: Failed converting \"$path\".";
    }

    return $result;
}


sub munin_get_keypath {
    my $hash = shift;
    my $asfile = shift || '';

    my @group = ();
    my $host = 0;
    my @service = ();

    my $i = $hash;

    while (ref ($i) eq "HASH") {
	# Not sure when a #%#name node can go missing
	my $name = $i->{'#%#name'} || '*BUG*';
	goto gotoparent if $name eq '*BUG*';
	last if $name eq 'root';
	if ($host) {
	    # Into group land now
	    unshift(@group,$name);
	} else {
	    # In service land, working towards host.
	    # If i or my parent has a graph_title we're still working with services
	    if (defined $i->{'#%#parent'}{graph_title} or defined $i->{graph_title}) {
		$name =~ s/-/_/g; # can't handle dashes in service or below
		unshift(@service,$name);
	    } else {
		$host = 1;
		unshift(@group,$name);
	    }
	}
      gotoparent:
	$i=$i->{'#%#parent'};
    }

    if ($asfile) {
	return (shift @group).'/'.join('/',@group).'-'.join('-',@service);
    } else {
	return join(';',@group).':'.join('.',@service);
    }
}


sub munin_get_filename {
    my $hash = shift;

    my $loc  = munin_get_keypath ($hash,1);
    my $ret  = munin_get ($hash, "dbdir");
    
    if (!defined $loc or !defined $ret) {
        return;
    }
    
    return ($ret . "/$loc-" . lc substr (munin_get($hash, "type", "GAUGE"), 0,1). ".rrd");
}


sub munin_get_bool
{
    my $hash   = shift;
    my $field  = shift;
    my $default = shift;

    my $ans = munin_get ($hash, $field, $default);
    return if not defined $ans;

    if ($ans =~ /^yes$/i or
        $ans =~ /^true$/i or
        $ans =~ /^on$/i or
        $ans =~ /^enable$/i or
        $ans =~ /^enabled$/i
       ) {
	return 1;
    } elsif ($ans =~ /^no$/i or
        $ans =~ /^false$/i or
        $ans =~ /^off$/i or
        $ans =~ /^disable$/i or
        $ans =~ /^disabled$/i
      ) {
	return 0;
    } elsif ($ans !~ /\D/) {
	return $ans;
    } else {
	return $default;
    }
}

sub munin_get_bool_val
{
    my $field    = shift;
    my $default  = shift;

    if (!defined $field)
    {
    if (!defined $default)
    {
        return 0;
    }
    else
    {
        return $default;
    }
    }

    if ($field =~ /^yes$/i or
        $field =~ /^true$/i or
        $field =~ /^on$/i or
        $field =~ /^enable$/i or
        $field =~ /^enabled$/i
       )
    {
    return 1;
    }
    elsif ($field =~ /^no$/i or
        $field =~ /^false$/i or
        $field =~ /^off$/i or
        $field =~ /^disable$/i or
        $field =~ /^disabled$/i
      )
    {
    return 0;
    }
    elsif ($field !~ /\D/)
    {
    return $field;
    }
    else
    {
    return;
    }
}


sub munin_get
{
    my ($hash, $field, $default) = @_;

    # Iterate to top if needed
    do {
        return $default if (ref ($hash) ne "HASH");

        my $hash_field = $hash->{$field};
        return $hash_field if (defined $hash_field && ref($hash_field) ne "HASH");

        # Go up
        $hash = $hash->{'#%#parent'};
    } while (defined $hash);

    return $default;
}


sub munin_copy_node_toloc
{
    my $from = shift;
    my $to   = shift;
    my $loc  = shift;

    return unless defined $from and defined $to and defined $loc;

    if (ref ($from) eq "HASH") {
	foreach my $key (keys %$from) {
	    next if substr($key,0,3) eq '#%#';
	    if (ref ($from->{$key}) eq "HASH") {
		munin_copy_node_toloc ($from->{$key}, $to, [@$loc, $key]);
	    } else {
		munin_set_var_loc ($to, [@$loc, $key], $from->{$key});
	    }
	}
    } else {
	$to = $from;
    }
    return $to;
}


sub munin_copy_node
{
    my $from = shift;
    my $to   = shift;

    if (ref ($from) eq "HASH") {
	foreach my $key (keys %$from) {
	    if (ref ($from->{$key}) eq "HASH") {
                # Easier to do with the other copy function
		munin_copy_node_toloc ($from->{$key}, $to, [$key]); 
	    } else {
		munin_set_var_loc ($to, [$key], $from->{$key});
	    }
	}
    } else {
	$to = $from;
    }
    return $to;
}


sub munin_node_status
{
    my ($config, $limits, $domain, $node, $check_draw) = @_;
    my $state = "ok";

    return unless defined $config->{domain}->{$domain}->{node}->{$node};
    my $snode = $config->{domain}->{$domain}->{node}->{$node};

    foreach my $service (keys %{$snode})
    {
	my $fres  = munin_service_status ($config, $limits, $domain, $node, $service, $check_draw);
	if (defined $fres)
	{
	    if ($fres eq "critical")
	    {
		$state = $fres;
		last;
	    }
	    elsif ($fres eq "warning")
	    {
		$state = $fres;
	    }
	}
    }

    return $state;
}


sub munin_category_status {
    my $hash       = shift || return;
    my $limits     = shift || return;
    my $category   = shift || return;
    my $check_draw = 1;
    my $state      = "ok";

    return unless (defined $hash and ref ($hash) eq "HASH");

    foreach my $service (@{munin_get_children ($hash)}) {
	next if (!defined $service or ref ($service) ne "HASH");
	next if (!defined $service->{'graph_title'});
	next if ($category ne munin_get ($service, "graph_category", "other"));
	next if ($check_draw and not munin_get_bool ($service, "graph", 1));

	my $fres  = munin_service_status ($service, $limits, $check_draw);
	if (defined $fres) {
	    if ($fres eq "critical") {
		$state = $fres;
		last;
	    } elsif ($fres eq "warning") {
		$state = $fres;
	    } elsif ($fres eq "unknown" and $state eq "ok") {
		$state = $fres;
	    }
	}
    }

    return $state;
}

sub munin_service_status {
    my ($config, $limits, $check_draw) = @_;
    my $state = "ok";

    return unless defined $config;
    for my $fieldnode (@{munin_find_field ($config, "label")}) {
	my $field = munin_get_node_name ($fieldnode);
	my $fres  = munin_field_status ($fieldnode, $limits, $check_draw);
	if (defined $fres) {
	    if ($fres eq "critical") {
		$state = $fres;
		last;
	    } elsif ($fres eq "warning") {
		$state = $fres;
	    }
	}
    }

    return $state;
}


sub munin_field_status {
    my ($hash, $limits, $check_draw) = @_;
    my $state = "ok";

    # Return undef if nagios is turned off, or the field doesn't have any limits
    if ((!defined munin_get ($hash, "warning", undef)) and (!defined munin_get ($hash, "critical"))) {
	return;
    }

    if (!defined $check_draw or !$check_draw or munin_draw_field ($hash)) {
	my $loc  = munin_get_node_loc ($hash);
	my $node = munin_get_node ($limits, $loc);
	return $node->{"state"} || "ok";
    }
    return $state;
}

sub munin_graph_column_headers
{
    my ($config, $domain, $node, $serv) = @_;
    my $ret = 0;
    my @fields = ();

    foreach my $field (keys %{$config->{domain}->{$domain}->{node}->{$node}->{client}->{$serv}})
    {
	if ($field =~ /^([^\.]+)\.negative$/ and munin_draw_field ($config->{domain}->{$domain}->{node}->{$node}, $serv, $1))
	{
	    return 1;
	}
	elsif ($field =~ /^([^\.]+)\.label$/ and munin_draw_field ($config->{domain}->{$domain}->{node}->{$node}, $serv, $1))
	{
	    push @fields, $1;
	}
    }

    return 1 if (munin_get_max_label_length ($config->{'domain'}->{$domain}->{'node'}->{$node}, $config, $domain, $node, $serv, \@fields) > 20);

    return $ret;
}


sub munin_get_max_label_length
{
    my $service = shift;
    my $order   = shift;
    my $result  = 0;
    my $tot     = munin_get ($service, "graph_total");

    for my $field (@$order) {
	my $path = undef;
	(my $f = $field) =~ s/=.+//;
	next if (!munin_get_bool ($service->{$f}, "process", 1));
	next if (munin_get_bool ($service->{$f}, "skipdraw", 0));
	next if (!munin_get_bool ($service->{$f}, "graph", 1));

	my $len = length (munin_get ($service->{$f}, "label") || $f);

	if ($result < $len) {
	    $result = $len;
	}
    }
    if (defined $tot and length $tot > $result) {
	$result = length $tot;
    }
    return $result;
}


sub munin_get_field_order
{
    my $hash = shift;
    my $result  = [];

    return if !defined $hash or ref($hash) ne "HASH";

    my $order = munin_get ($hash, "graph_order");

    if (defined $hash->{graph_sources}) {
	foreach my $gs (split /\s+/, $hash->{'graph_sources'}) {
	    push (@$result, "-".$gs);
	}
    } 
    if (defined $order) {
	push (@$result, split /\s+/, $order);
    } 

    for my $fieldnode (@{munin_find_field ($hash, "label")}) {
        my $fieldname = munin_get_node_name ($fieldnode);
	push @$result,$fieldname
	    if !grep m[^\Q$fieldname\E(?:=|$)], @$result;
    }

    for my $fieldnode (@{munin_find_field ($hash, "stack")}) {
        my $fieldname = munin_get_node_name ($fieldnode);
	push @$result,$fieldname 
	    if !grep m[^\Q$fieldname\E(?:=|$)], @$result;;
    }

    # We have seen some occurances of redundance in the graph_order
    # due to plugin bugs and so on.  This make process_service
    # generate rrd commands with multiple definitions of the same
    # data.  SO: Make sure there is no redundance in the order.

    my %seen = ();
    my $nresult = [];

    for my $field (@$result) {
	next if exists($seen{$field});

	push @$nresult, $field;
	$seen{$field}=1;
    }
    
    return $nresult;
}


sub munin_get_rrd_filename {
    my $field   = shift;
    my $path    = shift;

    my $result  = undef;

    # Bail out on bad input data
    return if !defined $field or ref ($field) ne "HASH";

    # If the field has a .filename setting, use it
    if ($result = munin_get ($field, "filename")) {
	return $result;
    }

    # Handle custom paths (used in .sum, .stack, graph_order, et al)
    if (defined $path and length $path) {

	my $sourcenode = munin_get_node_partialpath ($field, $path);
	$result = munin_get_filename ($sourcenode);

	for my $f (@COPY_FIELDS) {
	    if (not exists $field->{$f} and exists $sourcenode->{$f}) {
		DEBUG "DEBUG: Copying $f...\n";
		munin_set_var_loc ($field, [$f], $sourcenode->{$f});
	    }
	}
    } else {
	$result = munin_get_filename ($field);
    }
    return $result;
}


sub munin_mkdir_p {
    my ($dirname, $umask) = @_;

    eval {
        mkpath($dirname, 0, $umask);
    };
    return if $EVAL_ERROR;
    return 1;
}

sub exit_if_run_by_super_user {
    if ($EFFECTIVE_USER_ID == 0) {
        print qq{This program will easily break if you run it as root as you are
trying now.  Please run it as user '$Munin::Common::Defaults::MUNIN_USER'.  The correct 'su' command
on many systems is 'su - munin --shell=/bin/bash'
Aborting.
};
        exit 1;
    }
}

sub print_version_and_exit {
    print qq{munin version $Munin::Common::Defaults::MUNIN_VERSION.

Copyright (C) 2002-2009 Jimmy Olsen, Audun Ytterdal, Tore Andersson, Kjell-Magne Øierud, Nicolai Langfeldt, Linpro AS, Redpill Linpro AS and others.

This is free software released under the GNU General Public
License. There is NO warranty; not even for MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. For details, please refer to the file
COPYING that is included with this software or refer to
http://www.fsf.org/licensing/licenses/gpl.txt
};
    exit 0;
}


sub look_for_child {
    # wait for child process in blocking or non-blocking mode.
    my ($block) = @_;

    my $pid;

    if ($block) {
    	$pid = waitpid(-1, 0);
    } else {
        $pid = waitpid(-1, WNOHANG);
        if ($pid == 0) {
            return 0;
        }
    }

    if ($pid < 0) {
        ERROR "[ERROR] Unexpectedly ran out of children: $!";
	croak "[ERROR] Ran out of children: $!\n";
    }

    if ($? != 0) {
        WARN "[WARNING] Child $pid failed: " . ($? << 8) . 
	    "(signal " . ($? & 0xff) . ")";
    }
    return 1;
}


sub wait_for_remaining_children {
    my ($running) = @_;
    while ($running > 0) {
	look_for_child("block");
	--$running;
    }
    return $running;
}

sub munin_has_subservices {
    my ($hash) = @_;
    return 0 unless defined $hash;

    # Only services (which again require graph_title) can have subservices
    return 0 unless defined $hash->{'graph_title'};

    if (!defined $hash->{'#%#has_subservices'}) {
	$hash->{'#%#has_subservices'} = scalar (grep $_, map { ref($hash->{$_}) eq "HASH" and $_ ne '#%#parent' and defined $hash->{$_}->{'graph_title'} ? 1 : undef } keys %$hash);
    }
    return $hash->{'#%#has_subservices'};
}

sub munin_get_host_path_from_string {
	# splits a host definition, as used in the config, into a group array and a host name
	my $key = shift;
	my (@groups) = split(';', $key);
	my $host = pop(@groups);
	if(scalar @groups > 0){
	} else {
		my @groups = split('.', $key);
		if(scalar @groups > 1){
			@groups = ($groups[0]);
		}
	}
	return (\@groups, $host);
}

1;

__END__

=head1 NAME

Munin::Master::Utils - Exports a lot of utility functions.

=head1 SYNOPSIS

 use Munin::Master::Utils;

=head1 SUBROUTINES

=over

=item B<munin_category_status>

Gets current status of a category.

Parameters: 
 - $hash: A ref to the hash node whose children to check
 - $limits: A ref to the root node of the limits tree
 - $category: The category to review
 - $check_draw: [optional] Ignore undrawn fields

Returns:
 - Success: The status of the field
 - Failure: undef


=item B<munin_readconfig_base>

Read configuration file, include dir files, and initialize important
default values that are optional.

Parameters:
 - $file: munin.conf filename. If omitted, default filename is used.

Returns:
 - Success: The $config hash (also cached in module)

=item B<munin_copy_node>

Copy hash node.

Parameters:
 - $from: Hash node to copy
 - $to: Where to copy it to

Returns:
 - Success: $to
 - Failure: undef


=item B<munin_copy_node_toloc>

Copy hash node at.

Parameters:
 - $from: Hash node to copy
 - $to: Where to copy it to
 - $loc: Path to node under $to

Returns:
 - Success: $to
 - Failure: undef


=item B<munin_createlock>



=item B<munin_delete>



=item B<munin_draw_field>

Check whether a field will be visible in the graph or not.

Parameters:
 - $hash: A ref to the hash node for the field

Returns:
 - Success: Boolean; true if field will be graphed, false if not
 - Failure: undef


=item B<munin_field_status>

Gets current status of a field.

Parameters: 
 - $hash: A ref to the field hash node
 - $limits: A ref to the root node of the limits tree
 - $check_draw: [optional] Ignore undrawn fields

Returns:
 - Success: The status of the field
 - Failure: undef


=item B<munin_find_field>

Search a hash to find hash nodes with $field defined.

Parameters: 
 - $hash: A hash ref to search
 - $field: The name of the field to search for, or a regex
 - $avoid: [optional] Stop traversing further down if this field is found

Returns:
 - Success: A ref to an array of the hash nodes containing $field.
 - Failure: undef


=item B<munin_get>

Get variable.

Parameters:
 - $hash: Ref to hash node
 - $field: Name of field to get
 - $default: [optional] Value to return if $field isn't set

Returns:
 - Success: field contents
 - Failure: $default if defined, else undef


=item B<munin_get_bool>

Get boolean variable.

Parameters:
 - $hash: Ref to hash node
 - $field: Name of field to get
 - $default: [optional] Value to return if $field isn't set

Returns:
 - Success: 1 or 0 (true or false)
 - Failure: $default if defined, else undef


=item B<munin_get_bool_val>



=item B<munin_get_children>

Get all child hash nodes.

Parameters: 
 - $hash: A hash ref to the parent node

Returns:
 - Success: A ref to an array of the child nodes
 - Failure: undef


=item B<munin_get_field_order>

Get the field order in a graph.

Parameters:
 - $hash: A hash ref to the service

Returns:
 - Success: A ref to an array of the field names
 - Failure: undef


=item B<munin_get_filename>

Get rrd filename for a field, without any bells or whistles. Used by
munin-update to figure out which file to update.

Parameters:
 - $hash: Ref to hash field

Returns:
 - Success: Full path to rrd file
 - Failure: undef


=item B<munin_get_html_filename>

Get the full path-name of an html file.

Parameters:
 - $hash: A ref to the service hash node

Returns:
 - Success: The file name with full path
 - Failure: undef


=item B<munin_get_max_label_length>

Get the length of the longest label in a graph.

Parameters:
 - $hash: the graph in question
 - $order: A ref to an array of fields (graph_order)

Returns:
 - Success: The length of the longest label in the graph
 - Failure: undef


=item B<munin_get_node>

Gets a node by loc.

Parameters:
 - $hash: A ref to the hash to set the variable in
 - $loc: A ref to an array with the full path of the node

Returns:
 - Success: The node ref found by $loc
 - Failure: undef

=item B<munin_get_node_loc>

Get location array for hash node.

Parameters: 
 - $hash: A ref to the node

Returns:
 - Success: Ref to an array with the full path of the variable
 - Failure: undef


=item B<munin_get_node_name>

Return the name of the hash node supplied.

Parameters: 
 - $hash: A ref to the hash node

Returns:
 - Success: The name of the node


=item B<munin_get_node_partialpath>

Gets a node from a partial path.

Parameters: 
 - $hash: A ref to the "current" location in the hash tree
 - $var: A path string with relative location (from the $hash).

Returns:
 - Success: The node
 - Failure: undef


=item B<munin_get_parent>

Get parent node of a hash.

Parameters: 
 - $hash: A ref to the node

Returns:
 - Success: Ref to an parent
 - Failure: undef


=item B<munin_get_parent_name>

Return the name of the parent of the hash node supplied

Parameters: 
 - $hash: A ref to the hash node

Returns:
 - Success: The name of the parent node
 - Failure: If no parent node exists, "none" is returned.


=item B<munin_get_picture_filename>

Get the full path+name of a picture file.

Parameters:
 - $hash: A ref to the service hash node
 - $scale: [optional] The scale (day, week, year, month)
 - $sum: [optional] Boolean value, whether it's a sum graph or not.

Returns:
 - Success: The file name with full path
 - Failure: undef


=item B<munin_get_picture_loc>

Get location array for hash node for picture purposes. Differs from
munin_get_node_loc in that it honors #%#origin metadata

Parameters: 
 - $hash: A ref to the node 

Returns: 
 - Success: Ref to an array with the full path of the variable
 - Failure: undef


=item B<munin_get_root_node>

Get the root node of the hash tree.

Parameters:
 - $hash: A hash node to traverse up from

Returns:
 - Success: A ref to the root hash node
 - Failure: undef


=item B<munin_get_rrd_filename>

Get the name of the rrd file corresponding to a field. Checks for lots
of bells and whistles.  This function is the correct one to use when
figuring out where to fetch data from.

Parameters:
 - $field: The hash object of the field
 - $path: [optional] The path to the field (as given in graph_order/sum/stack/et al)

Returns:
 - Success: A string with the filename of the rrd file
 - Failure: undef


=item B<munin_get_separated_node>


Copy a node to a separate node without "specials".

Parameters:
 - $hash: The node to copy

Returns:
 - Success: A ref to a new node without "#%#"-fields
 - Failure: undef


=item B<munin_get_var_path>



=item B<munin_getlock>



=item B<munin_graph_column_headers>


=item B<munin_has_subservices>

  munin_has_subservices($hash);

Checks whether the service represented by $hash has subservices (multigraph),
and returns the result.

Parameters:
 - $hash: Hash reference pointing to a service

Returns:
 - true: if the hash is indeed a service, and said service has got subservices
 - false: otherwise


=item B<munin_mkdir_p>

 munin_mkdir_p('/a/path/', oct('777'));

Make a directory and recursively any nonexistent directory in the path
to it.


=item B<munin_node_status>



=item B<munin_nscasend>



=item B<munin_overwrite>

Take contents of one config-namespace and replace/insert the instances
needed.

=item B<munin_parse_config>



=item B<munin_path_to_loc>

Returns a loc array from a path string.

Parameters: 
 - $path: A path string

Returns:
 - Success: A ref to an array with the loc
 - Failure: undef


=item B<munin_readconfig_part>

Read a partial configuration

Parameters:
 - $what: name of the part that should be loaded (datafile or limits)

Returns:
 - Success: a $config with the $specified part, but overwritten by $config

=item B<munin_removelock>



=item B<munin_runlock>



=item B<munin_service_status>

Gets current status of a service.

Parameters: 
 - $hash: A ref to the field hash node
 - $limits: A ref to the root node of the limits tree
 - $check_draw: [optional] Ignore undrawn fields

Returns:
 - Success: The status of the field
 - Failure: undef


=item B<munin_set>

Sets a variable in a hash.

Parameters: 
 - $hash: A ref to the hash to set the variable in
 - $var: The name of the variable
 - $val: The value to set the variable to

Returns:
 - Success: The $hash we were handed
 - Failure: undef


=item B<munin_set_var_loc>

Sets a variable in a hash.

Parameters: 
 - $hash: A ref to the hash to set the variable in
 - $loc: A ref to an array with the full path of the variable
 - $val: The value to set the variable to

Returns:
 - Success: The $hash we were handed
 - Failure: undef


=item B<munin_set_var_path>

Sets a variable in a hash.

Parameters: 
 - $hash: A ref to the hash to set the variable in
 - $var: A string with the full path of the variable
 - $val: The value to set the variable to

Returns:
 - Success: The $hash we were handed
 - Failure: The $hash we were handed


=item B<munin_writeconfig>



=item B<munin_writeconfig_loop>



=back

=head1 COPYING

Copyright (C) 2003-2007 Jimmy Olsen, Audun Ytterdal

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; version 2 dated June,
1991.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=cut

# vim: syntax=perl ts=8
