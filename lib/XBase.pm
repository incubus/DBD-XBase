
=head1 NAME

XBase - Perl module for reading and writing the dbf files

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

This module can read and write XBase database file, known as dbf in
dBase and FoxPro world. It also reads memo fields from the dbt files,
if needed. Module XBase provides simple native interface to XBase
files and you can also use the DBD::XBase DBI driver (is not complete
yet).

B<Warning> for now: It doesn't support any index files at the present
time! That means if you change your dbf, your idx&mdx (if you have
any) will not match. So do not do that.

The following methods are supported:

=head2 General methods

=over 4

=item new

Creates the XBase object, the argument gives the dbf file (table in
fact) name. A suffix .dbf will be appended if needed. This method
creates a new object and reads the file header. It will also read
appropriate memo file if there is a memo field in dbf.

=item close

Closes the object/file.

=item create

Creates new database file on disk and initializes it with 0 records.
A dbt (memo) file will be also created if the table contains some memo
field. Arguments to create are passed as hash.

You can call this method as method of another XBase object and then
you only need to pass B<name> value of the hash; the structure
(fields) of the new file will be the same as of the original object.

If you call create using class name (XBase), you have to (besides
B<name>) also specify another four values, each being a reference
to list: B<field_names>, B<field_types>, B<field_lengths> and
B<field_decimals>. The field types are specified by one letter
strings. If you set certain value (except field name) as undefined,
create will make it into some reasonable default.

The new file mustn't exist yet -- XBase will not allow you to
overwrite existing table. Use B<drop> to delete them first (or unlink).

=item drop

This method closes the table and deletes it on disk (including dbt
file, if there is any).

=item last_record

Returns number of the last record in the file. The lines deleted but
present in the file are included in this number.

=item last_field

Returns number of the last field in the file, number of fields minus 1.

=item field_names, field_types, field_lengths, field_decimals

Return list of field names and so on for the dbf file.

=back

When dealing with the records, reading or writing, you always have
to specify the number of the record in the file. The range is
0 .. $table->last_record().

=head2 Reading the data

=over 4

=item get_record

Returns a list of data (field values) from the specified record (line
of the table). The first argument in the call is the number of the
record. If you do not specify any other argument, all fields are
returned. You can also put list of field names after the record number
and then only those will be returned. The first value of the returned
list is the 1/0 _DELETED value saying if the record is deleted or not,
so on success, get_record will never return empty list.

=item get_record_as_hash

Returns hash (in list context) or reference to hash (in scalar
context) containing field values indexed by field names. The deleted
flag has name _DELETED. The only argument in the call is the record
number.

=back

=head2 Writing the data

=over 4

=item set_record

As arguments, takes the number of the record and the list of values
of the fields. It writes the record to the file. Unspecified fields
(if you pass less than you should) are set to undef/empty. The record
is undeleted.

=item set_record_hash

Takes number of the record and hash as arguments, sets the fields,
unspecified are undeffed/emptied. The record is undeleted.

=item update_record_hash

Like B<write_record_hash> but preserves fields that do not have value
specified in the hash. The record is undeleted.

=item delete_record, undelete record

Deletes/undeletes the record.

=back

The set and update methods return the record number actually written,
number 0 is returned as true.

=head2 Errors and debugging

If the method fails (returns undef of null list), the error message
can be retrieved via B<errstr> method. If the B<new> or B<create>
method fails, you have no object so you get the error message using
class syntax XBase->errstr().

The methods B<get_header_info> returns (not prints) information about
the file and about the fields, B<dump_records> prints all records from
the file, one on a line, fields separated by commas.

Module XBase::Base(3) defines some basic functionality and also following
variables, that affect the internal behaviour:

=over 4

=item $DEBUG

Enables error messages on stderr.

=item $FIXPROBLEMS

When reading the file, try to continue, even if there is some
(minor) missmatch in the data.

=back

In the module XBase there is variable $CLEARNULLS that specifies,
whether will the reading methods cuts off spaces and nulls from the
end of fixed character fields on read. The default is true.

=head1 LITTLE EXAMPLE

This is a code to update field MSG in record where ID is 123.

	use XBase;
	my $table = new XBase("test.dbf") or die XBase->errstr();
	for (0 .. $table->last_record())
		{
		my ($deleted, $id)
			= $table->get_record($_, "ID")
		die $table->errstr unless defined $deleted;
		next if $deleted;
		if ($id == 123)
			{
			$table->update_record_hash($_,
				"MSG" => "New message");
			last;
			}
		}

=head1 MEMO FIELDS and INDEX FILES

If there is a memo field in the dbf file, the module tries to open
file with the same name but extension .dbt. It uses module
XBase::Memo(3) for this. It reads and writes this memo field
transparently (ie you do not know about it).

No index files are currently supported. Two reasons: you do not need
them when reading the file because you specify the record number
anyway and writing them is extremely difficult. I will try to add the
support but do not promise anything ;-) There are too many too complex
questions: how about compound indexes? Which index formats should
I support? What files contain the index data? I do not have dBase nor
Fox* so do not have data to experiment.

Please send me examples of your data files and suggestions for
interface.

=head1 HISTORY

I have been using the Xbase(3) module by Pratap Pereira for quite
a time to read the dbf files, but it had no writing capabilities, it
was not C<use strict> clean and the author did not support the
module behind the version 1.07. So I started to make my own patches
and thought it would be nice if other people could make use of them.
I thought about taking over the development of the original Xbase
package, but the interface seemed rather complicated to me and I also
disliked the licence Pratap had about the module.

So with the help of article XBase File Format Description by Erik
Bachmann on URL http://www.geocities.com/SiliconValley/Pines/2563/xbase.htm
I have written a new module. It doesn't use any code from Xbase-1.07
and you are free to use and distribute it under the same terms as Perl
itself.

Please send all bug reports cc'ed to my e-mail, since I might miss
your post in c.l.p.misc or dbi-users (or other groups). Any comments
both about the Perl and XBase are welcome.

=head1 VERSION

0.039

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1); DBD::XBase(3) and DBI(3) for DBI interface

=cut

# ########
use 5.004;	# Yes, 5.004 and everything should be fine

# #############################
# Here starts the XBase package

package XBase;

use strict;
use XBase::Base;	# will give us general methods


# ##############
# General things

use vars qw( $VERSION $errstr $CLEARNULLS @ISA );

@ISA = qw( XBase::Base );

$VERSION = "0.039";

$errstr = "Use of \$XBase::errstr is depreciated, please use XBase->errstr() instead\n";

# If set, will cut off the spaces and nulls from ends of character fields
$CLEARNULLS = 1;

# ########################
# Constructor, open, close

# Constructor of the class; expects class name and filename of the
# .dbf file, returns the object if the file can be read, null otherwise
sub new
	{
	my $class = shift;
	my $result = $class->SUPER::new(@_);
	###
	### depreciated
	### $errstr = $XBase::Base::errstr unless $result;
	###
	$result;
	}
sub open
	{
	my $self = shift;
	if (not defined $self->{'opened'} or not $self->{'opened'})
		{
		if (@_ and not defined $self->{'filename'})
			{ $self->{'filename'} = shift; }
		my $filename = $self->{'filename'};
		if ((not -f $filename) and $filename !~ /\.dbf$/i)
			{ $self->{'filename'} = $filename . '.dbf'; }
		}
	$self->SUPER::open(@_);
	}
# We have to provide way to fill up the object upon open
sub read_header
	{
	my $self = shift;
	my ($filename, $fh) = @{$self}{ qw( filename fh ) };

	my $header;		# read the header
	$fh->read($header, 32) == 32 or do
		{ Error "Error reading header of $filename\n"; return; };

	my ($version, $last_update, $num_rec, $header_len, $record_len,
		$res1, $incompl_trans, $enc_flag, $rec_thread,
		$multiuser, $mdx_flag, $language_dr, $res2)
		= unpack "Ca3Vvva2CCVa8CCa2", $header;
				# parse the data

	my ($names, $types, $lengths, $decimals) = ( [], [], [], [] );

				# will read the field descriptions
	while (tell($fh) < $header_len - 1)
		{
		my $field_def;	# read the field description
		$fh->read($field_def, 32) == 32 or do
			{
			Warning "Error reading field description\n";
			last if FIXPROBLEMS;
			return;
			};

		last if substr($field_def, 0, 1) eq "\r";
				# we have found the terminator

		my ($name, $type, $address, $length, $decimal,
			$multiuser1, $work_area, $multiuser2,
			$set_fields_flag, $res, $index_flag)
				= unpack "A11aVCCa2Ca2Ca7C", $field_def;
	
		$name = uc $name;

		if ($type eq "C")
			{ $length += 256 * $decimal; $decimal = 0; }
				# fixup for char length > 256

		push @$names, $name;
		push @$types, $type;
		push @$lengths, $length;
		push @$decimals, $decimal;
		}		# store the information

	my $hashnames;		# create name-to-num_of_field hash
	@{$hashnames}{ reverse @$names } = reverse ( 0 .. $#$names );

	my $template = join "", "a1",
		map { "a" . $lengths->[$_]; } (0 .. $#$names);
	
			# now it's the time to store the values to the object
	@{$self}{ qw( version last_update num_rec header_len record_len
		field_names field_types field_lengths field_decimals
		hash_names unpack_template last_field ) } =
			( $version, $last_update, $num_rec, $header_len,
			$record_len, $names, $types, $lengths, $decimals,
			$hashnames, $template, $#$names );

	if (grep { /^[MGBP]$/ } @$types)
		{ $self->{'memo'} = $self->init_memo_field(); }

	1;	# return true since everything went fine
	}

sub init_memo_field
	{
	my $self = shift;
	return $self->{'memo'} if defined $self->{'memo'};
	my $dbtname = $self->{'filename'};
	$dbtname =~ s/(\.dbf)?$/.dbt/i;
	require XBase::Memo;
	return XBase::Memo->new($dbtname);
	}

sub close
	{
	my $self = shift;
	if (defined $self->{'memo'})
		{ $self->{'memo'}->close(); delete $self->{'memo'}; }
	$self->SUPER::close();
	}

# ###############
# Little decoding

# Returns the number of the last record
sub last_record		{ shift->{'num_rec'} - 1; }
# And the same for fields
sub last_field		{ shift->{'last_field'}; }

# List of field names, types, lengths and decimals
sub field_names		{ @{shift->{'field_names'}}; }
sub field_types		{ @{shift->{'field_types'}}; }
sub field_lengths	{ @{shift->{'field_lengths'}}; }
sub field_decimals	{ @{shift->{'field_decimals'}}; }

# Return field number for field name
sub field_name_to_num
	{
	my $self = shift;
	my $name = shift;
	$self->{'hash_names'}{$name};
	}


# #############################
# Header, field and record info

# Returns (not prints!) the info about the header of the object
sub get_header_info
	{
	my $self = shift;
	my $hexversion = sprintf "0x%02x", $self->{'version'};
	my $longversion = $self->decode_version_info();
	my $printdate = $self->decode_last_change($self->{'last_update'});
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
	return join "", $result, map { $self->get_field_info($_) }
					(0 .. $self->last_field());
	}

# Returns info about field in dbf file
sub get_field_info
	{
	my ($self, $num) = @_;
	sprintf "%d.\t%-16.16s%-8.8s%-8.8s%-8.8s\n", $num + 1,
		map { $self->{$_}[$num] }
			qw( field_names field_types field_lengths field_decimals );
	}

# Returns last_change item in printable string
sub decode_last_change
	{
	shift if ref $_[0];
	my ($year, $mon, $day) = unpack "C3", shift;
	$year += 1900;
	return "$year/$mon/$day";
	}

# Prints the records as comma separated fields
sub dump_records
	{
	my $self = shift;
	my $num;
	for $num (0 .. $self->last_record())
		{ print join(':', map { defined $_ ? $_ : ''; }
				$self->get_record($num, @_)), "\n"; }
	1;
	}
sub decode_version_info
	{
	my $version = shift;
	$version = $version->{'version'} if ref $version;
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
	if ($dbtflag)
		{ $result .= " with DBT file"; }
	elsif ($memo)
		{ $result .= " with some memo file"; }
	$result .= " containing SQL table" if $sqltable;
	$result;
	}



# ###################
# Reading the records

# Returns fields of the specified record; parameters and number of the
# record (starting from 0) and optionally names of the required
# fields. If no names are specified, all fields are returned. The
# first value in the returned list if always 1/0 deleted flag. Returns
# empty list on error

sub get_record
	{
	NullError();
	my ($self, $num, @fields) = @_;

	my @data = $self->read_record($num);
				# SUPER will uncache/unpack for us
	return unless @data;

	@data = $self->process_list_on_read(@data);

	if (@fields)		# now make a list of numbers of fields
		{		# to be returned
		return $data[0], map {
			if (not defined $self->{'hash_names'}{$_})
				{
				Warning "Field named '$_' does not seem to exist\n";
				return unless FIXPROBLEMS;
				undef;
				}
			else
				{ $data[$self->{'hash_names'}{$_} + 1]; }
			} @fields;
		}
	return @data;
	}

sub get_record_as_hash
	{
	my ($self, $num) = @_;
	my @list = $self->get_record($num);
	return () unless @list;
	my $hash = {};
	@{$hash}{ '_DELETED', $self->field_names() } = @list;
	return %$hash if wantarray;
	$hash;
	}

sub process_list_on_read
	{
	my $self = shift;

	my @data;
	my $num;
	for $num (0 .. $self->last_field() + 1)
		{
		my $value = $_[$num];
		if ($num == 0)
			{
			if ($value eq '*')      { $data[$num] = 1; }
			elsif ($value eq ' ')	{ $data[$num] = 0; }
			else { Warning "Unknown deleted flag '$value' found\n";}
			next;
			}
		my $type = $self->{'field_types'}[$num - 1];
		if ($type eq 'C')
			{
			$value =~ s/\s+$// if $CLEARNULLS;
			$data[$num] = $value
			}
		elsif ($type eq 'L')
			{
			if ($value =~ /^[YyTt]$/)	{ $data[$num] = 1; }
			if ($value =~ /^[NnFf]$/)	{ $data[$num] = 0; }
			# return undef;	# ($value eq '?')
			}
		elsif ($type eq 'N' or $type eq 'F')
			{
			next unless $value =~ /\d/;
			my $len = $self->{'field_lengths'}[$num - 1];
			my $dec = $self->{'field_decimals'}[$num - 1];
			if ($dec)
				{ $data[$num] = sprintf "%-$len.${dec}f", $value; }
			else
				{ $data[$num] = sprintf "%-${len}d", $value; }
			$data[$num] += 0;
			}
		elsif ($type =~ /^[MGBP]$/)
			{
			if (defined $self->{'memo'} and $value !~ /^ +$/)
				{ $data[$num] = $self->{'memo'}->read_record($value); }
			}
		else
			{ $data[$num] = $value;	}
		}
	@data;
	}


# #############
# Write records

# Write record, values of the fields are in the argument list.
# Record is always undeleted
sub set_record
	{
	NullError();
	my ($self, $num) = (shift, shift);
	my @data = $self->process_list_on_write($num, @_,
				(undef) x ($self->last_field - $#_));
	$self->write_record($num, " ", @data);
	$num = "0E0" unless $num;
	$num;
	}

# Write record, fields are specified as hash, unspecified are set to
# undef/empty
sub set_record_hash
	{
	NullError();
	my ($self, $num, %data) = @_;
	$self->set_record($num, map { $data{$_} } @{$self->{'field_names'}} );
	}

# Write record, fields specified as hash, unspecified will be
# unchanged
sub update_record_hash
	{
	NullError();
	my ($self, $num, %data) = @_;

	my @data = $self->get_record($num);	# read the original data first
	return unless @data;

	shift @data;		# remove the deleted flag

	my $i;
	for $i (0 .. $self->last_field())
		{
		if (exists $data{$self->{'field_names'}[$i]})
			{ $data[$i] = $data{$self->{'field_names'}[$i]}; }
		}

	$self->set_record($num, @data);
	}

# Actually write the data (calling XBase::Base::write_record) and keep
# the overall structure of the file correct;
sub write_record
	{
	my ($self, $num) = (shift, shift);
	$self->SUPER::write_record($num, @_);

	if ($num > $self->last_record())
		{
		$self->SUPER::write_record($num + 1, "\x1a");	# add EOF
		$self->update_last_record($num) or return;
		}
	$self->update_last_change() or return;
	1;
	}

# Delete and undelete record
sub delete_record
	{
	NullError();
	my ($self, $num) = @_;
	if ($num > $self->last_record())
		{ Error "Can't delete record number $num, there is not so many of them\n"; return;}
	$self->write_record($num, "*");
	1;
	}
sub undelete_record
	{
	NullError();
	my ($self, $num) = @_;
	if ($num > $self->last_record())
		{ Error "Can't undelete record number $num, there is not so many of them\n"; return;}
	$self->write_record($num, " ");
	1;
	}

# Convert Perl values to those in dbf
sub process_list_on_write
	{
	my ($self, $rec_num) = (shift, shift);

	my @types = @{$self->{'field_types'}};
	my @lengths = @{$self->{'field_lengths'}};
	my @decimals = @{$self->{'field_decimals'}};

	my @data = ();
	my $num;
	my $value;
	for $num (0 .. $self->last_field())
		{
		my ($type, $length, $decimal) = ($types[$num],
				$lengths[$num], $decimals[$num]);
		
		$value = shift;
		if ($type eq 'C')
			{
			$value .= "";
			$value = sprintf "%-"."$length.$length"."s", $value;
			}
		elsif ($type eq 'L')
			{
			if (not defined $value)	{ $value = "?"; }
			elsif ($value == 1)	{ $value = "Y"; }
			elsif ($value == 0)	{ $value = "N"; }
			else			{ $value = "?"; }
			$value = sprintf "%-"."$length.$length"."s", $value;
			}
		elsif ($type =~ /^[NFD]$/)
			{
			$value += 0;
			$value = sprintf "%$length.${decimal}f", $value;
			$value =~ s/[.,]//;
			}
		elsif ($type =~ /^[MGBP]$/)
			{
			if (defined $self->{'memo'})
				{
				my $memo_index;
				# we need to figure out, where in memo file
				# to store the data
				if ($rec_num <= $self->last_record())
					{
					$memo_index = ($self->read_record($rec_num))[$num + 1];
					}
				$memo_index = -1 if not defined $memo_index or $memo_index =~ /^ +$/;
				
				# we suggest but memo object may
				# choose another location	
			
				$memo_index = $self->{'memo'}
					->write_record($memo_index, $value);
				$value = $memo_index + 0;
				}
			else
				{ $value = ""; }
			$value = sprintf "%"."$length.$length"."s", $value;
			}
		else
			{
			$value .= "";
			$value = sprintf "%-$length.${decimal}s", $value;
			}
		}
	continue
		{ $data[$num] = $value; }
	@data;
	}

# Update the last change date
sub update_last_change
	{
	my $self = shift;
	return if defined $self->{'updated_today'};
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
	NullError();
	my $class = shift;
	my %options = @_;
	if (ref $class)
		{ %options = ( %$class, %options ); $class = ref $class; }

	my $version = $options{'version'};
	$version = 3 unless defined $version;

	my $header = pack "CCCCVvvvCCA12CCv", $version, 0, 0, 0, 0, 0, 0, 0,
			0, 0, "", 0, 0, 0;

	my $key;
	for $key ( qw( field_names field_types field_lengths field_decimals ) )
		{
		if (not defined $options{$key})
			{
			Error "Tag $key must be specified when creating new table\n";
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
		if ($type eq "C")
			{
			$decimal = int($length / 256);
			$length %= 256;
			}
		$header .= pack "A11A1VCCvCvCA7C", $name, $type, 0,
				$length, $decimal, 0, 0, 0, 0, "", 0;
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
		$dbtname =~ s/(\.dbf)?$/.dbt/i;
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
			{ $self->{'memo'}->drop(); }
		return $self->SUPER::drop();
		}
	XBase::Base::drop($filename);
	}

1;

