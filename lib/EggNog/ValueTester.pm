package EggNog::ValueTester;

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	testdata_default script_tester remake_td remove_td shellst_is
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use Test::More;
use File::Path;
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;			# avoid exceptions with the unblessed
use EggNog::Binder ();

our $testdata_default = 'td';	# a constant

our ($perl, $blib, $bin);
our ($rawstatus, $status);	# "shell status" version of "is"

# Return values useful for testing a given $script:
#   $td		temporary directory, or empty string on error
#   $cmd	command string
#   $homedir	--home value
#   $tdata	value intended for --testdata
#   $indb	boolean to test if internal binder is being used
#   $exdb	boolean to test if external binder is being used

sub script_tester { my( $script )=@_;

	use Config;
	# td = temporary test directory/database
	# simple token with no path parts can serve as both a subdirectory
	# and as fragment of an external database name, eg, egg_td_egg
	my $td = "td_$script";		# test dir/database named for script

	# Depending on circs, use blib, but prepare to use lib as fallback.
	my $blib = (-e "blib" || -e "../blib" ?	"-Mblib" : "-Ilib");
	my $bin = ($blib eq "-Mblib" ?		# path to testable script
		"blib/script/" : "") . $script;

	$perl = $Config{perlpath};	# perl used in testing
	my $cmd = "2>&1 $perl $blib " .	# command to run, capturing stderr
		(-e $bin ?		# exit status in $? >> 8
			$bin : "../$bin") . " ";
	my $homedir = $td;		# config, prefixes, binders, minters,...
	my $indb = 1;			# default
	my $exdb = 0;			# default
	# xxx these settings should be derived using the session start up code!
	# EGG_DBIE=e means e and NOT i
	# EGG_DBIE=i means i and NOT e
	# EGG_DBIE=ie means i and e
	# EGG_DBIE=ei means i and e
	# EGG_DBIE=xyz means i (default) and NOT e (default)

	# The way we're called there's no --testdata option, so we pull
	# from the environment. Later we actually generate a --testsdata
	# option to support tests that will rely on it to create binder
	# names that don't conflict with other names.

	my $tdata = $ENV{EGG_TESTDATA} || $testdata_default;

	if ($ENV{EGG_DBIE}) {
		if (index($ENV{EGG_DBIE}, 'e') >= 0) {
			$exdb = 1;
			say("script_tester: detecting env var " .
				"EGG_DBIE=$ENV{EGG_DBIE}");
			my $mgstatus = `mg status`;	# yyy mongo-specific
			if ($mgstatus !~ m/OK.*running/) {
				say STDERR "script_tester: database daemon ",
					"appears to be down; did you do ",
					"\"mg start\"?";
				return ('');		# error
			}
			index($ENV{EGG_DBIE}, 'i') >= 0 or
				$indb = 0;
		}
		#$indb = index($ENV{EGG_DBIE}, 'i') >= 0;	# not default
	}
	my $hgbase = "--home $homedir "		# home-binder-group base string
		. "--testdata $tdata";

	return ($td, $cmd, $homedir, $tdata, $hgbase, $indb, $exdb);
}

sub shellst_is { my( $expected, $output, $label )=@_;

	$status = ($rawstatus = $?) >> 8;
	$status != $expected and	# if not what we thought, then we're
		print $output, "\n";	# likely interested in seeing output
	return is($status, $expected, $label);
}

sub remake_td { my( $td, $tdata )=@_;	# make $td with possible cleanup

	remove_td($td, $tdata);
	#-e $td and
	#	remove_td($td, $tdata);
	mkdir($td) or
		say STDERR "$td: couldn't mkdir: $!";
}

sub remove_td { my( $td, $tdata )=@_;

	# remove $td but make sure $td isn't set to "."
	# yyy maybe one day $td is optional
	! $td || $td eq "." and
		say STDERR "bad dirname \$td=$td";
	my $ok = try {
		rmtree($td);
	}
	catch {
		say STDERR "$td: couldn't remove: $@";
		return undef;	# returns from "catch", NOT from routine
	};
	# not bothering to check status of $ok

	if ($tdata) {

		# Tweak local environment so test binders get distinct names
		# when session (created next) default vals get set (kludge?).

		$ENV{EGG_TESTDATA} ||=		# don't override user setting
			$tdata;
		my ($sh, $msg) = EggNog::Session::make_session();
		if (! $sh) {
			say STDERR "couldn't create session: $msg";
			return undef;
		}
		# session created; local $sh var session object
		# will be destroyed when it goes out of scope
		if (! EggNog::Binder::brmgroup($sh)) {
			outmsg($sh);
			return undef;
		}
		return 1;
	}
}

## Use this subroutine to get actual commands onto STDIN (eg, bulkcmd).
##
#sub run_cmds_on_stdin { my( $td, $cmd, $cmdblock )=@_;
#
#	my $msg = file_value("> $td/getcmds", $cmdblock, "raw");
#	$msg		and return $msg;
#	return `$cmd - < $td/getcmds`;
#}

1;

=head1 NAME

ValueTester - routines for temporary directory and command script testing

=head1 SYNOPSIS

 use EggNog::ValueTester ':all';	    # import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2013 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
