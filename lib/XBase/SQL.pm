
# ####################
# Parsing SQL commands

package XBase::SQL;

### BEGIN { eval { use locale; }; }

use strict;
use vars qw( $VERSION $DEBUG %COMMANDS );
$VERSION = '0.044';
$DEBUG = 3;

# ##################
# Regexp definitions

my $FIELDNAME = q!\w+!;
my $TABLENAME = q!\w+!;
my $SELECTFIELDS = qq!\\*|$FIELDNAME(?:\\s*,\\s*$FIELDNAME)*!;
my $INSERTFIELDS = qq#((?!values\\b)$FIELDNAME(?:\\s*,\\s*$FIELDNAME)*)?#;
my $NUMBER = q!-?(\d*\.)?\d+!;
my $STRINGSTART = q!["']!;
my $STRING = "($STRINGSTART)" . q#(\\\\\\\\|\\\\\\2|.)*?\\2#;
my $INSERTCONSTANTS = qq!(?:null|$STRING|$NUMBER)!;

my %TYPES = ( 'char' => 'C', 'num' => 'N', 'boolean' => 'L', 'blob' => 'M',
		'memo' => 'M', 'float' => 'N', 'date' => 'D' );
my $FIELDTYPE = join('|', '(', keys %TYPES, ')') .
				q!\s*(\(\s*(\d+)(\.(\d+))?\s*\))?\s*!;

%COMMANDS = (
	'COMMANDS' => [ qw{ select SELECT | insert INSERT | delete
				DELETE | update UPDATE | create CREATE } ],
	'SELECT' => [ qw{ SELECTFIELDS ? from TABLE WHERE ? } ],
	'INSERT' => [ qw{ into TABLE INSERTFIELDS ? values
						\( INSERTCONSTANTS \) } ],
	'DELETE' => [ qw{ from TABLE ( where BOOLEAN ) ? } ],
	'UPDATE' => [ qw{ TABLE SETCOLUMNS ( where BOOLEAN ) ? } ],
	'CREATE' => [ qw{ table TABLE \( COLUMNDEF \) } ],
	'TABLE' => q'\w+',
	'FIELDNAME' => q'\w+',
	'SELECTFIELDS' => [ qw{ \* | FIELDNAME ( }, q'\s*,\s*', qw{ FIELDNAME ) * } ],
	
	'WHERE' => [ qw{ where BOOLEAN } ],
	'BOOLEAN' => [ qw{ \( BOOLEAN \) | RELATION ( ( and | or ) RELATION ) * } ],
	'RELATION' => [ qw{ FIELDNAME RELOP ARITHMETIC } ],
	'RELOP' => [ qw{ = | == | <= | >= | <> | != | < | > } ],
	
	'ARITHMETIC' => [ qw{ \( ARITHMETIC \)
		| ( FIELDNAME | NUMBER | STRING ) ( ( \+ | \- | \* | \/ | \% ) ARITHMETIC ) ? } ],
	'NUMBER' => q'-?\d*\.?\d+',
	'STRING' => [ qw{ STRINGDBL | STRINGSGL } ] ,
	'STRINGDBL' => [ qw{ \" (\\\\|\\"|.)* \" } ],
	'STRINGSQL' => [ qw{ \' (\\\\|\\'|.)* \' } ],
	);

my %STORE = (
	'TABLE' => 'table',
	'FIELDNAME' => sub { push @{shift->{'selectfields'}}, @_; },
	'WHERE' => sub { my $self = shift; $self->{'whereexpression'} =
		$self->{'expression'}; delete $self->{'expression'}; },
	'and' => sub { push @{ shift->{'expression'} }; },
	'>=' => sub { push @{ shift->{'expression'} }; },
	'<=' => sub { push @{ shift->{'expression'} }; },
	);

my %ERRORS = (
	'TABLE' => 'Table name expected',
	'RELATION' => 'Relation expected',
	'ARITHMETIC' => 'Arithmetic expression expected',
	'from' => 'From specification expected',
	'into' => 'Into specification expected',
	'values' => 'Values specification expected',
	'\\(' => 'Left paren expected',
	'\\)' => 'Right paren missing',
	'\\*' => 'Star expected',
	'\\"' => 'Double quote expected',
	"\\'" => 'Single quote expected',
	);

sub Log (@)
	{
	my $level = 1;
	if (@_ > 1)	{ $level = shift; }
	return if $DEBUG < $level;
	my $i;
	for ($i = 1; $i < 20; $i++)
		{ last if ((caller($i))[3] ne 'XBase::SQL::match'); }
	$i -= 2;
	print STDERR '  ' x $i, @_;
	}

sub parse
	{
	my $self = bless {}, shift;
	
	$self->{'string'} = shift;
	$self->match('COMMANDS');
	my $errstr = $self->{'errstr'};

	if ($self->{'string'} ne '' and not defined $errstr)
		{ $errstr = 'Unexpected characters in SQL command'; }
	
	if (defined $errstr and substr($errstr, -1) ne "\n")
		{
		my $string = $self->{'string'};
		if ($string eq '')
			{ $errstr .= " near the end of SQL command\n"; }
		else
			{ $errstr .= q! near '! . substr($string, 0, 24) . ( length $string < 24 ? '' : '...' ) . qq!'\n!; }	
		$self->{'errstr'} = $errstr;
		}
	$self;
	}

sub match
	{
	my $self = shift;		# object self reference

	my @regexps = ( shift );	# regexp to match
	@regexps = @{$regexps[0]} if ref $regexps[0];

	my $globalmodif;		# global modifier for this match call
	my $md = $regexps[0];
	if (not defined $md or $md eq '?' or $md eq '*')
		{
		$globalmodif = $md;
		shift @regexps;
		}

	my @patterns = shift;		# call stack
	if (not defined $patterns[0])	{ @patterns = (); }
	elsif (ref $patterns[0])	{ @patterns = @{$patterns[0]}; }

	my $origpattern = "@regexps";

	if (@regexps == 1 and defined $COMMANDS{$regexps[0]})
		{			# pull COMMANDS specification
		$regexps[0] = $COMMANDS{$regexps[0]};
		@regexps = @{$regexps[0]} if ref $regexps[0];
		}

	Log 3, "Match called with $origpattern => @regexps\n";
	Log 3, "Globalmodif set to $globalmodif\n" if defined $globalmodif;

	my $startstoredstring = $self->{'string'};
					# save string
	my (@found, @totalfound);
	my $first = 1;
	my $i = 0;
	while ($i < @regexps)		# walk along the list
		{
		my $found;
		my $result = 0;
		my $regexp = $regexps[$i];
		my $modif = undef;
		my $beforestoredstring = $self->{'string'};
					# save for this step
		my @subregexps;
		if ($regexp eq '(')
			{		# paren group
			my $nest = 1;

			while (++$i < @regexps and $nest)
				{
				if ($regexps[$i] eq '(')	{ $nest++; }
				elsif ($regexps[$i] eq ')')	{ $nest--; }
				push @subregexps, $regexps[$i] if $nest;
				}
			}
		elsif (defined $COMMANDS{$regexp})
			{
			@subregexps = ( $regexp );
			$i++;
			}
		else
			{
			Log "Matching /$regexp/ on '$self->{'string'}'\n";
			if ($self->{'string'} =~ s/^\s*($regexp)\s*//si)
				{
				push @found, ($found = $1);
				$result = 1;
				Log "--- Found `$found'\n";
				}
			$i++;
			}
		if ($i < @regexps and ($regexps[$i] eq '*' or $regexps[$i] eq '?'))
			{ $modif = $regexps[$i]; $i++; }

		if (@subregexps)
			{
			unshift @subregexps, $modif;
			$modif = undef;
		
			my @result = $self->match([ @subregexps ],
						[ @patterns, $origpattern ]);
			$result = shift @result;
			push @found, @result if $result;
			}

		if ($result)
			{
			### Log "Match OK (idx @{[$i-1]})\n";
			for (reverse @patterns, $regexp, $origpattern)
				{
				my $store;
				$store = $STORE{$_} if defined $STORE{$_};
				next unless defined $store;
				if (defined $store)
					{
					if (ref $store eq 'CODE')
						{ $self->$store($found); }
					else
						{ $self->{$store} = $found; }
					last;
					}
				}
			
			if (defined $modif and $modif eq '*')	{ $i -= 2; next; }
			
			if ($i >= @regexps and
				defined $globalmodif and $globalmodif eq '*')
				{
				$startstoredstring = $self->{'string'};
				push @totalfound, @found;
				@found = ();
				$i = 0;
				$first = 1;
				}
			else
				{ $first = 0; }
			if (defined $regexps[$i] and $regexps[$i] eq '|')
				{ $i = @regexps; }
			next;
			}
		elsif ($first)
			{
			if (defined $modif)
				{
				Log 10, "Yes, we have `$modif' on that item\n";
				delete $self->{'errstr'};
				$self->{'string'} = $beforestoredstring;
				next;
				}

			$first = 0;
			my $nest = 0;
			my $regexp;
			while ($i < @regexps)
				{
				$regexp = $regexps[$i];
				if ($regexp eq '(')	{ $nest++; }
				elsif ($regexp eq ')')	{ $nest--; }
				last if $nest == 0 and $regexp eq '|';
				$i++;
				}
			if (defined $regexp and $regexp eq '|')
				{
				Log 10, "Yes, we have found or section\n";
				$i++;
				$first = 1;
				delete $self->{'errstr'};
				$self->{'string'} = $beforestoredstring;
				next;
				}

			if (defined $globalmodif)
				{
				Log 10, "Yes, we've got globalmodif\n";
				delete $self->{'errstr'};
				$self->{'string'} = $startstoredstring;
				@found = ();
				last;
				}
			}

		Log 1, "Failed, returning\n";
		if (not defined $self->{'errstr'} and defined $ERRORS{$regexp})
			{ $self->{'errstr'} = $ERRORS{$regexp}; }
		return;
		}
	Log 1, "OK, returning @totalfound @found\n";
	($self, @totalfound, @found);
	}

__END__



	$FIELDNAME\\s+$FIELDTYPE --
			(\s*,\s*$FIELDNAME\\s+$FIELDTYPE)* -- \\)",

			(?:\\s*,\\s*$INSERTCONSTANTS)*-- \\)",

		{
		'regexp' => "$SELECTFIELDS -- from -- $TABLENAME -- \\&where",
		'store' => [ \&process_match_select_fields, undef, 'table' ],
		},
	'insert' =>
		{
		'regexp' => "into -- $TABLENAME -- $INSERTFIELDS --
			values -- \\( -- $INSERTCONSTANTS --
			(?:\\s*,\\s*$INSERTCONSTANTS)*-- \\)",
		'store' => [ undef, 'table', \&process_match_insert_fields,
			undef, undef, \&process_match_insert_constants,
				\&process_match_insert_constants ],
		},
	'delete' =>
		{
		'regexp' => "from -- $TABLENAME -- \\&where",
		'store' => [ undef, 'table' ],
		},
	'update' =>
		{
		'regexp' => "$TABLENAME -- \\&set_columns -- \\&where",
		'store' => [ 'table' ],
		},
	'create' =>
		{
		'regexp' => "table -- $TABLENAME -- \\( --
			$FIELDNAME\\s+$FIELDTYPE --
			(\s*,\s*$FIELDNAME\\s+$FIELDTYPE)* -- \\)",
		'store' => [ undef, 'table', undef,
			\&process_match_create_fields,
			\&process_match_create_fields ],
		},
	);

my %ERRORS = (
	'table' => 'Table name expected',
	'from' => 'From specification expected',
	'into' => 'Into specification expected',
	'values' => 'Values specification expected',
	'\\(' => 'Left paren expected',
	'\\)' => 'Right paren expected',
	);




sub process_match_select_fields
	{
	my ($self, $match) = @_;
	if ($match eq '*') { $self->{'selectall'} = 1; }
	else
		{
		my @fields = map { uc } split /\s*,\s*/s, $match;
		$self->{'selectfields'} = [ @fields ];
		$self->{'usedfields'} = [ @fields ];
		}
	}
sub process_match_insert_fields
	{
	my ($self, $match) = @_;
	return if $match eq '';
	my @fields = map { uc } split /\s*,\s*/s, $match;
	$self->{'insertfields'} = [ @fields ];
	$self->{'usedfields'} = [ @fields ];
	}

sub process_match_insert_constants
	{
	my ($self, $match) = @_;
	while ($match =~ s/^\s*,\s*($INSERTCONSTANTS)//)
		{
		local $_ = $1;
		if (/^null$/i)
			{ push @{$self->{'insertvalues'}}, 'undef'; }
		else
			{
			s/^['"]|['"]$//g;
			s/^'/\\'/g;
			push @{$self->{'insertvalues'}}, "'$_'";
			}
		}
	}

sub process_match_create_fields
	{
	my ($self, $match) = @_;
	while ($match =~ s/^\s*,\s*($FIELDNAME)\\s+//)
		{
		### ($FIELDTYPE)//)
			{
			}
		}
	}


my %SET = (
	'regexp' => "set -- $FIELDNAME -- = -- \\&match_arithmetic",
	'store' => [ undef, \&s ]
	);

sub set_columns
	{
	my $self = shift;
	local $_ = $self->{'string'};
	my $i = 1;
	while (1)
		{
		$self->match();
		}
	}

#
#
#

#########
##########
sub create
	{
	my $self = shift;
	local $_ = $self->{'string'};

	unless (s/^table\s+//si)
		{
		$self->{'errstr'} = 'Table specification missing';
		return;
		}

	unless (s/^(\w+)\s+//s)
		{
		$self->{'errstr'} = 'Table name expected';
		$self->{'string'} = $_;		return;
		}
	
	$self->{'table'} = $1;

	unless (s/^\(\s*//)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Left bracket expected";
		return $self;
		}

	my (@field_names, @field_types, @field_lengths, @field_decimals);

	while (s/^(\w+)\s+//)
		{
		push @field_names, uc $1;
		my $inputtypes = join '|', keys %TYPES;
		unless (s/^($inputtypes)\b\s*//i)
			{
			$self->{'string'} = $_;
			$self->{'errstr'} = 'Field type expected';
			return $self;
			}
		
		push @field_types, $TYPES{lc $1};
		
		my ($length, $decimal);
		if (/^\(/)
			{
			unless (s/^\(\s*(\d+)(\.(\d+))?\s*\)\s*//)
				{ 
				$self->{'string'} = $_;
				$self->{'errstr'} = 'Type specification expected';
				return $self;
				}
			($length, $decimal) = ($1, $3);
			}

		push @field_lengths, $length;
		push @field_decimals, $decimal;

		unless (s/^(,\s*|(?=\)))//)
			{
			$self->{'string'} = $_;
			$self->{'errstr'} = "Comma separating field definitions expected";
			return $self;
			}
		}

	unless (s/^\)\s*//)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Right bracket expected";
		return $self;
		}
	@{$self}{ qw( field_names field_types field_lengths field_decimals ) }
		= ( [ @field_names ], [ @field_types ], [ @field_lengths ], [ @field_decimals ] );

	$self->{'string'} = $_;
	$self;
	}


#########
sub where
	{
	my $self = shift;

	if ($self->{'string'} =~ s/^where(\s+|(?=\())//si)
		{
		$self->{'expression'} = '';
		$self->boolean();
		return $self if defined $self->{'errstr'};
		return $self if $self->{'expression'} eq '';

		my $fn = eval 'sub { my ($TABLE, $HASH) = @_; ' .  $self->{'expression'} . ' }';
		if ($@)
			{ $self->{'errstr'} = "Eval on where expression\n$self->{'expression'}\nfailed:\n$@"; }
		else
			{ $self->{'wherefn'} = $fn; }
		}
	$self;
	}


sub boolean
	{
	my $self = shift;
	local $_ = $self->{'string'};

	my $first = 1;
	my $quotes = 0;

	while (s/^\(\s*//)
		{ $quotes++; $self->{'expression'} .= ' ('; }

	$self->{'string'} = $_;
	while ($self->relation())
		{
		return $self if defined $self->{'errstr'};

		if ($self->{'string'} eq $_)	# nothing new found
			{
			if ($first)
				{
				$self->{'errstr'} = "No expression found";
				return $self;
				}
			last;
			}

		$first = 0;

		$_ = $self->{'string'};

		while ($quotes > 0 and s/^\)\s*//s)
			{ $quotes--; $self->{'expression'} .= ') '; }
		
		if (s/^(and|or)(?:\s+|(?=\())//si)
			{
			my $op = lc $1;
			$self->{'expression'} .= $op . ' ';
			}
		else
			{ last; }

		while (s/^\(\s*//)
			{ $quotes++; $self->{'expression'} .= ' ('; }

		$self->{'string'} = $_;
		}

	while ($quotes > 0 and s/^\)\s*//)
		{ $quotes--; $self->{'expression'} .= ') '; }

	$self->{'string'} = $_;
	if ($quotes > 0)
		{ $self->{'errstr'} = "Right bracket missing"; }

	$self;
	}

sub relation
	{
	my $self = shift;
	local $_ = $self->{'string'};

	if (s/^([\w]+)\s*//)
		{
		my $field = uc $1;
		push @{$self->{'usedfields'}}, $field;
		$self->{'expression'} .=
			qq!XBase::SQL::Expr->field('$field', \$TABLE, \$HASH) !;
		}
	else
		{ $self->{'errstr'} = "Field name not found"; return $self; }

	if (s/^(==?|<=|>=|<>|!=|<|>)\s*//)
		{
		my $op = $1;
		$op = '==' if $op eq '=';
		$self->{'expression'} .= $op . ' ';
		}
	else
		{
		$self->{'errstr'} = "Operator not found";
		$self->{'string'} = $_;
		return $self;
		}

	$self->{'string'} = $_;
	$self->arithmetic();
	}

sub arithmetic
	{
	my $self = shift;
	local $_ = $self->{'string'};

	my $quotes = 0;
	
	while (s/^\(\s*//s)
		{ $quotes++; $self->{'expression'} .= ' ('; }

	if (s/^(["'])((\\\\|\\\1|.)*?)\1//s)
		{
		my $string = $2;
		if ($1 eq '"')
			{ $string =~ s/'/\\'/gs; }
		$self->{'expression'} .= qq!XBase::SQL::Expr->string('$2') !;
		}
	elsif (s/^(-?(\d*\.)?\d+)//)
		{ $self->{'expression'} .= qq!XBase::SQL::Expr->number($1) !; }
	elsif (s/^([\w]+)//)
		{
		my $field = uc $1;
		push @{$self->{'usedfields'}}, $field;
		$self->{'expression'} .=
			qq!XBase::SQL::Expr->field('$field', \$TABLE, \$HASH) !;
		}
	else
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "No field name, string or number found";
		return $self;
		}

	s/^\s*//s;

	if (s!^([-+/%])\s*!!)
		{
		$self->{'expression'} .= $1 . ' ';
		$self->{'string'} = $_;
		$self->arithmetic();
		return $self if defined $self->{'errstr'};
		$_ = $self->{'string'};
		}

	while ($quotes > 0 and s/^\)\s*//)
		{ $quotes--; $self->{'expression'} .= ') '; }

	$self->{'string'} = $_;
	if ($quotes != 0)
		{ $self->{'errstr'} = "Right bracket missing"; }

	return $self;
	}

# #######################################
# Implementing methods in SQL expressions

package XBase::SQL::Expr;

use strict;

use overload
	'+'  => sub { XBase::SQL::Expr->number($_[0]->value + $_[1]->value); },
	'-'  => sub { my $a = $_[0]->value - $_[1]->value; $a = -$a if $_[2];
			XBase::SQL::Expr->number($a); },
	'/'  => sub { my $a = ( $_[2] ? $_[0]->value / $_[1]->value
				: $_[1]->value / $_[0]->value );
			XBase::SQL::Expr->number($a); },
	'%'  => sub { my $a = ( $_[2] ? $_[0]->value % $_[1]->value
				: $_[1]->value % $_[0]->value );
			XBase::SQL::Expr->number($a); },
	'<'  => \&less,
	'<=' => \&lesseq,
	'>'  => sub { $_[1]->less(@_[0, 2]); },
	'>=' => sub { $_[1]->lesseq(@_[0, 2]); },
	'!=' => \&notequal,
	'<>' => \&notequal,
	'==' => sub { my $a = shift->notequal(@_); return ( $a ? 0 : 1); },
	'""' => sub { ref shift; },
	;

sub new
	{ bless {}, shift; }
sub value
	{ shift->{'value'}; }

sub field
	{
	my ($class, $field, $table, $values) = @_;
	my $self = $class->new;
	$self->{'field'} = $field;
	$self->{'value'} = $values->{$field};

	my $type = $table->field_type($field);
	if ($type eq 'N')	{ $self->{'number'} = 1; }
	else			{ $self->{'string'} = 1; }
	
	$self;
	}
sub string
	{
	my $self = shift->new;
	$self->{'value'} = shift;
	$self->{'string'} = 1;
	$self;
	}
sub number
	{
	my $self = shift->new;
	$self->{'value'} = shift;
	$self->{'number'} = 1;
	$self;
	}

#
# Function working on Expr objects
#
sub less
	{
	my ($self, $other, $reverse) = @_;
	my $answer;
	if (defined $self->{'string'} or defined $other->{'string'})
		{ $answer = ($self->value lt $other->value); }
	else
		{ $answer = ($self->value < $other->value); }
	return -$answer if $reverse;
	$answer;
	}
sub lesseq
	{
	my ($self, $other, $reverse) = @_;
	my $answer;
	if (defined $self->{'string'} or defined $other->{'string'})
		{ $answer = ($self->value le $other->value); }
	else
		{ $answer = ($self->value <= $other->value); }
	return -$answer if $reverse;
	$answer;
	}
sub notequal
	{
	my ($self, $other) = @_;
	if (defined $self->{'string'} or defined $other->{'string'})
		{ ($self->value ne $other->value); }
	else
		{ ($self->value != $other->value); }
	}


1;

