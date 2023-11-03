package Munin::Master::Static::HTML::CGI;

# empty, it is just to have Perl loading this file to be able to override the
# standard ::CGI namespace to mock it

package CGI;

sub new {
        my $c = shift;
        my $params = shift;
        return bless $params, $c;
}

sub path_info {
	my $self = shift;
	return $self->{path_info};
}

sub url_param {
	my $self = shift;
	my $param = shift;
	die("undef") unless defined $param;
	return $self->{url_param}{$param};
}

my %header;
sub header {
	my $self = shift;
	%header = @_;

	# No return, so nothing is printed
	return "";
}

sub url {
	my $self = shift;
	return "";
}

1;
