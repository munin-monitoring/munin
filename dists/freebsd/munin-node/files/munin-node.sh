#!/bin/sh

PROGRAM=%PREFIX%/sbin/munin-node
CONFIG=%PREFIX%/etc/munin/munin-node.conf

case "$1" in
	start)
		if [ -x $PROGRAM -a -f $CONFIG -a -d $PLUGINS ]; then
			$PROGRAM --config $CONFIG && echo -n ' munin-node'
		fi
	;;

	stop)
		if [ -f $CONFIG ]; then
			PIDFILE=`awk '$1 == "pid_file" { print $2 }' $CONFIG`
			if [ -f $PIDFILE ]; then
				PID=`cat $PIDFILE`
				CMD=`ps -xa -o command -p $PID | sed 1d`
				case "$CMD" in
				*munin-node*)
					/bin/kill $PID && echo -n ' munin-node'
					;;
				esac
			fi
		fi
	;;

	*)
		echo "Usage: `basename $0` { start | stop }"
		exit 64
	;;
esac
