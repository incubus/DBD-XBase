
=head1 NAME

XBase::Index - base class for the index files for dbf

=cut

package XBase::Index;
use strict;
use vars qw( @ISA $DEBUG $VERSION );
use XBase::Base;
@ISA = qw( XBase::Base );

$VERSION = '0.141';

$DEBUG = 0;

# Open appropriate index file and create object according to suffix
sub new
	{
	my ($class, $file) = (shift, shift);
	my @opts = @_;
	if (ref $class) { @opts = ('dbf', $class, @opts); }
	if ($file =~ /\.ndx$/i)		{ return new XBase::ndx $file, @opts; }
	elsif ($file =~ /\.ntx$/i)	{ return new XBase::ntx $file, @opts; }
	elsif ($file =~ /\.idx$/i)	{ return new XBase::idx $file, @opts; }
	elsif ($file =~ /\.mdx$/i)	{ return new XBase::mdx $file, @opts; }
	elsif ($file =~ /\.cdx$/i)	{ return new XBase::cdx $file, @opts; }
	else { __PACKAGE__->Error("Error loading index: unknown extension\n"); }
	return;
	}

# For XBase::*x object, a record is one page, object XBase::*x::Page here
sub get_record
	{
	my $self = shift;
	my $newpage = ref $self;
	$newpage .= '::Page' unless substr($newpage, -6) eq '::Page';
	$newpage .= '::new';
	my $page = $self->$newpage(@_);
	if (defined $page) {
		local $^W = 0;
		print "Page $page->{'num'}:\tkeys: @{[ map { s/\s+$//; $_; } @{$page->{'keys'}}]}\n\tvalues: @{$page->{'values'}}\n\tlefts: @{$page->{'lefts'}}\n" if $DEBUG;
		}
	$page;
	}

# Get next (value, record number in dbf) pair
# The important values of the index object are 'level' holding the
# current level of the "cursor", 'pages' holing an array of pages for
# each level (currently open) and 'rows' with an array of current row
# in each level
sub fetch
	{
	my $self = shift;
	my ($level, $page, $row, $key, $val, $left);
	
	# cycle while we get to the leaf record or otherwise get
	# a real value, not a pointer to lower page
	while (not defined $val)
		{
		$level = $self->{'level'};
		if (not defined $level)
			{	# if we do not have level, let's start from zero
			$level = $self->{'level'} = 0;
			$page = $self->get_record($self->{'start_page'});
			if (not defined $page)
				{
				$self->Error("Index corrupt: $self: no root page $self->{'start_page'}\n");
				return;
				}
			# and initialize 'pages' and 'rows'
			$self->{'pages'} = [ $page ];
			$self->{'rows'} = [];
			}

		# get current page for this level
		$page = $self->{'pages'}[$level];
		if (not defined $page)
			{
			$self->Error("Index corrupt: $self: page for level $level lost in normal course\n");
			return;
			}

		# get current row for current level and increase it
		# (or setup to zero)
		my $row = $self->{'rows'}[$level];
		if (not defined $row)
			{ $row = $self->{'rows'}[$level] = 0; }
		else
			{ $self->{'rows'}[$level] = ++$row; }

		# get the (key, value, pointer) from the page
		($key, $val, $left) = $page->get_key_val_left($row);

		# there is another page to walk
		if (defined $left)
			{
			# go deeper
			$level++;
			my $oldpage = $page;
			# load the next page
			$page = $oldpage->get_record($left);
			if (not defined $page)
				{
				$self->Error("Index corrupt: $self: no page $left, ref'd from $oldpage, row $row, level $level\n");
				return;
				}
			# and put it into the structure
			$self->{'pages'}[$level] = $page;
			$self->{'rows'}[$level] = undef;
			$self->{'level'} = $level;
			# and even if some index structures allow the
			# value in the same row as record, we want to
			# skip it when going down
			$val = undef;
			next;
			}
		# if we're luck and got the value, return it	
		if (defined $val)
			{
			return ($key, $val);
			}
		# we neither got link to lower page, nor the value
		# so it means we are backtracking the structure one
		# (or more) levels back
		else
			{
			$self->{'level'} = --$level;	# go up the levels
			return if $level < 0;		# do not fall over 
			$page = $self->{'pages'}[$level];
			if (not defined $page)
				{
				$self->Error("Index corrupt: $self: page for level $level lost when backtracking\n");
				return;
				}
			### next unless defined $page;
			$row = $self->{'rows'}[$level];
			my ($backkey, $backval, $backleft) = $page->get_key_val_left($row);
			# this is a hook for ntx files where we do not
			# want to miss a values that are stored inside
			# the structure, not only in leaves.
			if (not defined $page->{'last_key_is_just_overflow'} and defined $backleft and defined $backval)
				{ return ($backkey, $backval); }
			}
		}
	return;	
	}

# Rewind the index to start
# the easiest way to do this is to cancel the 'level' -- this way we
# do not know where we are and we have to start anew
sub prepare_select
	{
	my $self = shift;
	delete $self->{'level'};
	1;
	}

# Position index to a value (or behind it, if nothing found), so that
# next fetch fetches the correct value
sub prepare_select_eq
	{
	my ($self, $eq) = @_;
	$self->prepare_select();		# start from scratch

	my $left = $self->{'start_page'};
	my $level = 0;
	my $parent = $self;
	
	# we'll need to know if we want numeric or string compares
	my $numdate = ($self->{'key_type'} ? 1 : 0);

	while (1)
		{
		my $page = $parent->get_record($left);	# get page
		if (not defined $page)
			{
			$self->Error("Index corrupt: $self: no page $left for level $level\n");
			return;
			}
		my $row = 0;
		my ($key, $val);
		while (($key, $val, my $newleft) = $page->get_key_val_left($row))
			{
			$left = $newleft;

			# finish if we are at the end of the page or
			# behind the correct value
			if (not defined $key)
				{ last; }
			if ($numdate ? $key >= $eq : $key ge $eq)
				{ last; }
			$row++;
			}
		
		# we know where we are positioned on the page now
		$self->{'pages'}[$level] = $page;
		$self->{'rows'}[$level] = $row;

		if (not defined $left)		# if there is no lower level
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

# Get (key, record number if dbf, lower page index) from the index
# page
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
	return;
	}

sub num_keys
	{ $#{shift->{'keys'}}; }


# #############
# dBase III NDX

package XBase::ndx;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::Base XBase::Index );

*DEBUG = \$XBase::Index::DEBUG;

sub read_header
	{
	my $self = shift;
	my %opts = @_;
	my $header;
	$self->{'dbf'} = $opts{'dbf'};
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
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::ndx );

*DEBUG = \$XBase::Index::DEBUG;

# Constructor for the ndx page
sub new
	{
	my ($indexfile, $num) = @_;
	my $parent;
	if ((ref $indexfile) =~ /::Page$/)
		{			# we can be called from parent page
		$parent = $indexfile;
		$indexfile = $parent->{'indexfile'};
		}
	
	my $data = $indexfile->read_record($num) or return;	# get 512 bytes
	my $noentries = unpack 'V', $data;			# num of entries
	
	my $keylength = $indexfile->{'key_length'};		
	my $keyreclength = $indexfile->{'key_record_length'};	# length

	print "page $num, noentries $noentries, keylength $keylength\n" if $DEBUG;
	my $numdate = $indexfile->{'key_type'};		# numeric or string?
	my $bigend = substr(pack('d', 1), 0, 2) eq '?ð';	# endian
	
	my $offset = 4;
	my $i = 0;
	my ($keys, $values, $lefts) = ([], [], []);		# three arrays

	while ($i < $noentries)				# walk the page
		{
		# get the values for entry
		my ($left, $recno, $key)
			= unpack 'VVa*', substr($data, $offset, $keylength + 8);
		if ($numdate)
			{			# some decoding for numbers
			$key = reverse $key if $bigend;
			$key = unpack 'd', $key;
			}
		print "$i: \@$offset VVa$keylength -> ($left, $recno, $key)\n" if $DEBUG > 1;
		push @$keys, $key;
		push @$values, ($recno ? $recno : undef);
		$left = ($left ? $left : undef);
		push @$lefts, $left;
		
		if ($i == 0 and defined $left)
			{ $noentries++; }	# fixup for nonleaf page
				### shouldn't this be for last page only?
		}
	continue
		{
		$i++;
		$offset += $keyreclength;
		}

	my $self = bless { 'keys' => $keys, 'values' => $values,
		'num' => $num, 'keylength' => $keylength,
		'lefts' => $lefts, 'indexfile' => $indexfile }, __PACKAGE__;
	
	if ($num == $indexfile->{'start_page'}
			or (defined
			$parent->{'last_key_is_just_overflow'} and
			$parent->{'lefts'}[$#{$parent->{'lefts'}}] == $num)) {
		$self->{'last_key_is_just_overflow'} = 1;
		}

	$self;
	}

# ###########
# Clipper NTX

package XBase::ntx;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::Base XBase::Index );

sub read_header
	{
	my $self = shift;
	my %opts = @_;
	my $header;
	$self->{'dbf'} = $opts{'dbf'};
	$self->{'fh'}->read($header, 1024) == 1024 or do
		{ __PACKAGE__->Error("Error reading header of $self->{'filename'}: $!\n"); return; };
	
	@{$self}{ qw( signature compiler_version start_offset first_unused
		key_record_length key_length decimals max_item
		half_page key_string unique ) }
			= unpack 'vvVVvvvvvA256c', $header;

	my $key_string = uc $self->{'key_string'};
	$key_string =~ s/^.*?->//;
	$self->{'key_string'} = $key_string;

	if ($self->{'signature'} != 3 and $self->{'signature'} != 6) {
		__PACKAGE__->Error("$self: bad signature value `$self->{'signature'}' found\n");
		return;
		}
	$self->{'key_string'} =~ s/[\000 ].*$//s;
	$self->{'record_len'} = 1024;
	$self->{'header_len'} = 0;
	
	$self->{'start_page'} = int($self->{'start_offset'} / $self->{'record_len'});
	my $field_type;
	if (defined $self->{'dbf'}) {
		$field_type = $self->{'dbf'}->field_type($key_string);
		if (not defined $field_type) {
			__PACKAGE__->Error("Couldn't find key string `$key_string' in dbf file, can't determine field type\n");
			return;
			}
		}
	elsif (defined $opts{'type'}) {
		$field_type = $opts{'type'};
		}
	else {
		__PACKAGE__->Error("Index type (char/numeric) unknown for $self\n");
		return;
		}
	$self->{'key_type'} = ($field_type =~ /^[NDIF]$/ ? 1 : 0);

	$self;
	}
sub last_record
	{ -1; }


package XBase::ntx::Page;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::ntx );

*DEBUG = \$XBase::Index::DEBUG;

# Constructor for the ntx page
sub new
	{
	my ($indexfile, $num) = @_;
	my $parent;
	if ((ref $indexfile) =~ /::Page$/)
		{			# we could be called from parent page
		$parent = $indexfile;
		$indexfile = $parent->{'indexfile'};
		}
	my $data = $indexfile->read_record($num) or return;	# get data
	my $maxnumitem = $indexfile->{'max_item'} + 1;	# limit from header
	my $keylength = $indexfile->{'key_length'};
	my $record_len = $indexfile->{'record_len'};	# length

	my $numdate = $indexfile->{'key_type'};		# numeric or string?

	my ($noentries, @pointers) = unpack "vv$maxnumitem", $data;
			# get pointers where the entries are
	
	print "page $num, noentries $noentries, keylength $keylength; pointers @pointers\n" if $DEBUG;
	
	my ($keys, $values, $lefts) = ([], [], []);
	for (my $i = 0; $i < $noentries; $i++)		# walk the pointers
		{
		my $offset = $pointers[$i];
		my ($left, $recno, $key)
			= unpack 'VVa*', substr($data, $offset, $keylength + 8);

		if ($numdate)
			{
			### if looks like with ntx the numbers are
			### stored as ASCII strings or something
			### To Be Done
			if ($key =~ tr!,+*)('&%$#"!0123456789!) { $key = '-' . $key; }
			$key += 0;
			}

		print "$i: \@$offset VVa$keylength -> ($left, $recno, $key)\n" if $DEBUG > 1;
		push @$keys, $key;
		push @$values, ($recno ? $recno : undef);
		$left = ($left ? ($left / $record_len) : undef);
		push @$lefts, $left;

		### if ($i == 0 and defined $left and (not defined $parent or $num == $parent->{'lefts'}[-1]))
		if ($i == 0 and defined $left)
			{ $noentries++; }
				### shouldn't this be for last page only?
		}

	my $self = bless { 'num' => $num, 'indexfile' => $indexfile,
		'keys' => $keys, 'values' => $values, 'lefts' => $lefts, },
								__PACKAGE__;
	$self;
	}

# ###########
# FoxBase IDX

package XBase::idx;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::Base XBase::Index );

*DEBUG = \$XBase::Index::DEBUG;

sub read_header
	{
	my $self = shift;
	my %opts = @_;
	my $header;
	$self->{'dbf'} = $opts{'dbf'};
	$self->{'fh'}->read($header, 512) == 512 or do
		{ __PACKAGE__->Error("Error reading header of $self->{'filename'}: $!\n"); return; };
	@{$self}{ qw( start_page start_free_list total_pages
		key_length index_options index_signature
		key_string for_expression
		) }
		= unpack 'VVVv CC a220 a276', $header;
	
	$self->{'key_record_length'} = $self->{'key_length'} + 4;
	$self->{'key_string'} =~ s/[\000 ].*$//s;
	$self->{'record_len'} = 512;
	$self->{'start_page'} /= $self->{'record_len'};
	$self->{'start_free_list'} /= $self->{'record_len'};
	$self->{'header_len'} = 0;

	$self;
	}

sub last_record
	{ shift->{'total_pages'}; }

package XBase::idx::Page;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::idx );

*DEBUG = \$XBase::Index::DEBUG;

# Constructor for the idx page
sub new
	{
	my ($indexfile, $num) = @_;
	my $parent;
	if ((ref $indexfile) =~ /::Page$/)
		{			# we can be called from parent page
		$parent = $indexfile;
		$indexfile = $parent->{'indexfile'};
		}
	my $data = $indexfile->read_record($num) or return;	# get 512 bytes
	my ($attributes, $noentries, $left_brother, $right_brother)
		= unpack 'vvVV', $data;		# parse header of the page
	my $keylength = $indexfile->{'key_length'};
	my $keyreclength = $indexfile->{'key_record_length'};	# length

	print "page $num, noentries $noentries, keylength $keylength\n" if $DEBUG;
	my $numdate = $indexfile->{'key_type'};		# numeric or string?
	my $bigend = substr(pack('d', 1), 0, 2) eq '?ð';	# endian
	
	my $offset = 12;
	my $i = 0;
	my ($keys, $values, $lefts) = ([], [], []);		# three arrays

	while ($i < $noentries)				# walk the page
		{
		# get the values for entry
		my ($key, $recno) = unpack "\@$offset a$keylength N", $data;
		my $left;
		unless ($attributes & 2) {
			$left = $recno;
			$recno = undef;
			}
		if ($numdate)
			{			# some decoding for numbers
			$key = reverse $key if $bigend;
			$key = unpack 'd', $key;
			}
		print "$i: \@$offset VVa$keylength -> ($left, $recno, $key)\n" if $DEBUG > 1;
		push @$keys, $key;
		push @$values, ($recno ? $recno : undef);
		$left = ($left ? $left : undef);
		push @$lefts, $left;
		
		if ($i == 0 and defined $left)
			{ $noentries++; }	# fixup for nonleaf page
				### shouldn't this be for last page only?
		}
	continue
		{
		$i++;
		$offset += $keyreclength;
		}

	my $self = bless { 'keys' => $keys, 'values' => $values,
		'num' => $num, 'keylength' => $keylength,
		'lefts' => $lefts, 'indexfile' => $indexfile,
		'attributes' => $attributes,
		'left_brother' => $left_brother,
		'right_brother' => $right_brother }, __PACKAGE__;
	$self;
	}

# ############
# dBase IV MDX

package XBase::mdx;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::Base XBase::Index );

sub read_header
	{
	my $self = shift;
	my %opts = @_;
	my $expr_name = $opts{'expr'};

	my $header;
	$self->{'dbf'} = $opts{'dbf'};
	$self->{'fh'}->read($header, 544) == 544 or do
		{ __PACKAGE__->Error("Error reading header of $self->{'filename'}: $!\n"); return; };

	@{$self}{ qw( version created dbf_filename block_size
		block_size_adder production noentries tag_length res
		tags_used res nopages first_free noavail last_update ) }
			= unpack 'Ca3A16vvccccvvVVVa3', $header;
	
	$self->{'record_len'} = 512;
	$self->{'header_len'} = 0;

	for my $i (1 .. $self->{'tags_used'})
		{
		my $len = $self->{'tag_length'};
		
		$self->seek_to(544 + ($i - 1) * $len) or do
			{ __PACKAGE__->Error($self->errstr); return; };

		$self->{'fh'}->read($header, $len)  == $len or do
			{ __PACKAGE__->Error("Error reading tag header $i in $self->{'filename'}: $!\n"); return; };
	
		my $tag;
		@{$tag}{ qw( header_page tag_name key_format fwd_low
			fwd_high backward res key_type ) }
				= unpack 'VA11ccccca1', $header;

		$self->{'tags'}{$tag->{'tag_name'}} = $tag;

		$self->seek_to($tag->{'header_page'} * 512) or do
			{ __PACKAGE__->Error($self->errstr); return; };

		$self->{'fh'}->read($header, 24) == 24 or do
			{ __PACKAGE__->Error("Error reading tag definition in $self->{'filename'}: $!\n"); return; };
	
		@{$tag}{ qw( start_page file_size key_format_1
			key_type_1 res key_length max_no_keys_per_page
			second_key_type key_record_length res unique) }
				 = unpack 'VVca1vvvvva3c', $header;
		$self->seek_to($tag->{'root_page_ptr'} * 512) or do
			{ __PACKAGE__->Error($self->errstr); return; };
		}

## use Data::Dumper;
## print Dumper $self;

	if (defined $self->{'tags'}{$expr_name})
		{
		$self->{'active'} = $self->{'tags'}{$expr_name};
		$self->{'start_page'} = $self->{'active'}{'start_page'};
		}

	$self;
	}
sub last_record
	{ -1; }

package XBase::mdx::Page;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::mdx );

*DEBUG = \$XBase::Index::DEBUG;

sub new
	{
	my ($indexfile, $num) = @_;

	my $parent;
	if ((ref $indexfile) =~ /::Page$/)		### parent page
		{
		$parent = $indexfile;
		$indexfile = $parent->{'indexfile'};
		}
	$indexfile->seek_to_record($num) or return;
	my $data;
	$indexfile->{'fh'}->read($data, 1024) == 1024 or return;

	my $keylength = $indexfile->{'active'}{'key_length'};
	my $keyreclength = $indexfile->{'active'}{'key_record_length'};
	my $offset = 8;

	my ($noentries, $noleaf) = unpack 'VV', $data;

	print "page $num, noentries $noentries, keylength $keylength; noleaf: $noleaf\n" if $DEBUG;
	if ($noleaf == 54 or $noleaf == 20 or $noleaf == 32
						or $noleaf == 80)
		{ $noentries++; }

	my ($keys, $values, $lefts) = ([], [], []);

	for (my $i = 0; $i < $noentries; $i++)
		{
		my ($left, $key)
			= unpack "\@${offset}Va${keylength}", $data;

		push @$keys, $key;

		if ($noleaf == 54 or $noleaf == 20 or $noleaf == 32 or
		$noleaf == 80)
			{ push @$lefts, $left; }
		else
			{ push @$values, $left; }
		$offset += $keyreclength;
		}

	my $self = bless { 'num' => $num, 'indexfile' => $indexfile,
		'keys' => $keys, 'values' => $values, 'lefts' => $lefts, },
								__PACKAGE__;
	$self;
	}

# ###########
# FoxBase CDX

package XBase::cdx;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::Base XBase::Index );

*DEBUG = \$XBase::Index::DEBUG;

sub read_header
	{
	my $self = shift;
	my %opts = @_;
### use Data::Dumper; print Dumper $self;
	my $header;
	
	$self->{'dbf'} = $opts{'dbf'} if not exists $self->{'dbf'};

	$self->{'fh'}->read($header, 1024) == 1024 or do
		{ __PACKAGE__->Error("Error reading header of $self->{'filename'}: $!\n"); return; };
	@{$self}{ qw( start_page start_free_list total_pages
		key_length index_options index_signature
		sort_order total_expr_length for_expression_length
		key_expression_length
		key_string
		) }
		= unpack 'VVNv CC @502 vvv @510 v @512 a512', $header;

	$self->{'total_pages'} = -1;	### the total_pages value 11
		### found in rooms.cdx is not correct, so we invalidate it

	($self->{'key_string'}, $self->{'for_string'}) =
		($self->{'key_string'} =~ /^([^\000]*)\000([^\000]*)/);

	$self->{'key_record_length'} = $self->{'key_length'} + 4;
	$self->{'record_len'} = 512;
	$self->{'start_page'} /= $self->{'record_len'};
	$self->{'start_free_list'} /= $self->{'record_len'};
	$self->{'header_len'} = 0;
	

	if (defined $opts{'tag'}) {
		my $subidx = bless { %$self }, ref $self;

		$self->prepare_select_eq($opts{'tag'});
		my $value = $self->fetch;

		print "Adjusting start_page value by $value for $opts{'tag'}\n" if $DEBUG;
		$subidx->{'fh'}->seek($value, 0);
		$subidx->read_header;

### use Data::Dumper; print Dumper $subidx;

		my $key_string = $subidx->{'key_string'};
		my $field_type;
		if (defined $subidx->{'dbf'}) {
			$field_type = $subidx->{'dbf'}->field_type($key_string);
			if (not defined $field_type) {
				__PACKAGE__->Error("Couldn't find key string `$key_string' in dbf file, can't determine field type\n");
				return;
				}
			}
		elsif (defined $opts{'type'}) {
			$field_type = $opts{'type'};
			}
		else {
			__PACKAGE__->Error("Index type (char/numeric) unknown for $subidx\n");
			return;
			}
		$subidx->{'key_type'} = ($field_type =~ /^[NDIF]$/ ? 1 : 0);

		for (keys %$self) { delete $self->{$_} }
		for (keys %$subidx) { $self->{$_} = $subidx->{$_} }
		$self = $subidx;

### use Data::Dumper; print Dumper $self;
		}

	$self;
	}

sub last_record
	{ shift->{'total_pages'}; }

package XBase::cdx::Page;
use strict;
use vars qw( @ISA $DEBUG );
@ISA = qw( XBase::cdx );

*DEBUG = \$XBase::Index::DEBUG;

# Constructor for the cdx page
sub new
	{
	my ($indexfile, $num) = @_;
	my $parent;
	if ((ref $indexfile) =~ /::Page$/)
		{			# we can be called from parent page
		$parent = $indexfile;
		$indexfile = $parent->{'indexfile'};
		}
	my $data = $indexfile->read_record($num)
		or do { print $indexfile->errstr; return; };	# get 512 bytes
	my ($attributes, $noentries, $left_brother, $right_brother)
		= unpack 'vvVV', $data;		# parse header of the page
	my $keylength = $indexfile->{'key_length'};
	my $keyreclength = $indexfile->{'key_record_length'};	# length

	print "page $num, noentries $noentries, keylength $keylength\n" if $DEBUG;
	my $numdate = $indexfile->{'key_type'};		# numeric or string?
	my $bigend = substr(pack('d', 1), 0, 2) eq '?ð';	# endian

	my ($keys, $values, $lefts) = ([], [], []);

	if ($attributes & 2)
		{
		print "leaf page, compressed\n" if $DEBUG;
		my ($free_space, $recno_mask, $duplicate_count_mask,
		$trailing_count_mask, $recno_count, $duplicate_count,
		$trailing_count, $holding_recno) = unpack '@12 vVCCCCCC', $data;
		print '$free_space, $recno_mask, $duplicate_count_mask, $trailing_count_mask, $recno_count, $duplicate_count, $trailing_count, $holding_recno) = ',
			"$free_space, $recno_mask, $duplicate_count_mask, $trailing_count_mask, $recno_count, $duplicate_count, $trailing_count, $holding_recno)\n" if $DEBUG > 3;
	
		my $prevkeyval = '';
		for (my $i = 0; $i < $noentries; $i++) {
			my $one_item = substr($data, 24 + $i * $holding_recno, $holding_recno) . "\0" x 4;
			my $numeric_one_item = unpack 'V', $one_item; print "one_item: 0x", unpack('H*', $one_item), " ($numeric_one_item)\n" if $DEBUG > 3;

			my $recno = $numeric_one_item & $recno_mask;
			$numeric_one_item >>= $recno_count;
			my $dupl = $numeric_one_item & $duplicate_count_mask;
			$numeric_one_item >>= $duplicate_count;
			my $trail = $numeric_one_item & $trailing_count_mask;
			$numeric_one_item >>= $trailing_count;

			print "Item $i: trail $trail, dupl $dupl, recno $recno\n" if $DEBUG > 1;

			my $getlength = $keylength - $trail - $dupl;
			my $key = substr($prevkeyval, 0, $dupl);
			if ($getlength) {
				$key .= substr($data, -$getlength);
				$key .= "\000" x $trail;
				substr($data, -$getlength) = '';
				}
			$prevkeyval = $key;

### print "Key $key\n";
			if ($numdate)
				{		# some decoding for numbers
				if ("\200" & substr($key, 0, 1)) {
					substr($key, 0, 1) &= "\177";
					}
				else { $key = ~$key; }
				if ($keylength == 8) {
					$key = reverse $key unless $bigend;
					$key = unpack 'd', $key;
					}
				else {
					$key = unpack 'N', $key;
					}
				}

			print "$key -> $recno\n" if $DEBUG > 4;
			push @$keys, $key;
			push @$values, $recno;
			push @$lefts, undef;
			}
		}

	else {
		for (my $i = 0; $i < $noentries; $i++) {
			my $offset = 12 + $i * ($keylength + 8);
			my ($key, $recno, $page)
				= unpack "\@$offset a$keylength NN", $data;
			if ($numdate)
				{		# some decoding for numbers
				if ("\200" & substr($key, 0, 1)) {
					substr($key, 0, 1) &= "\177";
					}
				else { $key = ~$key; }
				if ($keylength == 8) {
					$key = reverse $key unless $bigend;
					$key = unpack 'd', $key;
					}
				else {
					$key = unpack 'N', $key;
					}
				}
### 			print "Value: $key; dbf recno: $recno; page $page\n";
			push @$keys, $key;
			push @$values, undef;
			push @$lefts, $page / 512;
			}
		}

	my $self = bless { 'keys' => $keys, 'values' => $values,
		'num' => $num, 'keylength' => $keylength,
		'lefts' => $lefts, 'indexfile' => $indexfile,
		'attributes' => $attributes,
		'left_brother' => $left_brother,
		'right_brother' => $right_brother }, __PACKAGE__;
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

	while (my @data = $cur->fetch()) {
		last if $data[0] != 1097;
		print "@data\n";
		}

This is a snippet of code to print ID and NAME fields from dbf
data.dbf where ID equals 1097. Provided you have index on ID in
file id.ndx. You can use the same code for ntx and idx index files.
For the cdx and mdx, the prepare_select call would be

	prepare_select_with_index(['rooms.cdx', 'ROOMNAME'])

so instead of plain filename you specify an arrayref with filename and
an index tag in that file. The reason is that cdx and mdx can contain
multiple indexes in one file and you have to distinguish, which you
want to use.

=head1 DESCRIPTION

The module XBase::Index is a collection of packages to provide index
support for XBase-like dbf database files.

An index file is generaly a file that holds values of certain database
field or expression in sorted order, together with the record number
that the record occupies in the dbf file. So when you search for
a record with some value, you first search in this sorted list and
once you have the record number in the dbf, you directly fetch the
record from dbf.

=head2 What indexes do

To make the searching in this ordered list fast, it's generally organized
as a tree -- it starts with a root page with records that point to
pages at lower level, etc., until leaf pages where the pointer is no
longer a pointer to the index but to the dbf. When you search for a
record in the index file, you fetch the root page and scan it
(lineary) until you find key value that is equal or grater than that you
are looking for. That way you've avoided reading all pages describing
the values that are lower. Here you descend one level, fetch the page
and again search the list of keys in that page. And you repeat this
process until you get to the leaf (lowest) level and here you finaly
find a pointer to the dbf. XBase::Index does this for you.

Some of the formats also support multiple indexes in one file --
usually there is one top level index that for different field values
points to different root pages in the index file (so called tags).

XBase::Index supports (or aims to support) the following index
formats: ndx, ntx, mdx, cdx and idx. They differ in a way they store
the keys and pointers but the idea is always the same: make a tree of
pages, where the page contains keys and pointer either to pages at
lower levels, or to dbf (or both). XBase::Index only supports
read only access to the index fields at the moment (and if you need
writing them as well, follow reading because we need to have the
reading support stable before I get to work on updating the indexes).

=head2 Testing your index file (and XBase::Index)

You can test your index using the indexdump script in the main
directory of the DBD::XBase distribution (I mean test XBase::Index
on correct index data, not testing corrupted index file, of course ;-)
Just run

	./indexdump ~/path/index.ndx
	./indexdump ~/path/index.cdx tag_name

or

	perl -Ilib ./indexdump ~/path/index.cdx tag_name

if you haven't installed this version of XBase.pm/DBD::XBase yet. You
should get the content of the index file. On each row, there is
the key value and a record number of the record in the dbf file. Let
me know if you get results different from those you expect. I'd
probably ask you to send me the index file (and possibly the dbf file
as well), so that I can debug the problem.

The index file is (as already noted) a complement to a dbf file. Index
file without a dbf doesn't make much sense because the only thing that
you can get from it is the record number in the dbf file, not the
actual data. But it makes sense to test -- dump the content of the
index to see if the sequence is OK.

The index formats usually distinguish between numeric and character
data. Some of the file formats include the information about the type
in the index file, other depend on the dbf file. Since with indexdump
we only look at the index file, you may need to specify the -type
option to indexdump if it complains that it doesn't know the data
type of the values (this is the case with cdx at least). The possible
values are num, char and date and the call would be like

	./indexdump -type=num ~/path/index.cdx tag_name

(this -type option may not work with all index formats at the moment
-- will be fixed and patches always welcome).

You can use C<-ddebug> option to indexdump to see how pages are
fetched and decoded, or run debugger to see the calls and parsing.

=head2 Using the index files to speed up searches in dbf

The syntax for using the index files to access data in the dbf file is
generally

	my $table = new XBase "tablename";
		# or any other arguments to get the XBase object
		# see XBase(3)
	my $cur = $table->prepare_select_with_index("indexfile",
		"list", "of", "fields", "to", "return");

or

	my $cur = $table->prepare_select_with_index(
		[ "indexfile_with_tags", "tag_name" ],
		"list", "of", "fields", "to", "return");

where we specify the tag in the index file (this is necessary with cdx
and mdx). After we have the cursor, we can search to given record and
start fetching the data:

	$cur->find_eq('jezek');
	while (my @data = $cur->fetch) { # do something

=head2 Supported index formats

The following table summarizes which formats are supproted by
XBase::Index. If the field says something else that Yes, I welcome
testers and offers of example index files.

  Reading of index files -- types supported by XBase::Index

  type	string		numeric		date
  ----------------------------------------------------------
  ndx	Yes		Yes		Yes (you need to
  					convert to Julian)

  ntx	Yes		Yes		Untested

  idx	Untested	Untested	Untested
  	(but should be pretty usable)

  mdx	Untested	Untested	Untested

  cdx	Yes		Yes		Untested


  Writing of index files -- not supported untill the reading
  is stable enough.

So if you have access to an index file that is untested or unsupported
and you care about support of these formats, contact me. If you are
able to actually generate those files on request, the better because I
may need specific file size or type to check something. If the file
format you work with is supported, I still appreciate a report that it
really works for you.

B<Please note> that there is very little documentation about the file
formats and the work on XBase::Index is heavilly based on making
assumption based on real life data. Also, the documentation is often
wrong or only describing some format variations but not the others.
I personally do not need the index support but am more than happy to
make it a reality for you. So I need your help -- contact me if it
doesn't work for you and offer me your files for testing. Mentioning
word XBase somewhere in the Subject line will get you (hopefully ;-)
fast response. Mentioning work Help or similar stupidity will probably
make my filters to consider your email as spam. Help yourself by
making my life easier in helping you.

=head2 Programmer's notes

Programmers might find the following information usefull when trying
to debug XBase::Index from their files:

The XBase::Index module contains the basic XBase::Index package and
also packages XBase::ndx, XBase::ntx, XBase::idx, XBase::mdx and
XBase::cdx, and for each of these also a package
XBase::index_type::Page. Reading the file goes like this: you create
as object calling either new XBase::Index or new XBase::ndx (or
whatever the index type is). This can also be done behind the scenes,
for example XBase::prepare_select_with_index calls new XBase::Index.
The index file is opened using the XBase::Base::new/open and then the
XBase::index_type::read_header is called. This function fills the
basic data fields of the object from the header of the file. The new
method returns the object corresponding to the index type.

Then you probably want to do $index->prepare_select or
$index->prepare_select_eq, that would possition you just before record
equal or greater than the parameter (record in the index file, that
is). Then you do a series of fetch'es that return next pair of (key,
pointer_to_dbf). Behind the scenes, prepare_select_eq or fetch call
XBase::Index::get_record which in turn calls
XBase::index_type::Page::new. From the index file perspective, the
atomic item in the file is one index page (or block, or whatever
you call it). The XBase::index_type::Page::new reads the block of data
from the file and parses the information in the page -- pages have
more or less complex structures. Page::new fills the structure, so
that the fetch calls can easily check what values are in the page.

For some examples, please see eg/use_index in the distribution
directory.

=head1 VERSION

0.141

=head1 AUTHOR

(c) 1998--1999 Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

XBase(3), XBase::FAQ(3)

=cut

