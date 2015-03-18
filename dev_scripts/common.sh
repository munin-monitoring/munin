# shell fragment to be sourced.

# - set sandbox environment variables
#
# - change directory to basedir

FINDBIN=$(cd -- "$(dirname "$0")" && pwd)
BASEDIR="$(cd "$FINDBIN/.." && pwd -P)"

SANDBOX="${BASEDIR}/sandbox"
CONFDIR="${SANDBOX}/etc"
RUNDIR="${SANDBOX}/var/run"

USER=$(id -un)
GROUP=$(id -gn)

MUNIN_NODE_PORT=4947
MUNIN_HTTPD_PORT=4948

PATH="${SANDBOX}/bin":$PATH
export PATH

PERL5LIB="${SANDBOX}/lib/perl5"
export PERL5LIB

cd "$BASEDIR"
