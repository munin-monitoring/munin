package Munin::Master::Config;

use base qw(Munin::Common::Config);


# Notes about config data structure:
#
# In Munin all configuration and gathered data is stored in the same
# config tree of hashes.  Since ~april 2009 we've made the tree object
# oriented so the objects in there must be instantiated as the right
# object type.  And so we can use the object type to determine
# behaviour when we itterate over the objects in the tree.
#
# The Class Munin::Common::Config is the base of Munin::Master::Config.
# The master programs (munin-update, munin-limits) instantiate
# a Munin::Master::Config object.
#
# Please note that the munin-node configuration is also based on
# Munin::Common::Config but is quite a lot simpler with regards to syntax
#
# The Class Munin::Master::GroupRepository is based on Munin::Master::Config
# and contains a tree of Munin::Master::Group objects.
#
# The M::M::Group objects can be nested.  Under a M::M::Group object there
# can be a (flat) collection of M::M::Host objects.  The M::M::Host class
# is based in M::M::Group.
#
# A M::M::Host is a monitored host (not a node).  Munin gathers data
# about a host by connecting to a munin-node and asking about the host.
#
# Since multigraph plugins are hierarchical each host can contain
# data for nested plugin names/dataseries labels.
#
# The configuration file formats are everywhere identical in structure
# but the resulting configuration tree differs a bit.  On the munin-master
# the syntax is like this:
#
# Global setting:
#
#   attribute value
#
# Simple group/host/service tree:
#
#   Group;Host:service.attribute
#   Group;Host:service.label.attribute
#
# Groups can be nested:
#
#   Group;Group;Group;Host:(...)
#
# (When multigraph is supported) services can be nested:
#
#   (...);Host:service:service.(...)
#   (...);Host:service:service.service.(...)
#
# All attributes (attribute names) are known and appears in the @legal
# array (and accompanying hash).
#
# Structure:
# - A group name is always postfixed by a ;
# - The host name is the first word with a : after it
# - After that there are services and attributes
#
# For ease of configuration munin supports a [section] shorthand:
#
#   [Group;]
#   [Group;Group;]
#   [Group;Host]
#   [Group;Host:service]
#
# The section is prefixed to the subsequent settings in the appropriate
# manner with the correct infixes (";", ":" or ".").  Usage can look like
# this:
#
#   [Group;]
#      Group;Host:service.attribute value
#
# is equivalent to
#
#   [Group;Group;]
#      Host:service.attribute value
#
# is equivalent to
#
#   [Group;Group;Host]
#      service.attribute value
#
# is equivalent to
#
#   [Group;Group;Host:service]
#      attribute value
#
# As part of multigraph we're supporting nested services as well:
#
#   [Group;Group;Host]
#      service.attribute value
#      service.service.attribute value
#
#   [Group;Group;Host:service]
#      attribute value             # Group;Group;Host:service.attribute
#      :service.attribute value    # Group;Group;Host:service.service.attribute
#
#   [Group;Group;Host:service.service]
#      attribute value             # Group;Group;Host:service.service.attribute
#      service.attribute value    # ...;Host:service:service.service.attribute
#

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use Munin::Common::Defaults;
use Munin::Master::Group;
use Munin::Master::Host;
use Munin::Common::Logger;

my %booleans = map {$_ => 1} qw(
    debug
    verbose
    fork
    tls_verify_certificate
    update
    use_node_name
    use_default_node
);


{
    my $instance;

    sub instance {
        my ($class) = @_;

        $instance ||= bless {

	    # To be able to identify if we're the root instance or a nested one.
	    root_instance => 1,

	    config      => bless ( {
		carbon_server    => "",
		carbon_port      => "",
		carbon_prefix    => "",
		config_file      => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.conf",
		dbdir            => $Munin::Common::Defaults::MUNIN_DBDIR,
		verbose          => 0,
		debug            => 0,
		fork             => 1,
		graph_data_size  => 'normal',
		graph_strategy   => 'cron',
		groups           => {},
		local_address    => 0,
		logdir           => $Munin::Common::Defaults::MUNIN_LOGDIR,
		logoutput        => 'syslog',
		max_processes    => 16,
		rundir           => $Munin::Common::Defaults::MUNIN_STATEDIR,
		timeout          => 180,
		tls              => 'disabled',
		tls_ca_certificate => "$Munin::Common::Defaults::MUNIN_CONFDIR/cacert.pem",
		tls_certificate  => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.pem",
		tls_private_key  => "$Munin::Common::Defaults::MUNIN_CONFDIR/munin.pem",
		tls_verify_certificate => 0,
		tls_verify_depth => 5,
		tmpldir          => "$Munin::Common::Defaults::MUNIN_CONFDIR/templates",
	        staticdir        => "$Munin::Common::Defaults::MUNIN_CONFDIR/static",
	        cgitmpdir        => "$Munin::Common::Defaults::MUNIN_CGITMPDIR",
		ssh_command      => "ssh",
		ssh_options      => "-o ChallengeResponseAuthentication=no -o StrictHostKeyChecking=no",
	    }, $class ),

	    oldconfig => bless ( {
		config_file      => "$Munin::Common::Defaults::MUNIN_DBDIR/datafile",
	    }, $class ),

        }, $class;

        return $instance;
    }
}


# Returns true if $char is the last character of $str.
sub _final_char_is {
    # Not a object method.
    my ($char, $str) = @_;

    return rindex($str, $char) == ( length($str) - 1 );
}


sub _create_and_set {
    my ($self,$groups,$host,$key,$value) = @_;
    # Nested creation of group and host class objects, and then set
    # attribute value.

    my $setref = $self;  # Used as "iterator" as we traverse the hash.

    my @key = split(/\./, $key);
    my $last_word = pop @key;

    if ($booleans{$last_word}) {
	$value = $self->_parse_bool($value);
    }

    # If there is a host there is a group.  So need only check group to see
    # how deep we go.
    if ($#{$groups} == -1) {
	$self->{$key} = $value;
	return;
    }

    foreach my $group (@{$groups}) {
	# Create nested group objects
	$setref->{groups}{$group} ||= Munin::Master::Group->new($group);

	if ($setref eq $self) {
	    $setref->{groups}{$group}{group}=undef;
	} else {
	    $setref->{groups}{$group}{group}=$setref;
	}

	$setref = $setref->{groups}{$group};
    }

    if ($host) {
	if (! defined ( $setref->{hosts}{$host} ) ) {
	    $setref->{hosts}{$host} =
		Munin::Master::Host->new($host,$setref,{ $key => $value });
	} else {
            $setref->{hosts}{$host}->{$key} = $value;
	}
    } else {
	# Implant key/value into group
	$setref->{$key} = $value;
    }

    #
}


sub set_value {
    my ($self, $longkey, $value) = @_;

    my ($groups,$host,$key) = $self->_split_config_line($longkey);

    $self->_create_and_set($groups,$host,$key,$value);
}


sub _extract_group_name_from_definition {
    # Extract the group name from any munin.conf section name
    #
    # This a object method for the sake of finding it with the help of
    # a object of the right kind.

    # Cases:
    # * foo.example.com      ->  example.com
    # * bar;foo.example.com  ->  bar
    # * foo                  ->  foo
    # * bar;foo              ->  bar
    # * bar;		     ->  bar
    #
    # More cases:
    # * bar;foo.example.com:service

    my ($self, $definition) = @_;

    my $dot_loc = index($definition, '.');
    my $sc_loc = index($definition, ';');

    # Return bare hostname
    return $definition if $sc_loc == -1 and $dot_loc == -1;

    # Return explicit group name
    return substr($definition, 0, $sc_loc)
	if $sc_loc > -1 and ($dot_loc == -1 or $sc_loc < $dot_loc);

    # Return domain name as group name
    return substr($definition, $dot_loc + 1);
}


sub _concat_config_line {
    # Canonify and concatenate current prefix and the config line
    # we're parsing now in a correct manner.

    # See also _split_config_line.

    # No sanity checking in this procedure.  Use _concat_config_line_ok to
    # get sanity/syntax checking.

    my ($self, $prefix, $key, $value) = @_;

    my $longkey;

    # Allowed constructs:
    # [group;host]
    #     port 4949
    #
    # This is shorthand for [domain;host.domain]:
    #   [host.domain]
    #     port 4949
    #
    # [group;]
    # [group;host]
    # [group;host:service]
    # [group;host:service.field]
    # [group1;group2;host:service.field]
    #    keyword value
    #    field.keyword value (only if no service in prefix)
    #    group_order ....
    #
    # And more recently this for nested services (multigraph).
    # [group1;group2;host:service:service...]
    #     :service.field.keyword value
    #
    # Rules:
    # - Last ';' terminates group part
    # - Last ':' terminates the host part
    # - The rest is a collection of services and time series data
    #   - which we collect under the host name in the data-structure.

    # Note that keywords can come directly after group names in the
    # concatenated syntax: group;group_order ...

    if ($prefix eq '') {
	# If the prefix is empty then the key had better be well formed and
	# complete, because we'll use it without further checking.
	return $key;
    }

    if (index($prefix,';') == -1) {
	# Handle shorthand: Group name is given by host name
	my $group = $self->_extract_group_name_from_definition($prefix);
	$prefix = "$group;$prefix";
    }

    if (_final_char_is(';',$prefix)) {
	# Prefix ended in the middle of a group.  The rest can be
	# appended.
	$longkey = $prefix.$key;
    } elsif (index($prefix,':') != -1) {
	# Host name ends explicitly in the prefix. Use "." everywhere after :
	# Key is a nested service name
	$longkey = $prefix.'.'.$key;
    } else {
	# Prefix ends in host name but ":" is missing.
	$longkey = $prefix.':'.$key;
    }

    return $longkey;
}


sub _concat_config_line_ok {
    # Concatenate config line and do some extra syntaxy checks
    #
    # If the arrived at config line is not legal as far as we can tell
    # then croak here.

    my ($self, $prefix, $key, $value) = @_;

    if (!defined($key) or !$key) {
	ERROR "[ERROR] Somehow we're missing a keyword sometime after section [$prefix]";
	die "[ERROR] Somehow we're missing a keyword sometime after section [$prefix]";
    }

    my $longkey = $self->_concat_config_line($prefix,$key,$value);

    # _split_config_line_ok has the best starting point for checks on the
    # syntax/contents and so we call that to get the checks performed.
    #
    eval {
	$self->_split_config_line_ok($longkey);
    };
    if ($EVAL_ERROR) {
	# _split_config_line_ok already logged the problem.
	my $err_msg = "[ERROR] config error under [$prefix] for '$key $value' : $EVAL_ERROR";
	ERROR $err_msg;
	die $err_msg;
    }

    return $longkey;
}


sub _split_config_line {
    # After going to all that trouble with putting a "longkey" together
    # we now pursue splitting the key in a nice and accurate manner.
    #
    # See also _concat_config_line

    my ($self,$line) = @_;

    my $groups;
    my $host;
    my $key;

    # Cases to keep in mind
    #   htmldir
    #   Group;address
    #   Group;Group;address
    #   Group;Host:address
    #   Group;Host:if_eth0.in.value
    #   Group;Host:snmp_foo_if_input.snmp_foo_if_input_0.value

    my $sc = index($line,';');

    if ($sc == -1) {
	$groups='';
    } else {
	# Note that .+ is greedy so $groups is the whole groups grouping
	$line =~ /(.+);(.*)/;
	($groups, $line) = ($1, $2);
    }

    # Now left with (1:1 with cases above)
    #   address
    #   address
    #   Host:address
    #   Host:if_eth0.in.value
    #   Host:snmp_foo_if_input.snmp_foo_if_input_0.value

    my $cc = index($line,':');

    if ($cc == -1) {
	# No host delimiter: the rest is a setting
	$host = '';
	$key = $line;
    } else {
	# Can see host delimiter.  Copy it and the rest is a setting.
	$host = substr($line,0,$cc);
	substr($line,0,$cc+1) = '';
	$key = $line;
    }

    return ([split(';',$groups)],$host,$key);
}


sub _split_config_line_ok {
    # Split config line and do some extra syntaxy checks
    #
    # If all is not well we'll corak here.

    my ($self,$longkey,$value) = @_;


    my ($groups,$host,$key) = $self->_split_config_line($longkey);

    my @words = split (/[.]/, $key);
    my $last_word = pop(@words);

    if (! $self->is_keyword($last_word)) {
	# We have seen some problems with $value in the following
	# error message.  Se make sure it's defined so we can see the
	# message.
	$value = '' unless defined $value;
	croak "Parse error in ".$self->{config_file}." for $key:\n".
	    " Unknown keyword at end of left hand side of line $NR ($key $value)\n";
    }

    if ($host =~ /[^-A-Za-z0-9\.]/) {
	# Since we're not quite sure what context we're called in we'll report the error message more times rather than fewer.
	ERROR "[ERROR] Hostname '$host' contains illegal characters (http://en.wikipedia.org/wiki/Hostname#Restrictions_on_valid_hostnames).  Please fix this by replacing illegal characters with '-'.  Remember to do it on both in the master configuration and on the munin-node.";
	croak "[ERROR] Hostname '$host' contains illegal characters (http://en.wikipedia.org/wiki/Hostname#Restrictions_on_valid_hostnames).  Please fix this by replacing illegal characters with '-'.  Remember to do it on both in the master configuration and on the munin-node.\n";
    }

    return ($groups,$host,$key);
}


sub _parse_config_line {
    # Parse and save contents of random user configuration.
    my ($self, $prefix, $key, $value) = @_;

    my $longkey = $self->_concat_config_line_ok($prefix,$key,$value);

    $self->set_value($longkey,$value);
}


sub parse_config {
    my ($self, $io) = @_;

    my $section = undef;

    my $continuation = '';

    my $prefix = '';

    while (my $line = <$io>) {
        $self->_strip_comment($line);
        $self->_trim($line);

	# Handle continuation lines (ending in \)
	if ($line =~ s|\\$||) {
	    $continuation .= $line;
	    next;
	} elsif ($continuation) {
	    $line = $continuation . $line;
	    $continuation = '';
	}

        # This must be handled after continuation handling otherwise
	# empty lines will be ignored in continuation context.
        next if !length($line);

	# Group/host/service configuration is saved for later persual.
	# Everything else is saved at once.  Note that _trim removes
	# leading whitespace so section changes can only happen if a new
	# [foo] comes along.

        if ($line =~ m{\A \[ ([^]]+) \] \s* \z}xms) {
	    $prefix = $1;
	} else {
	    my($key,$value) = split(/\s+/,$line,2);
	    $self->_parse_config_line($prefix,$key,$value);
        }
    }
}


sub look_up {
	# The path through the hash works out to:
	# $self->{groups}{localdomain}[...]{hosts}{localhost}

    my ($self,$key) = @_;

    my (@groups) = split(';',$key);
    my $host = pop(@groups);

    my $value = $self;

    for my $group (@groups) {
	if (defined $value and
	    defined $value->{groups} and
	    defined $value->{groups}{$group}) {

	    $value = $value->{groups}{$group};

	} else {
	    return undef;
	}
    }

    if (defined $value and
	defined $value->{hosts} and
	defined $value->{hosts}{$host}) {

	return $value->{hosts}{$host};
    };

    return undef;
}


sub get_groups_and_hosts {
    my ($self) = @_;

    return $self->{groups};
}


sub get_all_hosts {
    # Note! This method is implemented in multiple classes to make the
    # recursion complete.
    my ($self) = @_;

    my @hosts = ();
    for my $group (values %{$self->{groups}}) {
        push @hosts, $group->get_all_hosts;
    }
    return @hosts;
}



sub set {
    my ($self, $config) = @_;

    # Note: config overrides self.
    %$self = (%$self, %$config);
}


1;


__END__

=head1 NAME

Munin::Master::Config - Holds the master configuration.

=head1 METHODS

=over

=item B<instance>

  my $config = Munin::Master::Config->instance;

Returns the (possibly newly created) singleton configuration instance.

=item B<set_value>

  $config->set_value($longkey, $value);

Set a value in the config, where $longkey is the full ;:. separated value.

=item B<parse_config>

  $config->parse_config($io);

Populates the fields of $config from the configuration file referred to by
filehandle $io.

=item B<look_up>

  my $value = $config->look_up($key);

Look up a group/host by a key such as "localdomain;localhost" etc.
If the path does not exist create it with correct class and so on.

Lookup ends at host name.  If something is missing along the way
undef is returned.

=item B<get_groups_and_hosts>

  my $gah = $config->get_groups_and_hosts();

Returns all the groups and hosts defined in the configuration.

=item B<get_all_hosts>

  my $hosts = $config->get_all_hosts();

Returns a list of all the hosts defined in the configuration.

=item B<set>

  $config->set(\%attrs);

Sets the keys and values in $config to those in %attrs.

=back

=cut
