
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

0.03

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


$VERSION = "0.03";

sub read_header
	{
	my $self = shift;

	my $header;
	$self->{'fh'}->read($header, 17) == 17 or do
		{ Error "Error reading header of $self->{'filename'}\n";
		return; };

	my ($next_for_append, $block_size, $dbf_filename, $reserved)
		= unpack "VVA8C", $header;

	my $version = 3;
	if ($reserved == 0)
		{
		bless $self, "XBase::Memo::dBaseIV";
		$version = 4;
		}
	else		# $reserved == 3;
		{
		bless $self, "XBase::Memo::dBaseIII";
		}

	$block_size = 512 if $version == 3;
	($dbf_filename = $self->{'filename'}) =~ s/\.db.$//i;

	@{$self}{ qw( next_for_append header_len record_len dbf_filename
		version ) }
		= ( $next_for_append, 0, $block_size,
		$dbf_filename, $version );
	
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
		if ($buffer =~ /^(.*?)\x1a\x1a/)
			{ return $result . $+; }
		$result .= $buffer;
		$num++;
		}
	return $result;
	}
sub write_record
	{
	my ($self, $num) = (shift, shift);
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
	return $buffer . $rest_data;
	}

sub write_record
	{
	my ($self, $num) = (shift, shift);
	my $data = join "", @_;
	my $length = length $data;
	$data = pack ("CCCCV", "\xff", "\xff", "\x08", 0, $length)
			.  $data . "\x1a\x1a";
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

1;

