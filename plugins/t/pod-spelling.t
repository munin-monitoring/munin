use Test::More;

plan skip_all => 'set TEST_POD_SPELLING to enable this test' unless $ENV{TEST_POD_SPELLING};

eval 'use Test::Spelling';
plan (
    skip_all => "Test::Spelling required for testing POD spelling"
) if $@;

add_stopwords(<DATA>);
all_pod_files_spelling_ok();

__END__
API
auth
authpassword
authprotocol
baseoid
ContextEngineIDs
Dagfinn
des
DES
desede
DNS
EDE
eg
Elio
filename
FIPS
Hagander
HMAC
hostname
IETF
Ilmari
IP
Langfeldt
libpq
Linpro
Magnus
Mannsåker
md
multigraph
Munin's
namespace
netstat
Nicolai
NIST
Nordbøe
OID
OIDs
Pettenò
PGDATABASE
PIB
PostgreSQL
privpassword
privprotocol
psql
Redpill
reeder
Retrive
sha
Skillingstad
SNMP
snmpv
SNMPv
somepassword
someuser
stat'ed
statefile
stateful
subtables
TODO
tuple
UDP
url
username
usm
wget
wildcard
Wildcard
WILDCARD
