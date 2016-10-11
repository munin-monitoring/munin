use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 2;

use_ok('Munin::Common::Utils');

use Data::Dumper;

subtest 'is_valid_hostname' => sub {
    plan tests => 5;

    my $valid_hostname = 'munin.example.com';
    ok(Munin::Common::Utils::is_valid_hostname($valid_hostname) eq $valid_hostname,
       'valid hostname should return itself');

    my $empty_hostname = '';
    ok(! defined(Munin::Common::Utils::is_valid_hostname($empty_hostname)),
       'fail on empty hostname');

    my $hostname_with_invalid_chars='foo/bar.example.com';
    ok(! defined(Munin::Common::Utils::is_valid_hostname($hostname_with_invalid_chars)),
       'fail on hostname with invalid characters');

    my $long_component_hostname = 'a' x 64 . '.example.com';
    ok(! defined(Munin::Common::Utils::is_valid_hostname($long_component_hostname)),
       'fail on hostname component length > 63');

    my $long_hostname = join ('.', 'a' x 63, 'b' x 63, 'c' x 63, 'd' x 63 ) . '.example.com';
    ok(! defined(Munin::Common::Utils::is_valid_hostname($long_hostname)),
       sprintf('fail on hostname length > 255 (test is %s)', length($long_hostname) ));

};
