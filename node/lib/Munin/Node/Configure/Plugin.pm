package Munin::Node::Configure::Plugin;

use strict;
use warnings;

use Data::Dumper;


sub new
{
    my ($class, %opts) = @_;

    my $name = delete $opts{name} or die "Must provide name\n";
    my $path = delete $opts{path} or die "Must provide path\n";

    my %plugin = (
        name         => $name,      # the (base)name of the plugin
        path         => $path,      # the full path to the plugin
        default      => 'no',       # whether this plugin thinks it should be installed
        installed    => [],         # list of installed services (as link names)
        suggestions  => [],         # list of suggestions (as wildcards)
        family       => 'contrib',  # the family it belongs to
        capabilities => {},         # what capabilities it supports
        errors       => [],         # list of errors reported against this plugin

        %opts,
    );

    return bless \%plugin, $class;
}


################################################################################

sub is_wildcard { return ((shift)->{path} =~ /_$/); }

sub is_installed { return @{(shift)->{installed}} ? 'yes' : 'no'; }


# reports which wildcard plugin identities should be added, removed,
# or left as they are.  in (sort of) mathematical terms:
#   (remove) = (installed) \ (suggested)
#   (add)    = (suggested) \ (installed)
#   (same)   = (installed) ⋂ (suggested)
sub _diff_suggestions
{
    my ($installed, $suggested) = @_;

    my (%remove, %add, %same);
    @remove{ @$installed } = ();
    @add{ @$suggested }    = ();
    @same{ @$installed }   = (1) x scalar @$installed;

    foreach my $to_remove (@$suggested) {
        delete $remove{$to_remove};
    }

    foreach my $to_add (@$installed) {
        delete $add{$to_add};
    }

    my @same = grep $same{$_}, @$suggested;

    my @add    = sort keys %add;
    my @remove = sort keys %remove;

    return (\@same, \@add, \@remove);
}


# returns a string of the form:
# 'no',  'no [reason why it's not used]',
# 'yes', 'yes (unchanged +additions -removals)'
sub suggestion_string
{
    my ($self) = @_;
    my $msg = '';

    if ($self->{default} eq 'yes') {
        my ($same, $add, $remove) = _diff_suggestions($self->installed_wild,
                                                      $self->suggested_wild);
        my @suggestions = @$same;
        push @suggestions, map { '+' . $_ } @$add;
        push @suggestions, map { '-' . $_ } @$remove;

        $msg = ' (' . join(' ', @suggestions) . ')' if @suggestions;
    }
    elsif ($self->{defaultreason}) {
        # Report why it's not being used
        $msg = " [$self->{defaultreason}]";
    }

    return $self->{default} . $msg;
}


sub installed_services_string { return join ' ', @{(shift)->installed_wild}; }


### Service name <-> wildcard conversion ###############################################
# NOTE that these functions do not round-trip!

# Extracts the wildcards from a service name and formats them in a user-friendly way.
sub _reduce_wildcard
{
    my ($self, $link_name) = @_;
    my $name = $self->{name};
    my $wild;

    if ($name =~ /^snmp_(_\w+)/) {
        $link_name =~ /^snmp_(.+)$1(.*)/;
        $wild = $1 . (length($2)? "/$2" : '');  # FIXME hack :-(
    }
    else {
        ($wild = $link_name) =~ s/^$name//;
    }
    DEBUG("\tFound wildcard instance '$wild'");
    return length($wild)? $wild : ();  # FIXME more hack
}


# converts a wildcard to the appropriate service name
sub _expand_wildcard
{
    my ($self, $suggestion) = @_;

    if ($self->{name} =~ /^snmp__(\w+)/) {
        my ($host, $wild) = @$suggestion;
        $wild ||= '';
        return 'snmp_' . $host . '_' . $1 . $wild;
    }
    else {
        return $self->{name} . $suggestion;
    }
}


################################################################################

# return an arrayref of the installed and suggested service names (eg. 'memory'
# or 'if_eth0')
sub installed_links { return (shift)->{installed}; }
sub suggested_links { return [ map { $_[0]->_expand_wildcard($_) } @{$_[0]->{suggestions}} ]; }

# return an arrayref of the installed or suggested wildcards (eg. 'eth0' or
# 'switch.example.com/1').  nothing is returned if the plugin contains no wildcards.
# FIXME: behaviour of non-wildcard plugins?
sub installed_wild { return [ map { $_[0]->_reduce_wildcard($_) } @{$_[0]->{installed}} ]; }
sub suggested_wild { return (shift)->{suggestions}; }


# returns a list of service names that should be added for this plugin
sub services_to_add
{
    my ($self) = @_;

    if ($self->{default} eq 'yes') {
        # FIXME: hack
        push @{$self->{suggestions}}, '';
    }
    return @{(_diff_suggestions($self->installed_links, $self->suggested_links))[1]};
}


# returns a list of service names that should be removed.
sub services_to_remove
{
    my ($self) = @_;
    return @{(_diff_suggestions($self->installed_links, $self->suggested_links))[2]};
}


# Associates a link name from the servicedir with this plugin
sub add_instance { push @{(shift)->{installed}}, shift; }


# Extracts any magic-markers from the plugin
sub read_magic_markers
{
    my ($self) = @_;
    my $PLUGIN;

    DEBUG("\tReading magic markers.");

    unless (open ($PLUGIN, '<', $self->{path})) {
        DEBUG("Could not open plugin '$self->{path}' for reading: $!");
        return;
    }

    while (<$PLUGIN>) {
        if (/#%#\s+family\s*=\s*(\S+)\s*/) {
            $self->{family} = $1;
            DEBUG("\tSet family to '$1'." );
        }
        elsif (/#%#\s+capabilities\s*=\s*(.+)/) {
            my @caps = split(/\s+/, $1);
            foreach my $capability (@caps) {
                $self->{capabilities}{$capability} = 1;
            }
            DEBUG("\tCapabilities are: ", join(', ', @caps));
        }
    }
    close ($PLUGIN);
    return;
}


### Parsing plugin responses ###################################################

sub parse_autoconf_response
{
    my ($self, @response) = @_;

    unless (scalar(@response) == 1) {
        # FIXME: not a good message
        $self->log_error('Wrong amount of autoconf');
        return;
    }

    my $line = shift @response;

    unless ($line =~ /^(yes)$/
         or $line =~ /^(no)(?:\s+\((.*)\))?\s*$/)
    {
        $self->log_error("Junk printed to stdout");
        return;
    }

    DEBUG("\tGot yes/no: $line");

    $self->{default} = $1;
    $self->{defaultreason} = $2;

    return;
}


sub parse_suggest_response
{
    my ($self, @suggested) = @_;

    foreach my $line (@suggested) {
        if ($line =~ /^[-\w.]+$/) {
            DEBUG("\tAdded suggestion: $line");
            push @{$self->{suggestions}}, $line;
        }
        else {
            $self->log_error("\tBad suggestion: $line");
        }
    }

    unless (@{ $self->{suggestions} }) {
        $self->log_error("No suggestions");
        return;
    }

    return;
}


my $oid_pattern      = qr/^[0-9.]+[0-9]+$/;
my $oid_root_pattern = qr/^[0-9.]+\.$/;

sub parse_snmpconf_response
{
    my ($self, @response) = @_;

    foreach my $line (@response) {
        my ($key, $value) = $line =~ /(\w+)\s+(.+\S)/;

        next unless $key and defined $value;

        DEBUG("\tAnalysing line: $line");

        if ($key eq 'require') {
            my ($oid, $regex) = split /\s+/, $value, 2;

            if ($oid =~ /$oid_root_pattern/) {
                $oid =~ s/\.$//;
                push @{ $self->{require_root} }, [$oid, $regex];

                DEBUG("\tRegistered 'require': $oid");
                DEBUG("\t\tFiltering on /$regex/") if $regex;
            }
            elsif ($oid =~ /$oid_pattern/) {
                push @{ $self->{require_oid} }, [$oid, $regex];

                DEBUG("\tRegistered 'require': $oid");
                DEBUG("\t\tFiltering on /$regex/") if $regex;
            }
            else {
                $self->log_error("Invalid format for 'require': $value");
            }
        }
        elsif ($key eq 'index') {
            if ($self->{index}) {
                $self->log_error('index redefined');
                next;
            }
            unless ($value =~ /$oid_root_pattern/) {
                $self->log_error('index must be an OID root');
                next;
            }

            ($self->{index} = $value) =~ s/\.$//;
            DEBUG("\tRegistered 'index'  : $value");
        }
        elsif ($key eq 'number') {
            if ($self->{number}) {
                $self->log_error('number redefined');
                next;
            }

            unless ($value =~ /$oid_pattern/) {
                $self->log_error('number must be an OID');
                next;
            }

            $self->{number} = $value;
            DEBUG("\tRegistered 'number' : $value");
        }
        else {
            $self->log_error("Couldn't parse line: $line");
        }
    }
}


### Debugging and error reporting ##############################################
# Logs an error due to this plugin, and prints it out if debugging is on
sub log_error
{
    my ($self, $msg) = @_;

    chomp $msg;
    push @{$self->{errors}}, $msg;
    DEBUG($msg);

    return;
}


use Munin::Node::Config;
my $config = Munin::Node::Config->instance;

# Prints out a debugging message
sub DEBUG { print '# ', @_, "\n" if $config->{DEBUG}; }


1;
# vim: sw=4 : ts=4 : expandtab
