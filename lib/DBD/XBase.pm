
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

$VERSION = '0.064';

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

	if ($parsed_sql->{'command'} eq 'create')
		{
		return DBI::_new_sth($dbh, {
			'Statement'	=> $statement,
			'dbh'		=> $dbh,
			'xbase_parsed_sql'	=> $parsed_sql,
			});
		}
	
	my $table = $parsed_sql->{'table'}[0];
	my $xbase = $dbh->{'xbase_tables'}->{$table};
	if (not defined $xbase)
		{
		my $filename = $dbh->{'dsn'} . '/' . $table;
		$xbase = new XBase($filename);
		if (not defined $xbase)
			{
			${$dbh->{'Err'}} = 3;
			${$dbh->{'Errstr'}} =
				"Table $table not found: @{[XBase->errstr]}\n";
			return;
			}
		$dbh->{'xbase_tables'}->{$table} = $xbase;	
		}

	$parsed_sql->{'xbase'} = $xbase;

	my $field;
	my @nonexistfields = ();
	for $field (@{$parsed_sql->{'usedfields'}})
		{
		push @nonexistfields unless (defined $xbase->field_type($field) or grep { $_ eq $field } @nonexistfields);
		}
	if (@nonexistfields)
		{
		my $plural = ((scalar(@nonexistfields) > 1) ? 1 : 0);
		${$dbh->{'Err'}} = 4;
		${$dbh->{'Errstr'}} = qq!Field@{[$plural ? "s" : ""]} @{[$plural ? "do not" : "doesn't"]} exist in table $table\n!;
		return;
		}

	DBI::_new_sth($dbh, {
		'Statement'	=> $statement,
		'dbh'		=> $dbh,
		'xbase_parsed_sql'	=> $parsed_sql,
		'xbase_table'	=> $xbase,
		});
	}

sub STORE {
	my ($dbh, $attrib, $value) = @_;
	if ($attrib eq 'AutoCommit')
		{ return 1 if $value; croak("Can't disable AutoCommit"); }
	$dbh->DBD::_::db::STORE($attrib, $value);
	}
sub FETCH {
	my ($dbh, $attrib) = @_;
	if ($attrib eq 'AutoCommit')
		{ return 1; }
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
	### print STDERR "bind_col: $sth, $col_num, $col_var_ref, $sth->{'xbase_bind_col'}[$col_num]\n";
	1;
	}

sub execute
	{
	my $sth = shift;
	if (@_)
		{ @{$sth->{'param'}} = @_; }
	$sth->{'param'} = [] unless defined $sth->{'param'};
	my $xbase = $sth->{'xbase_table'};
	my $parsed_sql = $sth->{'xbase_parsed_sql'};

	delete $sth->{'xbase_current_record'}
				if defined $sth->{'xbase_current_record'};

	my $command = $parsed_sql->{'command'};
	if ($command eq 'delete')
		{
		my $recno = 0;
		my $last = $xbase->last_record();
		if (not defined $parsed_sql->{'wherefn'})
			{
			for ($recno = 0; $recno <= $last; $recno++)
				{ $xbase->delete_record($recno); }
			}
		else
			{
			for ($recno = 0; $recno <= $last; $recno++)
				{
				my $values = $xbase->get_record_as_hash($recno);
				next if $values->{'_DELETED'} != 0;
				next unless &{$parsed_sql->{'wherefn'}}($xbase, $values, $sth->{'param'});
				$xbase->delete_record($recno);
				}
			}
		return 1;
		}
	elsif ($command eq 'update')
		{
		my $recno = 0;
		my $last = $xbase->last_record();
		my $wherefn = $parsed_sql->{'wherefn'};
		my @fields = @{$parsed_sql->{'fields'}};
		my @values = &{$parsed_sql->{'updatefn'}}($xbase, $sth->{'param'}, 0);
		for ($recno = 0; $recno <= $last; $recno++)
			{
			my $values = $xbase->get_record_as_hash($recno);
			next if $values->{'_DELETED'} != 0;
			next if defined $wherefn and not &{$wherefn}($xbase, $values, $sth->{'param'});
			
			my %newval;
			@newval{ @fields } = @values;
			$xbase->update_record_hash($recno, %newval);
			}
		return 1;
		}
	elsif ($command eq 'insert')
		{
		my $recno = 0;
		my $last = $xbase->last_record();
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
	elsif ($command eq 'create')
		{
		my $dbh = $sth->{'dbh'};
		my $table = ${$parsed_sql->{'table'}}[0];
		my $filename = $dbh->{'dsn'} . '/' . $table;
		my $xbase = XBase->create('name' => $filename,
			'field_names' => $parsed_sql->{'createfields'},
			'field_types' => $parsed_sql->{'createtypes'},
			'field_lengths' => $parsed_sql->{'createlengths'},
			'field_decimals' => $parsed_sql->{'createdecimals'});
		if (not defined $xbase)
			{
			### ${$sth->{'Err'}} = 10;
			${$sth->{'Errstr'}} = XBase->errstr();
			return;
			}
		$dbh->{'xbase_tables'}->{$table} = $xbase;	
		return 1;
		}
	elsif ($command eq 'select')
		{
		unless (defined $sth->{'num_of_fields'})
			{
			my $numfields = scalar( @{ $sth->FETCH('NAME') } );
			$sth->STORE('NUM_OF_FIELDS', $numfields);
			$sth->{'num_of_fields'} = $numfields;
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
	my $current = $sth->{'xbase_current_record'};
	my $parsed_sql = $sth->{'xbase_parsed_sql'};
	my $table = $sth->{'xbase_table'};
	return unless $parsed_sql->{'command'} eq 'select';
	$current = 0 unless defined $current;
	my @fields = @{ $sth->FETCH('NAME') };
	while ($current <= $table->last_record())
		{
		my $values = $table->get_record_as_hash($current);
		$sth->{'xbase_current_record'} = ++$current;
		next if $values->{'_DELETED'} != 0;
		if (defined $parsed_sql->{'wherefn'})
			{ next unless &{$parsed_sql->{'wherefn'}}($table, $values, $sth->{'param'}); }
		my $retarray = [ @{$values}{ @fields } ];
		my $i = 0;
		for my $ref ( @{$sth->{'xbase_bind_col'}} )
			{
### print STDERR "Ref: $ref\n";
			next unless defined $ref;
			$$ref = $retarray->[$i]
			}
		continue
			{ $i++; }
		return $retarray;
		}
	$sth->finish(); return;
	}
*fetchrow_arrayref = \&fetch;

sub FETCH
	{
	my ($sth, $attrib) = @_;
	if ($attrib eq 'NAME')
		{
		my $parsed_sql = $sth->{'xbase_parsed_sql'};
		my $table = $sth->{'xbase_table'};
		if (defined $parsed_sql->{'selectall'})
			{ return [ $table->field_names() ]; }
		else
			{ return [ @{$parsed_sql->{'fields'}} ]; }
		}
	elsif ($attrib eq 'NULLABLE')
		{
		my $name = $sth->FETCH('NAME');
		return [ (1) x scalar(@$name) ];
		}
	else
		{ return $sth->DBD::_::st::FETCH($attrib); }
	}
sub STORE
	{
	my ($sth, $attrib, $value) = @_;
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
		{
		## further processing
		}

=head1 DESCRIPTION

DBI compliant driver for module XBase. Please refer to DBI(3)
documentation for how to actually use the module.
In the B<connect> call, specify the directory for a database name.
This is where the DBD::XBase will look for the tables.

The SQL commands currently supported by DBD::XBase include:

=over 4

=item select

    select fields from table [ where condition ]

Fields is a comma separated list of fields or a C<*> for all. The
C<where> condition specifies which rows will be returned, you can
compare fields and constants and stack expressions using C<and> or
C<or>, and also use brackets. Examples:

    select * from salaries where name = "Smith"	
    select first,last from people where login = "ftp"
						or uid = 1324

You can use bind parameters in the where clause. To check for NULL
values, use ID IS NULL, not ID == NULL.

=item delete

    delete from table [ where condition ]

The C<where> condition si the same as for C<select>. Examples:

    delete from jobs		## emties the table
    delete from jobs where companyid = "ISW"
    delete from jobs where id < ?

=item insert

    insert into table [ ( fields ) ] values ( list of values )

Here fields is a comma separated list of fields to set, list of values
is a list of values to assign. If the fields are not specified, the
fields in the natural order in the table are set. Example:

    insert into accounts (login, uid) values ("guest", 65534)

You can use bind parameters in the list of values:

    insert into accounts (login, uid) values (?, ?)

=item update

    update table set field = new value [ , set more fields ]
					[ where condition ]

Example:

    update table set uid = 65534 where login = "guest"

Again, the value can also be specified as bind parameter.

=item create table

    create table table name ( columns specification )

Columns specification is a comma separated list of column names and
types. Example:

    create table rooms ( roomid int, cat char(10), balcony boolean)

=item drop table

    drop table table name

=back

=head1 VERSION

0.064

=head1 AUTHOR

(c) 1997--1998 Jan Pazdziora, adelton@fi.muni.cz,
http://www.fi.muni.cz/~adelton/ at Faculty of Informatics, Masaryk
University in Brno, Czech Republic

=head1 SEE ALSO

perl(1); DBI(3), XBase(3)

=cut

