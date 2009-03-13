use warnings;
use strict;

use English qw(-no_match_vars);
use File::Find;
use FindBin;
use Test::More tests => 1;

my $count = 0;

find(\&fixes, "$FindBin::Bin/../lib");
ok($count == 0, "Should not find any FIX comments");

sub fixes {

  my $file = $File::Find::name;

  return unless -f $file;
  #return unless $file =~ /$file_pattern/;

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
}
