	
eval 'use XBase';
if (not $@ and eval { $XBase::VERSION < 0.0342 } )
	{
	print <<EOF;
	I can see you had XBase module installed before. There have been
	many changes since version $XBase::VERSION but the most important
	is that \$XBase::errstr is no longer supported. Please, use
	XBase->errstr() instead in your scripts. Thank you.
EOF
	}

eval 'use DBI';
if ($@ ne '')
	{
	print <<EOF;
	You do not seem to have DBI installed, so you want be able to
	use DBD::XBase (it's not ready yet, so don't worry about it now ;-).
EOF
	}

use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME' =>	'XBase',
	'DISTNAME' =>	'DBD-XBase',
	'VERSION_FROM' =>	'lib/XBase.pm',
        'dist' =>	{ COMPRESS => 'gzip -9f', SUFFIX => 'gz',
			POSTOP => 'mv $(DISTNAME)-$(VERSION).tar.gz ../' },
	);
