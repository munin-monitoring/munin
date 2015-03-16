#!/bin/sh
# -*- sh -*-

: << =cut

=head1 NAME

sendmail_mailtraffic - Plugin to monitor sendmail statistics

=head1 CONFIGURATION

This plugin uses the following configuration variables:

 [sendmail_mailstats]
  env.mailstats - Path to the "mailstats" command

=head2 DEFAULT CONFIGURATION

The default configuration for "mailstats" is to look for a binary called "mailstats" in PATH.

=head1 AUTHOR

Unknown author

=head1 LICENSE

GPLv2

=head1 MAGIC MARKERS

 #%# family=auto
 #%# capabilities=autoconf

=cut

if [ -n "$mailstats" ];
	then MAILSTATS=$mailstats;
	else MAILSTATS=`which mailstats 2>/dev/null`;
fi

if [ "$1" = "autoconf" ]; then
	if [ -n "$MAILSTATS" -a -x "$MAILSTATS" ]
		then echo yes
		else echo "no (no mailstats command)"
	fi
	exit 0
fi

if [ "$1" = "config" ]; then

	echo "graph_title Sendmail email volumes"
	echo "graph_order received sent"
	echo 'graph_vlabel bytes/${graph_period}'
	echo "graph_category mail"
	echo "received.label received"
	echo "sent.label sent"
	echo "received.max 1000000"
	echo "received.min 0"
	echo "sent.max 1000000"
	echo "sent.min 0"
	echo "received.type DERIVE"
	echo "sent.type DERIVE"
	exit 0
fi

$MAILSTATS -P | awk '/^ *T/ {
  received = received + $5
  sent = sent + $3
}

END {
  print "received.value", received
  print "sent.value", sent
}'

