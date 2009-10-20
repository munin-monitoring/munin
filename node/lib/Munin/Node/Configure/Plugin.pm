package Munin::Node::Configure::Plugin;

use strict;
use warnings;

use Munin::Node::Configure::Debug;


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


# returns true if the plugin is in one of the families
sub in_family { $_[0]->{family} eq $_  && return 1 foreach @_; return 0; }


sub is_installed { return @{(shift)->{installed}} ? 'yes' : 'no'; }


# report which services (link or wildcard) should be added, removed,
# or left as they are.
#   (remove) = (installed) \ (suggested)
#   (add)    = (suggested) \ (installed)
#   (same)   = (installed) ⋂ (suggested)
sub _remove { _set_difference(@_); }
sub _add    { _set_difference(reverse @_); }
sub _same   { _set_intersection(@_); }


# returns a string of the form:
# 'no',  'no [reason why it's not used]',
# 'yes', 'yes (unchanged +additions -removals)'
sub suggestion_string
{
    my ($self) = @_;
    my $msg = '';

    if ($self->{default} eq 'yes') {
        my @suggestions = _same($self->_installed_wild, $self->_suggested_wild);
        push @suggestions,
            map { "+$_" } _add($self->_installed_wild, $self->_suggested_wild);
        push @suggestions,
            map { "-$_" } _remove($self->_installed_wild, $self->_suggested_wild);

        $msg = ' (' . join(' ', @suggestions) . ')' if @suggestions;
    }
    elsif ($self->{defaultreason}) {
        # Report why it's not being used
        $msg = " [$self->{defaultreason}]";
    }

    return $self->{default} . $msg;
}


sub installed_services_string { return join ' ', @{(shift)->_installed_wild}; }


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


# Converts a wildcard into a human-readable form
sub _flatten_wildcard { return ref($_[0]) ? join('/', @{$_[0]}) : $_[0]; }


################################################################################

# return an arrayref of the installed and suggested service names (eg. 'memory'
# or 'if_eth0')
sub _installed_links { return (shift)->{installed}; }

sub _suggested_links
{
    my ($self) = @_;
    if ($self->{default} eq 'yes' and not $self->is_wildcard) {
        return [ $self->{name} ];
    }
    else {
        return [ map { $self->_expand_wildcard($_) } @{$self->{suggestions}} ];
    }
}

# return an arrayref of the installed or suggested wildcards (eg. 'eth0' or
# 'switch.example.com/1').  nothing is returned if the plugin contains no wildcards.
sub _installed_wild { return [ map { $_[0]->_reduce_wildcard($_) } @{$_[0]->{installed}} ]; }
sub _suggested_wild { return [ map { _flatten_wildcard($_) } @{(shift)->{suggestions}}]; }


# returns a list of service names that should be added for this plugin
sub services_to_add
{
    my ($self) = @_;
    return _add($self->_installed_links, $self->_suggested_links);
}

# returns a list of service names that should be removed.
sub services_to_remove
{
    my ($self) = @_;
    return _remove($self->_installed_links, $self->_suggested_links);
}


# Associates a link name from the servicedir with this plugin
sub add_instance { push @{(shift)->{installed}}, shift; }


# Adds a suggestion
sub add_suggestions { push @{(shift)->{suggestions}}, @_; }


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
            $self->add_suggestions($line);
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


### Set operations #############################################################

# returns the list of elements in arrayref $a that are not in arrayref $b
# NOTE this is *not* a method.
sub _set_difference
{
    my ($A, $B) = @_;
    my %set;
    @set{@$A} = ();
    delete @set{@$B};
    return sort keys %set;
}


# returns the list of elements common to arrayrefs $a and $b
# NOTE this is *not* a method.
sub _set_intersection
{
    my ($A, $B) = @_;
    my %set;
    @set{@$A} = (1) x @$A;
    return sort grep $set{$_}, @$B;
}


1;
# vim: sw=4 : ts=4 : expandtab
