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

    # "root" is *not* allowed due to a 2.0 bug
    echo "$@" | sed -e 's/^[^A-Za-z_]/_/' -e 's/[^A-Za-z0-9_]/_/g' -e 's/^root$/__root/'
}


# Look up warning environment variables.  Takes these two options:
# $1 = field name
# $2 = optional override of environment variable name
#
# Checks for "$2" in the environment, then "$1_warning", then "warning"

get_warning () {
    # Skip $2 if it isn't defined
    if [ -n "$2" ]; then
        local warntmp=$(eval "echo \$$2")
        if [ -n "$warntmp" ]; then
            echo "${warntmp}"
            return
        fi
    fi
    local warntmp=$(eval "echo \$${1}_warning")
    if [ -n "$warntmp" ]; then
        echo "${warntmp}"
        return
    fi
    local warntmp=$warning
    if [ -n "$warntmp" ]; then
        echo "${warntmp}"
        return
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
    # Skip $2 if it isn't defined
    if [ -n "$2" ]; then
        local crittmp=$(eval "echo \$$2")
        if [ -n "$crittmp" ]; then
            echo "${crittmp}"
            return
        fi
    fi
    local crittmp=$(eval "echo \$${1}_critical")
    if [ -n "$crittmp" ]; then
        echo "${crittmp}"
        return
    fi
    local crittmp=$critical
    if [ -n "$crittmp" ]; then
        echo "${crittmp}"
        return
    fi
}

print_critical () {
    critout=$(get_critical $1 $2)
    if [ -n "${critout}" ]; then
        echo "${1}.critical ${critout}"
    fi
}

# adjust_threshold() takes a threshold string and a base value in, and returns
# the threshold string adjusted for percentages if percent sizes are present.
# If not, the threshold is left unchanged.
# Usage:
#   adjust_threshold "50%:50%" 200 
# Returns:
#   100:100
#
adjust_threshold () {

    if [ -n "$1" -a -n "$2" ]; then
        echo "$1" | awk "BEGIN { FS=\":\"; OFS=\":\" }
        \$1 ~ /.*%/ {\$1 = $2 * substr(\$1, 0, length(\$1) - 1) / 100}
        \$2 ~ /.*%/ {\$2 = $2 * substr(\$2, 0, length(\$2) - 1) / 100}

        { print }"
    fi

}

# print_thresholds() takes three arguments. The first is the field name, the
# second is the default environment variable for warnings (see the second
# argument to get_warning), and the third is the default environment variable
# for criticals (see the second argument to get_critical).
#
# This is a convenience function for plugins that don't need to do anything
# special for warnings vs criticals.
#
# Usage:
#   warning='20' critical='40' print_thresholds user
# Returns:
#   user.warning 20
#   user.critical 40

print_thresholds() {
    print_warning $1 $2
    print_critical $1 $3
}

# print_adjusted_thresholds() takes four arguments.  The first is the field
# name, the second is the base value (see the second argument to
# adjust_threshold), the third is the default environment variable for
# warnings (see the second argument to get_warning), and the fourth is the
# default environment variable for criticals (see the second argument to
# get_critical).
#
# Usage:
#   warning=20% critical=40% print_adjusted_thresholds "user" 800
# Returns:
#   user.warning 160
#   user.critical 320
#
print_adjusted_thresholds () {
    tempthresh=$(get_warning $1 $3)
    if [ -n "$tempthresh" ]; then
        echo "$1.warning $(adjust_threshold "$tempthresh" "$2")"
    fi
    tempthresh=$(get_critical $1 $4)
    if [ -n "$tempthresh" ]; then
        echo "$1.critical $(adjust_threshold "$tempthresh" "$2")"
    fi
    unset tempthresh
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

# vim: ft=sh sw=4 ts=4 et
