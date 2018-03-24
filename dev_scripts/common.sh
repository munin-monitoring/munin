# shell fragment to be sourced.

# - set sandbox environment variables
#
# - change directory to basedir

unset LC_CTYPE LANG

FINDBIN=$(cd -- "$(dirname "$0")" && pwd)
BASEDIR="$(cd "$FINDBIN/.." && pwd -P)"

SANDBOX="${BASEDIR}/sandbox"
CONFDIR="${SANDBOX}/etc"
RUNDIR="${SANDBOX}/var/run"

case "$(uname)" in
	Darwin)
		USER=$(id -u -n)
		GROUP=$(id -g -n)
		;;
	*)
		USER=$(id -un)
		GROUP=$(id -gr)
		;;
esac

MUNIN_NODE_PORT=4947
MUNIN_HTTPD_PORT=4948
MUNIN_DBURL=${SANDBOX}/var/lib/datafile.sqlite
export MUNIN_DBURL

PATH="${SANDBOX}/bin":$PATH
export PATH

PERL5LIB="${SANDBOX}/lib/perl5"
export PERL5LIB

cd "$BASEDIR"
