
use Config;
my $filename = $0;

$filename =~ s/\.PL$//;
open OUT,">$filename" or die "Can't create $filename: $!";
chmod(0755, $filename);
print "Extracting $filename (with #! and variable substitution)\n";

print OUT <<"EOHEADER";
$Config{'startperl'} -w

EOHEADER

print OUT <<'EOBODY';

use XBase;
use Getopt::Long;

my %options;
Getopt::Long::GetOptions( \%options,
	'help', 'version', 'rs=s', 'fs=s', 'undef=s', 'fields=s'
	) or exit;

if (defined $options{'version'})
	{ die "This is dbfdump version $XBase::VERSION\n"; }

if (defined $options{'help'})
	{
	die <<EOF;
Usage: dbfdump [ options ] files
    possible options: -rs record separator, -fs field separator,
    -fields comma separated list of fields to print, -undef string
    to print for NULL values
EOF
	}
if (defined $options{'fields'})
	{ $options{'fields'} = [ split /\s*,\s*/, $options{'fields'} ]; }

my $file;
for $file (@ARGV)
	{
	my $table = new XBase $file;
	if (not defined $table)
		{
		print STDERR XBase->errstr;
		next;
		}
	$table->dump_records(%options);
	$table->close;
	}

1;

__END__

=head1 NAME

dbfdump - Dump the record of the dbf file

=head1 FORMAT

	dbfdump [options] files

options are

	-fields		comma separated list of fields to print
	-rs		record separator
	-fs		field separator
	-undef		string to print for NULL values

=head1 SYNOPSIS

	dbfdump -fields id,msg table
	dbfdump -fs=' : ' table

=head1 DESCRIPTION

Dbfdump print to standard output content of dbf files listed. By
default, it prints all fields, separated by colons, one record on
a line. The record separators can be changed by options on the command
line. It is also possible to specify list of fields to print -- comma
separated list for the C<-fields> command line parameter.

The content of associated memo files (dbf, fpt) is printed for memo
fields.

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz, http://www.fi.muni.cz/~adelton/
at Faculty of Informatics, Masaryk University in Brno, Czech Republic

=head1 SEE ALSO

perl(1); XBase(3)

EOBODY

