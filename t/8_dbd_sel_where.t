#!/usr/bin/perl -w

use strict;

BEGIN	{ $| = 1;
	print "Load DBI\n";
	eval 'use DBI';
	if ($@ ne '')
		{
		print "1..0\n";
		print "DBI couldn't be loaded, aborting test\n";
		print "ok 1\n";
		exit;
		}
	print "1..5\n"; }

END	{ print "not ok 1\n" unless $::DBIloaded; }



### DBI->trace(2);
$::DBIloaded = 1;
print "ok 1\n";

my $dir = ( -d './t' ? 't' : '.' );

print "Connect to dbi:XBase:$dir\n";
my $dbh = DBI->connect("dbi:XBase:$dir") or do
	{
	print $DBI::errstr;
	print "not ok 2\n";
	exit;
	};
print "ok 2\n";

my $command = "select facility,roomname from rooms where
				facility = 'Audio' or roomname > 'B'";
print "Prepare command '$command'\n";
my $sth = $dbh->prepare($command) or do
	{
	print $dbh->errstr();
	print "not ok 3\n";
	exit;
	};
print "ok 3\n";

print "Execute it\n";
$sth->execute() or do
	{
	print $sth->errstr();
	print "not ok 4\n";
	exit;
	};
print "ok 4\n";

print "And now get the result\n";

my $result = '';
my @line;
while (@line = $sth->fetchrow_array())
	{ $result .= "@line\n"; }


my $expected_result = join '', <DATA>;

if ($result ne $expected_result)
	{
	print "Expected:\n$expected_result";
	print "Got:\n$result";
	print "not ";
	}
print "ok 5\n";

$sth->finish();
$dbh->disconnect();

1;

__DATA__
Main Bay  1
Main Bay 14
Main Bay  2
Main Bay  5
Main Bay 11
Main Bay  6
Main Bay  3
Main Bay  4
Main Bay 10
Main Bay  8
Main Gigapix
Main Bay 12
Main Bay 15
Main Bay 16
Main Bay 17
Main Bay 18
Audio Mix A
Audio Mix B
Audio Mix C
Audio Mix D
Audio Mix E
Audio ADR-Foley
Audio Mach Rm
Audio Transfer
Main Bay 19
Main Dub
Audio Flambe
Film FILM 1
Film FILM 2
Film FILM 3
Film SCANNING
Audio Mix F
Audio Mix G
Audio Mix H
Film BullPen
Film Celco
Main MacGrfx
Audio Mix J
Main BAY 7
