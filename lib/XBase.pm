
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
Note for now: no DBD:: support currently exists.

Remember: Since the version number is pretty low now, you might want
to check the CHANGES file any time you upgrade to see wheather some of
the features you use haven't disappeared.

WARNING for now: It doesn't support any index files at the present
time! That means if you change your dbf, your idx&mdx (if you have
any) will not match. So do not do that.

The following methods are supported:

=over 4

=item new

Creates the XBase object, takes the file's name as argument, parses
the file's header, fills the data structures.

=item close

Closes the object/file.

=item get_record

Returns data from the specified record (line of the table). The first
argument is the number of the record. If there are any other
arguments, they are considered to be the names of the fields and only
the specified fields are returned. If no field names are present,
returns all fields in the record. The first value of the returned list
is the 1/0 value saying if the record is deleted or not.

=item last_record

Number of the last records in the file. The lines deleted but present
in the file are included in this count.

=item last_field

Number of the last field in the file.

=item field_names, field_types

List of field names or types for the dbf file.

=back

If the method fails (returns undef of null list), the error message
can be retrieved via B<errstr> method. If the B<new> method fails, you
have no object and so B<new> (and only B<new>) puts the error message
into the $XBase::errstr variable.

The methods B<get_header_info> and B<dump_records> can be used to
quickly view the content of the file, at least for now. Please speak
up if you like them and want them to be supported. They are here
mainly for my debugging purposes.

For writing, you have methods:

=over 4

=item write_record

As arguments, takes the number of the record and the list of values
of the fields. It writes the record to the file. Unspecified fields
(if you pass less than you should) are set to undef/empty. The record
is undeleted.

=item write_record_hash

Takes number of the record and hash, sets the fields, unspecified are
undeffed/emptied.

=item update_record_hash

Like B<write_record_hash> but preserves fields that do not have value
specified in the hash.

=item delete_record, undelete record

Deletes/undeletes the record.

=back

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

Would you like different interface? Please, write me, we shall figure
something out.

=head1 HISTORY

I have been using the Xbase(3) module by Pratap Pereira for quite
a time to read the dbf files, but it had no writing capabilities, it
was not C<-w>/C<use strict> clean and the author did not support the
module behind the version 1.07. So I started to make my own patches
and thought it would be nice if other people could make use of them.
I thought about taking over the development of the original Xbase
package, but the interface seemed rather complicated to me and I also
disliked the licence Pratap had about the module.

So with the help of article XBase File Format Description by Erik
Bachmann, URL ( http:// ... ), I have written a new module. It doesn't
use any code from Xbase-1.07 and you are free to use and distribute it
under the same terms as Perl itself.

Please send all bug reports CC'ed to my e-mail, since I might miss
your post in c.l.p.misc or dbi-users (or other groups). Any comments
from both Perl and XBase gurus are welcome, since I do neither use
dBase nor Fox*, so there are probably pieces missing.

=head1 VERSION

0.0292

=head1 AUTHOR

Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), XBase::Base(3), DBD::XBase(3), DBI(3)

=cut

# ########
use 5.004;	# Hmm, maybe it would work with 5.003 or so, but I do
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

$VERSION = "0.0292";

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
	my $printdate = $self->decode_last_change($self->{'last_update'});
	my $numfields = scalar @{$self->{'field_types'}};
	my $result = sprintf <<"EOF";
Filename:	$self->{'filename'}
Version:	$hexversion
Num of records:	$self->{'num_rec'}
Header length:	$self->{'header_len'}
Record length:	$self->{'record_len'}
Last change:	$printdate
Num fields:	$numfields
Field info:
	Name		Type	Len	Decimal
EOF
	return $result, map { $self->get_field_info($_) }
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
	$version = $version->{'version'} if ref $version->{'version'};
	my ($vbits, $dbtflag, $memo, $sqltable) = (0, 0, 0, 0);
	if ($version == 3)	{ $vbits = 3; }
	elsif ($version == 0x83)	{ $vbits = 3; $memo = 0; $dbtflag = 1;}
	else {
		$vbits = $version & 0x07;
		$dbtflag = ($version >> 8) & 1;
		$memo = ($version >> 3) & 1;
		$sqltable = ($version >> 4) & 0x07;
		}
	print "Version: $vbits; dbt: $dbtflag; memo: $memo; SQL table: $sqltable\n";
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
	my %hash;
	@hash{ '_DELETED', $self->field_names() } = @list;
	%hash;
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
			# memo fields are indexed from 1, we need $value - 1
			$data[$num] = $self->{'memo'}->read_record($value - 1)
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
					$memo_index =
					($self->read_record($rec_num))[$num + 1] - 1;
					}
				$memo_index = -1 if $memo_index =~ /^ +$/;
				
				# we suggest but memo object may
				# choose another location	
			
				$memo_index = $self->{'memo'}
					->write_record($memo_index, $value);
				$value = $memo_index + 1;
				}
			else
				{ $value = ""; }
			$value = sprintf "%-$length.${totlen}s", $value;
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

__END__


# Creating new dbf file
sub create
	{
	my $class = shift;
	if (ref $class)
		{ return $class->create_duplicate(@_); }
		
	}
sub create_duplicate
	{
	my $other = shift;
	my %options = @_;
	if (not defined $options{'name'})
		{
		Error "Name tag has to be specified when creating new table\n";
		return;
		}
	$options{'version'} = $other->{'version'}
		unless defined $options{'version'};
	return __PACKAGE__ create(%options,
		'fields_names' => [ $other->field_names() ],
		'field_types' => [ $other->field_types() ],
		'field_lengths' => [ $other->{'field_lengths'} ],
		'field_decimals' => [ $other->{'field_decimals'} ],
	}

1;

