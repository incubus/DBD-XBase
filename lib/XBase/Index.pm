
=head1 NAME

XBase::Index - base class for the index files for dbf

=cut

package XBase::Index;
use strict;
use vars qw( @ISA $VERSION $DEBUG );
use XBase::Base;
@ISA = qw( XBase::Base );

$DEBUG = 0;

$VERSION = '0.0631';

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

sub prepare_select
	{ }

sub prepare_select_eq
	{
	my ($self, $eq) = @_;
	@{$self}{ qw( pages actives ) } = ( [], [] );
	my $level = -1;
	my $numdate = $self->{'key_type'};
	my ($key, $val);
	$val = - $self->{'start_page'};
	while (defined $val and $val < 0)
		{
		$level++;
		my $page = $self->get_record(-$val);
		my $active = 0;
		while (($key, $val) = $page->get_key_val($active))
			{
			### if ($key =~ /^\000/ or
			if ($numdate ? $key >= $eq : $key ge $eq)
				{ last; }
			$active++;
			}
		$self->{'pages'}[$level] = $page;
		if ($page->is_ref and $page->num_keys() < $active)
			{
			$active = $page->num_keys();
			(undef, $val) = $page->get_key_val($active);
			}
		$self->{'actives'}[$level] = $active;
		}
	$self->{'actives'}[$level] --;
	1;
	}

sub fetch
	{
	my $self = shift;
	my $level = $#{$self->{'actives'}};
	if ($level < 0)
		{
		$self->{'pages'}[0] = $self->get_record($self->{'start_page'});
		$level = 0;
		}

	my ($key, $val);
	while ($level >= 0 and not defined $val)
		{
		if (defined $self->{'actives'}[$level])
			{ $self->{'actives'}[$level]++; }
		else
			{ $self->{'actives'}[$level] = 0; }
		my ($page, $active) = ( $self->{'pages'}[$level],
					$self->{'actives'}[$level] );
		($key, $val) = $page->get_key_val($active);
		if (not defined $val)	{ $level--; }
		}
	return unless defined $val;

	while ($val < 0)
		{
		$level++;
		my $page = $self->get_record(-$val);
		$self->{'actives'}[$level] = 0;
		$self->{'pages'}[$level] = $page;
		($key, $val) = $page->get_key_val(0);
		}

### print "pages @{[ map { $_->{'num'} } @{$self->{'pages'}} ]}, actives @{$self->{'actives'}}\n";
	($key, $val);
	}

sub last_record
	{ shift->{'total_pages'}; }

sub get_record
	{
	my ($self, $num) = @_;
	return $self->XBase::IndexPage::new($num);
	}

package XBase::IndexPage;
use strict;
use vars qw( $DEBUG );

$DEBUG = 0;

sub new
	{
	my ($indexfile, $num) = @_;
	my $data = $indexfile->read_record($num) or return;
	my $noentries = unpack 'V', $data;
	print "Page $num, " if $DEBUG;
	### if ($num == $indexfile->{'start_page'}) { $noentries++; print "(actually rootpage) " if $DEBUG; }
	### $noentries++;
	my $isref = 0;
	my $keylength = $indexfile->{'key_length'};
	print "noentries $noentries, keylength $keylength, keyreclen $indexfile->{'key_record_length'}\n" if $DEBUG;
	my $offset = 4;
	my ($keys, $values) = ([], []);
	my $numdate = $indexfile->{'key_type'};
	my $bigend = substr(pack( "d", 1), 0, 2) eq '?ð';
	for (my $i = 0; $i < $noentries; $i++)
		{
		my ($lower, $recno, $key);
		($lower, $recno, $key) = unpack "\@$offset VVa$keylength", $data;
		if ($numdate)
			{
			$key = reverse $key if $bigend;
			$key = unpack "d", $key;
			}
		### print "$i: \@$offset VVa$keylength -> ($lower, $recno, $key)\n" if $DEBUG;
		if ($lower != 0) { $recno = -$lower; }
		push @$keys, $key;
		push @$values, $recno;
		$offset += $indexfile->{'key_record_length'};
		if ($i == 0 and $recno < 0)
			{ $noentries++; $isref = 1; }
		}
	print "Page $num:\tkeys: @{[ map { s/\s+$//; $_; } @$keys]} -> values: @$values\n" if $DEBUG;
	my $self = bless { 'keys' => $keys, 'values' => $values,
		'num' => $num, 'keylength' => $keylength }, __PACKAGE__;
	$self->{'is_ref'} = $isref;
	$self;
	}
sub get_key_val
	{
	local $^W = 0;
	my ($self, $num) = @_;
	my $printkey = $self->{'keys'}[$num];
	$printkey =~ s/\s+$//;
	print "Getkeyval: $num: $printkey, $self->{'values'}[$num]\n"
				if $DEBUG and $num <= $#{$self->{'keys'}};
	return ($self->{'keys'}[$num], $self->{'values'}[$num])
				if $num <= $#{$self->{'keys'}};
	();
	}
sub num_keys
	{ $#{shift->{'keys'}}; }
sub is_ref
	{ shift->{'is_ref'}; }
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

0.0631

=head1 AUTHOR

(c) 1998 Jan Pazdziora, adelton@fi.muni.cz

=cut

