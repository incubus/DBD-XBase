
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

DBI compliant driver for module XBase.

=head1 VERSION

0.034

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

$VERSION = '0.034';

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
	my $parsed_sql = DBD::XBase::db::_parse_SQL($statement);
	if (not ref $parsed_sql)
		{
		${$dbh->{Err}} = 2;
		${$dbh->{Errstr}} = "Error: $parsed_sql\n";
		return;
		}
	my $sth = DBI::_new_sth($dbh, {
		'Statement'	=> $statement,
		'dbh'		=> $dbh,
		'xbase_parsed_sql'	=> $parsed_sql,
		});
	$sth;
	}

# select fields from table [ where conditions ]
# update table set operation [, operations ] [ where conditions ]
# delete from table where conditions
# insert into table [ fields ] values values

sub _parse_SQL
	{
	my $statement = shift;
	if (not @_)
		{ $statement = $statement->{'Statement'} if ref $statement; }
	else
		{ $statement = shift; }
	local $_ = $statement;
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
		if ($errstr eq "" and not s/^\s*from\s*//i)
			{ $errstr = "From specification missing: $_"; }
		if ($errstr eq "" and s/^(\S+)\s*$//)
			{ $result->{'table'} = $+; }
		elsif ($errstr eq "")
			{ $errstr = "Table specification missing: $_"; }
		}
	else
		{ $errstr = "Unknown command: $_"; }
	($errstr ne "") ? $errstr : $result;
	}


package DBD::XBase::st;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;
sub errstr	{ $DBD::XBase::errstr }

sub execute
	{
	my $sth = shift;
	my $parsed_sql = $sth->{'xbase_parsed_sql'};
	my $dbh = $sth->{'dbh'};
	if ($parsed_sql->{'command'} eq "select")
		{
		my $from = $parsed_sql->{'table'};
		my $table = $dbh->{'xbase_tables'}->{$from};
		if (not defined $table)
			{
			my $filename = $dbh->{'dsn'} . "/" . $parsed_sql->{'table'};
			$table = new XBase($filename);

			if (not defined $table)
				{
				${$sth->{Err}} = 3;
				${$sth->{Errstr}} = $XBase::errstr;
				return;
				}
			$dbh->{'xbase_tables'}->{$from} = $table;
			}
		$sth->{'xbase_current_record'} = 0;
		$sth->{'xbase_table'} = $table;
		}
	}

sub fetch
	{
        my $sth = shift;
	my $current = $sth->{'xbase_current_record'};
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
		if ($hash{'_DELETED'} == 0)
			{ return [ @hash{ @fields } ]; }
		}
	$sth->finish(); return ();
	}
	
1;
