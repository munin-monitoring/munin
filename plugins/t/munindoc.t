# vim: sw=4 : ts=4 : et

use strict;
use warnings;

use 5.10.0;

use Test::More 'no_plan';

use IO::Scalar;
use File::Find;

use Data::Dumper;

plan skip_all => 'set TEST_POD to enable this test'
    unless $ENV{TEST_POD};


# both are in standard distribution, but just in case...
eval {
    require Pod::Simple::SimpleTree;
    require Test::Differences;
};
plan skip_all => 'Pod::Select and Pod::Simple::SimpleTree required to run these tests'
    if $@;

Test::Differences->import();

sub check_munindoc
{
    # skip SVN stuff, and directories.  neither contains any POD.
    if ( -d and m{\.svn}) {
        $File::Find::prune = 1;
        return;
    }
    return if -d;

    my $plugin = $File::Find::name;

    my @sections = (
        'NAME',
        'APPLICABLE SYSTEMS',
        'CONFIGURATION',
        'INTERPRETATION',
        (m{snmp__} ? 'MIB INFORMATION' : ()),
        'MAGIC MARKERS',
        'BUGS',
        'VERSION',
        'AUTHOR',
        'LICENSE',
    );

    my $root = Pod::Simple::SimpleTree->new->parse_file($plugin)->root;

    # FIXME: check for POD errors?

    my @headings = map  { $_->[2] } grep { 'ARRAY' eq ref $_ && $_->[0] eq 'head1' && $_->[2] ~~ @sections } @$root;
    eq_or_diff(\@headings, \@sections, "$plugin - All POD sections exist");

    # additional tests?
}


# find_pod_files doesn't work because (a) they don't end in .p[lm], (b) their
# shebang file is "broken" and (c) some plugins aren't even perl (shock!  horror!).
find({
    wanted => \&check_munindoc,
    no_chdir => 1,
}, glob('node.d*/'));

