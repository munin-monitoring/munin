use strict;
use warnings;

use lib qw(t/lib);

use Devel::Confess;;
use Test::More;
use Test::Differences;
use Test::MockModule;

our ($path_info, %url_param); # Simply Override it later

package CGI;

sub new {
	return bless {}, shift;
}

sub path_info {
	my $self = shift;
	return $path_info;
}

sub url_param {
	my $self = shift;
	my $param = shift;
	die("undef") unless defined $param;
	return $url_param{$param};
}

my %header;
sub header {
	my $self = shift;
	%header = @_;
}

sub url {
	my $self = shift;
	return "";
}

BEGIN
{
	# mocking the load
	$INC{'CGI.pm'} = "/usr/lib/perl5/site_perl/5.10.0/CGI.pm";
}

package main;

my $cgi = new CGI();

require_ok( 'Munin::Master::HTML' );


# Redirect to / test if empty
$path_info = "";
Munin::Master::HTML::handle_request($cgi);

# We need to start a new line before done_testing(), otherwise the testing
# framework cannot correclty parse the test results output
print "\n";
done_testing();

1;

__DATA__
$ ag cgi lib/Munin/Master/HTML.pm
27:	my $path = $cgi->path_info();
66:		print $cgi->header( -type => $mime_types{$ext});
74:	if (defined $cgi->url_param("graph_ext")) {
75:		$graph_ext = $cgi->url_param("graph_ext");
95:		print $cgi->header(
96:			-Location => ($cgi->url(-path_info=>1,-query=>1) . "/"),
208:		$template_params{CONTENT_ONLY} = $cgi->url_param("content_only") || 0;
510:		my $cgi_graph_url = '/';
531:			$service_template_params{"ZOOM$t"} = "/dynazoom.html?cgiurl_graph=$cgi_graph_url" .
533:			$service_template_params{"IMG$t"} = $cgi_graph_url . "$path-$t.$graph_ext";
551:		print $cgi->header( "-Content-Type" => "text/html", );
557:		my $is_dump_enabled = $cgi->url_param("dump");
571:		# We cannot use "print_to => \*STDOUT" since it does *NOT* work with FastCGI
575:		print $cgi->header( "-Content-Type" => "text/xml", );
581:		print $cgi->header( "-Content-Type" => "application/json", );
