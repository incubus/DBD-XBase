#!/usr/bin/perl -w

use strict;

BEGIN	{ $| = 1; print "1..3\n"; }
END	{ print "not ok 1\n" unless $::XBaseloaded; }


print "Load the module: use XBase\n";

use XBase;
$::XBaseloaded = 1;
print "ok 1\n";

my $dir = ( -d "t" ? "t" : "." );

$XBase::Base::DEBUG = 1;	# We want to see any problems

print "Create the new XBase object, load the data from table rooms.dbf\n";

my $table = new XBase("$dir/rooms");
print XBase->errstr unless defined $table;
print "not " unless defined $table;
print "ok 2\n";

exit unless defined $table;	# It doesn't make sense to continue here ;-)

my $read_table = join "\n", (map { join ':', $table->get_record($_) }
				(0 .. $table->last_record())), '';

my $read_expected_data = join '', <DATA>;

if ($read_table ne $read_expected_data)
	{
	print "Expected result:\n$read_expected_data";
	print "Got:\n$read_table";
	print "not ";
	}
print "ok 3\n";

1;

__DATA__
0: None:
0:Bay  1:Main
0:Bay 14:Main
0:Bay  2:Main
0:Bay  5:Main
0:Bay 11:Main
0:Bay  6:Main
0:Bay  3:Main
0:Bay  4:Main
0:Bay 10:Main
0:Bay  8:Main
0:Gigapix:Main
0:Bay 12:Main
0:Bay 15:Main
0:Bay 16:Main
0:Bay 17:Main
0:Bay 18:Main
0:Mix A:Audio
0:Mix B:Audio
0:Mix C:Audio
0:Mix D:Audio
0:Mix E:Audio
0:ADR-Foley:Audio
0:Mach Rm:Audio
0:Transfer:Audio
0:Bay 19:Main
0:Dub:Main
0:Flambe:Audio
0:FILM 1:Film
0:FILM 2:Film
0:FILM 3:Film
0:SCANNING:Film
0:Mix F:Audio
0:Mix G:Audio
0:Mix H:Audio
0:BullPen:Film
0:Celco:Film
0:MacGrfx:Main
0:Mix J:Audio
0:AVID:Main
0:BAY 7:Main
0::
