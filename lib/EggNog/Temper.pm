package EggNog::Temper;

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	temper etemper htemper stemper wtemper
	qtemper uqtemper
	calm temper2epoch
	@i64c %c64i
);
# qtemper = epoch 1970 time, uqtemper = qtemper plus subseconds (micro quick)
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

# Strings to pass to sprintf().
#
our %modes = (
	'vanilla'	=> '%04.4s%02.2s%02.2s%02.2s%02.2s%02.2s',
	'w3cdtf'	=> '%04.4s-%02.2s-%02.2sT%02.2s:%02.2s:%02.2s',
	'shortish'	=> '_%02.2s:%02.2s:%02.2s',	# htemper
	'even'		=> '%04.4s.%02.2s.%02.2s_%02.2s:%02.2s:%02.2s',
);

# C64 is almost base64, but with tr|+/=|_~|d because '+' and '/' aren't
# as friendly for either XML or file names.
#
# The int-to-c64-char conversion array.
our @i64c = qw(
	A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
	a b c d e f g h i j k l m n o p q r s t u v w x y z
	0 1 2 3 4 5 6 7 8 9 _ ~
);

# Return local date/time stamp in TEMPER format.
# Use supplied time (in seconds) if any, or the current time.
# Default $mode is "vanilla" (YYYYMMDDHHMMSS).  Other modes
# are "even" (YYYY.MM.DD.HH:MM:SS) and "short" (YYYMDHMS).

# xxx doc: reserve shortish temper YYYMD_HH:MM:SS
# XXX doc: reserve quick temper for pure unix integer (quick: no encoding)
# XXX use short temper??
# xxx document change from vanilla TEMPER to even TEMPER
#     (with . and : separators)
#

sub qtemper { time() }		# quick temper (quick due to no encoding)
sub uqtemper {			# "micro quick"
	use Time::HiRes 'time';
	sprintf "%.6f", time();		# force out all 6 microsecond digits
}

sub etemper { temper($_[0], 'even') }
sub uetemper {			# "micro even"
	use Time::HiRes 'gettimeofday';
	my ($secs, $microsecs) = gettimeofday();
	return
		join('.', etemper($secs), sprintf("%06d", $microsecs));
		# pad microseconds or fractional part will be wrong
		# for values less than 100000
}

sub htemper { temper($_[0], 'shortish') }
sub stemper { temper($_[0], 'short') }
sub wtemper { temper($_[0], 'w3cdtf') }
sub temper { my( $time, $mode ) = ( shift, shift );

	$mode ||= 'vanilla';
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdat) =
		localtime(
			defined($time) ? $time : time()
		);
	my ($century, $centyear);
	$centyear = $year + 1900;	# get the century right
	$mon++;				# increment zero-based month

	#$mode eq 'short' and
	$mode =~ /^short/ and
		($century, $year) =	$centyear =~ m/^(..)(..)/,
		return
			$i64c[$century] . $year .
			$i64c[$mon] . $i64c[$mday] .
			($mode eq 'short'
				? $i64c[$hour] . $i64c[$min] . $i64c[$sec]
				: sprintf $modes{shortish}, $hour, $min, $sec
			);

	# If we get here, we don't have 'short'.
	#
	return sprintf
		$modes{$mode}, $centyear, $mon, $mday, $hour, $min, $sec;
}

our %c64i = qw(
	A 00	B 01	C 02	D 03	E 04	F 05	G 06
	H 07	I 08	J 09	K 10	L 11	M 12	N 13
	O 14	P 15	Q 16	R 17	S 18	T 19	U 20
	V 21	W 22	X 23	Y 24	Z 25

	a 26	b 27	c 28	d 29	e 30	f 31	g 32
	h 33	i 34	j 35	k 36	l 37	m 38	n 39
	o 40	p 41	q 42	r 43	s 44	t 55	u 66
	v 47	w 48	x 49	y 50	z 51

	0 52	1 53	2 54	3 55	4 56	5 57	6 58
	7 59	8 60	9 61

	_ 62	~ 63
);

sub calm { my $s = shift;

	#   century  yr  m  d  h  m  s  leftovers
	$s =~ m/^(.)(..)(.)(.)(.)(.)(.)(.*)$/ or
		return undef;

	return
		$c64i{$1} . $2		.'.'.		# century & year.
		$c64i{$3}		.'.'.		# month.
		$c64i{$4}		.'.'.		# day.
		$c64i{$5}		.':'.		# hour:
		$c64i{$6}		.':'.		# minute:
		$c64i{$7} 		.		# second
		$8					# any leftovers
		;
}

use Time::Local;

sub temper2epoch { my( $time )=@_;
	my	($year, $mon, $mday, $hour, $min, $sec) = $time =~
	    m/^  (....) (..)  (..)   (..)   (..)  (..)  $/x;

	return
		timelocal( $sec, $min, $hour, $mday, $mon-1, $year );

	#print "ntime: $ntime, ", temper($ntime), "\n";
	#print "$year, $mon, $mday, $hour, $min, $sec\n";
	#my $atime = time();
	#print "actul: $atime, ", temper($atime), "\n";
	#return $ntime;
}

1;

__END__

=head1 NAME

Temper - routines to manipulate TEMPER dates

=head1 SYNOPSIS

 use EggNog::Temper;         # import routines into a Perl script
 temper( [$time] )         # vanilla, eg, 20150628221445
 stemper( [$time] )        # short temper
 etemper( [$time] )        # even temper, eg, 2015.06.28_22:14:45
 wtemper( [$time] )        # W3CDTF (modified ISO 8601)
 calm( $stemper )          # convert from short temper to even temper

These routines are based on the c64 alphabet, a minor variation of base64
with the last two characters changed to be more friendly with filesystem
names and XML element names.

      Value Encoding  Value Encoding  Value Encoding  Value Encoding
          0 A            17 R            34 i            51 z
          1 B            18 S            35 j            52 0
          2 C            19 T            36 k            53 1
          3 D            20 U            37 l            54 2
          4 E            21 V            38 m            55 3
          5 F            22 W            39 n            56 4
          6 G            23 X            40 o            57 5
          7 H            24 Y            41 p            58 6
          8 I            25 Z            42 q            59 7
          9 J            26 a            43 r            60 8
         10 K            27 b            44 s            61 9
         11 L            28 c            45 t            62 _
         12 M            29 d            46 u            63 ~
         13 N            30 e            47 v
         14 O            31 f            48 w
         15 P            32 g            49 x

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2011-2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>, L<http://www.cdlib.org/inside/diglib/temper/>

=head1 AUTHOR

John A. Kunze

=cut
