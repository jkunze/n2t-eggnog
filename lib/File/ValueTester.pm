package File::ValueTester;

use 5.010;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	script_tester remake_td remove_td shellst_is
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use Test::More;
use File::Path;
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;			# avoid exceptions with the unblessed
use File::Binder ();

our ($perl, $blib, $bin);
our ($rawstatus, $status);	# "shell status" version of "is"

# Return values usefule for testing a given $script:
#   $td		temporary directory
#   $cmd	command string
#   $homedir	--home value
#   $bgroup	binder group (for exdb case)
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
	my $bgroup;			# external binder group
	my $indb = 1;			# default
	my $exdb = 0;			# default
	if ($ENV{EGG_DBIE}) {
		index($ENV{EGG_DBIE}, 'e') >= 0 and
			say("script_tester: detecting env var " .
				"EGG_DBIE=$ENV{EGG_DBIE}");
		$bgroup = $td;		# td_egg is ok as dir or bgroup name
		$exdb = 1;
		$indb = index($ENV{EGG_DBIE}, 'i') >= 0;	# not default
	}
	my $hgbase = "--home $homedir";		# home-binder-group base string
	$bgroup and				# empty unless EGG_DBIE is set
		$hgbase .= " --bgroup $bgroup";
	return ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb);
}

sub shellst_is { my( $expected, $output, $label )=@_;

	$status = ($rawstatus = $?) >> 8;
	$status != $expected and	# if not what we thought, then we're
		print $output, "\n";	# likely interested in seeing output
	return is($status, $expected, $label);
}

# Call with remake_td($td);
sub remake_td { my( $td, $bgroup )=@_;	# make $td with possible cleanup

	#my $td = shift;
	-e $td			and remove_td($td);
	if ($bgroup) {
		my $msg = File::Binder::brmgroup_standalone($bgroup);
		$msg and
			say STDERR $msg;
	}
	mkdir($td)		or say STDERR "$td: couldn't mkdir: $!";
}

# Call with remove_td($td);

sub remove_td { my( $td, $bgroup )=@_;

	# remove $td but make sure $td isn't set to "."
	# yyy maybe one day $td is optional
	! $td || $td eq "."	and say STDERR "bad dirname \$td=$td";
	my $ok = try {
		rmtree($td);
	}
	catch {
		say STDERR "$td: couldn't remove: $@";
		return undef;	# returns from "catch", NOT from routine
	};
	# not bothering to check status of $ok
	my $msg;
	if ($bgroup) {
		my $msg = File::Binder::brmgroup_standalone($bgroup);
		$msg and
			say STDERR $msg;
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

 use File::ValueTester ':all';	    # import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2013 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
