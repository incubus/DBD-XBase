
=head1 NAME

XBase::Base - Base input output module for XBase suite

=cut

package XBase::Base;

use strict;
use IO::File;

use vars qw( $VERSION $DEBUG $errstr );

# ##############
# General things

$VERSION = "0.0591";

# Sets the debug level
$DEBUG = 0;
sub DEBUG () { $DEBUG };

# Holds the text of the global error, if there was one
$errstr = '';
sub errstr ()	{ ( ref $_[0] ? $_[0]->{'errstr'} : $errstr ); }

# Prints error on STDERR if there is debug level set and sets errstr
sub Error (@)
	{
	my $self = shift;
	( ref $self ? $self->{'errstr'} : $errstr ) = join '', @_;
	}

# Nulls the errstr
sub NullError
	{ shift->Error(''); }

# ##########
# Contructor. If it is passed a name of the file, it opens it and
# calls method read_header to load the internal data structures
sub new
	{
	__PACKAGE__->NullError();
	my $class = shift;
	my $new = bless {}, $class;
	if (@_ and not $new->open(@_)) { return; }
	return $new;
	}
# Open the specified file. Uses the read_header to load the header data
sub open
	{
	__PACKAGE__->NullError();
	my ($self, $filename) = @_;
	if (defined $self->{'fh'}) { $self->close(); }

	my $fh = new IO::File;
	my $rw;
	if ($fh->open($filename, 'r+'))		{ $rw = 1; }
	elsif ($fh->open($filename, 'r'))	{ $rw = 0; }
	else { __PACKAGE__->Error("Error opening file $filename: $!\n"); return; }
	binmode($fh);
	@{$self}{ qw( fh filename rw ) } = ($fh, $filename, $rw);

		# read_header should be defined in the derived class
	$self->read_header();
	}
# Closes the file
sub close
	{
	my $self = shift;
	$self->NullError();
	if (not defined $self->{'fh'})
		{ $self->Error("Can't close file that is not opened\n"); return; }
	$self->{'fh'}->close();
	delete $self->{'fh'};
	1;
	}
# Drop (unlink) the file
sub drop
	{
	my $self = shift;
	$self->NullError();
	if (defined $self->{'filename'})
		{
		my $filename = $self->{'filename'};
		$self->close() if defined $self->{'fh'};
		if (not unlink $filename)
			{ $self->Error("Error unlinking file $filename: $!\n"); return; };
		}
	1;	
	}
# Create new file
sub create_file
	{
	my $self = shift;
	my ($filename, $perms) = @_;
	if (not defined $filename)
		{ __PACKAGE__->Error("Name has to be specified when creating new file\n"); return; }
	if (-f $filename)
		{ __PACKAGE__->Error("File '$filename' already exists\n"); return; }

	$perms = 0644 unless defined $perms;
	my $fh = new IO::File;
	unless ($fh->open($filename, "w+", $perms))
		{ return; }
	binmode($fh);
	@{$self}{ qw( fh filename rw ) } = ($fh, $filename, 1);
	return $self;
	}

# Computes the correct offset, asumes that header_len and record_len
# are defined in the object, probably set up by the read_header.
# Assumes that the file has got header and then records, numbered from
# zero
sub get_record_offset
	{
	my ($self, $num) = @_;
	my ($header_len, $record_len) = ($self->{'header_len'},
						$self->{'record_len'});
	unless (defined $header_len and defined $record_len)
		{ $self->Error("Header and record lengths not known in get_record_offset\n"); return; }
	unless (defined $num)
		{ $self->Error("Number of the record must be specified in get_record_offset\n"); return; }
	return $header_len + $num * $record_len;
	}
# Will get ready to write record of specified number
sub seek_to_record
	{
	my ($self, $num) = @_;
	my $offset = $self->get_record_offset($num);
	return unless defined $offset;
	$self->seek_to($offset);
	}
# Will get ready to write at given position
sub seek_to
	{
	my ($self, $offset) = @_;

	unless (defined $self->{'fh'})
		{ $self->Error("Cannot seek on unopened file\n"); return; }

	unless ($self->{'fh'}->seek($offset, 0))	# seek to the offset
		{ $self->Error("Error seeking to offset $offset on $self->{'filename'}: $!\n"); return; };
	1;
	}

# Read the record of given number. The second parameter is the length of
# the record to read. It can be undefined, meaning read the whole record,
# and it can be -1, meaning read at most the whole record
sub read_record
	{
	my ($self, $num, $in_length) = @_;

	unless (defined $num)
		{ $self->Error("Record number to read must be specified for read record\n"); return; }
	if ($num > $self->last_record())
		{ $self->Error("Can't read record $num, there is not so many of them\n"); return; }

	$self->seek_to_record($num) or return;

	$in_length = $self->{'record_len'} unless defined $in_length;
	
	my $buffer;
	my $actually_read = $self->{'fh'}->read($buffer,
		($in_length == -1 ?  $self->{'record_len'} : $in_length));
	
	if ($in_length != -1 and $actually_read != $in_length)
		{ $self->Error("Error reading the whole record num $num\n"); return; };

	$buffer;
	}
sub read_from
	{
	my ($self, $offset, $in_length) = @_;
	unless (defined $offset)
		{ $self->Error("Offset to read from must be specified\n"); return; }
	$self->seek_to($offset) or return;
	my $length = $in_length;
	$length = -$length if $length < 0;
	my $buffer;
	my $read = $self->{'fh'}->read($buffer, $length);
	return if not defined $read or ($in_length > 0 and $read != $in_length);
	$buffer;
	}


# Write the given record
sub write_record
	{
	my ($self, $num) = (shift, shift);
	my $offset = $self->get_record_offset($num);
	my $ret = $self->write_to($offset, @_);
	unless (defined $ret) { return; }
	( $num == 0 ) ? '0E0' : $num;
	}
# Write data directly to offset
sub write_to
	{
	my ($self, $offset) = (shift, shift);
	if (not $self->{'rw'})
		{ $self->Error("The file $self->{'filename'} is not writable\n"); return; }
	$self->seek_to($offset) or return;
	
	local ($,, $\) = ('', '');
	$self->{'fh'}->print(@_) or
		do { $self->Error("Error writing at offset $offset: $!\n"); return; } ;
	( $offset == 0 ) ? '0E0' : $offset;
	}

1;

__END__

=head1 SYNOPSIS

Used indirectly, via XBase or XBase::Memo.

=head1 DESCRIPTION

This module provides catch-all I/O methods for other XBase classes,
should be used by people creating additional XBase classes/methods.
The methods return nothing (undef) or error and the error message can
be retrieved using the B<errstr> method.

Methods are:

=over 4

=item new

Constructor. Creates the object and if the file name is specified,
opens the file.

=item open

Opens the file and using method read_header reads the header and sets
the object's data structure. The read_header should be defined in the
derived class, there is no default.

=item close

Closes the file, doesn't destroy the object.

=item drop

Unlinks the file.

=back

The methods assume that the file has got header of length header_len
bytes (possibly 0) and then records of length record_len. These two
values should be set by the read_header method.

=over 4

=item seek_to_record, seek_to

Seeks to record of given number or to absolute position.

=item read_record

Reads specified record from get_record_offset position. You can give
second parameter saying length (in bytes) you want to read. The
default is record_len. If the required length is -1, it will read
record_len but will not complain if the file is shorter. Whis is nice
at the end of the file.

When the unpack_template value is specified in the object, read_record
unpacks the string read and returns list of resulting values.

=item write_record, write_to

Writes data to specified record position or to the absolute position
in the file. The data is not padded to record_len, just written out.

=back

=head1 VERSION

0.059

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), XBase(3)

