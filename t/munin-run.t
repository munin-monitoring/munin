use Test::More tests => 6;
use strict;

my $PREFIX = $ENV{PWD}.'/t/install';
my $run    = "$PREFIX/sbin/munin-run --sconfdir=$ENV{PWD}/t/plugin-conf.d";

sub run {
    my $plugin = shift or die "run(): plugin required\n";

    my @lines = `$run $plugin` or warn "No output from '$plugin' plugin\n";
    warn "Error running '$plugin' plugin\n", @lines if $?;

    my %ret;
    for (@lines) {
	if (/^(\w+)\.(\w+)\s+(.+)/) { # unfuck cperl-mode +
	    $ret{$1}{$2} = $3;
	}
	elsif (/(\w+)\s+(.+)/) {
	    $ret{$1} = $2;
	}
    }
    return %ret;
}

SKIP: {
    skip "need root for uid/gid tests", 4 if $>;
    skip "nobody/nogroup missing", 4
      unless getpwnam('nobody') && getgrnam('nogroup');

    my %id = run('id_default');
    is($id{uid}{extinfo}, 'nobody', "default user");
    like($id{gid}{extinfo}, qr/^nogroup/, "default group");
    
    my %id = run('id_root');
    is($id{uid}{value}, 0, 'user override');
    like($id{gid}{extinfo}, qr/\broot\b/, 'group override');
}

my %env = run('env');
is_deeply(\%env,
	  { count      => { value   => 1 },
	    munin_test => { value   => 4,
			    extinfo => 'test',
			  },
	  },
	  'environment variables');

TODO: {
    local $TODO = "munin-run doesn't handle this";

    my %config = run('env config');
    is($config{host_name}, 'test.example.com', 'host_name override');
}
