package Munin::Node::Configure::Plugin;

use strict;
use warnings;


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


sub is_wildcard { return ((shift)->{path} =~ /_$/); }

sub is_installed { return @{(shift)->{installed}} ? 'yes' : 'no'; }


sub suggestion_string
{
    my ($self) = @_;
    my $msg = '';  # either [reason] or (+add/-remove)

    if ($self->is_wildcard) {
        my ($same, $add, $remove) = main::diff_suggestions($self->{installed},
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



1;
# vim: sw=4 : expandtab
