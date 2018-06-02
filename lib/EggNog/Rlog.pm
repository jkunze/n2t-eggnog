package EggNog::Rlog;

# XXX how to record --sif and other, eg, --force in deltas?
# Unsure how sophisticated to make this.  Current use suggests
# these codes for messages
# 
#   C: changes
#   R: replayed changes
#   M: important meta events, eg, binder creation or deletion
#   P: mapping event (resolution of a given identifier)
#   N: notes
#   D: debugging

use 5.010;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	out logname
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Copy 'mv';
use File::Value ":all";
use EggNog::Temper;

# XXX encode contact/who in case of embedded token separators?
# xxx add locking protocol for logfiles?
# Move current log off to a "to_ship" log file area.
# if called from Binder, should lock the db first (why??)
# yyy the egg.orlogs is a shared rendezvous for two processes
#     but maybe it the destination should be an argument to cull?
#
sub cull { my( $self ) =
	     ( shift );

	my $dir = $self->{basename} .	# eg, directory from which to launch
		'.replay';		# the replaying of rlogs on a replica
	! -e $dir and			# make directory if need be
		mkdir $dir || return (0, $!);
	use File::Spec::Functions;
	my $sdir = catfile($dir, 'to_ship');
	! -e $sdir and			# make sub-directory if need be
		mkdir $sdir || return (0, $!);

	my ($vtime, $fname, $msg);
	$vtime = EggNog::Temper::temper();	# get vanilla temper string for
	$fname = "$sdir/rlog.$vtime";		# file uniqueness and ordering

=for removal

	$msg = -e $fname ? "1"		# either branch can return "1"
		: snag_file($fname);	# race lost if this returns "1"
	$msg eq "1" and			# if it existed or we lost a race
		($msg, $fname) =	# then guarantee uniqueness with
			snag_version("$fname.1");	# a version number
	$msg eq "-1" and
		return (0, $fname);

=cut

	# If we get here, we've secured the filename we're moving TO.
	# Now see if the log file we would be moving FROM even exists.
	# If not, we can leave early because there's nothing to cull.
	#
	! -e $self->{logname} and	# done: nothing to cull
		return (1, 'nothing to cull');

	# Now add a final note before closing and rename.
	#
	$self->out("N: culled to $fname");	# yyy keep?
	close $self->{fhandle};		# opened as a side-effect of "out"
	mv($self->{logname}, $fname) or
		return (0, $!);

	return (1, "culled to $fname");
}
#hotrlog:   active
#  v  (cull)
#warmrlog/*: not active, awaiting processing
#  v  (process)
#coolrlog: in process, eg, concatenate to main log, and
#         apply deltas to replicas, conversions, and/or a pairtree
#  v  (finish)
#coldrlog/*:  processed

############################
#
# out - the main method that gets called.
#
# $rlog = $mh->{rlog}; $emsg = $rlog->out(htemper(), $msg)
# $emsg and exit(1);
#
# XXX document
# There is no separate "open" or "create" method, just "out".
# The name of the log is 
# this does output and open and create all in one
# return "" on success, message on error
sub out { my( $self ) =
	    ( shift );	# remaining args are all joined with 'join_string'

	my $msg = $self->{preamble};		# start with preamble

	my @extras;				# default extra is temper time
	$self->{extra_func} and @extras =	# if defined, add any extras
		&{ $self->{extra_func} }();	# from your preferred function

	# yyy warn callers that they must encode their join_string
	#      chars or else!  (because we don't do it for them)
	my $message = join(			# join the message with each
		$self->{join_string},		# supplied extra and user arg
		$msg, @extras, @_		# considered a separate field
	);

	# First try to output.  On failure, retry after opening (eg, for
	# the first time) or re-opening (eg, after a culling event).
	#
	my $fh = $self->{fhandle};
	$self->{fhandle} and
		print($fh $message, "\n") and
			return '';
	# If we get here, the first output attempt failed.
# If we're going to a pipe ...
# Do popen to process with rotatelogs-type args, that
#      rotatelogs="$aptop/bin/rotatelogs -l"
#      let monthly=(604800 * 4)		# actually, just 4 weeks
#  0.    interval_rotatelogs $srvref_root/logs/error_log.%Y.%m.%d $monthly"
#      usage: interval_rotatelogs -l IntervalMins \
#                      .../transaction_log.%Y.%m.%d $monthly
# ErrorLog "|$rotatelogs $srvref_root/logs/error_log.%Y.%m.%d $monthly"
#  1. itself does popen on a rotatelogs process R and
#  2. also opens socket L to Librato API
#  3. for every line read from stdin
#   - writes line to R
#   - collects counts (hashes) for N-minute intervals (N=3?),
#   - at the end of every N minutes, writes stats to L
#       ... and clears collected stats (hashes)

# ** make it robust in re-opening any pipe/socket found closed

	# This will re-create a log file if it's no longer there.
	# First test to see if it existed (and if we will try to re-create it).
	#
	my $log_existed = -e $self->{logname};
	open($fh, ">> $self->{logname}") or
		return "log open failed: $!";
	# If we get here, that should have opened (and maybe created) it.

	select((select($fh), $| = 1)[0]);	# unbuffer $fh filehandle
	$self->{fhandle} = $fh;

	# Second try with our output.  On failure, give up.
	# If the file is new, write a header first.
	#
	$log_existed or		# if we just (re)created log, output header
		print($fh
		    join(	$self->{join_string},
			$msg, @extras,		# start list we're joining
			$self->{header},	# eg, client version
			"(Rlog $VERSION)\n",	# document Rlog version
		    ),
		    join(	$self->{join_string},
			"N: key: H=header, N=note, C=change, D=debug, M=meta\n",
		    ),
		);	# ... or set X-XXX header
		# XXXXX test print's return and set X-XXX header on error
	$self->{fhandle} and			# this is the retry
		print($fh $message, "\n") and
			return '';

	# If we get here, both attempts to write failed.
	#
	return "log write failed: $!";	# set X-XXX header?
}

sub logname { my $base = shift;		# xxx document
	$base =~ s/_$//;	# XXX temp kludge while still doing .rlog
	return $base . '.rlog';
}

# call with $rlog = EggNog::Rlog->new(catfile($dbhome, $hname), { opts });
#
sub new { my( $class, $basename,  $opt ) =
	    (  shift,     shift, shift );

	my $self = {};
	bless $self, $class;

	$basename ||= '';
	$self->{basename} = $basename;
	#$self->{logname} = $basename . '.rlog';
	$self->{logname} = logname $basename;
	use File::Basename;
	-w dirname($self->{logname}) or
		return undef;
	# $self->{fhandle} remains undefined until first used
	$self->{preamble} =			# preamble to each log line
		$opt->{preamble} || $<;		# default is system userid
	$self->{join_string} =			# join fields with string
		$opt->{join_string} || ' ';
	$self->{extra_func} =			# join fields with string
		$opt->{extra_func} ||
			\&EggNog::Temper::etemper;
	$self->{header} =			# header string for top of
		$opt->{header} ||		# newly (re)created log file
			"EggNog::Rlog version $VERSION";
	return $self;
}

sub DESTROY {
	my $self = shift;

	defined($self->{fhandle})	and close $self->{fhandle};
	$self->{opt}->{verbose} and
		#$om->elem("destroying minder handler: $self");
		print "destroying rlog object: $self\n";
	undef $self;
}

1;

=head1 NAME

rlog - routines to support robust replay logs

=head1 SYNOPSIS

 use EggNog::Rlog ':all';	    # import routines into a Perl script

The log file gets recreated if it disappears, typically with a
culling event (supplied).

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
