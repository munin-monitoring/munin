package Munin::Master::Static::Graph;

use strict;
use warnings;

use Getopt::Long;
use Parallel::ForkManager;
use File::Basename;
use File::Path qw(make_path remove_tree);

use Munin::Master::Static::CGI;

use Munin::Master::Graph;

sub create
{
	my ($jobs, $destination) = @_;

	# Get the list of png to create
	my @paths;
	{
		use Munin::Master::Update;
		my $dbh = Munin::Master::Update::get_dbh(1);
		my $row_ref = $dbh->selectall_arrayref("SELECT path FROM url WHERE type = ?", {}, "service");

		# Process results
		@paths = map {
			my $path = @{$_}[0];
			(
				"$path-year.png",
				"$path-month.png",
				"$path-week.png",
				"$path-day.png",
				"$path-hour.png",
			);
		} @$row_ref;
	}

	my $pm = Parallel::ForkManager->new($jobs);
	for my $path (@paths) {
		my $worker_id = $pm->start();
		next if $worker_id;

		# Mock CGI interface, in order to reuse most of munin-httpd internals
		my $cgi = CGI->new({
			path_info => "/$path",
		});

		$destination = $1 if $destination =~ m/(.*)/;
		my $filepath = "$destination/$path";

		# redirect STDOUT to the file
		print "s: $filepath\n";

		my $dirpath = dirname($filepath);
		make_path($dirpath);

		do {
			local *STDOUT;
			open (STDOUT, '>', $filepath);

			Munin::Master::Graph::handle_request($cgi);
		};

		$pm->finish();
	}

	# wait for every worker to finish
	$pm->wait_all_children();

}

1;
