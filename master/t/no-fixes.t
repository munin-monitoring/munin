use warnings;
use strict;

# Check for comments and POD flagged with FIX.

# Are there any modules that already does this?
# Perl::Critic::Policy::Bangs::ProhibitFlagComments doesn't consider
# POD. Make a Perl::Critic::Policy out of this?

use English qw(-no_match_vars);
use File::Find;
use FindBin;
use Test::More tests => 1;
use Pod::Simple::TextContent;

my $count = 0;

find(\&fixes, "$FindBin::Bin/../lib");
is($count, 0, "Should not find any FIX comments");

sub fixes {

  my $file = $File::Find::name;

  return unless -f $file;

  #
  # Check comments
  #
  open my $F, '<', $file 
      or warn "Couldn't open $file: $!" && return;
  while (<$F>) {
      if (m{#\s*FIX}) {
          printf "Found a FIX comment at %s: %d\n",
              $file, $.;
          $count++;
      }
  }
  close $F;

  #
  # Check POD
  #
  my $pod_parser = Pod::Simple::TextContent->new;
  my $pod = "";
  $pod_parser->output_string(\$pod);
  $pod_parser->parse_file($file);
  my $pod_count = scalar(grep {/FIX/} split /\n/, $pod);
  printf "Found %d FIX(es) in POD in %s\n",
      $pod_count,$file if $pod_count;
  $count += $pod_count;
}
