# -*- sh -*-
# Support functions for shell munin plugins
#

clean_fieldname () {
    # Clean up field name so it complies with munin requirements.
    # Even though most versions of munin sanitises field names
    # this at least avoids getting .s in field names which will
    # very much still break munin.
    #
    # usage: name="$(clean_fieldname "$item")"
    # 
    echo "$@" | sed -e 's/^[^A-Za-z_]/_/' -e 's/[^A-Za-z0-9_]/_/g'
}


# Look up warning environment variables in the following order:
# $1 = field name
# $2 = optional override of environment variable name
#
# Hmm, this first looks for field_warning, then $2 then warning.  Not the
# order one expects.

get_warning () {
    warn_env="${1}_warning"
    defwarn_env=${2:-warning}
    warntmp=$(eval "echo \$${warn_env}")
    warntmpd=$(eval "echo \$${defwarn_env}")

    warnout=${warntmp:-$warntmpd}

    if [ -n "${warnout}" ]; then
	echo "${warnout}"
    fi
}


# Usage: 
#   warning=${warning:-92}
#   print_warning "$name"

print_warning () {
	warnout=$(get_warning $1 $2)
	if [ -n "${warnout}" ]; then
		echo "${1}.warning ${warnout}"
	fi
}

# Ditto for critical values

get_critical () {
	crit_env="${1}_critical"
	defcrit_env=${2:-critical}
	crittmp=$(eval "echo \$${crit_env}")
	crittmpd=$(eval "echo \$${defcrit_env}")

	critout=${crittmp:-$crittmpd}

	if [ -n "${critout}" ]; then
		echo "${critout}"
	fi
}

print_critical () {
	critout=$(get_critical $1 $2)
	if [ -n "${critout}" ]; then
		echo "${1}.critical ${critout}"
	fi
}


is_multigraph () {
    # Multigraph feature is available in Munin 1.4.0 and later.
    # But it also needs support on the node to stay perfectly
    # compatible with old munin-masters.
    #
    # Using this procedure at the start of a multigraph plugin makes
    # sure it does not interact with old node installations at all
    # and thus does not break anything.
    #
    case $MUNIN_CAP_MULTIGRAPH:$1 in
	1:*) return;; # Yes! Rock and roll!
	*:autoconf)
	    echo 'no (no multigraph support)'
	    exit 0
	    ;;

	*:config)
	    echo 'graph_title This plugin needs multigraph support'
	    echo 'multigraph.label No multigraph here'
	    echo 'multigraph.info This plugin has been installed in a munin-node that is too old to know about multigraph plugins.  Even if your munin master understands multigraph plugins this is not enough, the node too needs to be new enough.  Version 1.4.0 or later should work.'
	    exit 0
	    ;;

	*: ) echo 'multigraph.value 0'
	    exit 0
	    ;;
    esac
}


is_dirtyconfig () {
    # Detect if node/server supports dirty config (feature not yet supported)
    case $MUNIN_CAP_DIRTYCONFIG in
	1) exit 1;;
	*) exit 0;;
    esac
}



# janl_: can I in a shell script save STDOUT so I can restore it after
#        a "exec >>somefile"?
# james: exec 2>&4 etc.
# janl_: this saves handle 2 in handle 4?
# james: yes, that's basically the same as dup
# james: dup2, even
# janl_: so... ... "exec 4>&2" to restore?
# james: Actually you can do: exec 4>&2- ... which closes 4 afterwards ...
#        I think that's historical behaviour and not a newish extension

