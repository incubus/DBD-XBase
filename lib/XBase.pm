# #######################################################

=head1 NAME

XBase - Perl module for reading and writing the dbf files

=cut

# ############
package XBase;

use 5.004;		# Yes, 5.004 and everything should be fine
use strict;
use XBase::Base;	# will give us general methods

# ##############
# General things

use vars qw( $VERSION $errstr $CLEARNULLS @ISA );

@ISA = qw( XBase::Base );
$VERSION = '0.062';
$CLEARNULLS = 1;		# Cut off white spaces from ends of char fields

*errstr = \$XBase::Base::errstr;


# #########################################
# Open, read_header, init_memo_field, close

# Open the specified file or try to append the .dbf suffix.
sub open
	{
	my ($self) = shift;
	my %options;
	if (scalar(@_) % 2) { $options{'name'} = shift; }	
	$self->{'openoptions'} = { %options, @_ };
	my $filename = $self->{'openoptions'}{'name'};
	for my $ext ('', '.dbf', '.DBF')
		{
		if (-f $filename.$ext)
			{
			$self->NullError();
			return $self->SUPER::open($filename.$ext);
			}
		}
	return $self->SUPER::open($filename);
	}
# We have to provide way to fill up the object upon open
sub read_header
	{
	my $self = shift;
	my $fh = $self->{'fh'};

	my $header;				# read the header
	$fh->read($header, 32) == 32 or do
		{ __PACKAGE__->Error("Error reading header of $self->{'filename'}: $!\n"); return; };

	@{$self}{ qw( version last_update num_rec header_len record_len ) }
		= unpack 'Ca3Vvv', $header;	# parse the data
	my $header_len = $self->{'header_len'};

	my ($names, $types, $lengths, $decimals) = ( [], [], [], [] );
	my ($unpacks, $readproc, $writeproc) = ( [], [], [] );
	my $lastoffset = 1;
	
	while (tell($fh) < $header_len - 1)	# read the field desc's
		{
		my $field_def;
		my $read = $fh->read($field_def, 32);
		last if substr($field_def, 0, 1) eq "\r";
						# we have found the terminator
		
		if ($read != 32)	
			{ __PACKAGE__->Error("Error reading field description: $!\n"); return; };

		my ($name, $type, $length, $decimal)
			= unpack 'A11a1 @16CC', $field_def;
		my ($rproc, $wproc);

		if ($type eq 'C')		# char
			{
			# fixup for char length > 256
			$length += 256 * $decimal; $decimal = 0;
			$rproc = sub { my $value = shift;
				$value =~ s/\s+$// if $CLEARNULLS; $value; };
			$wproc = sub { my $value = shift;
				sprintf '%-*.*s', $length, $length,
					(defined $value ? $value : ''); };
			}
		elsif ($type eq 'L')		# logical (boolean)
			{
			$rproc = sub { my $value = shift;
				if ($value =~ /^[YyTt]$/) { return 1; }
				if ($value =~ /^[NnFf]$/) { return 0; }
				undef; };
			$wproc = sub { my $value = shift;
				sprintf '%-*.*s', $length, $length,
					(defined $value ? ( $value ? 'Y' : 'N') : '? '); };
			}
		elsif ($type =~ /^[NFD]$/)	# numbers, dates
			{
			$rproc = sub { my $value = shift;
				($value =~ /\d/) ? $value + 0 : undef; };
			$wproc = sub { my $value = shift;
				if (defined $value) { sprintf '%*.*f', $length, $decimal, ($value + 0); }
                                else { ' ' x $length; } };
			}
		elsif ($type =~ /^[MGBP]$/)	# memo fields
			{
			my $memo = $self->{'memo'};
			if (not defined $memo and not $self->{'openoptions'}{'ignorememo'})
				{ $memo = $self->{'memo'} = $self->init_memo_field() or return; }
			if (defined $memo)
				{
				$rproc = sub {
					my $value = shift;
					return undef unless $value =~ /\d/;
					$memo->read_record($value - 1) if defined $memo;
					};
				$wproc = sub {
					my $value = $memo->write_record(-1, $type, shift) if defined $memo;
					sprintf '%*.*s', $length, $length,
						(defined $value ? $value + 1: ''); };
				}
			else
				{
				$rproc = sub { undef; };
				$wproc = sub { ' ' x $length; };
				}
			}
		$name =~ s/[\000 ].*$//s;
		$name = uc $name;		# no locale yet
		push @$names, $name;
		push @$types, $type;
		push @$lengths, $length;
		push @$decimals, $decimal;
		push @$unpacks, '@' . $lastoffset . 'a' .  $length;
		push @$readproc, $rproc;
		push @$writeproc, $wproc;
		$lastoffset += $length;
		}

	my $hashnames = {};		# create name-to-num_of_field hash
	@{$hashnames}{ reverse @$names } = reverse ( 0 .. $#$names );

			# now it's the time to store the values to the object
	@{$self}{ qw( field_names field_types field_lengths field_decimals
		hash_names last_field field_unpacks
		field_rproc field_wproc ) } =
			( $names, $types, $lengths, $decimals,
			$hashnames, $#$names, $unpacks,
			$readproc, $writeproc );

	1;	# return true since everything went fine
	}
# When there is a memo field in dbf, try to open the memo file
sub init_memo_field
	{
	my $self = shift;
	return $self->{'memo'} if defined $self->{'memo'};
	require XBase::Memo;
	if (defined $self->{'openoptions'}{'memofile'})
		{ return XBase::Memo->new($self->{'openoptions'}{'memofile'}); }
	
	my $memo;
	my $memoname = $self->{'filename'};
	$memoname =~ s/\.DBF$/.FPT/ or $memoname =~ s/(\.dbf)?$/.fpt/;
	$memo = XBase::Memo->new($memoname, $self->{'version'}) and return $memo;
	
	$memoname = $self->{'filename'};
	$memoname =~ s/\.DBF$/.DBT/ or $memoname =~ s/(\.dbf)?$/.dbt/;
	$memo = XBase::Memo->new($memoname, $self->{'version'}) and return $memo;
	return;
	}
# Close the file (and memo)
sub close
	{
	my $self = shift;
	if (defined $self->{'memo'})
		{ $self->{'memo'}->close(); delete $self->{'memo'}; }
	$self->SUPER::close();
	}

# ###############
# Little decoding
sub version		{ shift->{'version'}; }
sub last_record		{ shift->{'num_rec'} - 1; }
sub last_field		{ shift->{'last_field'}; }

# List of field names, types, lengths and decimals
sub field_names		{ @{shift->{'field_names'}}; }
sub field_types		{ @{shift->{'field_types'}}; }
sub field_lengths	{ @{shift->{'field_lengths'}}; }
sub field_decimals	{ @{shift->{'field_decimals'}}; }

# Return field number for field name
sub field_name_to_num
	{ my ($self, $name) = @_; $self->{'hash_names'}{uc $name}; }
sub field_type
	{
	my ($self, $name) = @_;
	defined (my $num = $self->field_name_to_num($name)) or return;
	($self->field_types)[$num];
	}
sub field_length
	{
	my ($self, $name) = @_;
	defined (my $num = $self->field_name_to_num($name)) or return;
	($self->field_lengths)[$num];
	}
sub field_decimal
	{
	my ($self, $name) = @_;
	defined (my $num = $self->field_name_to_num($name)) or return;
	($self->field_decimals)[$num];
	}


# #############################
# Header, field and record info

# Returns (not prints!) the info about the header of the object
*header_info = \&get_header_info;
sub get_header_info
	{
	my $self = shift;
	my $hexversion = sprintf '0x%02x', $self->version;
	my $longversion = $self->get_version_info;
	my $printdate = $self->get_last_change;
	my $numfields = $self->last_field() + 1;
	my $result = sprintf <<"EOF";
Filename:	$self->{'filename'}
Version:	$hexversion ($longversion)
Num of records:	$self->{'num_rec'}
Header length:	$self->{'header_len'}
Record length:	$self->{'record_len'}
Last change:	$printdate
Num fields:	$numfields
Field info:
Num	Name		Type	Len	Decimal
EOF
	return join '', $result, map { $self->get_field_info($_) }
					(0 .. $self->last_field);
	}
# Return info about field in dbf file
sub get_field_info
	{
	my ($self, $num) = @_;
	sprintf "%d.\t%-16.16s%-8.8s%-8.8s%s\n", $num + 1,
		map { $self->{$_}[$num] }
			qw( field_names field_types field_lengths field_decimals );
	}
# Return last_change item as printable string
sub get_last_change
	{
	my $self = shift;
	my $date = $self;
	if (ref $self) { $date = $self->{'last_update'}; }
	my ($year, $mon, $day) = unpack 'C3', $date;
	$year += 1900;
	return "$year/$mon/$day";
	}
# Return text description of the version value
sub get_version_info
	{
	my $version = shift;
	$version = $version->version() if ref $version;
	my ($vbits, $dbtflag, $memo, $sqltable) = (0, 0, 0, 0);
	if ($version == 3)	{ $vbits = 3; }
	elsif ($version == 0x83)	{ $vbits = 3; $memo = 0; $dbtflag = 1;}
	else {
		$vbits = $version & 0x07;
		$dbtflag = ($version >> 7) & 1;
		$memo = ($version >> 3) & 1;
		$sqltable = ($version >> 4) & 0x07;
		}
	
	my $result = "ver. $vbits";
	if ($memo)	{ $result .= ' with memo file'; }
	elsif ($dbtflag)	{ $result .= ' with DBT file'; }
	$result .= ' containing SQL table' if $sqltable;
	$result;
	}


# Print the records as colon separated fields
sub dump_records
	{
	my $self = shift;
	my %options = ( 'rs' => "\n", 'fs' => ':', 'undef' => '' );
	my %inoptions = @_;
	for my $key (keys %inoptions)
		{
		my $value = $inoptions{$key};
		my $outkey = lc $key;
		$outkey =~ s/[^a-z]//g;
		$options{$outkey} = $value;
		}

	my ($rs, $fs, $undef, $fields) = @options{ qw( rs fs undef fields ) };
	my @fields = ();
	@fields = @$fields if defined $fields;

	my $cursor = $self->prepare_select(@fields);
	my @record;
	while (@record =  $cursor->fetch())
		{ print join($fs, map { defined $_ ? $_ : $undef } @record), $rs; }
	1;
	}



# ###################
# Reading the records

# Returns fields of the specified record; parameters and number of the
# record (starting from 0) and optionally names of the required
# fields. If no names are specified, all fields are returned. The
# first value in the returned list if always 1/0 deleted flag. Returns
# empty list on error.

sub get_record
	{
	my ($self, $num) = (shift, shift);
	$self->NullError();
	$self->get_record_nf( $num, map { $self->field_name_to_num($_); } @_);
	}
*get_record_as_hash = \&get_record_hash;
sub get_record_hash
	{
	my ($self, $num) = @_;
	my @list = $self->get_record($num) or return;
	my $hash = {};
	@{$hash}{ '_DELETED', $self->field_names() } = @list;
	return %$hash if wantarray;
	$hash;
	}
sub get_record_nf
	{
	my ($self, $num, @fieldnums) = @_;
	my $data = $self->read_record($num) or return;

	if (not @fieldnums)
		{ @fieldnums = ( 0 .. $self->last_field ); }
	my $unpack = join ' ', '@0a1', map {
		my $e;
		defined $_ and $e = $self->{'field_unpacks'}[$_];
		defined $e ? $e : '@0a0'; } @fieldnums;
	
	my $rproc = $self->{'field_rproc'};
	my @fns = (\&_read_deleted, map { (defined $_ and defined $rproc->[$_]) ? $rproc->[$_] : sub { undef; }; } @fieldnums);

	my @out = unpack $unpack, $data;

	for (@out) { $_ = &{ shift @fns }($_); }

	@out;
	}

# Processing on read
sub _read_deleted
	{
	my $value = shift;
	if ($value eq '*') { return 1; } elsif ($value eq ' ') { return 0; }
	undef;
	}

sub get_all_records
	{
	my $self = shift;
	my $cursor = $self->prepare_select(@_);

	my $result = [];
	my @record;
	while (@record = $cursor->fetch())
		{ push @$result, [ @record ]; }
	$result;
	}

# #############
# Write records

# Write record, values of the fields are in the argument list.
# Record is always undeleted
sub set_record
	{
	my ($self, $num) = (shift, shift);
	$self->NullError();
	my $wproc = $self->{'field_wproc'};
	my ($i, @data);
	for ($i = 0; $i <= $#$wproc; $i++)
		{ $data[$i] = &{ $wproc->[$i] }(shift); }
	$self->write_record($num, ' ', @data);
	}

# Write record, fields are specified as hash, unspecified are set to
# undef/empty
sub set_record_hash
	{
	my ($self, $num, %data) = @_;
	$self->NullError();
	$self->set_record($num, map { $data{$_} } $self->field_names );
	}

# Write record, fields specified as hash, unspecified will be
# unchanged
sub update_record_hash
	{
	my ($self, $num) = ( shift, shift );
	$self->NullError();

	my %olddata = $self->get_record_hash($num);
	return unless %olddata;
	$self->set_record_hash($num, %olddata, @_);
	}

# Actually write the data (calling XBase::Base::write_record) and keep
# the overall structure of the file correct;
sub write_record
	{
	my ($self, $num) = (shift, shift);
	my $ret = $self->SUPER::write_record($num, @_) or return;

	if ($num > $self->last_record)
		{
		$self->SUPER::write_record($num + 1, "\x1a");	# add EOF
		$self->update_last_record($num) or return;
		}
	$self->update_last_change or return;
	$ret;
	}

# Delete and undelete record
sub delete_record
	{
	my ($self, $num) = @_;
	$self->NullError();
	$self->write_record($num, "*");
	1;
	}
sub undelete_record
	{
	my ($self, $num) = @_;
	$self->NullError();
	$self->write_record($num, " ");
	1;
	}

# Update the last change date
sub update_last_change
	{
	my $self = shift;
	return 1 if defined $self->{'updated_today'};
	my ($y, $m, $d) = (localtime)[5, 4, 3]; $m++;
	$self->write_to(1, pack "C3", ($y, $m, $d)) or return;
	$self->{'updated_today'} = 1;
	}
# Update the number of records
sub update_last_record
	{
	my ($self, $last) = @_;
	$last++;
	$self->write_to(4, pack "V", $last);
	$self->{'num_rec'} = $last;
	}

# Creating new dbf file
sub create
	{
	XBase->NullError();
	my $class = shift;
	my %options = @_;
	if (ref $class)
		{ %options = ( %$class, %options ); $class = ref $class; }

	my $version = $options{'version'};
	$version = 3 unless defined $version;

	my $header = pack 'CCCCVvvvCCa12CCv', $version, 0, 0, 0, 0, 0, 0, 0,
			0, 0, '', 0, 0, 0;

	my $key;
	for $key ( qw( field_names field_types field_lengths field_decimals ) )
		{
		if (not defined $options{$key})
			{
			__PACKAGE__->Error("Tag $key must be specified when creating new table\n");
			return;
			}
		}

	my $record_len = 1;
	my $i;
	for $i (0 .. $#{$options{'field_names'}})
		{
		my $name = uc $options{'field_names'}[$i];
		$name = "FIELD$i" unless defined $name;
		$name .= "\0";
		my $type = $options{'field_types'}[$i];
		$type = "C" unless defined $type;

		my $length = $options{'field_lengths'}[$i];
		my $decimal = $options{'field_decimals'}[$i];

		if (not defined $length)		# defaults
			{
			if ($type eq "C")	{ $length = 64; }
			elsif ($type eq "D")	{ $length = 8; }
			elsif ($type =~ /^[NF]$/)	{ $length = 8; }
			}
						# force correct lengths
		if ($type =~ /^[MBGP]$/)	{ $length = 10; $decimal = 0; }
		elsif ($type eq "L")	{ $length = 1; $decimal = 0; }

		if (not defined $decimal)
			{ $decimal = 0; }
		
		$record_len += $length;
		my $offset = $record_len;
		if ($type eq "C")
			{
			$decimal = int($length / 256);
			$length %= 256;
			}
		$header .= pack 'a11a1VCCvCvCa7C', $name, $type, $offset,
				$length, $decimal, 0, 0, 0, 0, '', 0;
		}
	$header .= "\x0d";

	substr($header, 8, 4) = pack "vv", (length $header), $record_len;

	my $tmp = $class->new();
	my $newname = $options{'name'};
	if (defined $newname and $newname !~ /\.dbf$/) { $newname .= ".dbf"; }
	$tmp->create_file($newname, 0700) or return;
	$tmp->write_to(0, $header) or return;
	$tmp->update_last_change();
	$tmp->close();

	if (grep { /^[MBGP]$/ } @{$options{'field_types'}})
		{
		require XBase::Memo;
		my $dbtname = $options{'name'};
		$dbtname =~ s/\.DBF$/.DBT/ or $dbtname =~ s/(\.dbf)?$/.dbt/;
		my $dbttmp = XBase::Memo->new();
		$dbttmp->create('name' => $dbtname,
			'version' => $options{'version'}) or return;
		}

	return $class->new($options{'name'});
	}
# Drop the table
sub drop
	{
	my $self = shift;
	my $filename = $self;
	if (ref $self)
		{
		if (defined $self->{'memo'})
			{ $self->{'memo'}->drop(); delete $self->{'memo'}; }
		return $self->SUPER::drop();
		}
	XBase::Base::drop($filename);
	}
# Lock and unlock
sub locksh
	{
	my $self = shift;
	$self->SUPER::locksh;
	$self->{'memo'}->locksh() if defined $self->{'memo'};
	}
sub lockex
	{
	my $self = shift;
	$self->SUPER::lockex;
	$self->{'memo'}->lockex() if defined $self->{'memo'};
	}
sub unlock
	{
	my $self = shift;
	$self->{'memo'}->unlock() if defined $self->{'memo'};
	$self->SUPER::unlock;
	}

#
# Attempt for cursory select
#

sub prepare_select
	{
	my $self = shift;
	my $fieldnums = [ map { $self->field_name_to_num($_); } @_ ];
	return bless [ $self, undef, $fieldnums ], 'XBase::Cursor';
	}

package XBase::Cursor;

sub fetch
	{
	my $self = shift;
	my ($xbase, $recno, $fieldnums) = @{$self}[0 .. 2];
	if (defined $recno) { $recno++; }
	else { $recno = 0; }
	my $lastrec = $xbase->last_record;
	while ($recno <= $lastrec)
		{
		my ($del, @result) = $xbase->get_record_nf($recno, @$fieldnums);
		if (not $del)
			{
			$self->[1] = $recno;
			return @result;
			}
		$recno++;
		}
	return;
	}
sub last_fetched
	{ shift->[1]; }

1;

__END__

=head1 SYNOPSIS

  use XBase;
  my $table = new XBase("dbase.dbf") or die XBase->errstr();
  for (0 .. $table->last_record())
	{
	my ($deleted, $id, $msg)
		= $table->get_record($_, "ID", "MSG");
	print "$id:\t$msg\n" unless $deleted;
	}

=head1 DESCRIPTION

This module can read and write XBase database files, known as dbf in
dBase and FoxPro world. It also reads memo fields from the dbt and fpt
files, if needed. Module XBase provides simple native interface to
XBase files. For DBI compliant database access, check the DBD::XBase
and DBI modules.

B<Warning> for now: XBase doesn't support any index files at present!
That means if you change your dbf, your idx/mdx (if you have any) will
not match. You will need to regenerate them using other tools --
probably those that later make use of them. If you do not have any
indexes, do not worry about them.

The following methods are supported by XBase module:

=head2 General methods

=over 4

=item new

Creates the XBase object, loads the info form the dbf file. The first
parameter should be the name of existing dbf file (table, in fact) to
read. A suffix .dbf will be appended if needed. This method creates and
initializes new object, will also check for memo file, if needed.

The parameters can also be specified in the form of hash: values for
B<name> is then the name of the table, other flags supported are
B<memofile> to specify non standard name for the associated memo file
and B<ignorememo> to ignore memo file at all. The second is usefull if
you've lost the dbt file somewhere and you do not need it.

=item close

Closes the object/file.

=item create

Creates new database file on disk and initializes it with 0 records.
A dbt (memo) file will be also created if the table contains some memo
fields. Parameters to create are passed as hash.

You can call this method as method of another XBase object and then
you only need to pass B<name> value of the hash; the structure
(fields) of the new file will be the same as of the original object.

If you call B<create> using class name (XBase), you have to (besides
B<name>) also specify another four values, each being a reference
to list: B<field_names>, B<field_types>, B<field_lengths> and
B<field_decimals>. The field types are specified by one letter
strings (C, N, L, D). If you set some value as undefined, create will
make it into some reasonable default.

The new file mustn't exist yet -- XBase will not allow you to
overwrite existing table. Use B<drop> (or unlink) to delete it first.

=item drop

This method closes the table and deletes it on disk (including
associated memo file, if there is any).

=item last_record

Returns number of the last record in the file. The lines deleted but
present in the file are included in this number.

=item last_field

Returns number of the last field in the file, number of fields minus 1.

=item field_names, field_types, field_lengths, field_decimals

Return list of field names and so on for the dbf file.

=item field_type, field_length, field_decimal

For a field name, returns the appropriate value. Returns undef if the
field doesn't exist in the table.

=back

=head2 Reading the data one by one

When dealing with the records, reading or writing, you have
to specify the number of the record in the file. The range is
C<0 .. $table-E<gt>last_record()>.

=over 4

=item get_record

Returns a list of data (field values) from the specified record (line
of the table). The first parameter in the call is the number of the
record. If you do not specify any other parameters, all fields are
returned in the same order as they appear in the file. You can also
put list of field names after the record number and then only those
will be returned. The first value of the returned list is always the
1/0 C<_DELETED> value saying if the record is deleted or not, so on
success, B<get_record> will never return empty list.

=item get_record_as_hash

Returns hash (in list context) or reference to hash (in scalar
context) containing field values indexed by field names. The name of
the deleted flag is C<_DELETED>. The only parameter in the call is
the record number.

=back

=head2 Writing the data

All three writing methods always undelete the record. On success they
return true -- the record number actually written.

=over 4

=item set_record

As parameters, takes the number of the record and the list of values
of the fields. It writes the record to the file. Unspecified fields
(if you pass less than you should) are set to undef/empty.

=item set_record_hash

Takes number of the record and hash as parameters, sets the fields,
unspecified are undefed/emptied.

=item update_record_hash

Like B<set_record_hash> but fields that do not have value specified
in the hash retain their value.

=back

To explicitely delete/undelete a record, use methods B<delete_record>
or B<undelete_record> with record number as a parameter.

=head2 Dumping the content of the file

If you need to deal with the whole content of the dbf file, there is
a method B<get_all_records>. It returns a reference to array
containing array of values for each record. Only not deleted records
are returned and so the C<_DELETED> flag is not included in the record
data. As a parameter, pass list of fields to return for each record.

To read the records one by one, you can create a cursor using
B<prepare_select>. This returns an object and you can then call
repeatedly its method B<fetch> to retrieve next not deleted record. As
for B<get_all_records>, the C<_DELETED> is not included in the
returned list of field values, and you can specify only some of the
fields to be fetched in each record.

To print the content of the file in a readable form, use method
B<dump_records>. It prints all not deleted records from the file. By
default, all fields are printed, separated by colons, one record on
a row. The method can have parameters in a form of a hash with the
following keys:

=over 4

=item rs

Record separator, string, newline by default.

=item fs

Field separator, string, one colon by default.

=item fields

Reference to a list of names of the fields to print. By default it's
undef, meaning all fields.

=item undef

What to print for undefined (NULL) values, empty string by default.

=back

Example of use is

    use XBase;
    my $table = new XBase "table" or die XBase->errstr;
    $table->dump_records("fs" => " | ", "rs" => " <-+\n",
			"fields" => [ "id", "msg" ]);'

=head2 Errors and debugging

If the method fails (returns false or null list), the error message
can be retrieved via B<errstr> method. If the B<new> or B<create>
method fails, you have no object so you get the error message using
class syntax C<XBase-E<gt>errstr()>.

The method B<get_header_info> returns (not prints) string with
information about the file and about the fields.

Module XBase::Base(3) defines some basic functions that are inherited
by both XBase and XBase::Memo(3) module.

In the module XBase there is variable $CLEARNULLS that specifies,
whether will the reading methods cut off spaces and nulls from the
end of fixed character fields on read. The default is true.

=head1 LITTLE EXAMPLE

This is a code to update field MSG in record where ID is 123.

    use XBase;
    my $table = new XBase "test.dbf" or die XBase->errstr;
    for (0 .. $table->last_record)
    	{
    	my ($deleted, $id) = $table->get_record($_, "ID")
    	die $table->errstr unless defined $deleted;
    	next if $deleted;
	$table->update_record_hash($_, "MSG" => "New message")
						if $id == 123;
    	}

For some more examples please see the eg directory of the distribution.

=head1 MEMO FIELDS and INDEX FILES

If there is a memo field in the dbf file, the module tries to open
file with the same name but extension dbt or fpt. It uses module
XBase::Memo(3) for this. It reads and writes this memo field
transparently (you do not know about it).

No index files are currently supported. I'm working on a support for
ndx index files but it's still far from being ready. Please send me
examples of your data files and suggestions for interface if you need
indexes.

=head1 HISTORY

I have been using the Xbase(3) module by Pratap Pereira for quite
a time to read the dbf files, but it had no writing capabilities, it
was not C<use strict> clean and the author did not support the
module behind the version 1.07. So I started to make my own patches
and thought it would be nice if other people could make use of them.
I thought about taking over the development of the original Xbase
package, but the interface seemed rather complicated to me.

So with the help of article XBase File Format Description by Erik
Bachmann on URL

    http://www.geocities.com/SiliconValley/Pines/2563/xbase.htm

I have written a new module. It doesn't use any code from Xbase-1.07
and you are free to use and distribute it under the same terms as Perl
itself.

Please send all bug reports or patches CC'ed to my e-mail, since I
might miss your post in c.l.p.m or dbi-users (or other groups). Any
comments about both the Perl and XBase issues of this module are also
welcome.

=head1 VERSION

0.062

=head1 AUTHOR

(c) 1997--1998 Jan Pazdziora, adelton@fi.muni.cz,
http://www.fi.muni.cz/~adelton/ at Faculty of Informatics, Masaryk
University in Brno, Czech Republic

=head1 SEE ALSO

perl(1); DBD::XBase(3) and DBI(3) for DBI interface; dbfdump(1)

=cut

