#!/usr/bin/perl -w

use strict;
my $dir;


BEGIN {
	$| = 1;
	$dir = ( -d "t" ? "t" : "." );

	unless (-f "$dir/newtable.dbf" and -f "$dir/newtable.dbt")
		{
		print "1..0\n";
		print <<EOF;
Will not run the tests since newtable doesn't seem to exist.
It should have been created by 4_create.t test.
EOF
		print "ok 1\n";
		exit;
		}
	print "1..5\n";
	}

END { print "not ok 1\n" unless defined $::Xbaseloaded; }

print "Load the module: use XBase\n";

use XBase;
$::Xbaseloaded = 1;
print "ok 1\n";


print "Load the table\n";
my $table = new XBase("$dir/newtable");
print "not " unless defined $table;
print "ok 2\n";


print "And drop it\n";
$table->drop() or print "not ";
print "ok 3\n";


print "Check if the files have been deleted\n";
print "not " if -f "$dir/newtable.dbf";
print "ok 4\n";

print "not " if -f "$dir/newtable.dbt";
print "ok 5\n";


