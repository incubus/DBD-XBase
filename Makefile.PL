
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME' =>	'XbaseTable',
	'DISTNAME' =>	'DBD-Xbase',
	'VERSION_FROM' =>	'XbaseTable.pm',
        'dist' =>	{ COMPRESS => 'gzip -9f', SUFFIX => 'gz',
			POSTOP => 'mv $(DISTNAME)-$(VERSION).tar.gz ../' },
	);
