
# ####################
# Parsing SQL commands

package XBase::SQL::Expr;
package XBase::SQL;

### BEGIN { eval { use locale; }; }

use strict;
use vars qw( $VERSION $DEBUG %COMMANDS );

$VERSION = '0.058';
$DEBUG = 0;

# ##################
# Regexp definitions


my %TYPES = ( 'char' => 'C', 'num' => 'N', 'numeric' => 'N',
		'boolean' => 'L', 'blob' => 'M', 'memo' => 'M',
		'float' => 'F', 'date' => 'D' );

%COMMANDS = (
	'COMMANDS' => 	' SELECT | INSERT | DELETE | UPDATE | CREATE ',
	'SELECT' =>	' select SELECTFIELDS from TABLE WHERE ? ',
	'INSERT' =>	q' insert into TABLE INSERTFIELDS ? values
						\( INSERTCONSTANTS \) ',
	'DELETE' =>	' delete from TABLE WHERE ? ',
	'UPDATE' =>	' update TABLE set SETCOLUMNS WHERE ? ',
	'CREATE' =>	q' create table TABLE \( COLUMNDEF ( , COLUMNDEF ) * \) ',

	'TABLE' =>	q'\w+',
	'FIELDNAME' =>	q'[a-z]+',
	'EXPFIELDNAME' => 'FIELDNAME',
	'SELECTFIELDS' =>	'SELECTALL | FIELDNAME ( , FIELDNAME ) *',
	'SELECTALL' =>	q'\*',	
	'WHERE' =>	'where WHEREEXPR',
	'WHEREEXPR' =>	'BOOLEAN',
	'BOOLEAN' =>	q'\( BOOLEAN \) | RELATION ( ( and | or ) BOOLEAN ) *',
	'RELATION' =>	'EXPFIELDNAME RELOP ARITHMETIC',
	'RELOP' => [ qw{ == | = | <= | >= | <> | != | < | > } ],
	
	'ARITHMETIC' => [ qw{ \( ARITHMETIC \)
		| ( NUMBER | STRING | EXPFIELDNAME ) ( ( \+ | \- | \* | \/ | \% ) ARITHMETIC ) ? } ],
	'NUMBER' => q'-?\d*\.?\d+',
	'STRING' => [ qw{ STRINGDBL | STRINGSGL } ] ,
	'STRINGDBL' => q' \\" (\\\\\\\\|\\\\"|[^\\"])* \\" ',
	'STRINGSGL' => q! \\' (\\\\\\\\|\\\\'|[^\\'])* \\' !,
	'ORDER' => [ qw{ order by FIELDNAME } ],
	'INSERTCONSTANTS' => [ qw{ CONSTANT ( }, ',', qw{ INSERTCONSTANTS ) * } ],
	'CONSTANT' => [ qw{ NUMBER | STRING } ],
	'INSERTFIELDS' =>	'\( FIELDNAME ( , FIELDNAME ) * \)',
	
	'SETCOLUMNS' => 'SETCOLUMN ( , SETCOLUMN ) *',
	'SETCOLUMN' => 'FIELDNAME = ARITHMETIC',
	
	'TYPELENGTH' => q'\d+',
	'TYPEDEC' => q'\d+',
	'COLUMNDEF' => 'FIELDNAME FIELDTYPE',
	'FIELDTYPE' => 'TYPECHAR | TYPENUM | TYPEBOOLEAN | TYPEMEMO | TYPEDATE',
	'TYPECHAR' => q'char ( \( TYPELENGTH \) ) ?',
	'TYPENUM' => q'( num | numeric | float ) ( \( TYPELENGTH ( , TYPEDEC ) ? \) ) ?',
	'TYPEBOOLEAN' => q'boolean | logical',
	'TYPEMEMO' => q'memo | blob',
	'TYPEDATE' => q'date',
	);

my %STORE = (
	'SELECT' => sub { shift->{'command'} = 'select'; },
	'SELECTALL' => 'selectall',
	'SELECTFIELDS FIELDNAME' => 'selectfields',
	'SELECT TABLE' => 'table',

	'INSERT' => sub { shift->{'command'} = 'insert'; },
	'INSERT TABLE' => 'inserttable',
	'INSERTCONSTANTS CONSTANT' => sub { push @{shift->{'insertvalues'}},
		(shift) . '->value()'; },
	'INSERTFIELDS FIELDNAME' => 'insertfields',

	'DELETE' => sub { shift->{'command'} = 'delete'; },
	'DELETE TABLE' => 'table',

	'INSERT' => sub { shift->{'command'} = 'insert'; },
	'INSERT TABLE' => 'table',

	'UPDATE' => sub { shift->{'command'} = 'update'; },
	'UPDATE TABLE' => 'table',
	'UPDATE SETCOLUMN FIELDNAME' => 'updatefields',
	'UPDATE SETCOLUMN ARITHMETIC' => sub { my ($self, @expr) = @_;
		my $line = "sub { my (\$TABLE, \$HASH) = \@_; my \$e = XBase::SQL::Expr->other( @expr ); \$e->value(); }";
		### print "Evaling $line\n";
		my $fn = eval $line;
		if ($@) { push @{$self->{'updaterror'}}, $@; }
		else { push @{$self->{'updaterror'}}, undef;
			push @{$self->{'updatevalues'}}, $fn; }},

	'CREATE' => sub { shift->{'command'} = 'create'; },
	'CREATE TABLE' => 'table',
	'CREATE COLUMNDEF FIELDNAME' => 'createfields',
	'CREATE COLUMNDEF FIELDTYPE' => sub { my $self = shift;
		my ($type, $len, $dec) = @_[0, 2, 4];
		push @{$self->{'createtypes'}}, $TYPES{lc $type};
		push @{$self->{'createlengths'}}, $len;
		push @{$self->{'createdecimals'}}, $dec; },

	'WHEREEXPR' => sub { my ($self, $expr) = @_;
		### print "Evaling $expr\n";
		my $fn = eval "sub { my (\$TABLE, \$HASH) = \@_; $expr; }";
		if ($@) { $self->{'whereerror'} = $@; }
		else { $self->{'wherefn'} = $fn; }
		},
	);

my %SIMPLIFY = (
	'STRING' => sub { my $e = (get_strings(@_))[1];
				$e =~ s/'/\\'/g;
					"XBase::SQL::Expr->string('$e')"; },
	'NUMBER' => sub { my $e = (get_strings(@_))[0];
					"XBase::SQL::Expr->number('\Q$e\E')"; },
	'EXPFIELDNAME' => sub { my $e = (get_strings(@_))[0];
					"XBase::SQL::Expr->field('$e', \$TABLE, \$HASH)"; },
	'FIELDNAME' => sub { uc ((get_strings(@_))[0]); },
	'WHEREEXPR' => sub { join ' ', get_strings(@_); },
	'RELOP' => sub { my $e = (get_strings(@_))[0];
			if ($e eq '=') { $e = '=='; }
			elsif ($e eq '<>') { $e = '!=';} $e; },
	);

my %ERRORS = (
	'TABLE' => 'Table name',
	'RELATION' => 'Relation',
	'ARITHMETIC' => 'Arithmetic expression',
	'from' => 'From specification',
	'into' => 'Into specification',
	'values' => 'Values specification',
	'\\(' => 'Left paren',
	'\\)' => 'Right paren',
	'\\*' => 'Star',
	'\\"' => 'Double quote',
	"\\'" => 'Single quote',
	'STRING' => 'String',
	'SELECTFIELDS' => 'Columns to select',
	);

sub parse
	{
	my ($class, $string) = @_;
	my $self = bless {}, $class;

	my ($srest, $error, $errstr, @result) = match($string, 'COMMANDS');
	$srest =~ s/^\s+//s;

	if ($srest ne '' and not $error)
		{ $error = 1; $errstr = 'Extra characters in SQL command'; }
	if ($error)
		{
		if (not defined $errstr)
			{ $errstr = 'Error in SQL command'; }
		substr($srest, 40) = '...' if length $srest > 44;
		$self->{'errstr'} = "$errstr near `$srest'";
		### print "$self->{'errstr'}\n";
		}
	else
		{
		### print_result(\@result);
		$self->store_results(\@result, \%STORE);
		### use Data::Dumper; print Dumper $self;
		}
	$self;
	}
sub store_results
	{
	my ($self, $result, $store) = @_;

	my $i = 0;
	while ($i < @$result)
		{
		my ($regexp, $match) = @{$result}[$i, $i + 1];
		my %nstore = %$store;

		my ($tag, $value);
		while (($tag, $value) = each %$store)
			{
			my $oldtag = $tag;
			next unless $tag =~ s/^\Q$regexp\E($|\s+)//;

			delete $nstore{$oldtag};
			if ($tag eq '')
				{
				my @result;
				if (ref $match) { @result = get_strings($match); }
				else { @result = $match; }
				### print "Storing @result to $value\n";
				if (ref $value eq 'CODE')
					{ &{$value}($self, @result); }
				else
					{ push @{$self->{$value}}, @result; }
				}
			else { $nstore{$tag} = $value; }
			}
	
		if (ref $match)
			{ $self->store_results($match, \%nstore); }
		$i += 2;
		}
	}
sub get_strings
	{
	my @strings = @_;
	if (@strings == 1 and ref $strings[0])
		{ @strings = @{$strings[0]}; }
	my @result;	my $i = 1;
	while ($i < @strings)
		{
		if (ref $strings[$i])
			{ push @result, get_strings($strings[$i]); }
		else
			{ push @result, $strings[$i]; }
		$i += 2;
		}
	@result;
	}
sub print_result
	{
	my $result = shift;
	my @result = @$result;
	my @before = @_;
	my $i = 0;
	while ($i < @result)
		{
		my ($regexp, $string) = @result[$i, $i + 1];
		if (ref $string)
			{ print_result($string, @before, $regexp); }
		else
			{ print "$string:\t @before $regexp\n"; }
		$i += 2;
		}
	}
sub match
	{
	my $string = shift;
	my @regexps = @_;

	my $origstring = $string;

	my $title;

	if (@regexps == 1 and defined $COMMANDS{$regexps[0]})
		{
		$title = $regexps[0];
		my $c = $COMMANDS{$regexps[0]};
		@regexps = expand( ( ref $c ) ? @$c :
					grep { $_ ne '' } split /\s+/, $c);
		}

	my $modif;
	if (@regexps and $regexps[0] eq '?' or $regexps[0] eq '*')
		{ $modif = shift @regexps; }

### { local $^W = 0; print "Match: $title: $modif; `@regexps' on string `$string'\n"; }

	my @result;
	my $i = 0;
	while ($i < @regexps)
		{
		my $regexp = $regexps[$i];
		my ($error, $errstr, @r);
		if (ref $regexp)
			{ ($string, $error, $errstr, @r) = match($string, @$regexp); }
		elsif ($regexp eq '|')
			{ $i = $#regexps; next; }
		elsif (defined $COMMANDS{$regexp})
			{ ($string, $error, $errstr, @r) = match($string, $regexp); }
		elsif ($string =~ s/^\s*?($regexp)($|\b|(?=\W))//si)
			{ @r = $1; }
		else
			{ $error = 1; }

		if (defined $error)
			{
			if ($origstring eq $string)
				{
				while ($i < @regexps)
					{ last if $regexps[$i] eq '|'; $i++; }
				next if $i < @regexps;
				last if defined $modif;
				}
	
			if (not defined $errstr)
				{
				if (defined $ERRORS{$regexp})
					{ $errstr = $ERRORS{$regexp}; }
				elsif (defined $title and defined $ERRORS{$title})
					{ $errstr = $ERRORS{$title}; }
				$errstr .= ' expected' if defined $errstr;
				}

			return ($string, 1, $errstr, @result);
			}
	
		if (ref $regexp)
			{ push @result, @r; }
		elsif (@r > 1)
			{ push @result, $regexp, [ @r ]; }
		else
			{ push @result, $regexp, $r[0]; }
		}
	continue
		{
		$i++;
		if (defined $modif and $modif eq '*' and $i >= @regexps)
			{ $origstring = $string; $i = 0; }
		}

	if (defined $title and defined $SIMPLIFY{$title})
		{
		my $m = $SIMPLIFY{$title};
		@result = (( ref $m eq 'CODE' ) ? &{$m}(\@result) : $m);
		}
	return ($string, undef, undef, @result);
	}

sub expand
	{
	my @result;
	my $i = 0;
	while ($i < @_)
		{
		my $t = $_[$i];
		if ($t eq '(')
			{
			$i++;
			my $begin = $i;
			my $nest = 1;
			while ($i < @_ and $nest)
				{
				my $t = $_[$i];
				if ($t eq '(') { $nest++; }
				elsif ($t eq ')') { $nest--; }
				$i++;
				}
			$i--;
			push @result, [ expand(@_[$begin .. $i - 1]) ];	
			}
		elsif ($t eq '?' or $t eq '*')
			{
			my $prev = pop @result;
			push @result, [ $t, ( ref $prev ? @$prev : $prev ) ];
			}
		else
			{ push @result, $t; }
		$i++;
		}
	@result;
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
sub other
	{
	my $class = shift;
	my $other = shift;
	$other;
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

