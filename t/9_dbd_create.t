#!/usr/bin/perl -w

use strict;

BEGIN	{
	$| = 1;
	eval 'use DBI';
	if ($@ ne '')
		{
		print "1..0\n";
		print "DBI couldn't be loaded, aborting test\n";
		print "Error returned from eval was:\n", $@;
		print "ok 1\n";
		exit;
		}
	print "1..9\n";
	print "DBI loaded\n";
	}

END	{ print "not ok 1\n" unless $::DBIloaded; }



### DBI->trace(2);
$::DBIloaded = 1;
print "ok 1\n";

my $dir = ( -d './t' ? 't' : '.' );

print "Unlinking newtable.dbf and newtable.dbt\n";

if (-f "$dir/newtable.dbf")
	{ unlink "$dir/newtable.dbf"
		or print "Error unlinking $dir/newtable.dbf: $!\n"; }
if (-f "$dir/newtable.dbt")
	{ unlink "$dir/newtable.dbt"
		or print "Error unlinking $dir/newtable.dbt: $!\n"; }

print "ok 2\n";

print "Connect to dbi:XBase:$dir\n";
my $dbh = DBI->connect("dbi:XBase:$dir") or do
	{
	print $DBI::errstr;
	print "not ok 3\n";
	exit;
	};
print "ok 3\n";

my $command = 'create table newtable (name char(15), comment memo, uid date,
		float float(6,2), active boolean)';
print "Prepare command `$command'\n";
my $sth = $dbh->prepare($command) or do
	{
	print $dbh->errstr();
	print "not ok 4\n";
	exit;
	};
print "ok 4\n";

print "Execute it\n";
$sth->execute() or do
	{
	print $sth->errstr();
	print "not ok 5\n";
	exit;
	};
print "ok 5\n";

print "Check if both (dbf and dbt) files were created\n";

print "not " unless -f "$dir/newtable.dbf";
print "ok 6\n";
print "not " unless -f "$dir/newtable.dbt";
print "ok 7\n";

print "Check the new table using core XBase.pm\n";
print "Do new XBase('newtable')\n";

my $table = new XBase("$dir/newtable.dbf");
if (not defined $table)
	{
	print XBase->errstr, "\n";
	print "not ok 8\n";
	exit;
	}
print "ok 8\n";

print "Check the header of the newly created table\n";

my $header = $table->get_header_info();
$header =~ s!^Last change:\t.*$!Last change:\txxxx/xx/xx!m;
$header =~ s!^Filename:\tt/!Filename:\t!;

my $goodheader = join '', <DATA>;
if ($header ne $goodheader)
	{
	print "Got header:\n", $header;
	print "Good header is:\n", $goodheader;
	print "not ";
	}
print "ok 9\n";


$sth->finish();
$dbh->disconnect();

1;

__DATA__
Filename:	newtable.dbf
Version:	0x83 (ver. 3 with DBT file)
Num of records:	0
Header length:	193
Record length:	41
Last change:	xxxx/xx/xx
Num fields:	5
Field info:
Num	Name		Type	Len	Decimal
1.	NAME            C       15      0
2.	COMMENT         M       10      0
3.	UID             D       8       0
4.	FLOAT           F       6       2
5.	ACTIVE          L       1       0
