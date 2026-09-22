use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use IO::Socket::INET;
use POSIX qw(:sys_wait_h);

require_ok('Munin::Master::Update');
require_ok('Munin::Master::Graph');
require_ok('Munin::Master::Static::CGI');

use constant {
	NODE_START_TIMEOUT => 30,
	UPDATE_RUNS        => 5,
};

my @child_pids;
my $temp_dir;

END {
	if (@child_pids) {
		kill('TERM', @child_pids);
		for my $pid (@child_pids) {
			waitpid($pid, 0);
		}
	}
	if ($temp_dir && -d $temp_dir) {
		remove_tree($temp_dir);
	}
	$? = 0;
}

my $script_dir = __FILE__;
$script_dir =~ s{/[^/]+$}{};
my $test_node = "$script_dir/lib/node_test.pl";

my @ports = get_free_ports(3);

for my $port (@ports) {
	my $pid = fork();
	if ($pid == 0) {
		exec("perl", $test_node, $port, "30");
		die "exec failed: $!";
	}
	push @child_pids, $pid;
}

my $all_ready = wait_for_ports(\@ports, NODE_START_TIMEOUT);
ok($all_ready, "all test nodes are listening");

unless ($all_ready) {
	kill('TERM', @child_pids);
	die "Test nodes failed to start";
}

$temp_dir = tempdir("graph-$$-XXXXXX", TMPDIR => 1, CLEANUP => 0);

my $conf_file = "$temp_dir/munin.conf";
open my $fh, '>', $conf_file or die "Cannot write $conf_file: $!";
print $fh "dbdir   $temp_dir\n";
print $fh "htmldir $temp_dir\n";
print $fh "logdir  $temp_dir\n";
print $fh "rundir  $temp_dir\n";
print $fh "local_address 127.0.0.1\n";
print $fh "graph_data_size debug\n";
print $fh "fork 0\n";
print $fh "\n";
print $fh "[aesir;alfheim.aesir;aegir.alfheim.aesir]\n";
print $fh "     address 127.0.0.1\n";
print $fh "     port $ports[0]\n";
print $fh "\n";
print $fh "[asynjur;asgard.asynjur;alaisiagae.asgard.asynjur]\n";
print $fh "     address 127.0.0.1\n";
print $fh "     port $ports[1]\n";
print $fh "\n";
print $fh "[svartalfar;jotunheim.svartalfar;astrild.jotunheim.svartalfar]\n";
print $fh "     address 127.0.0.1\n";
print $fh "     port $ports[2]\n";
print $fh "\n";
print $fh "[localhost]\n";
print $fh "     port $ports[0]\n";
print $fh "\n";
print $fh "[testing.acme.com]\n";
print $fh "     port $ports[1]\n";
close $fh;

my $config = Munin::Master::Config->instance()->{"config"};
$config->parse_config_from_file($conf_file);

$config->{dbdir} = $temp_dir;
$config->{fork} = 0;

Munin::Common::Logger::configure(
	"output" => "screen",
	"level" => "info",
);

alarm(120);

my $update = Munin::Master::Update->new();
is($update->run(), UPDATE_RUNS, "update run populates DB");

my $dbh = Munin::Master::Update::get_dbh(1);
my $services = $dbh->selectall_arrayref(
	"SELECT path FROM url WHERE type = ?", {}, "service"
);
ok(scalar @$services > 0, "DB has services");

my $path = $services->[0][0];
my $cgi = CGI->new({ path_info => "/$path-hour.png" });

my $outfile = "$temp_dir/graph_out.txt";
do {
	local *STDOUT;
	open(STDOUT, '>', $outfile) or die "Cannot redirect STDOUT: $!";
	eval { Munin::Master::Graph::handle_request($cgi) };
	warn "handle_request died: $@" if $@;
	close STDOUT;
};

open my $in, '<', $outfile or die "Cannot read $outfile: $!";
local $/;
my $output = <$in>;
close $in;

like($output, qr/HTTP\/1\.[01] 200/, "graph request returns 200 OK");
ok(length($output) > 100, "graph output has data (" . length($output) . " bytes)");

alarm(0);

print "\n";

done_testing();

1;

sub get_free_ports {
	my ($count) = @_;
	my @ports;
	for (1 .. $count) {
		my $sock = IO::Socket::INET->new(
			LocalAddr => '127.0.0.1',
			LocalPort => 0,
			Proto     => 'tcp',
		);
		if ($sock) {
			push @ports, $sock->sockport();
			close($sock);
		} else {
			die "Cannot find free port: $!";
		}
	}
	return @ports;
}

sub wait_for_ports {
	my ($ports, $timeout) = @_;
	my $start = time();

	for my $port (@$ports) {
		my $ready = 0;
		while (time() - $start < $timeout) {
			my $sock = IO::Socket::INET->new(
				PeerAddr => '127.0.0.1',
				PeerPort => $port,
				Proto    => 'tcp',
				Timeout  => 1,
			);
			if ($sock) {
				close($sock);
				$ready = 1;
				last;
			}
			select(undef, undef, undef, 0.1);
		}
		return 0 unless $ready;
	}
	return 1;
}
