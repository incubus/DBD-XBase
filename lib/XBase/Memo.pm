
=head1 NAME

XBase::Memo - Generic support for various memo formats

=head1 SYNOPSIS

Used indirectly, via XBase.

=head1 DESCRIPTION

Objects of this class are created to deal with memo files, currently
.dbt. Defines method B<read_header> to parse that header of the file
and set object's structures, B<write_record> and B<last_record> to
work properly on this type of file.

There are two separate packages in this module, XBase::Memo::dBaseIII
and XBase::Memo::dBaseIV. Memo objects are effectively of one of these
types and they specify B<read_record> and B<write_record> methods.

=head1 VERSION

0.0584

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), XBase(3)

=cut


# ###################################
# Here starts the XBase::Memo package

package XBase::Memo;

use strict;
use XBase::Base;


use vars qw( $VERSION @ISA );
@ISA = qw( XBase::Base );


$VERSION = "0.0584";

sub read_header
	{
	my $self = shift;

	my $header;
	$self->{'fh'}->read($header, 512) == 512 or do
		{ Error "Error reading header of $self->{'filename'}\n";
		return; };

	my ($next_for_append, $block_size, $version);
	if ($self->{'filename'} =~ /\.fpt$/i)
		{
		($next_for_append, $block_size) = unpack 'N@6n', $header;
		$version = 5;
		bless $self, 'XBase::Memo::Fox';
		}
	else
		{
		($next_for_append, $version, $block_size)
					= unpack 'V@16C@20v', $header;
		if ($version == 3)
			{
			$block_size = 512;
			bless $self, 'XBase::Memo::dBaseIII';
			}
		else
			{
			$version = 4;
			bless $self, 'XBase::Memo::dBaseIV';
			}
		}

	$block_size = 512 if int($block_size) == 0;

	@{$self}{ qw( next_for_append header_len record_len version ) }
		= ( $next_for_append, 0, $block_size, $version );

	1;
	}

sub write_record
	{
	my ($self, $num) = (shift, shift);
	my $length = length(join "", @_);
	my $record_len = $self->{'record_len'};
	my $num_of_blocks = int (($length + $record_len - 1) / $record_len);
	$self->SUPER::write_record($num, @_);
	if ($num > $self->last_record())
		{
		$self->SUPER::write_to(0, pack "V", $num + $num_of_blocks);
		$self->{'next_for_append'} = $num + $num_of_blocks;
		}
	$num;
	}

sub last_record	{ shift->{'next_for_append'} - 1; }

sub create
	{
	my $self = shift;
	my %options = @_;
	$self->create_file($options{'name'}) or return;
	my $version = $options{'version'};
	$version = 3 unless defined $version;
	$version = 0 if $version == 4;
	my $header = 
	$self->write_to(0, pack "VVa8Ca495", 1, 0, '', $version) or return;
	$self->close();
	return $self;
	}


# ################################
# dBase III+ specific memo methods

package XBase::Memo::dBaseIII;

use XBase::Base;
use vars qw( @ISA );
@ISA = qw( XBase::Memo );

sub read_record
	{
	my ($self, $num) = @_;
	my $result = '';
	my $last = $self->last_record();
	while ($num <= $last)
		{
		my $buffer = $self->SUPER::read_record($num, -1);
		if (not defined $buffer) { return; }
		my $index = index($buffer, "\x1a\x1a");
		if ($index >= 0)
			{ return $result . substr($buffer, 0, $index); }
		$result .= $buffer;
		$num++;
		}
	return $result;
	}
sub write_record
	{
	my ($self, $num) = (shift, shift);
	my $type = shift;
	my $data = join "", @_, "\x1a\x1a";
	if ($num < $self->last_record() and $num != -1)
		{
		my $buffer = $self->read_record($num);
		if (defined $buffer)
			{
			my $length = length $buffer;
			my $record_len = $self->{'record_len'};
			my $space_in_blocks =
				int (($length + $record_len - 3) / $record_len);
			my $len_in_blocks =
				int ((length($data) + $record_len - 1) / $record_len);
			if ($len_in_blocks > $space_in_blocks)
				{ $num = $self->last_record() + 1; }
			}
		}
	else
		{
		$num = $self->last_record() + 1;
		}
	$self->SUPER::write_record($num, $data);
	$num;
	}

# ################################
# dBase IV specific memo methods

package XBase::Memo::dBaseIV;

use XBase::Base;
use vars qw( @ISA );
@ISA = qw( XBase::Memo );

sub read_record
	{
	my ($self, $num) = @_;
	my $result = '';
	my $last = $self->last_record();

	my $buffer = $self->SUPER::read_record($num, -1);
	if (not defined $buffer) { return; }
	my ($unused_id, $length) = unpack "VV", $buffer;
	my $block_size = $self->{'record_len'};
	if ($length < $block_size - 8)
		{ return substr $buffer, 8, $length; }
	my $rest_length = $length - ($block_size - 8);
	my $rest_data = $self->SUPER::read_record($num + 1, $rest_length);
	if (not defined $rest_data) { return; }
	return substr($buffer, 8, $block_size - 8) . $rest_data;
	}

sub write_record
	{
	my ($self, $num) = (shift, shift);
	my $type = shift;
	my $data = join "", @_;
	my $length = length $data;

	my $startfield = pack "CCCC", "\xff", "\xff", "\x08", 0;
	if (ref $self eq 'XBase::Memo::Fox')
		{
		if ($type eq 'P')	{ $startfield = pack 'V', 0; }
		elsif ($type eq 'M')	{ $startfield = pack 'V', 1; }
		else			{ $startfield = pack 'V', 2; }
		}
	$data = $startfield . pack ('V', $length) . $data . "\x1a\x1a";

	if ($num < $self->last_record() and $num != -1)
		{
		my $buffer = $self->read_record($num);
		if (defined $buffer)
			{
			my $length = length $buffer;
			my $record_len = $self->{'record_len'};
			my $space_in_blocks =
				int (($length + $record_len - 11) / $record_len);
			my $len_in_blocks =
				int ((length($data) + $record_len - 1) / $record_len);
			if ($len_in_blocks > $space_in_blocks)
				{ $num = $self->last_record() + 1; }
			}
		else
			{
			$num = $self->last_record() + 1;
			}
		}
	$self->SUPER::write_record($num, $data);
	$num;
	}


# #######################################
# FoxPro specific memo methods (fpt file)

package XBase::Memo::Fox;

use XBase::Base;
use vars qw( @ISA );
@ISA = qw( XBase::Memo::dBaseIV );

1;

