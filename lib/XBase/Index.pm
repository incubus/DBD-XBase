
=head1 NAME

XBase::Index - base class for the index files for dbf

=cut

package XBase::Index;
use strict;
use vars qw( @ISA $DEBUG $VERSION );
use XBase::Base;
@ISA = qw( XBase::Base );

$VERSION = '0.0941';

$DEBUG = 0;

sub new
	{
	my ($class, $file) = (shift, shift);
	if ($file =~ /\.ndx$/i)
		{ return new XBase::ndx $file, @_; }
	elsif ($file =~ /\.ntx$/i)
		{ return new XBase::ntx $file, @_; }
	else
		{ __PACKAGE__->Error("Error loading index: unknown extension\n"); }
	return;
	}

sub get_record
	{
	my $self = shift;
	my $newpage = ref $self;
	$newpage .= '::Page' unless substr($newpage, -6) eq '::Page';
	$newpage .= '::new';
	return $self->$newpage(@_);
	}

sub fetch
	{
	my $self = shift;
	my ($level, $page, $row, $key, $val, $left);
	while (not defined $val)
		{
		$level = $self->{'level'};
		if (not defined $level)
			{
			$level = $self->{'level'} = 0;
			$page = $self->get_record($self->{'start_page'});
			if (not defined $page)
				{
				$self->Error("Index corrupt: $self: no root page $self->{'start_page'}\n");
				return;
				}
			$self->{'pages'} = [ $page ];
			$self->{'rows'} = [];
			}

		$page = $self->{'pages'}[$level];
		if (not defined $page)
			{
			$self->Error("Index corrupt: $self: page for level $level lost\n");
			return;
			}

		my $row = $self->{'rows'}[$level];
		if (not defined $row)
			{ $row = $self->{'rows'}[$level] = 0; }
		else
			{ $self->{'rows'}[$level] = ++$row; }
		
		($key, $val, $left) = $page->get_key_val_left($row);
		if (defined $left)
			{
			$level++;
			my $oldpage = $page;
			$page = $oldpage->get_record($left);
			if (not defined $page)
				{
				$self->Error("Index corrupt: $self: no page $left, referenced from $oldpage, for level $level\n");
				return;
				}
			$self->{'pages'}[$level] = $page;
			$self->{'rows'}[$level] = undef;
			$self->{'level'} = $level;
			$val = undef;
			next;
			}
		if (defined $val)
			{
			return ($key, $val);
			}
		else
			{
			$self->{'level'} = --$level;
			next if $level < 0;
			$page = $self->{'pages'}[$level];
			next unless defined $page;
			$row = $self->{'rows'}[$level];
			my ($backkey, $backval, $backleft) = $page->get_key_val_left($row);
			if (defined $backleft and defined $backval)
				{ return ($backkey, $backval); }
			}
		}
	}

sub prepare_select_eq
	{
	my ($self, $eq) = @_;
	$self->prepare_select();

	my $left = $self->{'start_page'};
	my $level = 0;
	my $parent = $self;
	my $numdate = ($self->{'key_type'} ? 1 : 0);

	while (1)
		{
		my $page = $parent->get_record($left);
		if (not defined $page)
			{
			$self->Error("Index corrupt: $self: no page $left, for level $level\n");
			return;
			}
		my $row = 0;
		my ($key, $val);
		while (($key, $val, my $newleft) = $page->get_key_val_left($row))
			{
			$left = $newleft;
			if (not defined $key)
				{ last; }
			if ($numdate ? $key >= $eq : $key ge $eq)
				{ last; }
			$row++;
			}
		$self->{'pages'}[$level] = $page;
		$self->{'rows'}[$level] = $row;
		if (not defined $left)
			{
			$self->{'rows'}[$level] = ( $row ? $row - 1: undef);
			$self->{'level'} = $level;
			last;
			}
		$parent = $page;
		$level++;
		}
	1;
	}

sub prepare_select
	{
	my $self = shift;
	delete $self->{'level'};
	1;
	}

sub get_key_val_left
	{
	my ($self, $num) = @_;
	{
		local $^W = 0;
		my $printkey = $self->{'keys'}[$num];
		$printkey =~ s/\s+$//;
		print "Getkeyval: Page $self->{'num'}, row $num: $printkey, $self->{'values'}[$num], $self->{'lefts'}[$num]\n"
					if $DEBUG;
	}
	return ($self->{'keys'}[$num], $self->{'values'}[$num], $self->{'lefts'}[$num])
				if $num <= $#{$self->{'keys'}};
	();
	}

sub num_keys
	{ $#{shift->{'keys'}}; }

#
# dBase III NDX
#

package XBase::ndx;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::Base XBase::Index );

$DEBUG = 0;

sub read_header
	{
	my $self = shift;
	my $header;
	$self->{'fh'}->read($header, 512) == 512 or do
		{ __PACKAGE__->Error("Error reading header of $self->{'filename'}: $!\n"); return; };
	@{$self}{ qw( start_page total_pages key_length keys_per_page
		key_type key_record_length unique key_string ) }
		= unpack 'VV @12vvvv @23c a*', $header;
	
	$self->{'key_string'} =~ s/[\000 ].*$//s;
	$self->{'record_len'} = 512;
	$self->{'header_len'} = 0;

	$self;
	}

sub last_record
	{ shift->{'total_pages'}; }

package XBase::ndx::Page;
use strict;
use vars qw( $DEBUG @ISA );
@ISA = qw( XBase::ntx );

$DEBUG = 0;

sub new
	{
	my ($indexfile, $num) = @_;
	my $parent;
	if ((ref $indexfile) =~ /::Page$/)		### parent page
		{
		$parent = $indexfile;
		$indexfile = $parent->{'indexfile'};
		}
	my $data = $indexfile->read_record($num) or return;
	my $noentries = unpack 'v', $data;
	my $keylength = $indexfile->{'key_length'};
	my $keyreclength = $indexfile->{'key_record_length'};

	print "page $num, noentries $noentries, keylength $keylength\n" if $DEBUG;
	my $numdate = $indexfile->{'key_type'};
	my $bigend = substr(pack( "d", 1), 0, 2) eq '?ð';
	
	my $offset = 4;
	my $i =0;
	my ($keys, $values, $lefts) = ([], [], []);

	while ($i < $noentries)
		{
		my ($left, $recno, $key) = unpack "\@$offset VVa$keylength", $data;
		if ($numdate)
			{
			$key = reverse $key if $bigend; $key = unpack "d", $key;
			}
		### print "$i: \@$offset VVa$keylength -> ($left, $recno, $key)\n" if $DEBUG;
		push @$keys, $key;
		push @$values, ($recno ? $recno : undef);
		$left = ($left ? $left : undef);
		push @$lefts, $left;
		
		if ($i == 0 and defined $left)
			{ $noentries++; }
		}
	continue
		{
		$i++;
		$offset += $keyreclength;
		}

	{ local $^W = 0;
	print "Page $num:\tkeys: @{[ map { s/\s+$//; $_; } @$keys]} -> values: @$values\n\tlefts: @$lefts\n" if $DEBUG;
	}

	my $self = bless { 'keys' => $keys, 'values' => $values,
		'num' => $num, 'keylength' => $keylength,
		'lefts' => $lefts, 'indexfile' => $indexfile }, __PACKAGE__;
	$self;
	}

#
# Clipper NTX
#

package XBase::ntx;
use strict;
use vars qw( @ISA );
@ISA = qw( XBase::Base XBase::Index );

sub read_header
	{
	my $self = shift;
	my $header;
	$self->{'fh'}->read($header, 1024) == 1024 or do
		{ __PACKAGE__->Error("Error reading header of $self->{'filename'}: $!\n"); return; };
	
	@{$self}{ qw( signature compiler_version start_offset first_unused
		key_record_length key_length decimals max_item
		half_page key_string unique ) }
			= unpack 'vvVVvvvvva256c', $header;

	$self->{'key_string'} =~ s/[\000 ].*$//s;
	$self->{'record_len'} = 1024;
	$self->{'header_len'} = 0;
	
	$self->{'start_page'} = int($self->{'start_offset'} / $self->{'record_len'});

	$self;
	}
sub last_record
	{ -1; }


package XBase::ntx::Page;
use strict;
use vars qw( $DEBUG @ISA );
@ISA = qw( XBase::ntx );

$DEBUG = 0;

sub new
	{
	my ($indexfile, $num) = @_;
	my $parent;
	if ((ref $indexfile) =~ /::Page$/)		### parent page
		{
		$parent = $indexfile;
		$indexfile = $parent->{'indexfile'};
		}
	my $data = $indexfile->read_record($num) or return;
	my $maxnumitem = $indexfile->{'max_item'} + 1;
	my $keylength = $indexfile->{'key_length'};
	my $record_len = $indexfile->{'record_len'};

	my ($noentries, @pointers) = unpack "vv$maxnumitem", $data;
	
	print "page $num, noentries $noentries, keylength $keylength; pointers @pointers\n" if $DEBUG;
	
	my ($keys, $values, $lefts) = ([], [], []);
	for (my $i = 0; $i < $noentries; $i++)
		{
		my $offset = $pointers[$i];
		my ($left, $recno, $key) = unpack "\@$offset VVa$keylength", $data;

		push @$keys, $key;
		push @$values, ($recno ? $recno : undef);
		$left = ($left ? ($left / $record_len) : undef);
		push @$lefts, $left;

		if ($i == 0 and defined $left)
		### if ($i == 0 and defined $left and (not defined $parent or $num == $parent->{'lefts'}[-1]))
			{ $noentries++; }
		}

	print "Page $num:\tkeys: @{[ map { s/\s+$//; $_; } @$keys]} -> values: @$values\n\tlefts: @$lefts\n" if $DEBUG;

	my $self = bless { 'num' => $num, 'indexfile' => $indexfile,
		'keys' => $keys, 'values' => $values, 'lefts' => $lefts, },
								__PACKAGE__;
	$self;
	}


1;

__END__

=head1 SYNOPSIS

	use XBase;
	my $table = new XBase "data.dbf";
	my $cur = $table->prepare_select_with_index("id.ndx",
		"ID", "NAME);
	$cur->find_eq(1097);

	while (my @data = $cur->fetch())
	        {
		last if $data[0] != 1097;
		print "@data\n";
		}

This is a snippet of code to print ID and NAME fields from dbf
data.dbf where ID equals 1097. Provided you have index on ID in
file id.ndx.

=head1 DESCRIPTION

This is the class that currently supports B<ndx> index files. The name
will change in the furute as we later add other index formats, but for
now this is the only index support.

The support is read only. If you update your data, you have to reindex
using some other tool than XBase::Index currently. Anyway, you have the
tool to do that because XBase::Index doesn't support creating the
index files either. So, read only.

I will stop documenting here for now because the module is not
finalized and you might think that if I write something in the man
page, it will stay so. Most probably not ;-) Please see eg/use_index
in the distribution directory for more information.

=head1 VERSION

0.0941

=head1 AUTHOR

(c) 1998 Jan Pazdziora, adelton@fi.muni.cz

=cut

