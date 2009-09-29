package Munin::Node::Configure::Plugin;

use strict;
use warnings;


sub new
{
	my ($class, %opts) = @_;

	my $name = delete $opts{name} or die;
	my $path = delete $opts{path} or die;

	my %plugin = (
		name         => $name,
		path         => $path,
		default      => 'no',
		installed    => [],
		suggestions  => [],
		installed_links => [],
		suggested_links => [],
		family       => 'contrib',
		capabilities => {},

		%opts,
	);

	return bless \%plugin, $class;
}


sub is_wildcard { return ((shift)->{path} =~ /_$/); }


1;
