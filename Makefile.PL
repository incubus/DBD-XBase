	
eval 'use XBase';
if (not @_ and eval { $XBase::VERSION < 0.0342 } )
	{
	print <<EOF;
	I can see you had installed XBase module before. There have been
	many changes since version $XBase::VERSION but the most important
	is that \$XBase::errstr is no longer supported. Please, use
	XBase->errstr() instead in your scripts. Thank you.
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
