
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME' =>	'XBase',
	'DISTNAME' =>	'DBD-XBase',
	'VERSION_FROM' =>	'lib/XBase.pm',
        'dist' =>	{ COMPRESS => 'gzip -9f', SUFFIX => 'gz',
			POSTOP => 'mv $(DISTNAME)-$(VERSION).tar.gz ../' },
	);
