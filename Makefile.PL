
eval 'use XBase';
if (not $@)
	{
	if (eval { $XBase::VERSION < 0.063 } )
		{
		print <<EOF;
	I can see you had the XBase module installed before. We have
	a small support for ndx indexes now -- you might want to check
	eg/use_index file to see how to use them or how to help to
	make it work really well in the future.
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
    ($] >= 5.005 ? (
	'AUTHOR'	=> 'Jan Pazdziora (adelton@fi.muni.cz)',
	'ABSTRACT'	=> 'Works with XBase (dbf) files, includes DBI support',
		) : ()),
	'PL_FILES'	=> { 'bin/dbfdump.PL' => 'bin/dbfdump' },
	'EXE_FILES'	=> [ 'bin/dbfdump' ],
        'dist'		=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
		POSTOP => 'mv $(DISTNAME)-$(VERSION).tar.gz ../' },
	'clean'		=> { FILES => 'bin/dbfdump t/newtable.dbf t/newtable.dbt t/write.dbf t/write.dbt'},	
	);

