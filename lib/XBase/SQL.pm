
package XBase::SQL;

use strict;
use vars qw( $VERSION );
$VERSION = '0.0343';

my @COMMANDS = qw( select delete update insert );
my $COMMANDS = '(' . join("|", @COMMANDS) . ')';

sub new
	{
	my $class = shift;
	my $string = shift;

	my $self = bless {}, $class;
	my $errstr = undef;

	$string =~ /^\s+/;
	if ($string =~ /^$COMMANDS\s+/i)
		{
		my $command = $+;
		my $parse = 'parse_' . $command;

		$self->{command} = $command;
		$self->{string} = $';
		$self->$parse();
		}
	else
		{ $self->{errstr} = "No known SQL command found"; }
	
	if (defined $self->{errstr})
		{
		my $string = $self->{string};
		if ($string ne '')
			{
			$string = substr $string, 0, 16;
			$self->{errstr} .= " at '$string'";
			}
		$self->{errstr} .= "\n";
		}
	$self;	
	}


sub parse_select
	{
	my $self = shift;
	my $string = $self->{string};

	if ($string =~ s/^(\*\s+|\(\s*\*\s*\))\s*//)
		{ $self->{selectall} = 1; }
	elsif ($string =~ s/^\((\w+(\s*,\s*\w+)*)\s*\)\s+|(\w+(,\s*\w+)*)\s+//)
		{
		my $fields = $1;
		my @fields = split /\s*,\s*/, $fields;
		$self->{fields} = [ @fields ];
		}
	else
		{
		$self->{errstr} = "No column specification found";
		return $self;
		}

	if ($string =~ s/^from\s+//i)
		{
		if ($string =~ s/^(\w+)($|\s+)//)
			{ $self->{table} = $1; }
		else
			{
			$self->{errstr} = "Table name expected";
			$self->{string} = $string;
			return $self;
			}
		}
	else
		{
		$self->{errstr} = "From specification missing";
		$self->{string} = $string;
		return $self;
		}

	$self->{string} = $string;

	if ($string =~ s/^where\s+//i)
		{
		$self->{string} = $string;
		$self->parse_expression();
		return $self if defined $self->{errstr};
		$string = $self->{string};
		}
	
	if ($string =~ s/^order\s+by\s+//i)
		{
		$self->{string} = $string;
		$self->parse_order_by();
		return $self if defined $self->{errstr};
		$string = $self->{string};
		}

	if ($string ne '')
		{
		$self->{errstr} = "Unknown pieces in SQL command";
		}
	
	return $self;
	}
sub parse_insert
	{
	my $self = shift;
	my $string = $self->{string};
	if ($string !~ s/^into\s+//i)
		{
		$self->{errstr} = "Into specification missing";
		return $self;
		}

	if ($string =~ s/^(\w+)\s+//)
		{ $self->{table} = $1; }
	else
		{
		$self->{errstr} = "Table name expected";
		return $self;
		}

	if ($string =~ s/^(\w+(,\s*\w+)*)\s+|\((\w+(\s*,\s*\w+)*)\s*\)\s+//)
		{
		my $fields = $1;
		my @fields = split /\s*,\s*/, $fields;
		$self->{fields} = [ @fields ];
		}
	
	$self->{string} = $string;
	if ($string !~ s/^values\s+//i)
		{
		$self->{errstr} = "Values specification missing";
		return $self;
		}

	$self->{string} = $string;
	if ($string =~ s/^\((\w+(\s*,\s*\w+)*)\s*\)($|\s+)//)
		{
		my $values = $1;
		my @values = split /\s*,\s*/, $values;
		if (defined $self->{fields} and
				scalar @values != scalar @{$self->{fields}})
			{
			$self->{errstr} = "Number of values doesn't match number of columns";
			return $self;
			}
		$self->{'values'} = [ @values ];
		}
	else
		{
		$self->{errstr} = "Values missing";
		}
	$self->{string} = $string;
	return $self;
	}

sub parse_delete
	{
	my $self = shift;
	my $string = $self->{string};
	if ($string !~ s/^from\s+//i)
		{
		$self->{errstr} = "From specification missing";
		return $self;
		}

	if ($string =~ s/^(\w+)($|\s+)//)
		{ $self->{table} = $1; }
	else
		{
		$self->{errstr} = "Table name expected";
		return $self;
		}

	if ($string =~ s/^where\s+//i)
		{
		$self->{string} = $string;
		$self->parse_expression();
		return $self if defined $self->{errstr};
		$string = $self->{string};
		}
	
	if ($string ne '')
		{
		$self->{errstr} = "Unknown pieces in SQL command";
		}
	
	return $self;
	}

sub parse_update
	{
	my $self = shift;
	my $string = $self->{string};

	if ($string =~ s/^(\w+)($|\s+)//)
		{ $self->{table} = $1; }
	else
		{
		$self->{errstr} = "Table name expected";
		return $self;
		}

	if ($string !~ s/^set\s+//i)
		{
		$self->{errstr} = "Set specification missing";
		return $self;
		}

	if ($string =~ s/^(\w+\s*=\s*\w+(\s*,\s*\w+\s*=\s*\w+)*)($|\s+)//)
		{
		my $sets = $1;
		my @sets = split /\s*,\*/, $sets;
		$self->{set} = [ @sets ];
		}
	else
		{
		$self->{errstr} = "Assignments missing";
		return $self;
		}
	
	if ($string =~ s/^where\s+//i)
		{
		$self->{string} = $string;
		$self->parse_expression();
		return $self if defined $self->{errstr};
		$string = $self->{string};
		}
	
	if (defined $string and $string ne '')
		{
		$self->{errstr} = "Unknown pieces in SQL command";
		}
	
	return $self;
	}

sub parse_expression
	{
	my $self = shift;
	my $string = $self->{string};



	}
sub parse_relation
	{
	my $self = shift;
	my $string = $self->{string};

	$string =~ s/^\s+//;

	my $field1;
	if ($string =~ s/^(\w+)\s*//)
		{ $field1 = $+; }
	else
		{ $self->{errstr} = "Field name not found"; }

	my $operator;
	if ($string =~ s/=|<=|>=|<>|!=|<|>|=~//)
		{ $operator = $&; }
	else
		{
		$self->{string} = $string;
		$self->{errstr} = "Operator not found";
		return $self;
		}


	$self->parse_string_value();
	my $left_value;
	if (defined $self->{string_value})
		{
		$left_value = $self->{string_value};
		delete $self->{string_value};
		}
	elsif ($string =~ s/^[\w.-]+//)
		{
		$left_value = $&;
		}
	else
		{
		$self->{errstr} = "No valid expression found";
		return;
		}

	my $op;
	if ($string =~ s/=|<=|>=|<>|!=|<|>//)
		{ $op = $&; }
	else
		{
		$self->{string} = $string;
		$self->{errstr} = "Operand not found";
		}

	$self->parse_string_value();
	my $right_value;
	if (defined $self->{string_value})
		{
		$right_value = $self->{string_value};
		delete $self->{string_value};
		}
	elsif ($string =~ s/^[\w.-]+//)
		{ $right_value = $&; }
	else
		{
		$self->{errstr} = "No valid expression found";
		return;
		}

	$self->{where} = [ $left_value, $op, $right_value ];
	$self;
	}

sub parse_order_by
	{
	}

sub parse_string_value
	{
	my $self = shift;
	my $string = $self->{string};

	if ($string =~ s/^(["'])(\\\\|\\\1|.)*?\1//)
		{
		$self->{string} = $string;
		$self->{string_value} = $&;
		}
	$self;
	}


1;
