
=head1 NAME

DBD::XBase - DBI driver for XBase

=head1 SYNOPSIS

	use DBI;
	my $dbh = DBI->connect("DBI:XBase:/directory/subdir")
						or die $DBI::errstr;
	my $sth = $dbh->prepare("select (ID, MSG) from test")
						or die $dbh->errstr();
	$sth->execute() or die $sth->errstr();

	my @data;
	while (@data = $sth->fetchrow_array())
		{
		...
		}

=head1 DESCRIPTION

DBI compliant driver for module XBase. It is not ready yet, only the

	select * from table

works at the moment.

=head1 VERSION

0.0343

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
use XBase::SQL;

use vars qw($VERSION @ISA @EXPORT $err $errstr $drh);

require Exporter;

$VERSION = '0.0343';

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

	if (not -d $dsn)
		{
		$DBD::XBase::err = 1;
		$DBD::XBase::errstr = "Directory $dsn doesn't exist";
		return undef;
		}
	my $this = DBI::_new_dbh($drh, { 'dsn' => $dsn } );
	$this;
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

	my $parsed_sql = new XBase::SQL($statement);

	my $errstr;

	if (not ref $parsed_sql)
		{ $errstr = 'Parse SQL failed'; }
	elsif (defined $parsed_sql->{errstr})
		{ $errstr = $parsed_sql->{errstr}; }

	if (defined $errstr)
		{
		${$dbh->{Err}} = 2;
		${$dbh->{Errstr}} = "Error: $errstr\n";
		return;
		}

	my $sth = DBI::_new_sth($dbh, {
		'Statement'	=> $statement,
		'dbh'		=> $dbh,
		'xbase_parsed_sql'	=> $parsed_sql,
		});

	if (defined $parsed_sql->{table})
		{
		my $table = $parsed_sql->{table};
		my $xbase = $dbh->{'xbase_tables'}->{$table};
		if (not defined $xbase)
			{
			my $filename = $dbh->{'dsn'} . "/" . $table;
			$xbase = new XBase($filename);
			if (not defined $xbase)
				{
				${$dbh->{Err}} = 3;
				${$dbh->{Errstr}} = "Table not found: " . XBase->errstr . "\n";
				return;
				}
			$dbh->{'xbase_tables'}->{$table} = $xbase;	
			}
		$sth->{xbase_table} = $xbase;

### print STDERR "Not defined :-(\n" unless defined $sth->{xbase_table};

		if (defined $parsed_sql->{fields})
			{
			my $field;
			for $field (@{$parsed_sql->{fields}})
				{
				if (not grep { uc $field eq $_ }
						$xbase->field_names())
					{
					${$dbh->{Err}} = 4;
					${$dbh->{Errstr}} = "Column $field undefined in table $table\n";
					return;
					}
				}
			}
		}

	$sth;
	}


package DBD::XBase::st;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;
sub errstr	{ $DBD::XBase::errstr }

sub execute
	{
	my $sth = shift;
	my $parsed_sql = $sth->{xbase_parsed_sql};
	my $table = $parsed_sql->{table};
	my $xbase = $sth->{dbh}->{xbase_tables}->{$table};
	$sth->{xbase_table} = $xbase if defined $xbase;
	$sth;
	}

sub fetch
	{
        my $sth = shift;
	my $current = $sth->{'xbase_current_record'};
	$current = 0 unless defined $current;
	my $table = $sth->{'xbase_table'};
	my $parsed_sql = $sth->{'xbase_parsed_sql'};
	my @fields;
	if (defined $parsed_sql->{'selectall'})
		{ @fields = $table->field_names(); }
	else
		{ @fields = @{$parsed_sql->{'fields'}}; }
	while ($current <= $table->last_record())
		{
		my %hash = $table->get_record_as_hash($current);
		$sth->{'xbase_current_record'} = ++$current;
		next if $hash{'_DELETED'} != 0;
		if (defined $parsed_sql->{where})
			{


			}
		return [ @hash{ @fields } ];
		}
	$sth->finish(); return ();
	}
	
1;
