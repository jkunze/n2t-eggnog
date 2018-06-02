package EggNog::Log;

use 5.010;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	init_tlogger tlogger gentxnid
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Spec::Functions;
use File::Path 'mkpath';
use File::Basename;
use File::Value 'flvl';
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;
#use Config;

use constant TIMEZONE		=> 'US/Pacific';

# yyy maybe this should be more object oriented (with "new" and "DESTROY")

# can be called from config or mopen
# takes $sh (session or minter handler/hash), as long as it can access {opt}
# returns '' on success or message on error
# also returns by setting valued in $sh hash, these
#$sh->{xxxtxnlog}  (for the moment)
#$sh->{uuid_generator}
#$sh->{tlogger_preamble}
#$sh->{tlogger}

sub init_tlogger { my( $sh )=@_;

	# By default, set up unified, per-server (as opposed to per-binder)
	# transaction log ("txnlog") to record both the start and end
	# times of each operation, as well as request and response info.
	# User can specify an alternate filename, or can specify an empty
	# filename to disable this logging.
	# yyy this should replace the older rlog
	#
	my $tlogname =
		  # if user flag not defined, use default
		(! defined($sh->{opt}->{txnlog}) ? $sh->{txnlog_file_default} :

		  # if user flag defined and non-empty, use it
		($sh->{opt}->{txnlog}		 ? $sh->{opt}->{txnlog} :

		  # else flag is defined but empty, so disable (don't log)
		(undef)));

	# If there's no $tlogname, that means turn logging off, and that's
	# effectively done by setting the $min_level logging higher than
	# 'info', eg, to 'error', which squelches mere 'info' messages.
	# yyy not really

	my $msg;
	my $min_level = $tlogname ?	# no $tlogname sets minimum logging
		'info' : 'error';	# level too high to let info through

	if ($tlogname) {
		my $dir = dirname $tlogname;
		my $ok = try {
			mkpath( $dir );
		}
		catch {
			$msg = "Couldn't create txnlog directory \"$dir\": $@";
			return undef;	# returns from "catch", NOT from routine
		};
		$ok // return $msg;	# test for undefined since zero is ok

		my $weekly = 'yyyy-ww';			# rotate log every week
		#my $weekly = 'yyyy-MM-dd-HH-MM';	# every minute to test
		#my $weekly = 'yyyy-MM-dd';		# every day to test

		my $tlogger;
		$ok = try {
			$tlogger = txnlog_open($tlogname, $min_level, $weekly);
		}
		catch {
			$msg = "Couldn't open txnlog: $_";
			chomp $msg;	# since we know our die adds a \n
			return undef;	# returns from "catch", NOT from routine
		};
		$ok // return $msg;	# test for undefined since zero is ok

		use Data::UUID;		# to create a transaction id generator
		$sh->{uuid_generator} = new Data::UUID or
			return "couldn't create a transaction UUID generator";
		# yyy document this uuid_generator param in of $sh

		my $ruu = $sh->{ruu};
		$sh->{tlogger_preamble} = "$ruu->{who} $ruu->{where}";
		$sh->{tlogger} = $tlogger;
	}
	return '';
}

# xxx this should eventually obsolete gen_txnid and get_txnid
sub gentxnid { my( $sh )=@_;

	$sh->{tlogger} or	# speeding by $sh arg check, if not logging
		return '';	# transactions, return defined but false value
	my $txnid = $sh->{uuid_generator}->create_b64();
	$txnid =~ tr|+/=|_~|d;			# mimic nog nab
	$txnid and
		return $txnid;			# normal return
	addmsg($sh, "couldn't generate transaction id");
	return undef;
}

# Transaction logger. Normally returns the $txnid given or
# generated. But the empty string is returned if logging is turned off, and
# undef is returned on error. If the given $txnid is undefined, a $txnid is
# generated and returned, otherwise the given $txnid is returned.
# It is not an error to supply a $txnid of ''.

sub tlogger { my( $sh, $txnid, $msg )=@_;

	! $sh->{tlogger} and
		return '';
	$txnid //= gentxnid($sh);
	defined($txnid) or
		addmsg($sh, "couldn't generate transaction id"),
		return undef;

	# +jak jak-macbook 2017.10.08_19:38:06.303051 ho5M4Zqs5xGEVOa5cX4dag
	$sh->{tlogger}->info(
		$sh->{tlogger_preamble}, ' ',
		EggNog::Temper::uetemper(), ' ',
		( $txnid || '-' ), ' ',
		$msg,
	);
	return $txnid;
}

# Opens a transaction log file, with rotation into an unending series of
# time-stamped filenames. Arguments:
#
#   $file_base - path to main log file
#   $min_level - minimum logging level; use 'info' normally, or 'error'
#                to turn $tlogger->info("...") logging off
#   $rotation_schedule - string such as 'yyyy-ww' or 'yyyy-MM-dd-HH-MM',
#                using log4j style ala DailyRollingFileAppender
#
# Returns a $tlogger object, or throws an exception on error. Call with
#
#   $tlogger->info("my message")
#
# See "perldoc Log::Log4perl::Appender::File" on using recreate,
# recreate_check_interval, recreate_check_signal, etc.

sub txnlog_open { my( $file_base, $min_level, $rotation_schedule )=@_;

	$min_level ||= 'info';

	use Log::Log4perl qw(get_logger :levels);

	# This next bit of config file is used to humor minimal log4perl init.
	# I wasn't able to do the entire config via this file-in-a-string
	# method because the post_rotate anonymous sub, while it would get
	# called on schedule, it didn't receive arguments unless I defined 
	# it (as above) in Perl.

	my $log4_conf = << 'EOT';
	log4perl.rootlogger		= DEBUG, DUMMY
	log4perl.appender.DUMMY		= Log::Dispatch::File
	log4perl.appender.DUMMY.filename	= /dev/null
	log4perl.appender.DUMMY.layout	= Log::Log4perl::Layout::PatternLayout
EOT
	my $msg;
	my $ok = try {
		Log::Log4perl->init_once( \$log4_conf );
	}
	catch {
		$msg = "log4perl init_once failed: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	$ok // die "$msg\n";	# \n silences script name and line number

	my $file_date_suffix = '%Y.%m.%d';
	my $file_appender = Log::Log4perl::Appender->new(
		'Log::Dispatch::FileRotate',
		name		=> 'txnlog',
		mode		=> 'append',
		recreate	=> 1,	# can be expensive to check always, so
		recreate_check_interval	=> 30,	# only check every 30 seconds 
		autoflush	=> 1,
		min_level	=> $min_level,
		TZ		=> TIMEZONE,
		DatePattern	=> $rotation_schedule,
		filename	=> $file_base,
		max		=> 10000,
		# For max we should only need 1, because
		# of post_rotate, but that's not working in some versions and
		# giving a very high max makes us less likely to lose data.
		# This next snippet from doc at http://search.cpan.org/~mschout/
		# ...Log-Dispatch-FileRotate-1.34/lib/Log/Dispatch/FileRotate.pm

		# Comment out post_rotate because we cannot easily get a
		# version (eg, 1.46) of Log::Log4perl that supports it on AWS.
		#post_rotate	=> sub {
		#	my ($filename, $idx, $fileRotate) = @_;
		#	$idx != 1 and
		#		return;
		#	use POSIX qw(strftime);
		#	my $basename = $fileRotate->filename();
		#	my $newfilename = "$basename."
		#		. strftime $file_date_suffix, localtime();
		#	rename($filename, $newfilename);
		#},
	);

	my $logger = Log::Log4perl->get_logger('txnlog');
	$file_appender->layout(Log::Log4perl::Layout::PatternLayout
			->new( '%m%n' )) or
		die "could not add layout to log4perl appender\n";
	$logger->add_appender($file_appender) or
		die "could not add appender to log4perl logger\n";
	#use Data::Dumper "Dumper"; $Data::Dumper::Sortkeys = 1; print Dumper $file_appender;
	return $logger;
}

1;

=head1 NAME

Session - routines to support eggnog transaction logs

=head1 SYNOPSIS

 use EggNog::Log;	   

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2017 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
