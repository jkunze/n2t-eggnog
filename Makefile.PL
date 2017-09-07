use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $pm = {
    	'lib/File/Egg.pm' => 'blib/lib/File/Egg.pm',
    	'lib/File/Nog.pm' => 'blib/lib/File/Nog.pm',
    	'lib/File/Binder.pm' => 'blib/lib/File/Binder.pm',
    	'lib/File/Minder.pm' => 'blib/lib/File/Minder.pm',
    	'lib/File/Cmdline.pm' => 'blib/lib/File/Cmdline.pm',
    	'lib/File/Session.pm' => 'blib/lib/File/Session.pm',
    	'lib/File/Help.pm' => 'blib/lib/File/Help.pm',
    	'lib/File/Temper.pm' => 'blib/lib/File/Temper.pm',
    	'lib/File/RUU.pm' => 'blib/lib/File/RUU.pm',
    	'lib/File/Rlog.pm' => 'blib/lib/File/Rlog.pm',
    	'lib/File/ApacheTester.pm' => 'blib/lib/File/ApacheTester.pm',
    	'lib/File/ValueTester.pm' => 'blib/lib/File/ValueTester.pm',
    	'lib/File/StubResolver.pm' => 'blib/lib/File/StubResolver.pm',
};
-e 'lib/File/Resolver.pm' and
	$pm->{'lib/File/Resolver.pm'} = 'blib/lib/File/Resolver.pm';

WriteMakefile(
    EXE_FILES	   => [ 'egg', 'nog', 'anvl2egg', 'orlogs' ],
    NAME	   => 'File::EggNog',
    AUTHOR	   => 'John A. Kunze <jak@ucop.edu>',
    VERSION_FROM   => 'VERSION',
    ABSTRACT	   => 'commands and routines to make and resolve identifiers',
   ($ExtUtils::MakeMaker::VERSION ge 6.3002
     ? ('LICENSE'  => 'BSD')
     : ()),
    PM			=> $pm,
    PREREQ_PM		=> {
	'Fcntl'			=> '0',
	'BerkeleyDB'		=> '0',
	'DB_File'		=> '0',
	'Data::UUID'		=> '0',
	'File::OM'		=> '1.00',
	'File::Find'		=> '0',
	'File::Path'		=> '0',
	'File::Spec'		=> '0',
	'File::Value'		=> '1.01',
	'File::Namaste'		=> '1.00',
	'File::Pairtree'	=> '1.01',
	'Getopt::Long'		=> '0',
	'Sys::Hostname'		=> '0',
	'Text::ParseWords'	=> '0',
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'EggNog-*' },
);
