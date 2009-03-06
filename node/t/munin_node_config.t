use warnings;
use strict;

use Test::More tests => 11;

use English qw(-no_match_vars);
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('Munin::Node::Config');

my $conf = Munin::Node::Config->new();
isa_ok($conf, 'Munin::Node::Config');

###############################################################################
#                       _ P A R S E _ L I N E

### Corner cases

is($conf->_parse_line(""), undef, "Empty line is undef");

eval {
    $conf->_parse_line("foo");
};
like($@, qr{Line is not well formed}, "Need a name and a value");


### Hostname

my @res = $conf->_parse_line("hostname foo");
is_deeply(\@res, [fqdn => 'foo'], 'Parsing host name');

# The parser is quite forgiving ...
@res = $conf->_parse_line("hostname foo bar");
is_deeply(\@res, [fqdn => 'foo bar'],
          'Parsing invalid host name gives no error');


### Default user

my $uname = getpwuid $UID;

@res = $conf->_parse_line("default_client_user $uname");
is_deeply(\@res, [defuser => $UID], 'Parsing default user name');

@res = $conf->_parse_line("default_client_user $UID");
is_deeply(\@res, [defuser => $UID], 'Parsing default user ID');


### Default group

my $gid   = (split / /, $GID)[0];
my $gname = getgrgid $gid;

@res = $conf->_parse_line("default_client_group $gname");
is_deeply(\@res, [defgroup => $gid], 'Parsing default group');

eval {
    $conf->_parse_line("default_client_group xxxyyyzzz");
};
like($@, qr{Default group does not exist}, "Default group exists");


### Paranoia

@res = $conf->_parse_line("paranoia off");
is_deeply(\@res, [paranoia => 0], 'Parsing paranoia');  
