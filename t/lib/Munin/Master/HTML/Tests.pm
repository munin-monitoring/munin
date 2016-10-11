package Munin::Master::HTML::Tests;
use base qw(Test::Class);
use Test::More;

sub class : Test(1) {
    use_ok(Munin::Master::HTML);
}

sub function__url_to_path : Test(no_plan) {
    ok(
        Munin::Master::HTML::url_to_path('/foo/bar'),
        'returns a true value when given a path'
    );
}

1;
