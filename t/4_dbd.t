#!/usr/bin/perl -w

use strict;

BEGIN	{ $| = 1; print "1..7\n"; }
END	{ print "not ok 1\n" unless $::DBIloaded; }


print "Load DBI\n";

use DBI;
$::DBIloaded = 1;
print "ok 1\n";

my $dir = ( -d './t' ? 't' : '.' );
my $dbh = DBI->connect("dbi:XBase:$dir") or do
	{
	print $DBI::errstr;
	print "not ok 2\n";
	exit;
	};
print "ok 2\n";

my $sth = $dbh->prepare("select (ID, MSG) from test") or do
	{
	$dbh->errstr();
	print "not ok 3\n";
	exit;
	};
print "ok 3\n";

$sth->execute() or do
	{
	$sth->errstr();
	print "not ok 4\n";
	exit;
	};
print "ok 4\n";


my @line;

@line = $sth->fetchrow_array();
print "not " if "1:Record no 1" ne join ":", @line;
print "ok 5\n";

@line = $sth->fetchrow_array();
print "not " if "3:Message no 3" ne join ":", @line;
print "ok 6\n";

@line = $sth->fetchrow_array();
print "not " if scalar(@line) != 0;
print "ok 7\n";

$sth->finish();
$dbh->disconnect();

