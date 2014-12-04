use Test::More;

plan skip_all => 'set TEST_POD_SPELLING to enable this test' unless $ENV{TEST_POD_SPELLING};

eval 'use Test::Spelling';
plan (
    skip_all => "Test::Spelling required for testing POD spelling"
) if $@;

add_stopwords(<DATA>);
all_pod_files_spelling_ok();

__END__
arrayrefs
Audun
authpassword
authprotocol
autoconf
CIDR
configure's
ContextEngineIDs
contrib
Daemonises
des
DES
desede
dir
EDE
exitnoterror
FIPS
GPLv
HMAC
hostname
ie
IETF
ing
IP
IPs
IPv
Langfeldt
libdir
Linpro
md
MERCHANTABILITY
munindoc
netmask
Nicolai
NIST
noparanoia
OIDs
PIB
pidebug
pidfile
plaintext
privpassword
privprotocol
Redpill
reeder
reinitializes
reinstalled
sched
sconfdir
sconffile
servicedir
sha
SIGHUP
SIGINT
SIGKILL
SIGTERM
snmp
SNMP
snmpauthpass
snmpauthprotocol
snmpauto
snmpcommunity
snmpconf
snmpport
snmpprivpassword
snmpprivprotocol
snmpusername
snmpv
SNMPv
snmpversion
spooldir
spooler
STDERR
STDOUT
summarising
timestamp
unignored
username
Username
usm
wildcard
wildcards
Ytterdal
