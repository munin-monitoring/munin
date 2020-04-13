use strict;
use warnings;

use lib qw(t/lib);


use Test::More;
use Test::Differences;
use Test::MockModule;

my $cgi = Test::MockModule->new('CGI');

# Include
my ($path_info, %url_param); # Simply Override it later
$cgi->redefine("path_info", sub { return $path_info } );
$cgi->redefine("url_param", sub { return $url_param{$_} });

# Output
$cgi->mock("header", sub {  });

$cgi->path_info();

require_ok( 'Munin::Master::HTML' );
Munin::Master::HTML::handle_request($cgi);

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
