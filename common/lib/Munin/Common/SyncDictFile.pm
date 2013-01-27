package Munin::Common::SyncDictFile;
require Tie::Hash;
our @ISA = qw(Tie::Hash);

our $DEBUG_ENABLED;

use IO::File;

# The method invoked by the command tie %hash, classname. 
# Associates a new hash instance with the specified class. 
# LIST would represent additional arguments (along the lines 
# of AnyDBM_File and compatriots) needed to complete the association.
sub TIEHASH {
	my $classname = shift;

	my ($filename) = @_;
	my $self = {
		filename => $filename,
	};

	new IO::File($filename, O_CREAT) unless (-f $filename);

	return bless($self, $classname);
}

# Store datum value into key for the tied hash this.
sub STORE {
	my ($self, $key, $value) = @_;
	DEBUG("STORE($key, $value)");
	$key = escape_key($key);
	

	use IO::File;
	my $fh = _lock_write($self->{filename}, "r");
	my $fh_tmp = _lock_write($self->{filename} . ".tmp");

	# Read the whole file, writing it to $fh_tmp
	while(my $line = <$fh>) {
		chomp($line);
		DEBUG("read line $line");
		# Print the read line, but ignore the key we are currently storing
		print $fh_tmp "$line\n" unless $line =~ m/^$key:/;
	}
	
	# Print the stored key at the end
	DEBUG("Print the stored $key:$value");
	print $fh_tmp "$key:$value\n";

	# close (therefore flush data) before rename
	$fh_tmp = undef;

	# overwrite atomically
	# XXX - any locked process will have an old version
	rename $self->{filename} . ".tmp", $self->{filename};
}

# Retrieve the datum in key for the tied hash this.
sub FETCH {
	my ($self, $key) = @_;
	DEBUG("FETCH($key)");
	$key = escape_key($key);

	my $fh = _lock_read($self->{filename});

	# Read the whole file
	while(my $line = <$fh>) {
		chomp($line);
		next unless $line =~ m/^$key:(.*)/;
		# Found
		return $1;
	}
}

# Return the first key in the hash.
sub FIRSTKEY {
	my ($self) = @_; 
	DEBUG("FIRSTKEY()");
	my $fh = _lock_read($self->{filename});

	# Read the file to find a key
	while(my $line = <$fh>) {
		chomp($line);
		next unless $line =~ m/^(\w+):/;
		# Found
		return $1;
	}
}

# Return the next key in the hash.
sub NEXTKEY {
	my ($self, $lastkey) = @_;
	DEBUG("NEXTKEY($lastkey)");
	$key = escape_key($key);
	my $fh = _lock_read($self->{filename});
	
	# Read the file to find a key
	while(my $line = <$fh>) {
		chomp($line);
		next unless $line =~ m/^$key:(.*)/;
		# Found, read another line
		my $new_line = <$fh>;
		chomp($new_line);

		if ($new_line =~ m/^(\w+):/) {
			return $1;
		} else {
			# EOF
			return undef;
		}
	}
}

# Verify that key exists with the tied hash this.
sub EXISTS {
	my ($self, $key) = @_;
	DEBUG("EXISTS($key)");
	$key = escape_key($key);
	my $fh = _lock_read($self->{filename});

	# Read the whole file
	while(my $line = <$fh>) {
		chomp($line);
		next unless $line =~ m/^$key:(.*)/;
		# Found
		return 1;
	}

	# Not found
	return 0;
}

# Delete the key key from the tied hash this.
sub DELETE {
	my ($self, $key) = @_;
	DEBUG("DELETE($key)");
	$key = escape_key($key);
	$self->_lock_write();
}

# Clear all values from the tied hash this.
sub CLEAR {
	my ($self) = @_; 
	DEBUG("CLEAR()");
	my $fh = $self->_lock_write();
}

sub SCALAR {
	my ($self) = @_; 
	DEBUG("SCALAR()");
	my $fh = _lock_read($self->{filename});
	
	# Read the file to read the number of lines
	my $nb_lines = 0;
	while(my $line = <$fh>) {
		$nb_lines ++;
	}

	return $nb_lines;
}


sub _lock_read {
	my ($filename) = @_;

	use Fcntl qw(:flock);
	use IO::File;

	my $fh = IO::File->new($filename, "r")
		or die "Cannot open tied file '$filename' - $!";
	flock($fh, LOCK_SH) or die "Cannot lock tied file '$filename' - $!";
	return $fh;
}

sub _lock_write {
	my ($filename, $mode) = @_;
	$mode ||= "a+";

	use Fcntl qw(:flock);
	use IO::File;
	
	my $fh = IO::File->new($filename, $mode) 
		or die "Cannot open tied file '$filename' - $!";
	flock($fh, LOCK_EX) or die "Cannot lock tied file '$filename' - $!";
	return $fh;
}

sub DEBUG {
	print STDOUT "[DEBUG] @_" . "\n" if $DEBUG_ENABLED; 
}

# XXX - collision if there is a ____
# But should not happen often anyway
sub escape_key {
	my $key = shift;
	$key =~ s/:/____/g;
	return $key;
}

1;
