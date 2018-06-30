use 5.10.1;
use strict;
use warnings;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $pm = {
    	'lib/EggNog/Log.pm' => 'blib/lib/EggNog/Log.pm',
    	'lib/EggNog/Egg.pm' => 'blib/lib/EggNog/Egg.pm',
    	'lib/EggNog/Nog.pm' => 'blib/lib/EggNog/Nog.pm',
    	'lib/EggNog/Binder.pm' => 'blib/lib/EggNog/Binder.pm',
    	'lib/EggNog/Minder.pm' => 'blib/lib/EggNog/Minder.pm',
    	'lib/EggNog/Cmdline.pm' => 'blib/lib/EggNog/Cmdline.pm',
    	'lib/EggNog/Session.pm' => 'blib/lib/EggNog/Session.pm',
    	'lib/EggNog/Help.pm' => 'blib/lib/EggNog/Help.pm',
    	'lib/EggNog/Temper.pm' => 'blib/lib/EggNog/Temper.pm',
    	'lib/EggNog/Resolver.pm' => 'blib/lib/EggNog/Resolver.pm',
    	'lib/EggNog/Rlog.pm' => 'blib/lib/EggNog/Rlog.pm',
    	'lib/EggNog/RUU.pm' => 'blib/lib/EggNog/RUU.pm',
    	'lib/EggNog/ApacheTester.pm' => 'blib/lib/EggNog/ApacheTester.pm',
    	'lib/EggNog/ValueTester.pm' => 'blib/lib/EggNog/ValueTester.pm',
};

WriteMakefile(
    EXE_FILES	   => [ 'egg', 'nog', 'anvl2egg', 'orlogs' ],
    NAME	   => 'File::EggNog',	# XXX 'EggNog'
    AUTHOR	   => 'John A. Kunze <jak@ucop.edu>',
    VERSION_FROM   => 'VERSION',
    ABSTRACT	   => 'commands and routines to make and resolve identifiers',
   ($ExtUtils::MakeMaker::VERSION ge 6.3002
     ? ('LICENSE'  => 'BSD')
     : ()),
    PM			=> $pm,
    PREREQ_PM		=> {
	'perl'			=> '5.10.1',
	'Fcntl'			=> '0',
	'BerkeleyDB'		=> '0',
	'MongoDB'		=> '0',
	'DB_File'		=> '0',		# xxx drop
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
