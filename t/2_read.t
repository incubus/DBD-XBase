#!/usr/bin/perl -w

use strict;

BEGIN	{ $| = 1; print "1..10\n"; }
END	{ print "not ok 1\n" unless $::XBaseloaded; }


print "Load the module: use XBase\n";

use XBase;
$::XBaseloaded = 1;
print "ok 1\n";

my $dir = ( -d "t" ? "t" : "." );

$XBase::Base::DEBUG = 1;	# We want to see any problems
$XBase::CLEARNULLS = 1;		# Yes, we want that

print "Create the new XBase object, load the data from table test.dbf\n";

my $table = new XBase("$dir/test.dbf");
print "not " unless defined $table;
print "ok 2\n";

exit unless defined $table;	# It doesn't make sense to continue here ;-)


my @expected = (
	"0:1:Record no 1:This is a memo for record no one::19960813",
	"1:2:No 2:This is a memo for record 2:1:19960814",
	"0:3:Message no 3:This is a memo for record 3:0:19960102",
	);
my $rec_num = 0;
while ($rec_num < 3)
	{
	print "Do get_record($rec_num)\n";
	my $result = join ":", map { defined $_ ? $_ : "" }
					$table->get_record($rec_num);
	print "Got $result\nExpected $expected[$rec_num]\n";
	print "not " if $result ne $expected[$rec_num];
	print "ok ", $rec_num + 3, "\n";
	$rec_num++;
	}


$XBase::Base::DEBUG = 0;

print "Check if reading record that doesn't exist will produce error\n";
my (@result) = $table->get_record(3);
print "not " if @result;
print "ok 6\n";

print "Check error message\n";
print "Errstr: ", $table->errstr();
print "not " if $table->errstr() ne
	"Can't read record 3, there is not so many of them\n";
print "ok 7\n";



print "Get record 0 as hash\n";

my %hash = $table->get_record_as_hash(0);

my @keys = keys %hash;
my $gotvalues = join ', ',
	map { defined $_ ? ( /^\d+$/ ? $_ : qq["$_"] ) : 'undef' }
							values %hash;
my $expectedvalues = 'undef, 19960813, 1, 0, "This is a memo for record no one", "Record no 1"';

print "Got \@hash{ qw( @keys ) } =\n  ($gotvalues);\n";
print "Expected\n  ($expectedvalues)\n";

print "not " if $gotvalues ne $expectedvalues;
print "ok 8\n";


print "Create the new XBase object, load the data from table rooms.dbf\n";

$table = new XBase("$dir/rooms");
print XBase->errstr unless defined $table;
print "not " unless defined $table;
print "ok 9\n";

exit unless defined $table;	# It doesn't make sense to continue here ;-)

my $read_table = join "\n", (map { join ':', $table->get_record($_) }
				(0 .. $table->last_record())), '';

my $read_expected_data = join '', <DATA>;

print "Read records and check what we've got\n";
if ($read_table ne $read_expected_data)
	{
	print "Expected result:\n$read_expected_data";
	print "Got:\n$read_table";
	print "not ";
	}
print "ok 10\n";

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
