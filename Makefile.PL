
eval 'use XBase';
if (not $@)
	{
	if (eval { $XBase::VERSION <= 0.039 } )
		{
		print <<EOF;
	I can see you had the XBase module installed before. There have
	been many changes since version $XBase::VERSION so you might want
	to check the Changes file and also the documentation for what is
	new. The DBD driver has been extended, there is a new method
	get_all_records, dump_records is customizable, the distribution
	includes new script dbfdump.
EOF
		}
	elsif (eval { $XBase::VERSION <= 0.0597 } )
		{
		print <<EOF;
	I can see you had XBase module installed before. There have been
	quite a few changes since version $XBase::VERSION so you might want
	to check the Changes file and also the documentation for what
	is new. There is a new method get_all_records and dump_records was
	made customizable and there is a script dbfdump, to name a few.
EOF
		}
	}

eval 'use DBI';
if ($@ ne '')
	{
	print <<EOF;
	You do not seem to have DBI installed, so you will not be able
	to use DBD::XBase (but XBase should still be running fine).
EOF
	}

use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'		=> 'XBase',
	'DISTNAME'	=> 'DBD-XBase',
	'VERSION_FROM'	=> 'lib/XBase.pm',
	'PL_FILES'	=> { 'bin/dbfdump.PL' => 'bin/dbfdump' },
	'EXE_FILES'	=> [ 'bin/dbfdump' ],
        'dist'		=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
		POSTOP => 'mv $(DISTNAME)-$(VERSION).tar.gz ../' },
	'clean'		=> { FILES => 'bin/dbfdump'},	
	);

