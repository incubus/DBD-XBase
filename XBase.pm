
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

Warning for now: It doesn't support any index files at the present
time! That means if you change your dbf, your idx&mdx will not match.
So do not do that.

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

=back

If the method fails (returns undef of null), the error message can be
retrieved via B<errstr> method. If the B<new> method fails, you have
no object and the you can get the error string in the $XBase::errstr
variable.

The methods B<get_header_info> and B<dump_records> can be used to
quickly view the content of the file. They are here mainly for
debugging purposes so please do not rely on them.

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

There are following variables (parameters) in the XBase
namespace that affect the internal behavior:

=over 4

=item $DEBUG

Enables error messages on stderr.

=item $FIXERRORS

When reading the file, try to continue, even if there is some
(minor) missmatch in the data.

=item $CLEARNULLS

If true, cuts off spaces and nulls from the end of character fields on
read.

=back

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
your post in c\.l\.p\.m(isc|odules) or dbi-users. Any comments from
both Perl and XBase gurus are welcome, since I do neither use dBase
nor Fox*, so there are probably pieces missing.

=head1 VERSION

0.024

=head1 AUTHOR

Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), DBD::XBase(3), DBI(3)

=cut

use 5.004;	# hmm, maybe it would work with 5.003 or so, but I do
		# not have it, so this is more like a note, on which
		# version it has been tested


# ##################################
# Here starts the XBase package

package XBase::dbt;	# just quick fix, so that we know the module
package XBase;

use strict;
use IO::File;


# ##############
# General things

use vars qw( $VERSION $DEBUG $errstr $FIXERRORS $CLEARNULLS );
$VERSION = "0.024";

# Sets the debug level
$DEBUG = 1;
sub DEBUG () { $DEBUG };

# FIXERRORS can be set to make XBase to try to work with (read)
# even partially dameged file. Such actions are logged via Warning
$FIXERRORS = 1;
sub FIXERRORS () { $FIXERRORS };

# If set, will cut off the spaces and null from ends of character fields
$CLEARNULLS = 1;

# Holds the text of the error, if there was one
$errstr = '';

# Issues warning to STDERR if there is debug level set, but does Error
# if not FIXERRORS
sub Warning
	{
	if (not FIXERRORS) { Error(@_); return; }
	shift if ref $_[0];
	print STDERR "Warning: ", @_ if DEBUG;
	}
# Prints error on STDERR if there is debug level set and sets $errstr
sub Error
	{
	shift if ref $_[0];
	print STDERR @_ if DEBUG;
	$errstr .= join '', @_;
	}
# Nulls the $errstr, should be used in methods called from the mail
# program
sub NullError	{ $errstr = ''; }


# ########################
# Constructor, open, close

# Constructor of the class; expects class name and filename of the
# .dbf file, returns the object if the file can be read, null otherwise
sub new
	{
	NullError();
	my ($class, $filename) = @_;
	my $new = { 'filename' => $filename };
	bless $new, $class;
	$new->open() and return $new;
	return;
	}
# Called by XBase::new; opens the file and parses the header,
# sets the data structures of the object (field names, types, etc.).
# Returns 1 on success, null otherwise.
sub open
	{
	my $self = shift;
	return 1 if defined $self->{'opened'};
				# won't open if already opened

	my $fh = new IO::File;
	my ($filename, $writable, $mode) = ($self->{'filename'}, 0, "r");
	($writable, $mode) = (1, "r+") if -w $filename;
				# decide if we want r or r/w access

	$fh->open($filename, $mode) or do
		{ Error "Error opening file $self->{'filename'}: $!\n";
		return; };	# open the file

	my $header;
	$fh->read($header, 32) == 32 or do
		{ Error "Error reading header of $filename\n"; return; };

	my ($version, $last_update, $num_rec, $header_len, $record_len,
		$res1, $incompl_trans, $enc_flag, $rec_thread,
		$multiuser, $mdx_flag, $language_dr, $res2)
		= unpack "Ca3Vvva2CCVa8CCa2", $header;
				# read and parse the header

	my ($names, $types, $lengths, $decimals) = ( [], [], [], [] );

				# will read the field descriptions
	while (tell($fh) < $header_len - 1)
		{
		my $field_def;
		$fh->read($field_def, 32) == 32 or do
			{	# read the field description
			my $offset = tell $fh;
			Warning "Error reading field description at offset $offset\n";
			last if FIXERRORS;
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
				# store the information
		}

				# create name-to-num_of_field hash
	my ($hashnames, $i) = ({}, 0);
	for $i (0 .. $#$names)
		{
		$hashnames->{$names->[$i]} = $i
			unless defined $hashnames->{$names->[$i]};
		}
	my $template = "a1";
	my $num;
	for ($num = 0; $num <= $#$lengths; $num++)
		{
		my $totlen = $lengths->[$num] + $decimals->[$num];
		$template .= "a$totlen";
		}

				# now it's the time to store the
				# values to the object
	@{$self}{ qw( fh writable version last_update num_rec
		header_len record_len field_names field_types
		field_lengths field_decimals opened hash_names
		unpack_template last_field ) } =
			( $fh, $writable, $version, $last_update, $num_rec,
			$header_len, $record_len, $names, $types,
			$lengths, $decimals, 1, $hashnames, $template,
			$#$names );

	1;	# return true since everything went fine
	}

# Close the file, finish the work
sub close
	{
	NullError();
	my $self = shift;
	if (not defined $self->{'opened'})
		{ Error "Can't close file that is not opened\n"; return; }
	$self->{'fh'}->close();
	delete @{$self}{'opened', 'fh'};
	1;
	}

# ###############
# Little decoding

# Returns the number of the last record
sub last_record
	{ shift->{'num_rec'} - 1; }
# And the same for fields
sub last_field
	{ shift->{'last_field'}; }
# computes record's offset in the file
sub get_record_offset
	{
	my ($self, $num) = @_;
	return $self->{'header_len'} + $num * $self->{'record_len'};
	}

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
	### my $version = shift->{'version'};
	my $version = shift;
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

	if (not defined $num)
		{ Error "Record number to read must be specified\n"; return; }

	if ($num > $self->last_record())
		{ Error "Can't read record $num, there is not so many of them\n"; return; }

	my @data;
	if (defined $self->{'cached_num'} and $self->{'cached_num'} == $num)
		{ @data = @{$self->{'cached_data'}}; }
	else
		{ @data = $self->read_record($num); return unless @data; }

	# now make a list of numbers of fields to be returned
	if (@fields)
		{
		return $data[0], map {
			if (not defined $self->{'hash_names'}{$_})
				{
				Warning "Field named '$_' does not seem to exist\n";
				return unless FIXERRORS;
				undef;
				}
			else
				{ $data[$self->{'hash_names'}{$_} + 1]; }
			} @fields;
		}
	return @data;
	}

# Once we have the binary data from the pack, we want to convert them
# into reasonable perlish types. The arguments are the number of the
# field and the value. The delete flag has special number -1
sub process_item_on_read
	{
	my ($self, $num, $value) = @_;

	my $type = $self->{'field_types'}[$num];

	if ($num == -1)		# delete flag
		{
		if ($value eq '*')	{ return 1; }
		if ($value eq ' ')	{ return 0; }
		Warning "Unknown deleted flag '$value' found\n";
		return undef;
		}

	# now the other fields
	if ($type eq 'C')
		{
		$value =~ s/\s+$// if $CLEARNULLS;
		return $value;
		}
	if ($type eq 'L')
		{
		if ($value =~ /^[YyTt]$/)	{ return 1; }
		if ($value =~ /^[NnFf]$/)	{ return 0; }
		return undef;	# ($value eq '?')
		}
	if ($type eq 'N' or $type eq 'F')
		{
		substr($value, $self->{'field_lengths'}[$num], 0) = '.';
		return $value + 0;
		}
	if ($type =~ /^[MGBP]$/)
		{
		return undef if $value =~ /^ +$/;
		return $self->read_memo_data($value + 0);
		}

	$value;
	}

# Actually reads the record from file, stores in cache as well
sub read_record
	{
	my ($self, $num) = @_;

	my ($fh, $tell, $record_len, $filename ) =
		@{$self}{ qw( fh tell record_len filename ) };

	if (not defined $self->{'opened'})
		{ Error "The file $filename is not opened, can't read it\n";
		return; }	# will only read from opened file

	my $offset = $self->get_record_offset($num);
				# need to know where to start

	if (not defined $tell or $tell != $offset)
		{		# seek to the start of the record
		$fh->seek($offset, 0) or do {
			Error "Error seeking on $filename to offset $offset: $!\n";
			return;
			};
		}

	delete $self->{'tell'};
	my $buffer;
				# read the record
	$fh->read($buffer, $record_len) == $record_len or do {
			Warning "Error reading the whole record from $filename\nstarting offset $offset, record length $record_len\n";
			return unless FIXERRORS;
			};

	$self->{'tell'} = $tell = $offset + $record_len;
				# now we know where we are

	my $template = $self->{'unpack_template'};

	my @data = unpack $template, $buffer;
				# unpack the data

	my @result = map { $self->process_item_on_read($_, $data[$_ + 1]); }
					( -1 .. $self->last_field() );
				# process them

	$self->{'cached_data'} = [ @result ];
	$self->{'cached_num'} = $num;		# store in cache

	@result;		# and send back
	}

# Read additional data from the memo file
sub read_memo_data
	{
	my ($self, $num) = @_;
	my $dbt = $self->{'dbt'};
	if (not defined $dbt)
		{
		my $filename = $self->{'filename'};
		$filename =~ s/\.dbf//i;
		$filename .= '.dbt';
		$self->{'dbt'} = $dbt = new XBase::dbt($filename);
		return undef unless defined $dbt;
		}
	my $ret = $dbt->read_block($num);	
	return $ret;
	}

# #############
# Write records

# Write record, values of the fields are in the argument list,
# unspecified fields will be set to undef/empty. Record is always
# undeleted
sub write_record
	{
	NullError();
	my ($self, $num, @data) = @_;

	push @data, (undef) x ($self->last_field - $#data);

				# seek to position
	$self->will_write_record($num) or return;
	$self->{'fh'}->print(' ');
				# write undelete flag

				# process and write items
	$self->{'fh'}->print(
		### map { print "Writing: $_\n"; $_; }
		map { $self->process_item_on_write($_, $data[$_]); }
				( 0 .. $#data ) ) if @data;

	$self->{'cached_num'} = $num;
	$self->{'cached_data'} = [ @data ];

				# if we made the file longer, extend it
	if ($num > $self->last_record())
		{
		$self->{'fh'}->print("\x1a");	# add EOF
		$self->update_last_record($num) or return;
		}

	$self->update_last_change() or return;
	1;
	}

# Write record, fields are specified as hash, unspecified are set to
# undef/empty
sub write_record_hash
	{
	NullError();
	my ($self, $num, %data) = @_;
	$self->write_record($num, map { $data{$_} } @{$self->{'field_names'}} );
	}

# Write record, fields specified as hash, unspecified will be
# unchanged
sub update_record_hash
	{
	NullError();
	my ($self, $num, %data) = @_;
	if ($num > $self->last_record())
		{ Error "Can't updatge record $num, there is not so many of them\n"; return; }

				# read the original data first
	my @data = $self->get_record($num);
	return unless @data;

	shift @data;		# remove the deleted flag

	my $i;
	for $i (0 .. $self->last_field())
		{
		if (exists $data{$self->{'field_names'}[$i]})
			{ $data[$i] = $data{$self->{'field_names'}[$i]}; }
		}

	$self->write_record($num, @data);
	}

# Delete and undelete record
sub delete_record
	{
	NullError();
	my ($self, $num) = @_;
	if ($num > $self->last_record())
		{ Error "Can't delete record $num, there is not so many of them\n"; return; }
	my $offset = $self->get_record_offset($num);
	$self->will_write_record($num) or return;
	$self->{'fh'}->print("*");
	$self->{'cached_data'}[0] = 1 if $num == $self->{'cached_num'};
	$self->update_last_change() or return;
	1;
	}
sub undelete_record
	{
	NullError();
	my ($self, $num) = @_;
	if ($num > $self->last_record())
		{ Error "Can't undelete record $num, there is not so many of them\n"; return; }
	$self->will_write_record($num) or return;
	$self->{'fh'}->print(" ");
	$self->{'cached_data'}[0] = 0 if $num == $self->{'cached_num'};
	$self->update_last_change() or return;
	1;
	}

# Prepare everything to write at record position
sub will_write_record
	{
	my ($self, $num) = @_;
	my $offset = $self->get_record_offset($num);
	unless ($self->will_write_to($offset))
		{ Error "Error writing record $num\n"; return; }
	1;
	}

# Prepares everything for write at given position
sub will_write_to
	{
	my ($self, $offset) = @_;
	my $filename = $self->{'filename'};

				# the file should really be opened and
				# writable
	unless (defined $self->{'opened'})
		{ Error "The file $filename is not opened\n"; return; }
	if (not $self->{'writable'})
		{ Error "The file $filename is not writable\n"; return; }

	my ($fh, $header_len, $record_len) =
		@{$self}{ qw( fh header_len record_len ) };

				# we will cancel the tell position
	delete $self->{'tell'};

				# seek to the offset
	$fh->seek($offset, 0) or do {
		Error "Error seeking on $filename to offset $offset: $!\n";
		return;
		};
	1;
	}

# Convert Perl values to those in dbf
sub process_item_on_write
	{
	my ($self, $num, $value) = @_;

	my ($type, $length, $decimal) = ($self->{'field_types'}[$num],
		$self->{'field_lengths'}[$num],
		$self->{'field_decimals'}[$num]);
	my $totlen = $length + $decimal;

	# now the other fields
	if ($type eq 'C')
		{
		$value .= "";
		return sprintf "%-$totlen.${totlen}s", $value;
		}
	if ($type eq 'L')
		{
		if (not defined $value)	{ $value = "?"; }
		elsif ($value == 1)	{ $value = "Y"; }
		elsif ($value == 0)	{ $value = "N"; }
		else			{ $value = "?"; }
		return sprintf "%-$totlen.${totlen}s", $value;
		}
	if ($type =~ /^[NFD]$/)
		{
		$value += 0;
		$value = sprintf "%$totlen.${decimal}f", $value;
		$value =~ s/[.,]//;
		return $value;
		}

	###
	### Fixup for MGBP ### to be added, read from dbt
	###

	$value .= "";
	return sprintf "%-$length.${decimal}s", $value;
	}

# Update the last change date
sub update_last_change
	{
	my $self = shift;
	return if defined $self->{'updated_today'};
	$self->will_write_to(1) or return;
	my ($y, $m, $d) = (localtime)[5, 4, 3]; $m++;
	$self->{'fh'}->print(pack "C3", ($y, $m, $d));
	$self->{'updated_today'} = 1;
	}
# Update the number of records
sub update_last_record
	{
	my ($self, $last) = @_;
	$last++;
	$self->will_write_to(4);
	$self->{'fh'}->print(pack "V", $last);
	$self->{'num_rec'} = $last;
	}
1;

# #######################################################
# Here starts the XBase::dbf package, for memo files

package XBase::dbt;

sub Error (@)	{ XBase::Error(@_); }
sub Warning (@)	{ XBase::Warning(@_); }
sub FIXERRORS ()	{ XBase::FIXERRORS(); }

# ###########################
# Consturctor, open and close

# Creates the object, reads the header of the file
sub new
	{
	my ($class, $filename) = @_;
	my $new = { 'filename' => $filename };
	bless $new, $class;
	$new->open() and return $new;
	return;
	}

# Reads the header of the file, fills the structures
sub open
	{
	my $self = shift;
	return 1 if defined $self->{'opened'};
				# won't open if already opened

	my $fh = new IO::File;
	my ($filename, $writable, $mode) = ($self->{'filename'}, 0, "r");
	($writable, $mode) = (1, "r+") if -w $filename;
				# decide if we want r or r/w access

	$fh->open($filename, $mode) or do
		{ Error "Error opening file $self->{'filename'}: $!\n";
		return; };	# open the file

	my $header;
	$fh->read($header, 17) == 17 or do
		{ Error "Error reading header of $filename\n"; return; };

	my ($next_for_append, $block_size, $dbf_filename, $reserved)
		= unpack "VVA8C", $header;

	my $version = 4;
	if ($reserved == 3) { $version = 3; }

	$block_size = 512 if $version == 3;
	($dbf_filename = $self->{'filename'}) =~ s/\.dbf//i;

	@{$self}{ qw( next_for_append block_size dbf_filename version
		opened fh writable ) }
		= ( $next_for_append, $block_size, $dbf_filename,
		$version, 1, $fh, $writable );
	1;
	}

# Close the file
sub close
	{
	my $self = shift;
	if (not defined $self->{'opened'})
		{ Error "Can't close file that is not opened\n"; return; }
	$self->{'fh'}->close();
	delete @{$self}{'opened', 'fh'};
	1;
	}

# ##############
# Reading blocks

sub read_block
	{
	my ($self, $num) = @_;
	return unless $num > 0;

	my $block_size = $self->{'block_size'};
	my $offset = 512 + ($num - 1) * $block_size;

	my $filesize = -s $self->{'filename'};
	my $fh = $self->{'fh'};

	$fh->seek($offset, 0) or do
		{ Error "Error seeking to offset $offset: $!\n"; return; };

	# dBase III+ memo file type
	if ($self->{'version'} == 3)
		{
		my $result = '';
		while ($fh->tell() < $filesize)
			{
			my $buffer;
			$fh->read($buffer, $block_size) == $block_size or do
				{ Warning "Error reading memo block\n";
				return unless FIXERRORS; };
			if ($buffer =~ /^(.*?)\x1a\x1a/)
				{ return $result . $+; }
			$result .= $buffer;
			}
		return $result;
		}

	# dBase IV style
	elsif ($self->{'version'} == 4)
		{
		my $buffer;
		$fh->read($buffer, $block_size) == $block_size or do
			{ Warning "Error reading memo block\n";
			return unless FIXERRORS; };
		my ($unused_id, $length) = unpack "VV", $buffer;
		if ($length < $block_size - 8)
			{ return substr $buffer, 8, $length; }
		my $rest_length = $length - ($block_size - 8);
		my $rest_data;
		$fh->read($rest_data, $rest_length) == $rest_length or do
			{ Warning "Error reading memo block\n";
			return unless FIXERRORS; };
		return $buffer . $rest_data;
		}

	return;
	}

1;



