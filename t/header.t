#!/usr/bin/perl -w

use strict;

BEGIN	{ $| = 1; print "1..8\n"; }
END	{ print "not ok 1\n" unless $::XBaseloaded; }


print "First, let's try to at least load the module; use XBase.\n";

use XBase;
$::XBaseloaded = 1;
print "ok 1\n";

my $dir = ( -d "./t" ? "t/" : "" );

print "Create the new XBase object, load the data from table test.dbf\n";

my $table = new XBase("$dir/test.dbf");
print "not " unless defined $table;
print "ok 2\n";


print "Now, look into the object and check, if it has been filled OK\n";

my $version = $table->{'version'};
printf "Version: expecting 0x83, got 0x%02x\n", $version;
print "not " if $version != 0x83;
print "ok 3\n";


my $lastrec = $table->last_record();
print "Last record: expecting 2, got $lastrec\n";
print "not " if $lastrec != 2;
print "ok 4\n";


my $lastfield = $table->last_field();
print "Last field: expecting 4, got $lastfield\n";
print "not " if $lastfield != 4;
print "ok 5\n";


my $names = join " ", $table->field_names();
my $names_ok = "ID MSG NOTE BOOLEAN DATES";
print "Field names: expecting $names_ok, got $names\n";
print "not " if $names ne $names_ok;
print "ok 6\n";


$XBase::Base::DEBUG = 0;

print "Check if loading table that doesn't exist will produce error\n";
my $badtable = new XBase("nonexistent.dbf");
print "not " if defined $badtable;
print "ok 7\n";


print "Check the returned error message\n";
print "Errstr: $XBase::errstr";
print "not " if $XBase::errstr ne
	"Error opening file nonexistent.dbf: No such file or directory\n";
print "ok 8\n";

