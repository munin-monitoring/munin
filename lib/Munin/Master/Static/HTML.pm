package Munin::Master::Static::HTML;

use strict;
use warnings;

use Getopt::Long;
use Parallel::ForkManager;

sub create
{
	my ($jobs, $destination) = @_;

	# Get the list of HTML pages to create
	my @paths;
	{
		use Munin::Master::Update;
		my $dbh = Munin::Master::Update::get_dbh(1);
		my $row_ref = $dbh->selectall_arrayref("SELECT path FROM url");

		# Process results
		@paths = map {
			my $path = @{$_}[0] . ".html";
		} @$row_ref;
		push @paths, "/";
	}

	my $pm = Parallel::ForkManager->new($jobs);
	for my $path (@paths) {
		my $worker_id = $pm->start();
		next if $worker_id;

		# Mock CGI interface, in order to reuse most of munin-httpd internals
		my $cgi = CGI->new({
			path_info => $path,
		});

		$destination = $1 if $destination =~ m/(.*)/;
		my $filepath = "$destination/$path";
		$filepath = "$destination/index.html" if $path eq "/";

		# redirect STDOUT to the file
		print "s: $filepath\n";

		use File::Basename;
		use File::Path qw(make_path remove_tree);

		my $dirpath = dirname($filepath);
		make_path($dirpath);

		do {
			local *STDOUT;
			open (STDOUT, '>', $filepath);

			use Munin::Master::HTML;
			Munin::Master::HTML::handle_request($cgi);
		};

		$pm->finish();
	}

	# wait for every worker to finish
	$pm->wait_all_children();
}

package CGI;

sub new {
        my $c = shift;
        my $params = shift;
        return bless $params, $c;
}

sub path_info {
	my $self = shift;
	return $self->{path_info};
}

sub url_param {
	my $self = shift;
	my $param = shift;
	die("undef") unless defined $param;
	return $self->{url_param}{$param};
}

my %header;
sub header {
	my $self = shift;
	%header = @_;

	# No return, so nothing is printed
	return "";
}

sub url {
	my $self = shift;
	return "";
}

1;
