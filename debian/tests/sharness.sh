#!/bin/sh
#
# Copyright (c) 2011-2012 Mathias Lafeldt
# Copyright (c) 2005-2012 Git project
# Copyright (c) 2005-2012 Junio C Hamano
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/ .

# Public: Current version of Sharness.
SHARNESS_VERSION="0.3.0"
export SHARNESS_VERSION

# Public: The file extension for tests.  By default, it is set to "t".
: ${SHARNESS_TEST_EXTENSION:=t}
export SHARNESS_TEST_EXTENSION

# Keep the original TERM for say_color
ORIGINAL_TERM=$TERM

# For repeatability, reset the environment to a known state.
LANG=C
LC_ALL=C
PAGER=cat
TZ=UTC
TERM=dumb
EDITOR=:
export LANG LC_ALL PAGER TZ TERM EDITOR
unset VISUAL CDPATH GREP_OPTIONS

# Line feed
LF='
'

[ "x$ORIGINAL_TERM" != "xdumb" ] && (
		TERM=$ORIGINAL_TERM &&
		export TERM &&
		[ -t 1 ] &&
		tput bold >/dev/null 2>&1 &&
		tput setaf 1 >/dev/null 2>&1 &&
		tput sgr0 >/dev/null 2>&1
	) &&
	color=t

while test "$#" -ne 0; do
	case "$1" in
	-d|--d|--de|--deb|--debu|--debug)
		debug=t; shift ;;
	-i|--i|--im|--imm|--imme|--immed|--immedi|--immedia|--immediat|--immediate)
		immediate=t; shift ;;
	-l|--l|--lo|--lon|--long|--long-|--long-t|--long-te|--long-tes|--long-test|--long-tests)
		TEST_LONG=t; export TEST_LONG; shift ;;
	-h|--h|--he|--hel|--help)
		help=t; shift ;;
	-v|--v|--ve|--ver|--verb|--verbo|--verbos|--verbose)
		verbose=t; shift ;;
	-q|--q|--qu|--qui|--quie|--quiet)
		# Ignore --quiet under a TAP::Harness. Saying how many tests
		# passed without the ok/not ok details is always an error.
		test -z "$HARNESS_ACTIVE" && quiet=t; shift ;;
	--no-color)
		color=; shift ;;
	--root=*)
		root=$(expr "z$1" : 'z[^=]*=\(.*\)')
		shift ;;
	*)
		echo "error: unknown test option '$1'" >&2; exit 1 ;;
	esac
done

if test -n "$color"; then
	say_color() {
		(
		TERM=$ORIGINAL_TERM
		export TERM
		case "$1" in
		error)
			tput bold; tput setaf 1;; # bold red
		skip)
			tput setaf 4;; # blue
		warn)
			tput setaf 3;; # brown/yellow
		pass)
			tput setaf 2;; # green
		info)
			tput setaf 6;; # cyan
		*)
			test -n "$quiet" && return;;
		esac
		shift
		printf "%s" "$*"
		tput sgr0
		echo
		)
	}
else
	say_color() {
		test -z "$1" && test -n "$quiet" && return
		shift
		printf "%s\n" "$*"
	}
fi

error() {
	say_color error "error: $*"
	EXIT_OK=t
	exit 1
}

say() {
	say_color info "$*"
}

test -n "$test_description" || error "Test script did not set test_description."

if test "$help" = "t"; then
	echo "$test_description"
	exit 0
fi

exec 5>&1
exec 6<&0
if test "$verbose" = "t"; then
	exec 4>&2 3>&1
else
	exec 4>/dev/null 3>/dev/null
fi

test_failure=0
test_count=0
test_fixed=0
test_broken=0
test_success=0

die() {
	code=$?
	if test -n "$EXIT_OK"; then
		exit $code
	else
		echo >&5 "FATAL: Unexpected exit with code $code"
		exit 1
	fi
}

EXIT_OK=
trap 'die' EXIT

# Public: Define that a test prerequisite is available.
#
# The prerequisite can later be checked explicitly using test_have_prereq or
# implicitly by specifying the prerequisite name in calls to test_expect_success
# or test_expect_failure.
#
# $1 - Name of prerequiste (a simple word, in all capital letters by convention)
#
# Examples
#
#   # Set PYTHON prerequisite if interpreter is available.
#   command -v python >/dev/null && test_set_prereq PYTHON
#
#   # Set prerequisite depending on some variable.
#   test -z "$NO_GETTEXT" && test_set_prereq GETTEXT
#
# Returns nothing.
test_set_prereq() {
	satisfied_prereq="$satisfied_prereq$1 "
}
satisfied_prereq=" "

# Public: Check if one or more test prerequisites are defined.
#
# The prerequisites must have previously been set with test_set_prereq.
# The most common use of this is to skip all the tests if some essential
# prerequisite is missing.
#
# $1 - Comma-separated list of test prerequisites.
#
# Examples
#
#   # Skip all remaining tests if prerequisite is not set.
#   if ! test_have_prereq PERL; then
#       skip_all='skipping perl interface tests, perl not available'
#       test_done
#   fi
#
# Returns 0 if all prerequisites are defined or 1 otherwise.
test_have_prereq() {
	# prerequisites can be concatenated with ','
	save_IFS=$IFS
	IFS=,
	set -- $*
	IFS=$save_IFS

	total_prereq=0
	ok_prereq=0
	missing_prereq=

	for prerequisite; do
		case "$prerequisite" in
		!*)
			negative_prereq=t
			prerequisite=${prerequisite#!}
			;;
		*)
			negative_prereq=
		esac

		total_prereq=$(($total_prereq + 1))
		case "$satisfied_prereq" in
		*" $prerequisite "*)
			satisfied_this_prereq=t
			;;
		*)
			satisfied_this_prereq=
		esac

		case "$satisfied_this_prereq,$negative_prereq" in
		t,|,t)
			ok_prereq=$(($ok_prereq + 1))
			;;
		*)
			# Keep a list of missing prerequisites; restore
			# the negative marker if necessary.
			prerequisite=${negative_prereq:+!}$prerequisite
			if test -z "$missing_prereq"; then
				missing_prereq=$prerequisite
			else
				missing_prereq="$prerequisite,$missing_prereq"
			fi
		esac
	done

	test $total_prereq = $ok_prereq
}

# You are not expected to call test_ok_ and test_failure_ directly, use
# the text_expect_* functions instead.

test_ok_() {
	test_success=$(($test_success + 1))
	say_color "" "ok $test_count - $@"
}

test_failure_() {
	test_failure=$(($test_failure + 1))
	say_color error "not ok $test_count - $1"
	shift
	echo "$@" | sed -e 's/^/#	/'
	test "$immediate" = "" || { EXIT_OK=t; exit 1; }
}

test_known_broken_ok_() {
	test_fixed=$(($test_fixed + 1))
	say_color error "ok $test_count - $@ # TODO known breakage vanished"
}

test_known_broken_failure_() {
	test_broken=$(($test_broken + 1))
	say_color warn "not ok $test_count - $@ # TODO known breakage"
}

# Public: Execute commands in debug mode.
#
# Takes a single argument and evaluates it only when the test script is started
# with --debug. This is primarily meant for use during the development of test
# scripts.
#
# $1 - Commands to be executed.
#
# Examples
#
#   test_debug "cat some_log_file"
#
# Returns the exit code of the last command executed in debug mode or 0
#   otherwise.
test_debug() {
	test "$debug" = "" || eval "$1"
}

test_eval_() {
	# This is a separate function because some tests use
	# "return" to end a test_expect_success block early.
	eval </dev/null >&3 2>&4 "$*"
}

test_run_() {
	test_cleanup=:
	expecting_failure=$2
	test_eval_ "$1"
	eval_ret=$?

	if test -z "$immediate" || test $eval_ret = 0 || test -n "$expecting_failure"; then
		test_eval_ "$test_cleanup"
	fi
	if test "$verbose" = "t" && test -n "$HARNESS_ACTIVE"; then
		echo ""
	fi
	return "$eval_ret"
}

test_skip_() {
	test_count=$(($test_count + 1))
	to_skip=
	for skp in $SKIP_TESTS; do
		case $this_test.$test_count in
		$skp)
			to_skip=t
			break
		esac
	done
	if test -z "$to_skip" && test -n "$test_prereq" && ! test_have_prereq "$test_prereq"; then
		to_skip=t
	fi
	case "$to_skip" in
	t)
		of_prereq=
		if test "$missing_prereq" != "$test_prereq"; then
			of_prereq=" of $test_prereq"
		fi

		say_color skip >&3 "skipping test: $@"
		say_color skip "ok $test_count # skip $1 (missing $missing_prereq${of_prereq})"
		: true
		;;
	*)
		false
		;;
	esac
}

# Public: Run test commands and expect them to succeed.
#
# When the test passed, an "ok" message is printed and the number of successful
# tests is incremented. When it failed, a "not ok" message is printed and the
# number of failed tests is incremented.
#
# With --immediate, exit test immediately upon the first failed test.
#
# Usually takes two arguments:
# $1 - Test description
# $2 - Commands to be executed.
#
# With three arguments, the first will be taken to be a prerequisite:
# $1 - Comma-separated list of test prerequisites. The test will be skipped if
#      not all of the given prerequisites are set. To negate a prerequisite,
#      put a "!" in front of it.
# $2 - Test description
# $3 - Commands to be executed.
#
# Examples
#
#   test_expect_success \
#       'git-write-tree should be able to write an empty tree.' \
#       'tree=$(git-write-tree)'
#
#   # Test depending on one prerequisite.
#   test_expect_success TTY 'git --paginate rev-list uses a pager' \
#       ' ... '
#
#   # Multiple prerequisites are separated by a comma.
#   test_expect_success PERL,PYTHON 'yo dawg' \
#       ' test $(perl -E 'print eval "1 +" . qx[python -c "print 2"]') == "4" '
#
# Returns nothing.
test_expect_success() {
	test "$#" = 3 && { test_prereq=$1; shift; } || test_prereq=
	test "$#" = 2 || error "bug in the test script: not 2 or 3 parameters to test_expect_success"
	export test_prereq
	if ! test_skip_ "$@"; then
		say >&3 "expecting success: $2"
		if test_run_ "$2"; then
			test_ok_ "$1"
		else
			test_failure_ "$@"
		fi
	fi
	echo >&3 ""
}

# Public: Run test commands and expect them to fail. Used to demonstrate a known
# breakage.
#
# This is NOT the opposite of test_expect_success, but rather used to mark a
# test that demonstrates a known breakage.
#
# When the test passed, an "ok" message is printed and the number of fixed tests
# is incremented. When it failed, a "not ok" message is printed and the number
# of tests still broken is incremented.
#
# Failures from these tests won't cause --immediate to stop.
#
# Usually takes two arguments:
# $1 - Test description
# $2 - Commands to be executed.
#
# With three arguments, the first will be taken to be a prerequisite:
# $1 - Comma-separated list of test prerequisites. The test will be skipped if
#      not all of the given prerequisites are set. To negate a prerequisite,
#      put a "!" in front of it.
# $2 - Test description
# $3 - Commands to be executed.
#
# Returns nothing.
test_expect_failure() {
	test "$#" = 3 && { test_prereq=$1; shift; } || test_prereq=
	test "$#" = 2 || error "bug in the test script: not 2 or 3 parameters to test_expect_failure"
	export test_prereq
	if ! test_skip_ "$@"; then
		say >&3 "checking known breakage: $2"
		if test_run_ "$2" expecting_failure; then
			test_known_broken_ok_ "$1"
		else
			test_known_broken_failure_ "$1"
		fi
	fi
	echo >&3 ""
}

# Public: Run command and ensure that it fails in a controlled way.
#
# Use it instead of "! <command>". For example, when <command> dies due to a
# segfault, test_must_fail diagnoses it as an error, while "! <command>" would
# mistakenly be treated as just another expected failure.
#
# This is one of the prefix functions to be used inside test_expect_success or
# test_expect_failure.
#
# $1.. - Command to be executed.
#
# Examples
#
#   test_expect_success 'complain and die' '
#       do something &&
#       do something else &&
#       test_must_fail git checkout ../outerspace
#   '
#
# Returns 1 if the command succeeded (exit code 0).
# Returns 1 if the command died by signal (exit codes 130-192)
# Returns 1 if the command could not be found (exit code 127).
# Returns 0 otherwise.
test_must_fail() {
	"$@"
	exit_code=$?
	if test $exit_code = 0; then
		echo >&2 "test_must_fail: command succeeded: $*"
		return 1
	elif test $exit_code -gt 129 -a $exit_code -le 192; then
		echo >&2 "test_must_fail: died by signal: $*"
		return 1
	elif test $exit_code = 127; then
		echo >&2 "test_must_fail: command not found: $*"
		return 1
	fi
	return 0
}

# Public: Run command and ensure that it succeeds or fails in a controlled way.
#
# Similar to test_must_fail, but tolerates success too. Use it instead of
# "<command> || :" to catch failures caused by a segfault, for instance.
#
# This is one of the prefix functions to be used inside test_expect_success or
# test_expect_failure.
#
# $1.. - Command to be executed.
#
# Examples
#
#   test_expect_success 'some command works without configuration' '
#       test_might_fail git config --unset all.configuration &&
#       do something
#   '
#
# Returns 1 if the command died by signal (exit codes 130-192)
# Returns 1 if the command could not be found (exit code 127).
# Returns 0 otherwise.
test_might_fail() {
	"$@"
	exit_code=$?
	if test $exit_code -gt 129 -a $exit_code -le 192; then
		echo >&2 "test_might_fail: died by signal: $*"
		return 1
	elif test $exit_code = 127; then
		echo >&2 "test_might_fail: command not found: $*"
		return 1
	fi
	return 0
}

# Public: Run command and ensure it exits with a given exit code.
#
# This is one of the prefix functions to be used inside test_expect_success or
# test_expect_failure.
#
# $1   - Expected exit code.
# $2.. - Command to be executed.
#
# Examples
#
#   test_expect_success 'Merge with d/f conflicts' '
#       test_expect_code 1 git merge "merge msg" B master
#   '
#
# Returns 0 if the expected exit code is returned or 1 otherwise.
test_expect_code() {
	want_code=$1
	shift
	"$@"
	exit_code=$?
	if test $exit_code = $want_code; then
		return 0
	fi

	echo >&2 "test_expect_code: command exited with $exit_code, we wanted $want_code $*"
	return 1
}

# Public: Compare two files to see if expected output matches actual output.
#
# The TEST_CMP variable defines the command used for the comparision; it
# defaults to "diff -u". Only when the test script was started with --verbose,
# will the command's output, the diff, be printed to the standard output.
#
# This is one of the prefix functions to be used inside test_expect_success or
# test_expect_failure.
#
# $1 - Path to file with expected output.
# $2 - Path to file with actual output.
#
# Examples
#
#   test_expect_success 'foo works' '
#       echo expected >expected &&
#       foo >actual &&
#       test_cmp expected actual
#   '
#
# Returns the exit code of the command set by TEST_CMP.
test_cmp() {
	${TEST_CMP:-diff -u} "$@"
}

# Public: Schedule cleanup commands to be run unconditionally at the end of a
# test.
#
# If some cleanup command fails, the test will not pass. With --immediate, no
# cleanup is done to help diagnose what went wrong.
#
# This is one of the prefix functions to be used inside test_expect_success or
# test_expect_failure.
#
# $1.. - Commands to prepend to the list of cleanup commands.
#
# Examples
#
#   test_expect_success 'test core.capslock' '
#       git config core.capslock true &&
#       test_when_finished "git config --unset core.capslock" &&
#       do_something
#   '
#
# Returns the exit code of the last cleanup command executed.
test_when_finished() {
	test_cleanup="{ $*
		} && (exit \"\$eval_ret\"); eval_ret=\$?; $test_cleanup"
}

# Public: Summarize test results and exit with an appropriate error code.
#
# Must be called at the end of each test script.
#
# Can also be used to stop tests early and skip all remaining tests. For this,
# set skip_all to a string explaining why the tests were skipped before calling
# test_done.
#
# Examples
#
#   # Each test script must call test_done at the end.
#   test_done
#
#   # Skip all remaining tests if prerequisite is not set.
#   if ! test_have_prereq PERL; then
#       skip_all='skipping perl interface tests, perl not available'
#       test_done
#   fi
#
# Returns 0 if all tests passed or 1 if there was a failure.
test_done() {
	EXIT_OK=t

	if test -z "$HARNESS_ACTIVE"; then
		test_results_dir="$SHARNESS_TEST_DIRECTORY/test-results"
		mkdir -p "$test_results_dir"
		test_results_path="$test_results_dir/${SHARNESS_TEST_FILE%.$SHARNESS_TEST_EXTENSION}.$$.counts"

		cat >>"$test_results_path" <<-EOF
		total $test_count
		success $test_success
		fixed $test_fixed
		broken $test_broken
		failed $test_failure

		EOF
	fi

	if test "$test_fixed" != 0; then
		say_color error "# $test_fixed known breakage(s) vanished; please update test(s)"
	fi
	if test "$test_broken" != 0; then
		say_color warn "# still have $test_broken known breakage(s)"
	fi
	if test "$test_broken" != 0 || test "$test_fixed" != 0; then
		test_remaining=$(( $test_count - $test_broken - $test_fixed ))
		msg="remaining $test_remaining test(s)"
	else
		test_remaining=$test_count
		msg="$test_count test(s)"
	fi

	case "$test_failure" in
	0)
		# Maybe print SKIP message
		if test -n "$skip_all" && test $test_count -gt 0; then
			error "Can't use skip_all after running some tests"
		fi
		[ -z "$skip_all" ] || skip_all=" # SKIP $skip_all"

		if test $test_remaining -gt 0; then
			say_color pass "# passed all $msg"
		fi
		say "1..$test_count$skip_all"

		test -d "$remove_trash" &&
		cd "$(dirname "$remove_trash")" &&
		rm -rf "$(basename "$remove_trash")"

		exit 0 ;;

	*)
		say_color error "# failed $test_failure among $msg"
		say "1..$test_count"

		exit 1 ;;

	esac
}

# Public: Root directory containing tests. Tests can override this variable,
# e.g. for testing Sharness itself.
: ${SHARNESS_TEST_DIRECTORY:=$(pwd)}
export SHARNESS_TEST_DIRECTORY

# Public: Build directory that will be added to PATH. By default, it is set to
# the parent directory of SHARNESS_TEST_DIRECTORY.
: ${SHARNESS_BUILD_DIRECTORY:="$SHARNESS_TEST_DIRECTORY/.."}
PATH="$SHARNESS_BUILD_DIRECTORY:$PATH"
export PATH SHARNESS_BUILD_DIRECTORY

# Public: Path to test script currently executed.
SHARNESS_TEST_FILE="$0"
export SHARNESS_TEST_FILE

# Prepare test area.
test_dir="trash directory.$(basename "$SHARNESS_TEST_FILE" ".$SHARNESS_TEST_EXTENSION")"
test -n "$root" && test_dir="$root/$test_dir"
case "$test_dir" in
/*) SHARNESS_TRASH_DIRECTORY="$test_dir" ;;
 *) SHARNESS_TRASH_DIRECTORY="$SHARNESS_TEST_DIRECTORY/$test_dir" ;;
esac
test "$debug" = "t" || remove_trash="$SHARNESS_TRASH_DIRECTORY"
rm -rf "$test_dir" || {
	EXIT_OK=t
	echo >&5 "FATAL: Cannot prepare test area"
	exit 1
}

# Public: Empty trash directory, the test area, provided for each test. The HOME
# variable is set to that directory too.
export SHARNESS_TRASH_DIRECTORY

HOME="$SHARNESS_TRASH_DIRECTORY"
export HOME

mkdir -p "$test_dir" || exit 1
# Use -P to resolve symlinks in our working directory so that the cwd
# in subprocesses like git equals our $PWD (for pathname comparisons).
cd -P "$test_dir" || exit 1

this_test=${SHARNESS_TEST_FILE##*/}
this_test=${this_test%.$SHARNESS_TEST_EXTENSION}
for skp in $SKIP_TESTS; do
	case "$this_test" in
	$skp)
		say_color info >&3 "skipping test $this_test altogether"
		skip_all="skip all tests in $this_test"
		test_done
	esac
done

# vi: set ts=4 sw=4 noet :
