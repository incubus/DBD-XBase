#!/usr/bin/perl -w

use strict;

BEGIN	{ $| = 1; print "1..8\n"; }
END	{ print "not ok 1\n" unless $::XBaseloaded; }


print "Load the module: use XBase\n";

use XBase;
$::XBaseloaded = 1;
print "ok 1\n";

my $dir = ( -d "t" ? "t" : "." );

$XBase::Base::DEBUG = 1;        # We want to see any problems
$XBase::CLEARNULLS = 1;         # Yes, we want that


print "We will make a copy of database files test.dbf and test.dbt\n";

eval "use File::Copy;";
if ($@)
	{
	print "Look's like you do not have File::Copy, we will do cp\n";
	system("cp", "$dir/test.dbf", "$dir/write.dbf");
	system("cp", "$dir/test.dbt", "$dir/write.dbt");
	}
else
	{
	print "Will use File::Copy\n";
	copy("$dir/test.dbf", "$dir/write.dbf");
	copy("$dir/test.dbt", "$dir/write.dbt");
	}

unless (-f "$dir/write.dbf" and -f "$dir/write.dbt")
	{ exit; }		# Does not make sense to continue


print "Create the new XBase object, load the data from table write.dbf\n";

my $table = new XBase("$dir/write.dbf");
print "not " unless defined $table;
print "ok 2\n";

exit unless defined $table;


print "Will check what the last record number is\n";

my $last_record = $table->last_record();
print "Expecting 2, got $last_record\n";
print "not " if $last_record != 2;
print "ok 3\n";


print "And one more check in memo file (they are numbered from 1)\n";

$last_record = $table->{'memo'}->last_record();
print "Expecting 3, got $last_record\n";
print "not " if $last_record != 3;
print "ok 4\n";


print "Now, overwrite the message and read it back to see, what happened\n";

$table->set_record(1, 5, "New message", "New note", 1, "19700101");
$table->get_record(0);		# Force emptying caches
my $result1 = join ":", map { defined $_ ? $_ : "" } $table->get_record(1);

print "Got: $result1\n";
print "not " if $result1 ne "0:5:New message:New note:1:19700101";
print "ok 5\n";


print "Did last record stay the same?\n";

$last_record = $table->last_record();
print "Expecting 2, got $last_record\n";
print "not " if $last_record != 2;
print "ok 6\n";


print "And now we will append data\n";

$table->set_record(3, 245, "New record no 4", "New note for record 4", undef, "19700102");
$table->get_record(0);		# Force emptying caches
my $result2 = join ":", map { defined $_ ? $_ : "" } $table->get_record(3);

print "Got: $result2\n";
print "not " if $result2 ne "0:245:New record no 4:New note for record 4::19700102";
print "ok 7\n";


print "Now the number of records should have increased\n";

$last_record = $table->last_record();
print "Expecting 3, got $last_record\n";
print "not " if $last_record != 3;
print "ok 8\n";



