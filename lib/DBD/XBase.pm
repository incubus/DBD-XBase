
=head1 NAME

DBD::XBase - DBI driver for XBase

=head1 SYNOPSIS

	use DBI;
	my $dbh = DBI->connect("DBI:XBase:/directory/subdir");
	...

=head1 DESCRIPTION

We will put something here.

=head1 VERSION

0.01

=head1 AUTHOR

Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), XBase(3), DBD::XBase(3), DBI(3)

=cut

package DBD::XBase;

use strict;
use vars qw($VERSION @ISA @EXPORT);

require Exporter;

$VERSION = '0.01';

1;
