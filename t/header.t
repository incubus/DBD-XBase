#!/usr/bin/perl -w

use strict;

BEGIN	{ $| = 1; print "1..9\n"; }
END	{ print "not ok 1\n" unless $::XBaseloaded; }


print "First, let's try to at least load the module: use XBase\n";

use XBase;
$::XBaseloaded = 1;
print "ok 1\n";

my $dir = ( -d "t" ? "t" : "" );

$XBase::Base::DEBUG = 1;        # We want to see any problems
$XBase::CLEARNULLS = 1;         # Yes, we want that

print "Create the new XBase object, load the data from table test.dbf\n";

my $table = new XBase("$dir/test.dbf");
print "not " unless defined $table;
print "ok 2\n";

exit unless defined $table;     # It doesn't make sense to continue here ;-)


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
print "Got errstr: $XBase::errstr";
print "not " if $XBase::errstr ne
	"Error opening file nonexistent.dbf: No such file or directory\n";
print "ok 8\n";


print "Get verbose header info\n";

my $verinfo = $table->get_header_info();
my $goodinfo = <<'EOF';
Filename:	t/test.dbf
Version:	0x83 (ver. 3 with DBT file)
Num of records:	3
Header length:	193
Record length:	279
Last change:	1996/8/17
Num fields:	5
Field info:
Num	Name		Type	Len	Decimal
1.	ID              N       5       0       
2.	MSG             C       254     0       
3.	NOTE            M       10      0       
4.	BOOLEAN         L       1       0       
5.	DATES           D       8       0       
EOF

print "Got\n", $verinfo;

print "not " if $verinfo ne $goodinfo;
print "ok 9\n";


