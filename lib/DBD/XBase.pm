
=head1 NAME

DBD::XBase - DBI driver for XBase compatible database files

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

$VERSION = '0.065';

$err = 0;
$errstr = '';
$drh = undef;

sub driver
	{
	return $drh if $drh;
	my ($class, $attr) = @_;
	$class .= '::dr';
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

	my $parsed_sql = parse XBase::SQL($statement);
	### use Data::Dumper; print Dumper $parsed_sql;
	if (defined $parsed_sql->{'errstr'})
		{
		${$dbh->{'Err'}} = 2;
		${$dbh->{'Errstr'}} = 'Error in SQL parse: ' . $parsed_sql->{'errstr'};
		return;
		}

	return DBI::_new_sth($dbh, {
		'Statement'	=> $statement,
		'dbh'		=> $dbh,
		'xbase_parsed_sql'	=> $parsed_sql,
		});
	}

sub STORE
	{
	my ($dbh, $attrib, $value) = @_;
	if ($attrib eq 'AutoCommit')
		{ return 1 if $value; croak("Can't disable AutoCommit"); }
	elsif ($attrib eq 'xbase_ignorememo')
		{ $dbh->{'xbase_ignorememo'} = $value; return; }
	$dbh->DBD::_::db::STORE($attrib, $value);
	}
sub FETCH
	{
	my ($dbh, $attrib) = @_;
	if ($attrib eq 'AutoCommit')
		{ return 1; }
	elsif ($attrib eq 'xbase_ignorememo')
		{ return $dbh->{'xbase_ignorememo'}; }
	$dbh->DBD::_::db::FETCH($attrib);
	}

sub _ListTables
	{
	my $dbh = shift;
	opendir DIR, $dbh->{'dsn'} or return;
	my @result = ();
	while (defined(my $item = readdir DIR))
		{
		next unless $item =~ s/\.dbf$//;
		push @result, $item;
		}
	closedir DIR;
	@result;
	}
sub quote
	{
	my $text = $_[1];
	$text =~ s/([\\'])/\\$1/g;
	"'$text'";
	}
sub commit
	{ warn "Commit ineffective while AutoCommit is on"; 1; }
sub rollback
	{ warn "Commit ineffective while AutoCommit is on"; 0; }




package DBD::XBase::st;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;

sub bind_param
	{
	my ($sth, $param, $value, $attribs) = @_;
	$sth->{'param'}[$param - 1] = $value;
	1;
	}
sub bind_columns
	{
	my ($sth, $attrib, @col_refs) = @_;
	my $i = 1;
	for (@col_refs)
		{ $sth->bind_col($i, $_); $i++; }
	1;
	}
sub bind_col
	{
	my ($sth, $col_num, $col_var_ref) = @_;
	$col_num--;
	$sth->{'xbase_bind_col'}[$col_num] = $col_var_ref;
	1;
	}

sub execute
	{
	my $sth = shift;
	if (@_)	{ @{$sth->{'param'}} = @_; }
	$sth->{'param'} = [] unless defined $sth->{'param'};
	
	my $parsed_sql = $sth->{'xbase_parsed_sql'};
	my $command = $parsed_sql->{'command'};
	my $table = $parsed_sql->{'table'}[0];
	my $dbh = $sth->{'dbh'};

	if ($command eq 'create')
		{
		my $dbh = $sth->{'dbh'};
		my $filename = $dbh->{'dsn'} . '/' . $table;
		my $xbase = XBase->create('name' => $filename,
			'field_names' => $parsed_sql->{'createfields'},
			'field_types' => $parsed_sql->{'createtypes'},
			'field_lengths' => $parsed_sql->{'createlengths'},
			'field_decimals' => $parsed_sql->{'createdecimals'});
		if (not defined $xbase)
			{
			${$sth->{'Err'}} = 10;
			${$sth->{'Errstr'}} = XBase->errstr();
			return;
			}
		$dbh->{'xbase_tables'}->{$table} = $xbase;	
		return 1;
		}

	my $xbase = $dbh->{'xbase_tables'}->{$table};
	if (not defined $xbase)
		{
		my $filename = $dbh->{'dsn'} . '/' . $table;
		my %opts = ('name' => $filename);
		$opts{'ignorememo'} = 1 if $dbh->{'xbase_ignorememo'};
		$xbase = new XBase(%opts);
		if (not defined $xbase)
			{
			${$dbh->{'Err'}} = 3;
			${$dbh->{'Errstr'}} = "Table $table not found: @{[XBase->errstr]}\n";
			return;
			}
		$dbh->{'xbase_tables'}->{$table} = $xbase;	
		}

	if (defined $parsed_sql->{'ChopBlanks'})
		{ $xbase->{'ChopBlanks'} = $parsed_sql->{'ChopBlanks'}; }
	$parsed_sql->{'ChopBlanks'} = \$xbase->{'ChopBlanks'};

	my @nonexistfields;
	for my $field (@{$parsed_sql->{'usedfields'}})
		{
		push @nonexistfields, $field
			unless (defined $xbase->field_type($field)
				or grep { $_ eq $field } @nonexistfields);
		}
	if (@nonexistfields)
		{
		my $plural = ((scalar(@nonexistfields) > 1) ? 1 : 0);
		${$dbh->{'Err'}} = 4;
		${$dbh->{'Errstr'}} = qq!Field@{[$plural ? "s do not" : " doesn't"]} exist in table $table\n!;
		return;
		}

	if ($command eq 'insert')
		{
		my $last = $xbase->last_record;
		my @values = &{$parsed_sql->{'insertfn'}}($xbase, $sth->{'param'}, 0);
		if (defined $parsed_sql->{'fields'})
			{
			my %newval;
			@newval{ @{$parsed_sql->{'fields'} } } = @values;
			$xbase->set_record($last + 1);
			$xbase->update_record_hash($last + 1, %newval);
			}
		else
			{
			$xbase->set_record($last + 1, @values);
			}
		return 1;
		}
	
	if (defined $parsed_sql->{'selectall'})
		{
		$parsed_sql->{'fields'} = [ $xbase->field_names ];
		for my $field (@{$parsed_sql->{'fields'}})
			{ push @{$parsed_sql->{'usedfields'}}, $field
			unless grep { $_ eq $field } @{$parsed_sql->{'usedfields'}}; }
		}
	my $cursor = $xbase->prepare_select( @{$parsed_sql->{'usedfields'}} );
	my $wherefn = $parsed_sql->{'wherefn'};
	my @fields = @{$parsed_sql->{'fields'}} if defined $parsed_sql->{'fields'};
	### use Data::Dumper; print Dumper $parsed_sql;
	if ($command eq 'select')
		{
		$sth->{'xbase_cursor'} = $cursor;
		$sth->{'NUM_OF_FIELDS'} = scalar @fields;
		}
	elsif ($command eq 'delete')
		{
		if (not defined $wherefn)
			{
			my $last = $xbase->last_record;
			for (my $i = 0; $i < $last; $i++)
				{ $xbase->delete_record($i); }
			return 1;
			}
		my $values;
		while (defined($values = $cursor->fetch_hashref))
			{
			next unless &{$wherefn}($xbase, $values, $sth->{'param'}, 0);
			$xbase->delete_record($cursor->last_fetched);
			}
		}
	elsif ($command eq 'update')
		{
		my $values;
		while (defined($values = $cursor->fetch_hashref))
			{
			### print Dumper $values;
			next if defined $wherefn and not &{$wherefn}($xbase, $values, $sth->{'param'}, $parsed_sql->{'bindsbeforewhere'});
			my %newval;
			@newval{ @fields } = &{$parsed_sql->{'updatefn'}}($xbase, $values, $sth->{'param'}, 0);
			$xbase->update_record_hash($cursor->last_fetched, %newval);
			}
		}
	elsif ($command eq 'drop')
		{
		$xbase->drop;
		}
	1;
	}

sub fetch
	{
        my $sth = shift;
	return unless defined $sth->{'xbase_cursor'};
	my $cursor = $sth->{'xbase_cursor'};
	my $wherefn = $sth->{'xbase_parsed_sql'}{'wherefn'};

	my $xbase = $cursor->table;
	my $values;
	while (defined($values = $cursor->fetch_hashref))
		{
		next if defined $wherefn and not &{$wherefn}($xbase, $values, $sth->{'param'}, 0);
		last;
		}
	my $retarray;
	$retarray = [ @{$values}{ @{$sth->{'xbase_parsed_sql'}{'fields'}}} ]
		if defined $values;
	my $i = 0;
	for my $ref ( @{$sth->{'xbase_bind_col'}} )
		{
		next unless defined $ref;
		$$ref = $retarray->[$i];
		}
	continue
		{ $i++; }
	
	if (defined $values)
		{ return $retarray; }
	return;
	}
*fetchrow_arrayref = \&fetch;

sub FETCH
	{
	my ($sth, $attrib) = @_;
	if ($attrib eq 'NAME')
		{ return [ @{$sth->{'xbase_parsed_sql'}{'fields'}} ]; }
	elsif ($attrib eq 'NULLABLE')
		{ return [ (1) x scalar(@{ $sth->FETCH('NAME') }) ]; }
	elsif ($attrib eq 'ChopBlanks')
		{ return $sth->{'xbase_parsed_sql'}->{'ChopBlanks'}; }
	else
		{ return $sth->DBD::_::st::FETCH($attrib); }
	}
sub STORE
	{
	my ($sth, $attrib, $value) = @_;
	if ($attrib eq 'ChopBlanks')
		{ $sth->{'xbase_parsed_sql'}->{'ChopBlanks'} = $value; }
	return $sth->DBD::_::st::STORE($attrib, $value);
	}
    
sub finish { 1; }

1;

__END__

=head1 SYNOPSIS

    use DBI;
    my $dbh = DBI->connect("DBI:XBase:/directory/subdir")
    				or die $DBI::errstr;
    my $sth = $dbh->prepare("select MSG from test where ID != 1")
    				or die $dbh->errstr();
    $sth->execute() or die $sth->errstr();

    my @data;
    while (@data = $sth->fetchrow_array())
		{ ## further processing }

=head1 DESCRIPTION

DBI compliant driver for module XBase. Please refer to DBI(3)
documentation for how to actually use the module.
In the B<connect> call, specify the directory for a database name.
This is where the DBD::XBase will look for the tables.

Note that with dbf, there is no database server that the driver
would talk to. This DBD::XBase calls methods from XBase.pm module to
read and write the files on the disk directly.

The DBD::XBase doesn't make use of index files at the moment. If you
really need indexed access, check XBase(3) for notes about ndx
support.

=head1 SUPPORTED SQL COMMANDS

The SQL commands currently supported by DBD::XBase's prepare are:

=head2 select

    select fields from table [ where condition ]

Fields is a comma separated list of fields or a C<*> for all. The
C<where> condition specifies which rows will be returned, you can
have arbitrary arithmetic and boolean expression here, compare fields
and constants and use C<and> and C<or>. Examples:

    select * from salaries where name = "Smith"	
    select first,last from people where login = "ftp"
						or uid = 1324
    select id,name employ where id = ?

You can use bind parameters in the where clause, as the last example
shows. The actual value has to be supplied via bind_param or in the
call to execute, see DBI(3) for details. To check for NULL values in
the C<where> expression, use C<ID IS NULL> and C<ID IS NOT NULL>, not
C<ID == NULL>.

=head2 delete

    delete from table [ where condition ]

The C<where> condition is the same as for B<select>. Examples:

    delete from jobs		## emties the table
    delete from jobs where companyid = "ISW"
    delete from jobs where id < ?

=head2 insert

    insert into table [ ( fields ) ] values ( list of values )

Here fields is a (optional) comma separated list of fields to set,
list of values is a list of constants to assign. If the fields are
not specified, sets the fields in the natural order of the table.
You can use bind parameters in the list of values. Examples:

    insert into accounts (login, uid) values ("guest", 65534)
    insert into accounts (login, uid) values (?, ?)
    insert into passwd values ("user","*",4523,100,"Nice user",
				"/home/user","/bin/bash")

=head2 update

    update table set field = new value [ , set more fields ]
					[ where condition ]

Example:

    update passwd set uid = 65534 where login = "guest"
    update zvirata set name = "Jezek", age = 4 where id = 17

Again, the value can also be specified as bind parameter.

    update zvirata set name = ?, age = ? where id = ?

=head2 create table

    create table table name ( columns specification )

Columns specification is a comma separated list of column names and
types. Example:

    create table rooms ( roomid int, cat char(10), balcony boolean )

The allowed types are

    char num numeric int integer float boolean blob memo date

Some of them are synonyms. They are of course converted to appropriate
XBase types.

=head2 drop table

    drop table table name

Example:

    drop table passwd

=head1 VERSION

0.065

=head1 AUTHOR

(c) 1997--1998 Jan Pazdziora, adelton@fi.muni.cz,
http://www.fi.muni.cz/~adelton/ at Faculty of Informatics, Masaryk
University in Brno, Czech Republic

=head1 SEE ALSO

perl(1); DBI(3), XBase(3)

=cut

