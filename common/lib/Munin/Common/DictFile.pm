package Munin::Common::DictFile;
require Tie::Hash;
our @ISA = qw(Tie::StdHash);

our $DEBUG_ENABLED;

# The method invoked by the command tie %hash, classname. 
# Associates a new hash instance with the specified class. 
# LIST would represent additional arguments (along the lines 
# of AnyDBM_File and compatriots) needed to complete the association.
sub TIEHASH {
	my $classname = shift;

	my ($filename) = @_;

	my $self = {
		__filename__ => $filename,
	};

	# Read the whole file if it exists
	if (-e $filename) {
		open(FILE, $filename) or die "Cannot open tied file '$filename' - $!";

		while(my $line = <FILE>) {
			chomp($line);
			next unless $line =~ m/^'(.*)':\t'(.*)'$/;
			# Found a valid line, store it
			$self->{ _unescape($1) } = _unescape($2);
		}
		close(FILE);
	}

	return bless($self, $classname);
}

# Write everything down
sub DESTROY {
	my $self = shift;
	
	my $tmp_filename = $self->{__filename__} . ".tmp.$$";

	open(FILE, "> $tmp_filename") or die "Cannot open temp file '$tmp_filename' - $!";
	foreach my $key (keys %$self) {
		print FILE "'" . _escape($key) . "':\t'" . _escape($self->{$key}) . "'\n"; 
	}
	close (FILE);

	rename $tmp_filename, $self->{__filename__};
}

sub DEBUG {
	print STDOUT "[DEBUG] @_" . "\n" if $DEBUG_ENABLED; 
}

sub _escape {
	my $string = shift;
	$string =~ s/'/''/g;
	return $string;
}

sub _unescape {
	my $string = shift;
	$string =~ s/''/'/g;
	return $string;
}

1;
