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
	print "1..7\n"; }

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

my $command = "select ID, MSG from test";
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

print "And get two lines\n";

my @line;

@line = $sth->fetchrow_array();
my $result = join ":", @line;
print "Got: $result\n";
print "not " if $result ne "1:Record no 1";
print "ok 5\n";

@line = $sth->fetchrow_array();
$result = join ":", @line;
print "Got: $result\n";
print "not " if $result ne "3:Message no 3";
print "ok 6\n";

@line = $sth->fetchrow_array();
print "Got empty list\n" unless @line;
print "not " if scalar(@line) != 0;
print "ok 7\n";

$sth->finish();
$dbh->disconnect();

