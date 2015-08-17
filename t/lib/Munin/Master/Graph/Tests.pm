package Munin::Master::Graph::Tests;
use base qw(Test::Class);
use Test::More;

sub class : Test(1) {
    use_ok(Munin::Master::Graph);
}

sub function__is_ext_handled : Test(3) {
    ok( !Munin::Master::Graph::is_ext_handled(),
        'Should return a false value when run without params' );

    ok( Munin::Master::Graph::is_ext_handled('PNG'),
        'Should return a true value when argument is a supported extension' );

    ok( !Munin::Master::Graph::is_ext_handled('SOMETHING'),
        'Should return a false value when argument is an unsupported extension'
    );
}

sub function__remove_dups : Test(2) {

    my $test     = 'a a b c d  d   a e';
    my $expected = 'a b c d e';

    ok( !Munin::Master::Graph::remove_dups(),
        'Should return a false value when run without parameters' );

    is( Munin::Master::Graph::remove_dups($test),
        $expected,
        'Should return a white space separated list of unique tokens' );

}

1;
