
=head1 NAME

XBase::Base - Base input output module for XBase suite

=head1 SYNOPSIS

Used indirectly, via XBase or XBase::Memo.

=head1 DESCRIPTION

This module provides catch-all I/O methods for other XBase classes,
should be used by people creating additional XBase classes/methods.
The methods return nothing (undef) or error and the error message can
be retrieved using the B<errstr> method. If the $XBase::Base::DEBUG
variable is true, they also print the message on stderr, so the
caller doesn't need to do this, just die or ignore the problem.

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

=item get_record_offset

The argument is the number of the record, if returns the number

	$header_len + $number * $record_len

using values from the object. Please note, that I use the term record
here, even if in memo files the name block and in indexes page is more
common. It's because I tried to unify the methods. Maybe it's
a nonsense and we will drop this idea in the next version ;-)

=item seek_to_record

Seeks to record of given number.

=item seek_to

Seeks to given position. It undefs the tell value in the object, since
it assumes the users that will do print afterwards would not update it.

=item read_record

Reads specified record from get_record_offset position. You can give
second parameter saying length (in bytes) you want to read. The
default is record_len. If the required length is -1, it will read
record_len but will not complain if the file is shorter. Whis is nice
on the end of memo file.

The method caches last record read. Also, when key unpack_template
is specified in the object, it unpacks the string read and returns
list of resulting values.

=item write_record, write_to

Writes data to specified record position or to the absolute position
in the file.

=back

=head1 VERSION

0.045

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), XBase(3)

=cut

package XBase::Base;

use strict;
use IO::File;

use vars qw( $VERSION $DEBUG $errstr $FIXERRORS @EXPORT @EXPORT_OK
	@ISA $FIXPROBLEMS );

use Exporter;
@ISA = qw(Exporter);

@EXPORT = qw( DEBUG FIXPROBLEMS Error Warning NullError );

# ##############
# General things

$VERSION = "0.045";

# Sets the debug level
$DEBUG = 0;
sub DEBUG () { $DEBUG };

# FIXPROBLEMS can be set to make XBase to try to work with (read)
# even partially dameged file. Such actions are logged via Warning
$FIXPROBLEMS = 1;
sub FIXPROBLEMS () { $FIXPROBLEMS }

# Holds the text of the error, if there was one
$errstr = '';
sub errstr ()	{ (ref $_[0] ? $_[0]->{'errstr'} : $errstr); }

# Issues warning to STDERR if there is debug level set, but does Error
# if not FIXPROBLEMS
sub Warning (@)
	{
	if (not FIXPROBLEMS) { Error(@_); return; }
	shift if ref $_[0];
	print STDERR "Warning: ", @_ if DEBUG;
	}
# Prints error on STDERR if there is debug level set and sets $errstr
sub Error (@)
	{
	my $self;
	$self = shift if ref $_[0];
	print STDERR @_ if DEBUG;
	(defined $self ? $self->{'errstr'} : $errstr) .= join '', @_;
	}
# Nulls the $errstr, should be used in methods called from the mail
# program
sub NullError
	{ if (ref $_[0]) { $_[0]->{'errstr'} = ''; } else { $errstr = ''; } }


# Contructor. If it is passed a name of the file, it opens it and
# calls method read_header to load the internal data structures
sub new
	{
	NullError();
	my $class = shift;
	my $new = {};
	bless $new, $class;
	if (@_)	{ $new->open(@_) and return $new; return; }
	return $new;
	}
# Open the file. This is the second chance when filename can be
# specified. It uses the read_header to load the header data
sub open
	{
	NullError();
	my $self = shift;
	if (@_ and not defined $self->{'filename'})
		{ $self->{'filename'} = shift; }
	
	return 1 if defined $self->{'opened'};
				# won't open if already opened

	my $fh = new IO::File;
	my ($filename, $writable, $mode) = ($self->{'filename'}, 0, 'r');

	($writable, $mode) = (1, 'r+') if -w $filename;
				# decide if we want r or r/w access

	$fh->open($filename, $mode) or do
		{ Error "Error opening file $filename: $!\n"; return; };
				# open the file
	binmode($fh);		# f..k Windoze

	my $perms = (stat($filename))[2] & 0777;

	@{$self}{ qw( opened fh writable perms ) }
				= ( 1, $fh, $writable, $perms );

	unless ($self->can('read_header'))
		{ Error "Method read_header not defined for $self\n"; return; }
	
	unless ($self->read_header(@_))	# read_header should be
		{ return; }		# defined in the derived class

	1;
	}
# Closes the file
sub close
	{
	my $self = shift;
	$self->NullError();
	if (not defined $self->{'opened'})
		{ $self->Error("Can't close file that is not opened\n"); return; }
	$self->{'fh'}->close();
	delete @{$self}{'opened', 'fh'};
	1;
	}
# Drop (unlink) the file
sub drop
	{
	my $self = shift;
	my $filename = $self;
	$self->NullError();
	if (ref $self)
		{
		$filename = $self->{'filename'};
		$self->close() if defined $self->{'opened'};
		}
	unlink $filename or
		do { $self->Error("Error unlinking file $filename: $!\n"); return; };
	1;	
	}
# Create new file
sub create_file
	{
	my $self = shift;
	my ($name, $perms) = @_;
	if (not defined $name)
		{
		Error "Name has to be specified when creating new table\n";
		return;
		}
	if (-f $name)
		{
		Error "File '$name' already exists\n";
		return;
		}
	my $fh = new IO::File;
	$fh->open($name, "w+", $perms) and do
		{
		@{$self}{ qw( fh filename perms writable opened ) }
			= ( $fh, $name, $perms, 1, 1 );
		binmode($fh);		# f..k Windoze	
		return $self;
		};
	return;
	}

# Computes the correct offset, asumes that header_len and record_len
# are defined in the object, probably set up by the read_header.
# Assumes that the file has got header and then records, numbered from
# zero
sub get_record_offset
	{
	my $self = shift;
	my ($header_len, $record_len) = @{$self}{ qw( header_len record_len ) };
	unless (defined $header_len and defined $record_len)
		{
		$self->Error("Header and record lengths not known in get_record_offset\n");
		return;
		}
	my $num = shift;
	unless (defined $num)
		{
		$self->Error("Number of the record must be specified in get_record_offset\n");
		return;
		}
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
	return 1 if defined $self->{'tell'} and $self->{'tell'} == $offset;

	my $filename = $self->{'filename'};

			# the file should really be opened and writable
	if (not defined $self->{'opened'})
		{ $self->Error("The file $filename is not opened\n"); return; }
	### if (not $self->{'writable'})
	###	{ $self->Error("The file $filename is not writable\n"); return; }

	delete $self->{'tell'};	# we cancel the tell position

	$self->{'fh'}->seek($offset, 0)	# seek to the offset
		or do { $self->Error("Error seeking to offset $offset on $filename: $!\n");
		return;
		};
	1;
	}

# Read the record of given number. Cache last record read; when
# defined unpack_template, unpack into list. Of course, any class may
# redefine it, if this behaviour is not suitable
sub read_record
	{
	my ($self, $num, $in_length) = @_;

	if (not defined $num)
		{ $self->Error("Record number to read must be specified\n"); return; }
	if ($num > $self->last_record())
		{ $self->Error("Can't read record $num, there is not so many of them\n"); return; }

	if (defined $self->{'cached_num'} and $num == $self->{'cached_num'})
		{
		my $data = $self->{'cached_data'};
		if (ref $data)	{ return @$data; }
		return $data;
		}
	
	my $tell = $self->{'tell'};
	$self->seek_to_record($num) or return;

	my ($fh, $record_len) = @{$self}{ qw( fh record_len ) };
	my $buffer;

	$in_length = $record_len unless defined $in_length;

	my $actually_read = $fh->read($buffer, ($in_length == -1 ?
						$record_len : $in_length));
	
	if ($actually_read != $in_length and $in_length != -1)
		{
		$self->Warning("Error reading the whole record num $num\n");
		return unless FIXPROBLEMS;
		};
	
	$self->{'tell'} = (defined $tell) ? $tell + $actually_read : $fh->tell();
	
	$self->{'cached_num'} = $num;
	if (defined $self->{'unpack_template'})
		{
		my @data = unpack $self->{'unpack_template'}, $buffer;

		$self->{'cached_data'} = [ @data ];

		return @data;
		}
	else
		{
		$self->{'cached_data'} = $buffer;
		return $buffer;
		}
	}

# Write the record of given number
sub write_record
	{
	my ($self, $num) = (shift, shift);
	if (not $self->{'writable'})
		{ $self->Error("The file $self->{'filename'} is not writable\n"); return; }
	if (not defined $num)
		{ $self->Error("Record number to write must be specified\n"); return; }
	if (defined $self->{'cached_num'} and $num == $self->{'cached_num'})
		{ delete $self->{'cached_num'}; }
	$self->seek_to_record($num) or return;
	delete $self->{'tell'};

	local ($,, $\) = ("", "");
	my $fh = $self->{'fh'};
	$fh->print(@_) or
		do { $self->Error("Error writing record $num: $!\n"); return; } ;
	( $num == 0 ) ? "0E0" : $num;
	}

# Write to offset
sub write_to
	{
	my ($self, $offset) = (shift, shift);
	if (not $self->{'writable'})
		{ $self->Error("The file $self->{'filename'} is not writable\n"); return; }
	$self->seek_to($offset) or return;
	delete $self->{'tell'};
	
	local ($,, $\) = ("", "");
	my $fh = $self->{'fh'};
	$fh->print(@_) or
		do { $self->Error("Error writing at offset $offset: $!\n"); return; } ;
	( $offset == 0 ) ? "0E0" : $offset;
	}

1;

