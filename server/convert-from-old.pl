#!/usr/bin/perl -w

use strict;
use RRDs;

my $basedir = "/var/lib/lrrd";

if (! $ARGV[0] or $ARGV[0] ne "--do-it")
{
	print "
BIG FAT WARNING:

Running this program is dangerous for the health of your \".rrd\"-files.
It will search recursively for all files with an rrd-extension under
\"$basedir\". ANY RRDFILE FOUND WILL BE MODIFIED.

If you have any non-LRRD \".rrd\"-files under this directory, do not use
this utility.

If you are certain you only have LRRD-owned \".rrd\"-files under the
directory in question, rerun this program with the parameter 
\"--do-it\".

Have a nice day. :-)

";
	exit 1;
}

opendir (DIR, $basedir) or die "Could not open \"$basedir\" for reading: $!\n";
my @dirs = readdir (DIR);
closedir DIR;

foreach my $subdir (@dirs)
{
	next unless (-d "$basedir/$subdir");
	next if ($subdir =~ /^\./);
	print "Doing \"$basedir/$subdir\"...\n";
	opendir (SUBDIR, "$basedir/$subdir") or warn "Could not open \"$basedir/$subdir\" for reading (skipping): $!\n";
	my @files = readdir (SUBDIR);
	closedir SUBDIR;

	for my $file (@files)
	{
		my $type = "";
		my $ds   = "";

		next unless ($file =~ /\.rrd$/);

		my $info = RRDs::info ("$basedir/$subdir/$file");
		
		print "- $file...";

		foreach my $key (keys %{$info})
		{
			if ($key =~ /ds\[([^]]+)\].type/)
			{
				$ds   = $1;
				$type = $info->{$key};
#print "DS=\"$ds\", type=\"$type\"...";
			}
		}

		if ($ds eq "42")
		{
			print "already converted.\n";
			next;
		}

		print "converting...";
		RRDs::tune ("$basedir/$subdir/$file", "--data-source-rename", "$ds:42");
		print "renaming...";
		(my $newfile = $file) =~ s/\.rrd/-/;
		$newfile .= lc substr ($type, 0, 1) . ".rrd";
		if (link ("$basedir/$subdir/$file", "$basedir/$subdir/$newfile"))
		{
			unlink ("$basedir/$subdir/$file") || print "Could not remove file: $!";
		}
		else
		{
			print "Could not link file: $!\n";
		}

		print "\"$newfile\".\n";
	}
}

my $notfound = "";

print "Doing the configuration directory.../etc/lrrd/\n";
print "- lrrd-server.conf...";
if (-f "/etc/lrrd/lrrd-server.conf")
{
	if (link ("/etc/lrrd/lrrd-server.conf", "/etc/lrrd/server.conf"))
	{
		unlink ("/etc/lrrd/lrrd-server.conf") or print "could not remove file: $!";
	}
	else
	{
		print "could not link file: $!";
	}
	print "\n";
}
else
{
	print "not found\n";
	$notfound .= "\tmv lrrd-server.conf server.conf\n";
}

print "\n\n";
if (length $notfound)
{
	print "Could not find some of the files I need to upgrade. You probably have these in
a non-standard place. Find out where you have them, then cd to that directory,
and run the following:

$notfound


";
}
print "Done.\n";
