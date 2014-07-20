#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl munin_common_logger.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl munin_common_logger.t'
#   Stig Sandbeck Mathisen <ssm@fnord.no>     2014/03/23 13:36:14

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More qw( no_plan );
BEGIN { use_ok(Munin::Common::Logger); }

# do we have a log object?
{
    isa_ok( $Munin::Common::Logger::log, 'Log::Dispatch' );
}

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# _timestamp
{
    like(
        Munin::Common::Logger->_timestamp,
        qr{\d+-\d+-\d+ \d+:\d+:\d+},
        '_timestamp returns time on expected format'
    );
}

# set_log_level_to
{
    ok( Munin::Common::Logger::would_log('warning'),
        'should log with warning' );

    ok( !Munin::Common::Logger::would_log('debug'),
        'should not log with debug' );

    ok( Munin::Common::Logger::set_log_level_to('debug'),
        'change log level to debug' );

    ok( Munin::Common::Logger::would_log('debug'), 'should log with debug' );

}

# _remove_label
{
    my $message = '[DEBUG] some debugging text';
    is( Munin::Common::Logger::_remove_label($message),
        'some debugging text' );
}

# _remove_all_logging
#
# (This should only be used for testing, but we need to test it as well. This turns off logging.)
{
    ok( Munin::Common::Logger::_remove_all_logging );
}

# DEBUG, INFO, NOTICE, WARN, WARNING, ERROR, CRITICAL, ALERT, EMERGENCY, LOGCROAK
{

    my $message = 'munin test message';
    is( DEBUG($message),     undef, 'DEBUG()' );
    is( INFO($message),      undef, 'INFO()' );
    is( NOTICE($message),    undef, 'NOTICE()' );
    is( WARN($message),      undef, 'WARN()' );
    is( WARNING($message),   undef, 'WARNING()' );
    is( ERROR($message),     undef, 'ERROR()' );
    is( CRITICAL($message),  undef, 'CRITICAL()' );
    is( FATAL($message),     undef, 'FATAL()' );
    is( ALERT($message),     undef, 'ALERT()' );
    is( EMERGENCY($message), undef, 'EMERGENCY()' );

    eval { LOGCROAK($message) };
    like( $@, qr{$message}, 'LOGCROAK()' );

}
