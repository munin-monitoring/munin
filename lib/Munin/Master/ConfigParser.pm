package Munin::Master::ConfigParser;

use warnings;
use strict;

use Carp;

=head1 NAME

Munin::Master::ConfigParser - Parse config v3 INI format

=head1 SYNOPSIS

    my $parser = Munin::Master::ConfigParser->new();
    $parser->parse_file('/etc/munin/munin.conf');
    $parser->parse_file('/etc/munin/munin.conf.d/10-web.conf');

    # Access parsed data
    my $globals = $parser->globals();
    my $sections = $parser->sections();

=head1 DESCRIPTION

Parses Munin config files in both legacy and new INI format.

Supports:
- Legacy syntax: `key value` with optional indentation
- New syntax: `key = value` or `key value`
- Sections: `[group;host]` or `[group;host;service]`
- Comments: lines starting with # or ;
- Glob patterns in sections: `[web;app*.com]`
- Context reset between files

=cut

sub new {
    my ($class, %args) = @_;

    my $self = bless {
        globals   => {},    # name => value
        sections  => {},    # 'group;host' => { name => value }
        globs     => [],    # [pattern, context, name, value]
        errors    => [],
        file      => undef,
        line_num  => 0,
    }, $class;

    return $self;
}

=head1 PARSING

=head2 parse_file($filename)

Parse a config file. Resets context at start (per spec).

=cut

sub parse_file {
    my ($self, $filename) = @_;

    open my $fh, '<', $filename
        or croak "Cannot open '$filename': $!";

    $self->{file} = $filename;
    $self->{line_num} = 0;

    $self->_parse_fh($fh);

    close $fh
        or croak "Cannot close '$filename': $!";

    return;
}

=head2 parse_string($text)

Parse config from a string. For testing.

=cut

sub parse_string {
    my ($self, $text) = @_;

    open my $fh, '<', \$text
        or croak "Cannot open string: $!";

    $self->{file} = '<string>';
    $self->{line_num} = 0;

    $self->_parse_fh($fh);

    close $fh;

    return;
}

sub _parse_fh {
    my ($self, $fh) = @_;

    my @context = ();  # Reset per file per spec

    while (my $line = <$fh>) {
        $self->{line_num}++;

        # Trim whitespace
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;

        # Skip empty lines
        next unless length $line;

        # Skip comments
        next if $line =~ /^[#;]/;

        # Handle sections: [group;host;service]
        if ($line =~ /^\[(.+)\]$/) {
            @context = split /;/, $1;
            # Trim each part
            @context = map { s/^\s+|\s+$//g; $_ } @context;
            next;
        }

        # Handle key = value or key value
        # Also handle legacy: key  value (with extra spaces)
        if ($line =~ /^([\w.\*?]+)\s*(?:=\s*)?(.+)$/) {
            my ($key, $value) = ($1, $2);

            # Trim value
            $value =~ s/^\s+//;
            $value =~ s/\s+$//;

            # Remove optional quotes
            if ($value =~ /^["'](.*)["']$/) {
                $value = $1;
            }

            $self->_store(\@context, $key, $value);
            next;
        }

        # If we get here, it's a syntax error
        push @{$self->{errors}}, {
            file     => $self->{file},
            line     => $self->{line_num},
            message  => "Syntax error: $line",
        };
    }

    return;
}

sub _store {
    my ($self, $context, $key, $value) = @_;

    # No context = global setting
    if (!@$context) {
        $self->{globals}{$key} = $value;
        return;
    }

    # Check if any part of context contains glob chars
    my $has_glob = grep /[\*\?]/, @$context;

    if ($has_glob) {
        # Store as glob pattern
        my $pattern = join(';', @$context);
        push @{$self->{globs}}, [$pattern, $pattern, $key, $value];
        return;
    }

    # Store in sections
    my $section_key = join(';', @$context);
    $self->{sections}{$section_key}{$key} = $value;

    return;
}

=head1 ACCESSORS

=head2 globals()

Returns hashref of global settings.

=cut

sub globals {
    my ($self) = @_;
    return $self->{globals};
}

=head2 sections()

Returns hashref of section settings: { 'group;host' => { key => value } }

=cut

sub sections {
    my ($self) = @_;
    return $self->{sections};
}

=head2 globs()

Returns arrayref of glob patterns: [pattern, context, name, value]

=cut

sub globs {
    my ($self) = @_;
    return $self->{globs};
}

=head2 errors()

Returns arrayref of parse errors.

=cut

sub errors {
    my ($self) = @_;
    return $self->{errors};
}

=head2 has_errors()

Returns true if there were parse errors.

=cut

sub has_errors {
    my ($self) = @_;
    return scalar @{$self->{errors}};
}

=head1 IMPORT TO DB

=head2 import_to_db($configdb)

Import parsed config into a ConfigDB object.

=cut

sub import_to_db {
    my ($self, $configdb) = @_;

    # Import globals
    for my $key (keys %{$self->{globals}}) {
        $configdb->insert_global($key, $self->{globals}{$key});
    }

    # Import sections
    for my $section_key (keys %{$self->{sections}}) {
        my $settings = $self->{sections}{$section_key};
        my @parts = split /;/, $section_key;

        # Ensure hierarchy exists
        my $hid = $configdb->ensure_hierarchy(\@parts);

        # Store settings
        for my $key (keys %$settings) {
            $configdb->insert_host_setting($hid, $key, $settings->{$key});
        }
    }

    # Import globs
    for my $glob (@{$self->{globs}}) {
        my ($pattern, $context, $name, $value) = @$glob;
        $configdb->insert_glob($pattern, $context, $name, $value);
    }

    return;
}

1;

__END__

=head1 AUTHOR

Munin Team

=head1 LICENSE

GPLv2+

=cut
