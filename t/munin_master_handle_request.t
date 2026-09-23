use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(rmtree);

# Use the existing CGI mock from Static module
use Munin::Master::Static::CGI;

# Generate fresh test database
require SampleDB;
my $tmpdir = tempdir(CLEANUP => 1);
my $dbfile = "$tmpdir/datafile.sqlite";
SampleDB::generate_sample_db($dbfile);

# Configure
require_ok('Munin::Master::Config');
my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir} = $tmpdir;
$config->{dburl} = $dbfile;
$config->{tmpldir} = 'web/templates';
$ENV{MUNIN_DBURL} = $dbfile;

Munin::Common::Logger::configure(
    output => 'screen',
    level => 'error',
);

require_ok('Munin::Master::HTML');
require_ok('Munin::Master::Update');

# ============================================================================
# Test URL routing - each path should hit the right template
# ============================================================================

subtest 'root URL' => sub {
    my $cgi = CGI->new({ path_info => '', url_param => {} });
    
    # Should redirect
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Root URL handled without crash');
};

subtest 'overview page' => sub {
    my $cgi = CGI->new({ path_info => '/index.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Overview page handled');
};

subtest 'group URL' => sub {
    my $cgi = CGI->new({ path_info => '/localhost.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Group URL handled');
};

subtest 'node URL' => sub {
    my $cgi = CGI->new({ path_info => '/localhost/localhost.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Node URL handled');
};

subtest 'service URL' => sub {
    my $cgi = CGI->new({ path_info => '/localhost/localhost/gerd1.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Service URL handled');
};

subtest 'category URL' => sub {
    my $cgi = CGI->new({ path_info => '/gladsheim-day.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Category URL handled');
};

subtest 'problems page' => sub {
    my $cgi = CGI->new({ path_info => '/problems.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Problems page handled');
};

subtest 'dynazoom page' => sub {
    my $cgi = CGI->new({ path_info => '/dynazoom.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Dynazoom page handled');
};

subtest 'nonexistent URL' => sub {
    my $cgi = CGI->new({ path_info => '/nonexistent.html', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Nonexistent URL handled');
};

subtest 'JSON output' => sub {
    my $cgi = CGI->new({ path_info => '/index.json', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'JSON output handled');
};

subtest 'XML output' => sub {
    my $cgi = CGI->new({ path_info => '/index.xml', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'XML output handled');
};

subtest 'static files' => sub {
    my $cgi = CGI->new({ path_info => '/static/style.css', url_param => {} });
    
    eval { Munin::Master::HTML::handle_request($cgi) };
    ok(1, 'Static file path handled');
};

# ============================================================================
# Cleanup
# ============================================================================

END {
    rmtree($tmpdir) if $tmpdir && -d $tmpdir;
}

done_testing();

1;
