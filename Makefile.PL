
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME' =>	'XBase',
	'DISTNAME' =>	'DBD-Xbase',
	'VERSION_FROM' =>	'XBase.pm',
        'dist' =>	{ COMPRESS => 'gzip -9f', SUFFIX => 'gz',
			POSTOP => 'mv $(DISTNAME)-$(VERSION).tar.gz ../' },
	);
