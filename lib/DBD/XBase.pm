
=head1 NAME

DBD::XBase - DBI driver for XBase

=head1 SYNOPSIS

	use DBI;
	my $dbh = DBI->connect("DBI:XBase:/directory/subdir");
	...

=head1 DESCRIPTION

This module is not usable now, I just start to realize how to write
such a beast. Any help is appreciated.

=head1 VERSION

0.03

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), DBI(3), XBase(3)

=cut


# ##################################
# Here starts the DBD::XBase package

package DBD::XBase;

use strict;
use DBI ();
use XBase;

use vars qw($VERSION @ISA @EXPORT $err $errstr $drh);

require Exporter;

$VERSION = '0.03';

$err = 0;
$errstr = '';
$drh = undef;

sub driver
	{
	return $drh if $drh;
	my ($class, $attr) = @_;
	$class .= "::dr";
	$drh = DBI::_new_drh($class, {
		'Name'		=> 'XBase',
		'Version'	=> $VERSION,
		'Err'		=> \$DBD::XBase::err,
		'Errstr'	=> \$DBD::XBase::errstr,
		'Attribution'	=> 'DBD::XBase by Jan Pazdziora',
		});
	}


package DBD::XBase::dr;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;

sub connect
	{
	my ($drh, $dsn, $username, $password, $attrhash) = @_;
	my $this = DBI::_new_dbh($drh, { 'dsn' => $dsn } );

	if (not -d $dsn)
		{
		$DBD::XBase::errstr = "Directory $dsn doesn't exist";
		return undef;
		}
	my $this = DBI::_new_dbh($drh, {
		'Name'	=> $dsn,
		});
	}

sub disconnect_all
	{ }


package DBD::XBase::db;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;

sub prepare
	{
	my ($dbh, $statement, @attribs)= @_;
	my $sth = DBI::_new_sth($dbh, {
		'Statement'	=> $statement,
		'dbh'		=> $dbh,
		});
	$sth;
	}



package DBD::XBase::st;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;
sub errstr	{ $DBD::XBase::errstr }


use Data::Dumper;
sub execute
	{
	my $sth = shift;
	my $result = $sth->DBD::XBase::st::_parse_SQL($sth->{'Statement'});
	if (not ref $result)
		{ print STDERR "Error: $result\n"; return; }

	my $dbh = $sth->{'dbh'};
	if (defined $result->{'command'} and $result->{'command'} eq "select")
		{
		my $table = $dbh->{'tables'}->{$result->{'table'}};
		if (not defined $table)
			{
			my $table = new XBase($dbh->{'dsn'} . "/" .  $result->{'table'});
		
			print STDERR "Error creating XBase: $XBase::errstr\n"
				unless defined $table;
			
			return;
			
			$dbh->{'tables'}->{$result->{'table'}} = $table;
			}
		
		
		$table->dump_records();

		}

	}
sub _parse_SQL
	{
	shift if ref $_[0];
	local $_ = shift;
	my $errstr = '';
	my $backup = $_;
	my $result = {};
	if (s/^\s*select\s+//i)
		{
		$result->{'command'} = 'select';
		if (s/^\*\s//)
			{ $result->{'selectall'} = 1; }
		elsif (s/^\((\w+\s*(,\s*\w+\s*)*)\)//)
			{ $result->{'unparsedfields'} = $1; }
		elsif (s/^\w+\s*(,\s*\w+\s*)*//)
			{ $result->{'unparsedfields'} = $&; }
		else
			{ $errstr = "Bad field specification: $_"; }
		if (defined $result->{'unparsedfields'})
			{
			my $str = $result->{'unparsedfields'};
			$str =~ s/^\s+//;
			my @fields = split /\s*,\s*/, $str;
			$result->{'fields'} = [ @fields ];
			}
		if ($errstr eq "" and not s/^\s*from\s*//)
			{ $errstr = "From specification missing: $_"; }
		if ($errstr eq "" and s/^([\w.]+)\s*$//)
			{ $result->{'table'} = $+; }
		elsif ($errstr eq "")
			{ $errstr = "Table specification missing: $_"; }
		}
	else
		{ $errstr = "Unknown command: $_"; }
	($errstr ne "") ? $errstr : $result;
	}


package DBD::XBase::table;
use strict;



1;
