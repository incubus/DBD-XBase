
=head1 NAME

XBase - Perl module for reading and writing the dbf files

=head1 SYNOPSIS

	use XBase;
	my $table = new XBase("dbase.dbf");
	for (0 .. $table->last_record())
		{
		my ($deleted, $id, $msg)
			= $table->get_record($_, "ID", "MSG");
		print "$id:\t$msg\n" unless $deleted;
		}

=head1 DESCRIPTION

This module can read and write XBase database file, known as dbf in
dBase and FoxPro world. It also reads memo (and the like) fields from
the dbt files, if needed. This module should really be used via
DBD::XBase DBI driver, but this is the alternative interface.
Note for now: no real DBD:: support currently exists.

Remember: Since the version number is pretty low now, you might want
to check the CHANGES file any time you upgrade to see wheather some of
the features you use haven't disappeared.

WARNING for now: It doesn't support any index files at the present
time! That means if you change your dbf, your idx&mdx (if you have
any) will not match. So do not do that.

The following methods are supported:

=head2 General methods

=over 4

=item new

Creates the XBase object, takes the file's name as argument, parses
the file's header, fills the data structures.

=item close

Closes the object/file.

=item create

Creates new database file. Expects class name and hash of options,
containing at least B<name> and references to lists B<field_names>,
B<field_types>, B<field_lengths> and B<field_decimals>.

You can also pass reference to XBase object instead of class name (and
then can omit the other field_* attributes) and the new table will
have the same structure (fields) as the original object.

BUG: currently will not create .dbt file for you.

=item last_record

Number of the last record in the file. The lines deleted but present
in the file are included in this number.

=item last_field

Number of the last field in the file, number of fields minus 1.

=item field_names, field_types, field_lengths, field_decimals

List of field names and so for the dbf file.

=back

When dealing with the records, you always have to specify the number
of the record in the file. The range is 0 .. $table->last_record().

=head2 Reading the data

=over 4

=item get_record

Returns a list of data from the specified record (line of the table).
The first argument is the number of the record. If there are any other
arguments, they are considered to be the names of the fields and only
the specified fields are returned. If no field names are present,
returns all fields in the record. The first value of the returned list
is the 1/0 value saying if the record is deleted or not.

=item get_record_as_hash

Returns hash (in list context) or reference to hash (scalar), where
keys are the field names of the record and values the values. The
deleted flag has name _DELETED.

=back

=head2 Writing the data

=over 4

=item write_record

As arguments, takes the number of the record and the list of values
of the fields. It writes the record to the file. Unspecified fields
(if you pass less than you should) are set to undef/empty. The record
is undeleted.

=item write_record_hash

Takes number of the record and hash, sets the fields, unspecified are
undeffed/emptied. The record is undeleted.

=item update_record_hash

Like B<write_record_hash> but preserves fields that do not have value
specified in the hash. The record is undeleted.

=item delete_record, undelete record

Deletes/undeletes the record.

=back

=head2 Errors and debugging

If the method fails (returns undef of null list), the error message
can be retrieved via B<errstr> method. If the B<new> method fails, you
have no object and so B<new> (and only B<new>) puts the error message
into the $XBase::errstr variable.

The methods B<get_header_info> and B<dump_records> can be used to
quickly view the content of the file, at least for now. Please speak
up if you like them and want them to be supported. They are here
mainly for my debugging purposes.

Module XBase::Base(3) defines some basic functionality and also following
variables, that affect the internal behaviour:

=over 4

=item $DEBUG

Enables error messages on stderr.

=item $FIXPROBLEMS

When reading the file, try to continue, even if there is some
(minor) missmatch in the data.

=back

In the module XBase there is variable $CLEARNULLS which if true, will
make the reading methods cuts off spaces and nulls from the end of
character fields on read.

=head1 LITTLE EXAMPLE

This is a code to update field MSG in record where ID is 123.

	use XBase;
	my $table = new XBase("test.dbf");
	die $XBase::errstr unless defined $table;
	for (0 .. $table->last_record())
		{
		my ($deleted, $id)
			= $table->get_record($_, "ID");
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

Quiz question: can there be more than one memo field in the dbf file?
In what file (.dbt?) should I search for their values? Any ideas?

No index files are currently supported. Two reasons: you do not need
them when reading the file because you specify the record number
anyway and writing them is extremely difficult. I will try to add the
support but do not promise anything ;-) There are too many too complex
questions: how about compound indexes? Which index formats should
I support? What files contain the index data? I do not have dBase nor
Fox* so do not have data to experiment. Send me anything that might
help.

Any ideas, suggestions, URLs, help or code? Please write me, I am
writing this module for you.

=head1 INTERFACE

Would you like different interface in the module? Write me, we shall
figure something out.

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
Bachmann, URL http://www.geocities.com/SiliconValley/Pines/2563/xbase.htm,
I have written a new module. It doesn't use any code from Xbase-1.07
and you are free to use and distribute it under the same terms as Perl
itself.

Please send all bug reports CC'ed to my e-mail, since I might miss
your post in c.l.p.misc or dbi-users (or other groups). Any comments
from both Perl and XBase gurus are welcome, since I do neither use
dBase nor Fox*, so there are probably pieces missing.

=head1 VERSION

0.03

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1); DBD::XBase(3) and DBI(3) for DBI interface;
XBase::Base(3) and DBD::Memo(3) for internal details

=cut

# ########
use 5.004;	# Hmm, maybe it would work with 5.00293 or so, but I do
		# not have it, so this is more like a note, on which
		# version the module has been tested


# #############################
# Here starts the XBase package

package XBase;

use strict;
use XBase::Base;	# will give us general methods


# ##############
# General things

use vars qw( $VERSION $errstr $CLEARNULLS @ISA );

@ISA = qw( XBase::Base );

$VERSION = "0.03";

$errstr = '';	# only after new, otherwise use method $table->errstr;

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
	$errstr = $XBase::Base::errstr unless $result;
	$result;
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

		last if substr $field_def, 0, 1 eq "\x0d";
				# we have found the terminator

		my ($name, $type, $address, $length, $decimal,
			$multiuser1, $work_area, $multiuser2,
			$set_fields_flag, $res, $index_flag)
				= unpack "A11aVCCa2Ca2Ca7C", $field_def;
		
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
		map { "a" . ($lengths->[$_]+$decimals->[$_]); } (0 .. $#$names);
	
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
	my $filename = $self->{'filename'};
	$filename =~ s/\.dbf//i;
	$filename .= '.dbt';
	require 'XBase/Memo.pm';
	return XBase::Memo->new($filename);
	}

sub close
	{
	my $self = shift;
	if (defined $self->{'memo'})
		{ $self->{'memo'}->close(); }
	$self->SUPER::close();
	}

# ###############
# Little decoding

# Returns the number of the last record
sub last_record		{ shift->{'num_rec'} - 1; }
# And the same for fields
sub last_field		{ shift->{'last_field'}; }
# List of field names
sub field_names		{ @{shift->{'field_names'}}; }
# And list of field types
sub field_types		{ @{shift->{'field_types'}}; }


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
	Name		Type	Len	Decimal
EOF
	return join "", $result, map { $self->get_field_info($_) }
					(0 .. $self->last_field());
	}

# Returns info about field in dbf file
sub get_field_info
	{
	my ($self, $num) = @_;
	sprintf "\t%-16.16s%-8.8s%-8.8s%-8.8s\n", map { $self->{$_}[$num] }
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
		$dbtflag = ($version >> 8) & 1;
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
			substr($value, $self->{'field_lengths'}[$num - 1], 0) = '.';
			$data[$num] = $value + 0;
			}
		elsif ($type =~ /^[MGBP]$/)
			{
			$data[$num] = $self->{'memo'}->read_record($value)
				if defined $self->{'memo'} and
					not $value =~ /^ +$/;
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
	$self->write_record($num, "*");
	1;
	}
sub undelete_record
	{
	NullError();
	my ($self, $num) = @_;
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
		my $totlen = $length + $decimal;
		
		$value = shift;
		if ($type eq 'C')
			{
			$value .= "";
			$value = sprintf "%-$totlen.${totlen}s", $value;
			}
		elsif ($type eq 'L')
			{
			if (not defined $value)	{ $value = "?"; }
			elsif ($value == 1)	{ $value = "Y"; }
			elsif ($value == 0)	{ $value = "N"; }
			else			{ $value = "?"; }
			$value = sprintf "%-$totlen.${totlen}s", $value;
			}
		elsif ($type =~ /^[NFD]$/)
			{
			$value += 0;
			$value = sprintf "%$totlen.${decimal}f", $value;
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
			$value = sprintf "%$length.${totlen}s", $value;
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
	my %options = ();
	if (ref $class)
		{ %options = ( %$class, @_ ); $class = ref $class; }
		
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
		my $name = $options{'field_names'}[$i];
		$name = "FIELD$i" unless defined $name;
		my $type = $options{'field_types'}[$i];
		$type = "C" unless defined $type;
		my $length = $options{'field_lengths'}[$i];
		if (not defined $length)
			{
			if ($type eq "C")	{ $length = 64; }
			elsif ($type eq "D")	{ $length = 8; }
			elsif ($type =~ /^[NF]$/)	{ $length = 8; }
			elsif ($type =~ /^[MBGP]$/)	{ $length = 10; }
			elsif ($type eq "L")	{ $length = 1; }
			}
		my $decimal = $options{'field_decimals'}[$i];
		if (not defined $decimal)
			{
			$decimal = 0;
			}
		$header .= pack "A11A1VCCvCvCA7C", $name, $type, 0,
				$length, $decimal, 0, 0, 0, 0, "", 0;
		if ($type eq "C")
			{ $record_len += $length + 256 * $decimal; }
		else
			{ $record_len += $length + $decimal; }
		}
	$header .= "\x0d";

	substr($header, 8, 4) = pack "vv", (length $header), $record_len;

	my $tmp = $class->new();
	$tmp->create_file($options{'name'}, 0700) or return;
	$tmp->write_to(0, $header) or return;
	$tmp->update_last_change();
	$tmp->close();

	return $class->new($options{'name'});
	}

1;

