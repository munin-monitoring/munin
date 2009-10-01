package Munin::Node::Configure::Plugin;

use strict;
use warnings;

use Data::Dumper;


sub new
{
    my ($class, %opts) = @_;

    my $name = delete $opts{name} or die;
    my $path = delete $opts{path} or die;

    my %plugin = (
        name         => $name,
        path         => $path,
        default      => 'no',
        installed    => [],
        suggestions  => [],
        installed_links => [],
        suggested_links => [],
        family       => 'contrib',
        capabilities => {},

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
sub diff_suggestions
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


sub suggestion_string
{
    my ($self) = @_;
    my $msg = '';  # either [reason] or (+add/-remove)

    if ($self->is_wildcard) {
        my ($same, $add, $remove) = diff_suggestions($self->{installed},
                                                     $self->{suggestions});
        my @suggestions = @$same;
        push @suggestions, map { '+' . $_ } @$add;
        push @suggestions, map { '-' . $_ } @$remove;

        $msg = '(' . join(' ', @suggestions) . ')' if @suggestions;
    }
    elsif ($self->{defaultreason}) {
        # Report why it's not being used
        $msg = "[$self->{defaultreason}]";
    }

    return $self->{default} . ' ' . $msg;
}


sub installed_services_string
{
    my ($self) = @_;
    my @installed = @{$self->{installed}};

    my $suggestions = '';
    if ($self->is_wildcard and @installed) {
        $suggestions = join ' ', @installed;
    }

    return $suggestions;
}


# returns a list of service names that should be added for this plugin
sub services_to_add
{
    my ($self) = @_;
    my @to_add;

    if ($self->is_wildcard) {
        my ($same, $add, $remove) = diff_suggestions($self->{installed_links},
                                                     $self->{suggested_links});
        @to_add = @$add;
    }
    else {
        @to_add = ($self->{name});
    }

    return @to_add;
}


# returns a list of service names that should be removed.
sub services_to_remove
{
    my ($self) = @_;
    my @to_remove;

    if ($self->{default} eq 'no') {
        # Damnatio memoriae!
        @to_remove = @{ $self->{installed} };
    }
    elsif ($self->is_wildcard) {
        my ($same, $add, $remove) = diff_suggestions($self->{installed_links},
                                                     $self->{suggested_links});
        @to_remove = @$remove;
    }

    return @to_remove;
}


sub add_instance
{
    my ($self, $instance) = @_;

    if ($self->is_wildcard) {
#        DEBUG("\tWildcard plugin '$service' resolves to '$realfile'");

        # FIXME: doesn't work with snmp__* plugins
        (my $wild = $instance) =~ s/^$self->{name}//;

#        DEBUG("\tAdding wildcard instance '$wild'");
        push @{ $self->{installed} },       $wild;
        push @{ $self->{installed_links} }, $instance;
    }

    return;
}


# Extracts any magic-markers from the plugin
sub read_magic_markers
{
    my ($self) = @_;
    my $PLUGIN;

    $self->{family} = 'contrib';
    $self->{capabilities} = {};

#   DEBUG("\tReading magic markers.");

    unless (open ($PLUGIN, '<', $self->{path})) {
#       DEBUG("Could not open plugin '$self->{path}' for reading: $!");
        return;
    }

    while (<$PLUGIN>) {
        if (/#%#\s+family\s*=\s*(\S+)\s*/) {
            $self->{family} = $1;
#           DEBUG("\tSet family to '$1'." );
        }
        elsif (/#%#\s+capabilities\s*=\s*(.+)/) {
            my @caps = split(/\s+/, $1);
            foreach my $capability (@caps) {
                $self->{capabilities}{$capability} = 1;
            }
#           DEBUG("\tCapabilities are: ", join(', ', @caps));
        }
    }
    close ($PLUGIN);
    return;
}


################################################################################

sub parse_autoconf_response
{
    my ($self, @response) = @_;

    # If there's anything else, it means more than one line was printed
    unless (scalar(@response) == 1) {
        # FIXME: not a good message
#       log_error($self->{name}, 'Wrong amount of autoconf');
        return;
    }

    my $line = shift @response;

    # The line it did print isn't in a valid format
    unless ($line =~ /^(yes)$/
         or $line =~ /^(no)(?:\s+\((.*)\))?\s*$/)
    {
#       log_error($self->{name}, "Junk printed to stdout");
        return;
    }

    # Some recognized response
#   DEBUG("\tGot yes/no: $line");

    $self->{default} = $1;
    $self->{defaultreason} = $2;

    return;
}


sub parse_suggest_response
{
    my ($plugin, @suggested) = @_;

    foreach my $line (@suggested) {
        if ($line =~ /^[-\w.]+$/) {
            # This looks like it should be a suggestion.
#           DEBUG("\tAdded suggestion: $line");
            push @{ $plugin->{suggestions} }, $line;
            push @{ $plugin->{suggested_links} }, $plugin->{name} . $line;
        }
        else {
#           log_error($plugin->{name}, "\tBad suggestion: $line");
        }
    }

    unless (@{ $plugin->{suggestions} }) {
#       log_error($plugin->{name}, "No suggestions");
        return;
    }

    return;
}


my $oid_pattern      = qr/^[0-9.]+[0-9]+$/;
my $oid_root_pattern = qr/^[0-9.]+\.$/;

sub parse_snmpconf_response
{
    my ($plugin, @response) = @_;

    foreach my $line (@response) {
        my ($key, $value) = $line =~ /(\w+)\s+(.+\S)/;

        next unless defined $key and defined $value;

#       DEBUG("\tAnalysing line: $line");

        if ($key eq 'require') {
            my ($oid, $regex) = split /\s+/, $value, 2;

            if ($oid =~ /$oid_root_pattern/) {
                $oid =~ s/\.$//;
                push @{ $plugin->{require_root} }, [$oid, $regex];

#               DEBUG("\tRegistered 'require': $oid");
#               DEBUG("\t\tFiltering on /$regex/") if $regex;
            }
            elsif ($oid =~ /$oid_pattern/) {
                push @{ $plugin->{require_oid} }, [$oid, $regex];

#               DEBUG("\tRegistered 'require': $oid");
#               DEBUG("\t\tFiltering on /$regex/") if $regex;
            }
            else {
#               log_error($plugin->{name},
#                   "Invalid format for 'require': $value");
            }
        }
        elsif ($key eq 'index') {
            if ($plugin->{index}) {
#               log_error($plugin->{name}, 'index redefined');
                next;
            }
            unless ($value =~ /$oid_root_pattern/) {
#               log_error($plugin->{name}, 'index must be an OID root');
                next;
            }

            ($plugin->{index} = $value) =~ s/\.$//;
#           DEBUG("\tRegistered 'index'  : $value");
        }
        elsif ($key eq 'number') {
            if ($plugin->{number}) {
#               log_error($plugin->{name}, 'number redefined');
                next;
            }

            unless ($value =~ /$oid_pattern/) {
#               log_error($plugin->{name}, 'number must be an OID');
                next;
            }

            $plugin->{number} = $value;
#           DEBUG("\tRegistered 'number' : $value");
        }
        else {
#           log_error($plugin->{name}, "Couldn't parse line: $line");
        }
    }

    return;
}


1;
# vim: sw=4 : ts=4 : expandtab
