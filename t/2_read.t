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
my @values = map { defined $_ ? qq["$_"] : "undef" } values %hash;

print "Got \@hash{ qw( @keys ) } = (", join(", ", @values), ");\n";

print "Now check values ID, _DELETED, BOOLEAN\n";

my $id = $hash{'ID'};
print "not " if not defined $id or $id != 1;
print "ok 8\n";

my $deleted = $hash{'_DELETED'};
print "not " if not defined $deleted or $deleted != 0;
print "ok 9\n";

my $boolean = $hash{'BOOLEAN'};
print "not " if defined $boolean;
print "ok 10\n";

1;

