
package XBase::SQL;

use strict;
use vars qw( $VERSION );
$VERSION = '0.0343';

sub parse_command
	{
	my $class = shift;
	local $_ = shift;

	my $self = bless {}, $class;
	my $errstr = undef;

	s/^\s+//;

	my $command;
	if (s/^(select|delete|update|insert)\s+//s)
		{
		$self->{'string'} = $_;
		$self->{'command'} = $+;
		my $exec = 'parse_' . $self->{'command'};
		$self->$exec();
		}
	else
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "No supported SQL command found";
		}
	if (defined $self->{'errstr'} and defined $self->{'string'})
		{
		$self->{'errstr'} .= " at '" .
			substr($self->{'string'}, 0, 16) . "'";
		}
	$self;
	}


sub parse_select
	{
	my $self = shift;
	local $_ = $self->{'string'};

	if (s/^\*\s+|\(\s*\*\s*\)\s*//s)
		{ $self->{'selectall'} = 1; }
	elsif (s/^([\w]+(?:\s*,\s*[\w]+)*)\s+//s)
		{
		$self->{'selectfields'} = [ split /\s*,\s*/, $+ ];
		}
	else
		{ $self->{'errstr'} = "No column specification found"; return $self; }

	unless (s/^from\s+//si)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "From specification missing";
		return $self;
		}

	unless (s/^([\w.]+)(?:$|\s+)//s)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Table name expected";
		return $self;
		}

	$self->{'table'} = $+;
	$self->{'string'} = $_;

	return $self;
	}

sub parse_delete
	{
	my $self = shift;
	local $_ = $self->{'string'};
	unless (s/^from\s+//si)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "From specification missing";
		return $self;
		}

	unless (s/^([\w.]+)(?:$|\s+)//s)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Table name expected";
		return $self;
		}

	$self->{'table'} = $+;
	$self->{'string'} = $_;

	return $self;
	}

sub parse_insert
	{
	my $self = shift;
	local $_ = $self->{'string'};
	unless (s/^into\s+//si)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Into specification missing";
		return $self;
		}

	unless (s/^([\w.]+)(?:$|\s+)//s)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Table name expected";
		return $self;
		}
	
	$self->{'table'} = $+;

	if (s/^\(([\w]+(?:\s*,\s*[\w]+)*)\s*\)//s)
		{ $self->{'insertfields'} = [ split /\s*,\s*/, $+ ]; }


	unless (s/^values\s+//si)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Values specification missing";
		return $self;
		}


	$self->{'string'} = $_;
	return $self;
	}


my %STRINGOP = ( '=' => 'eq', '<' => 'lt', '>' => 'gt', '<=' => 'le',
                                '>=' => 'ge', '<>' => 'ne', '!=' => 'ne' );
my %NUMOP = ( '=' => '==' );

sub parse_conditions
	{
	my $self = shift;
	if ($self->{'command'} eq 'select')
		{
		if (defined $self->{'selectall'})
			{
			$self->{'selectfields'} = [ $self->{'xbase'}->field_names() ];
			}
		elsif (defined $self->{'selectfields'})
			{
			my $field;
			for $field (@{$self->{'selectfields'}})
				{
				unless (defined $self->{'xbase'}->field_name_to_num(uc $field))
					{
					$self->{'errstr'} = "Column $field does not exist in table $self->{'table'}";
					return;
					}
				$field = uc $field;
				}
			}
		else { die "Huh -- no fields -- fatal problem!"; }
		}
	elsif ($self->{'command'} eq 'insert')
		{

		}

	if ($self->{'string'} =~ s/^where(\s+|(?=\())//si)
		{
		$self->parse_boolean();
		return $self if defined $self->{'errstr'};
		$self->{'whereexpression'} = $self->{'expression'};
		delete $self->{'expression'};

		my $command = '';
		my $field; 
		for $field (@{$self->{'whereexpression'}})
			{       
			if (ref $field) 
				{       
				if ($field->[0] eq 'op')
					{
					if ($field->[2] eq 's') 
						{ $command .= ' ' . $STRINGOP{$field->[1]} . ' '; }
					elsif ($field->[1] eq '=')
						{ $command .= ' == '; } 
					else
						{ $command .= ' ' . $field->[1] . ' '; }
					}
				elsif ($field->[0] eq 'field')
					{ $command .= q! $HASH->{'! . (uc $field->[1]) . q!'} !; }
				elsif ($field->[0] eq 'string' or $field->[0] eq 'number' or $field->[0] eq 'arop')
					{ $command .= ' ' . $field->[1] . ' '; }
				}               
			else            
				{
				if ($field eq 'left')
					{ $command .= ' ('; }
				if ($field eq 'right')
					{ $command .= ') '; }
				if ($field eq 'and')
					{ $command .= ' and '; }
				if ($field eq 'or')
					{ $command .= ' or '; }
				}               
			}               
		$command = "sub { my \$HASH = shift; $command; }";
		### print STDERR "Where expression: $command\n";
		my $fn = eval $command;
		if ($@)
			{
			$self->{'errstr'} = "Eval on where expression $command failed: $@";
			return $self;
			}
		$self->{'wherefn'} = $fn;
		}

	if (not defined $self->{'errstr'} and
		$self->{'string'} =~ s/^order\s+by(\s+|(?=\())//si)
		{
		$self->parse_order_by();
		}
        if (not defined $self->{'errstr'} and $self->{'string'} ne '')
		{
		$self->{'errstr'} = ( /^\)/ ?
			"Extra right bracket found" :
			"Unknown characters in SQL command");
		}
	if (defined $self->{'errstr'} and defined $self->{'string'})
		{
		$self->{'errstr'} .= " at '" .
			substr($self->{'string'}, 0, 16) . "'";
		}
	$self;
	}

sub parse_boolean
	{
	my $self = shift;
	local $_ = $self->{'string'};

	my $first = 1;
	my $quotes = 0;

	while (s/^\(\s*//)
		{ $quotes++; push @{$self->{'expression'}}, 'left'; }

	$self->{'string'} = $_;
	while ($self->parse_relation())
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
			{ $quotes--; push @{$self->{'expression'}}, 'right'; }
		
		if (s/^(and|or)(?:\s+|(?=\())//si)
			{ push @{$self->{'expression'}}, $1; }
		else
			{ last; }

		while (s/^\(\s*//)
			{ $quotes++; push @{$self->{'expression'}}, 'left';}

		$self->{'string'} = $_;
		}

	while ($quotes > 0 and s/^\)\s*//)
		{ $quotes--; push @{$self->{'expression'}}, 'right'; }

	$self->{'string'} = $_;
	if ($quotes > 0)
		{ $self->{'errstr'} = "Right bracket missing"; }

	$self;
	}

sub parse_relation
	{
	my $self = shift;
	local $_ = $self->{'string'};

	if (s/^([\w]+)\s*//)
		{
		unless (defined $self->{'xbase'}->field_name_to_num(uc $+))
			{
			$self->{'errstr'} = "Column $+ does not exist in table $self->{'table'}";
			return;
			}
		push @{$self->{'expression'}}, [ 'field', $+ ];
		}
	else
		{ $self->{'errstr'} = "Field name not found"; return $self; }

	my $type = $self->{'xbase'}->field_types($self->{'xbase'}->field_name_to_num($+));
	$type = (($type =~ /^[CML]$/) ? 's' : 'd');

	my $operator;
	unless (s/^(==?|<=|>=|<>|!=|<|>)\s*//)
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "Operator not found";
		return $self;
		}

	push @{$self->{'expression'}}, [ 'op', $+, $type ];

	$self->{'string'} = $_;
	$self->parse_arithmetic();
	}

sub parse_arithmetic
	{
	my $self = shift;
	local $_ = $self->{'string'};

	my $prevop = $#{$self->{'expression'}};

	my $quotes = 0;
	
	while (s/^\(\s*//s)
		{ $quotes++; push @{$self->{'expression'}}, 'left'; }

	if (s/^(["'])((\\\\|\\\1|.)*?)\1//s)
		{
		my $string = $2;
		if ($1 eq '"')
			{ $string =~ s/'/\\'/gs; }
		push @{$self->{'expression'}}, [ 'string', "'$string'" ];
		if (ref $self->{'expression'}[$prevop] and
				$self->{'expression'}[$prevop][0] eq 'op')
			{ $self->{'expression'}[$prevop][2] = 's' }
		}
	elsif (s/^(-?(\d*\.)?\d+)//)
		{
		push @{$self->{'expression'}}, [ 'number', $1 ];
		}
	elsif (s/^[\w]+//)
		{
		push @{$self->{'expression'}}, [ 'field', $& ];
		}
	else
		{
		$self->{'string'} = $_;
		$self->{'errstr'} = "No field name, string or number found";
		return $self;
		}

	s/^\s*//s;

	if (s!^[-+/%]!!)
		{
		push @{$self->{'expression'}}, [ 'arop', $& ];
		s/^\s*//s;
		$self->{'string'} = $_;
		$self->parse_arithmetic();
		return $self if defined $self->{'errstr'};
		$_ = $self->{'string'};
		}

	while ($quotes > 0 and s/^\)\s*//)
		{ $quotes--; push @{$self->{'expression'}}, 'right'; }

	$self->{'string'} = $_;
	if ($quotes != 0)
		{ $self->{'errstr'} = "Right bracket missing"; }

	return $self;
	}


1;
