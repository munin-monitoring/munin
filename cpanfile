# BEWARE: this cpanfile is backported from master - it is only used for travis tests
# In all other regards (besides being used for testing) it is probably not
# accurate (too many dependencies, ...).

requires 'Digest::MD5';
requires 'File::Path';
requires 'File::ReadBackwards';
requires 'File::Temp';
requires 'Getopt::Long';
requires 'HTML::Template::Pro';
requires 'HTTP::Server::Simple::CGI';
requires 'IO::Scalar';
requires 'IO::Socket::INET6';
requires 'JSON';
requires 'LWP::Simple';
requires 'LWP::UserAgent';
requires 'List::MoreUtils';
requires 'List::Util';
requires 'Log::Dispatch';
requires 'Log::Dispatch::Screen';
requires 'Log::Dispatch::Syslog';
requires 'MIME::Base64';
requires 'Module::Build';
requires 'Net::DNS';
requires 'Net::Domain';
requires 'Net::IP';
requires 'Net::SNMP';
requires 'Net::SSLeay';
requires 'Net::Server::Fork';
requires 'Params::Validate';
requires 'Parallel::ForkManager';
requires 'Pod::Perldoc';
requires 'Pod::Usage';
requires 'Scalar::Util';
requires 'Socket';
requires 'Test::Perl::Critic';
requires 'Text::Balanced';
requires 'Time::HiRes';
requires 'URI';
requires 'URI::_server';
requires 'XML::Dumper';
requires 'XML::LibXML';
requires 'XML::Parser';

on test => sub {
    requires 'Directory::Scratch';
    requires 'File::Slurp';
    requires 'Test::Class';
    requires 'Test::Deep';
    requires 'Test::Differences';
    requires 'Test::Exception';
    requires 'Test::LongString';
    requires 'Test::MockModule';
    requires 'Test::MockObject';
    requires 'Test::MockObject::Extends';
    requires 'Test::More';
};

on develop => sub {
    requires 'Capture::Tiny';
    requires 'IO::Scalar';
    requires 'Pod::Simple::SimpleTree';
    requires 'Test::Perl::Critic';
    requires 'perl', 'v5.10.1';
};
