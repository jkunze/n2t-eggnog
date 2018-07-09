# xxx use Memoize for some of the char table lookups in Nog?

# xxx convert old /^\Q.../ matches into substr(), as per Egg.pm
##$status != 0 || $key !~ /^\Q$first/ and
#$status != 0 || $first ne substr($key, 0, length($first)) and

# xxx ok: nog mkminter 99999/jk4{eedk}
#     not ok: nog rmminter 99999/jk4{eedk}
#     the above rmminter command should work

# XXX what noid commands provoke badauthmsg?? As per Bind.pm...
#	$mh->{WeAreOnWeb} and			# check authz only if on web


# XXX Oct 2011 :
#     for resolver replication, tested wlog of bindings
#     - list ids by criteria (OM loop to read raw anvl)
# XXX change snag_dir snag_file to allow version capture by default, eg,
#     snag foo/    shouldn't fail by default, but return "foo1/", while
#     snag --noversion foo/    can fail
# xxx change snag_version to look for rightmost digit string not followed
#     by alphas (x2y->x2y.1 but x2->x3 and x-2y->x-2y1)
#     and finding none, insert digits to the left of rightmost '.'
# xxx can caster easily be shared on one system across all users or,
#   better, shared on a host across one organization?
# xxx should om->new have a default format??
# XXX should user bindings be cordoned off from other things, eg,
#     shoulders? pick-lists for known values of a field?
# XXX what about bulkcmds that keep re-opening $mh? (w.o. closing)
#     XXX can we take advantage of its being open already and not re-open?
# XXX test with CSV format
# XXX catch signals
#  sub catch_zap {
#      my $signame = shift;
#      $shucks++;
#      die "Somebody sent me a SIG$signame";
#  }
#  $SIG{INT} = ’catch_zap’;  # could fail in modules
#  $SIG{INT} = \&catch_zap;  # best strategy

package EggNog::Nog;

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Path;
use File::OM;
use File::Value ":all";
use File::Pairtree ":all";
use File::Namaste;
use EggNog::Log qw(tlogger);
use File::Copy 'mv';
use File::Find;
use EggNog::Temper 'temper';
use EggNog::Minder ':all';	# xxx be more restricitve
#use Math::BigInt;		# XXXXXX ??? leave as option? given slowdown?

# Nog - Nice opaque generator (Perl module)
# 
# Author:  John A. Kunze, jak@ucop.edu, California Digital Library
#		Originally created, UCSF/CKM, November 2002
# 
# Copyright 2008-2012 UC Regents.  Open source BSD license.

use constant LOCK_TIMEOUT	=>  5;			# seconds
use constant GERM_RANGE		=>  65536;		# 2**16
use constant SEQNUM_MIN		=>  1;
use constant SEQNUM_MAX		=>  1000000;
#use constant SPING		=> 'id';
use constant SPING		=> 's';

# xxx test bulk commands at scale -- 2011.04.24 Greg sez it bombed
#     out with a 1000 commands at a time; maybe lock timed out?

# xxxThe database must hold nearly arbitrary user-level identifiers
#    alongside various admin variables.  In order not to conflict, we
#    require all admin variables to start with ":/", eg, ":/oacounter".
#    We use "$A/" frequently as our "reserved root" prefix.

# XXX which module should this be in?
# We use a reserved "admin" prefix of $A for all administrative
# variables, so, "$A/oacounter" is ":/oacounter".
#
my $A = $EggNog::Minder::A;

use Fcntl qw(:DEFAULT :flock);
use File::Spec::Functions;
use DB_File;

our ($legalstring, $alphacount, $digitcount);
our $noflock = "";
our $Win;			# whether we're running on Windows

# Legal values of $how for the bind function.
# xxx document that we removed: purge replace mint peppermint new
# xxxx but put "mint" back in!
# xxx implement append and prepend or remove!
# xxx document mkid rmid
my @valid_hows = qw(
	set let add another append prepend insert delete mkid rm
);

# XXXX but d4 and d5 are 'real' in master_shoulders!! maybe these
#      should be df4 and df5?
# Default minder 'd5', as a partly occluded mnemonic of 'def', which is
# short for 'default'.  Creates a convention similar to 'fk' (fake) for
# a more real (less fake) but "not necessarily real" minder.
# 
our $default_minder_nab = "d4";		# default minder name for 'nab'
our $default_minder_mint = "99999/d5";	# default minder name for 'mint'

our $def_seq_n = 0;			# default sequential starting number xxx ?? needed?
our $def_rand_n = 0;			# default random starting seed xxx ?? needed?
our $def_stop_n = 1;			# default atlast stop number xxx
our $def_wrap_n = 0;			# default atlast wrap number xxx

our $def_seq_add_n = 1;			# default sequential add digit num xxx
our $def_rand_add_n = 1;		# default random add digit num xxx
our $def_rand_oklz = 1;			# default rand setting for oklz option

our $def_minter_type = "rand";		# default minter type
	# these defaults work well with the "first digit shoulder" convention,
	# since a digit precedes the first pair of non-digits "ee".
our $def_rand_mask = "eedk";		# default random mask, paired with ...
our $def_rand_nomask_atlast = "add3";	# default random 'atlast' keeps alpha
					# pairs isolated by digits (add eed)
our $def_rand_atlast = "add1";		# default random 'atlast'

our $def_seq_mask = "d";		# default sequential mask, paired with
our $def_seq_atlast = "add1";		# default seq 'atlast' keeps ids short
our $def_seq_oklz = 0;			# default seq setting for oklz option

our $minders = ".minders";
our %o;					# yyy global pairtree options

## XXXX but d4 and d5 are 'real' in master_shoulders!! maybe these
##      should be df4 and df5?  and not d4 and d5

my @minter_commands = qw(
	hold mint recycle unmint
);

#
# --- begin alphabetic listing (with a few exceptions) of functions ---
#

# Primes:
#   2        3        5        7      
#  11       13       17       19      
#  23       29       31       37      
#  41       43       47       53      
#  59       61       67       71      
#  73       79       83       89      
#  97      101      103      107      
# 109      113      127      131      
# 137      139      149      151      
# 157      163      167      173      
# 179      181      191      193      
# 197      199      211      223      
# 227      229      233      239      
# 241      251      257      263      
# 269      271      277      281      
# 283      293      307      311      
# 313      317      331      337      
# 347      349      353      359      
# 367      373      379      383      
# 389      397      401      409      
# 419      421      431      433      
# 439      443      449      457      
# 461      463      467      479      
# 487      491      499      503  ...

# yyy other character subsets? eg, 0-9, a-z, and _  (37 chars, with 37 prime)
#      this could be mask character 'w' ?
# yyy there are 94 printable ASCII characters, with nearest lower prime = 89
#      a radix of 89 would result in a huge, compact space with check chars
#      mask character 'c' ?

# Extended digits array.  Maps ordinal value to ASCII character.
my @xdig = (
	'0', '1', '2', '3', '4',   '5', '6', '7', '8', '9',
	'b', 'c', 'd', 'f', 'g',   'h', 'j', 'k', 'm', 'n',
	'p', 'q', 'r', 's', 't',   'v', 'w', 'x', 'z'
);
# $legalstring should be 0123456789bcdfghjkmnpqrstvwxz
$legalstring = join('', @xdig);
$alphacount = scalar(@xdig);		# extended digits count
$digitcount = 10;			# pure digit count

# xxx other alternatives:
# xxx  'd' digit = 0-9
# xxx  'e' edigit = 0-9 b-z
# xxx  'p' pdigit = 1-9   (positive digit)
# xxx  'b' edigit - digit = b-z
# xxx  'x' hex = 0-9 a-f

# Ordinal value hash for extended digits.  Maps ASCII characters to ordinals.
#{ 0-9 } { x }			cardinality 10:11, mask char d "digit"
#xxx repertoire... = [ chars, checks_to_add_to_chars, chars+checks ]
#    where chars+checks is often empty, but overrides checks_to_add... if not
#xxx my $repertoire_digit_d = [ "0123456789", "", "x" ];
my %ordxdig = (
	'0' =>  0,  '1' =>  1,  '2' =>  2,  '3' =>  3,  '4' =>  4,
	'5' =>  5,  '6' =>  6,  '7' =>  7,  '8' =>  8,  '9' =>  9,

	'b' => 10,  'c' => 11,  'd' => 12,  'f' => 13,  'g' => 14,
	'h' => 15,  'j' => 16,  'k' => 17,  'm' => 18,  'n' => 19,

	'p' => 20,  'q' => 21,  'r' => 22,  's' => 23,  't' => 24,
	'v' => 25,  'w' => 26,  'x' => 27,  'z' => 28
);

# Compute check character for given identifier.  If identifier ends in '+'
# (plus), replace it with a check character computed from the preceding chars,
# and return the modified identifier.  If not, isolate the last char and
# compute a check character using the preceding chars; return the original
# identifier if the computed char matches the isolated char, or undef if not.

# User explanation:  check digits help systems to catch transcription
# errors that users might not be aware of upon retrieval; while users
# often have other knowledge with which to determine that the wrong
# retrieval occurred, this error is sometimes not readily apparent.
# Check digits reduce the chances of this kind of error.
# yyy ask Steve Silberstein (of III) about check digits?

sub checkchar{ my( $id )=@_;
	return undef
		if (! $id );
	my $lastchar = chop($id);
	my $pos = 1;
	my $sum = 0;
	my $c;
	for $c (split(//, $id)) {
		# if character undefined, it's ordinal value is zero
		$sum += $pos * (defined($ordxdig{"$c"}) ? $ordxdig{"$c"} : 0);
		$pos++;
	}
	my $checkchar = $xdig[$sum % $alphacount];
	#print "RADIX=$alphacount, mod=", $sum % $alphacount, "\n";
	return $id . $checkchar
		if ($lastchar eq "+" || $lastchar eq $checkchar);
	return undef;		# must be request to check, but failed match
	# xxx test if check char changes on permutations
	# XXX include test of length to make sure < than 29 (R) chars long
	# yyy will this work for doi/handles?
}

# XXX never called, and uses obsolete minter_parts
my @minter_parts = qw( minter.bdb minter.lock minter.log minter.README );
# xxx do mirror image for lsbinder
# consider minter to exist if _any_ part of it exists
sub lsminter { my( $dbdir )=@_;

	-e $dbdir	or return 0;	# no directory means nothing exists
	my $dbname = catfile($dbdir, "minter.bdb");
	-e $dbname	and return 1;	# early check for common case

	my $found = 0;
	for my $p (@minter_parts) {	# tail part is what changes
		my $fp = catfile($dbdir, "minter.$p");	# its full path
		next	if $fp eq $dbname;	# already checked this
		-e $fp	and $found++;
	}
	return $found;
}

=pod

Note: users may see the term "blade" as shorthand for "mask that
determines the blade".  Below we use $mask for that part of the
template that determines the form of the blade.  More precisely,
"blade" refers to a specific concrete instance in an id.

Internal state vars
  type = generator type, machine readable, with N on end
  generator_type = generator type, human readable

=cut

sub mkminter { my( $mh, $mods, $minder, $template, $minderdir )=@_;

	$mh		or return undef;
	my $hname = $mh->{humname};		# name as humans know it

	# We have no RUU info yet because mopen() hasn't been called,
	# but we do have exactly the test we need already.
	#
	$mh->{remote} and			# check authz only if on web
		unauthmsg($mh),
		return undef;

	$mh->{fiso} and
		addmsg($mh, "cannot make a new $hname using an open handler " .
			"($mh->{fiso})"),
		return undef;

	# XXX document!
	# To create a minter with an empty shoulder in a dir called "tmp":
	#    Example (NAAN minter):  nog -d tmp mkminter "" ddddd
	# xxx Fix: nog mkminter -p foo -d tmp "" ddddd     # doesn't honor -p
	# xxx Fix: nog mkminter -d tmp mkminter tt ddddd   # doesn't honor -d
	#   while nog -p tmp mkminter tt ddddd        # does what you'd expect

	#print "xxxzzz before unless minder=$minder\n";
	unless ($minder) {
		$minder = prep_default_minder($mh, (O_CREAT|O_RDWR),
			$mh->{minderpath});	# xxx why not just O_CREAT?
		$minder or
			addmsg($mh,
			  "mkminter: no $hname specified and default failed"),
			return undef;
		return $minder;
	}

	$minder =~ s|/$||;		# remove fiso_uname's trailing /
	# xxx big default is shoulder; if not set, we 'generate' new minter

	my $om = $mh->{om};
	my $nog_opt = $mh->{opt};
	#my $contact = $mh->{ruu}->{who};

	my $type = lc( $$nog_opt{type} || $def_minter_type );
	# xxx check and warn if used with, eg, mint

	my $generator_type;
	$type eq "seq" and
		($generator_type = "sequential"),
	or $type eq "rand" and
		($generator_type = "random"),
	or
		addmsg($mh, "unknown minter type '$type'"),
		return undef,
	;

	# Preliminary look at template to see if it contains a mask.
	#
	$template ||= "";
	$template =~ s/{}//g;		# delete any empty mask parts
	my $nomask = $template !~ /[{}]/;
# xxx should these defaults come from noid->new?
	my $atlast = lc( $$nog_opt{atlast} ||
		($type =~ /^rand/ ?
			($nomask ? $def_rand_nomask_atlast : $def_rand_atlast)
			: $def_seq_atlast));

	# The proposed atlast action may have a status number at the end.
	# Parse to nail down action and status number.
	#
	my $confirm = 1;	# ready to "round-trip parse" for safety
	my ($atlast_status, $action) = atlast_type($atlast, $type, $confirm);
	$atlast_status =~ /[a-z]/i and		# if it's a message
		addmsg($mh, $atlast_status),	# bail
		return undef;
	$atlast = $action . $atlast_status;	# we're sure now

	# Check the proposed "germ" (quasi-seed). yyy should allow "random"
	# This option only makes sense for --type rand
	#
	my $germ = $$nog_opt{germ} || 0;
	$germ =~ /^\d+$/ || $germ =~ /^-[12]$/ or
		addmsg($mh,
			"germ ($germ) must be an integer greater than -3"),
		return undef;
	#
	# If we get here, $germ is now one of these values:
	#   0		(default)
	#   -1		random (not quasi, using Perl's default seed),
	#   -2		randomer (using the "truly random" module xxx)
	#   0 < $germ < GERM_RANGE
	#		reasonable value to use as $oacounter multiplier
	# xxx set -1 and -2 seeds _once_ only in mkminter
	#
	# We keep $germ low enough to avoid integer overflow (-1) when we
	# multiply it with the oacounter value, as that results in constant
	# seed when selecting the next counter; not horrible, it means
	# that after that point, random ids will look sequential because
	# the same counter will be selected over and over.
	# yyy not rigorously tested, but it may not be worth the trouble
	#
	$germ > GERM_RANGE and
		$germ %= GERM_RANGE;

	# Prepare to construct/parse the template.
	#
	$nomask and			# no mask means use default
		$template .= "{" . ($type =~ /^r/ ?
			$def_rand_mask : $def_seq_mask) . "}";

	my ($total, $shoulder, $mask, $msg);
	$total = parse_template($template, $shoulder, $mask, $msg);
		# defines $msg or defines $shoulder and $mask
	#print "xxxzzz template=$template, shoulder=$shoulder, mask=$mask\n";
	$total or
		addmsg($mh, $msg),
		return undef;
	$msg and			# this would be any warning message
		addmsg($mh, $msg, 'warning'),
	$minder ||= $shoulder;

#	# Check start number.
#	#
#	my $start = $$nog_opt{start} || 0;
#	$start !~ /^\d+$/ and		# if not pure digits
#		addmsg($mh, "starting number ($start) must be all digits"),
#		return undef;
#	$atlast =~ /^stop/ and $start >= $total and	# if minter is bounded
#		addmsg($mh, "starting number ($start) would exceed " .
#				"total ($total)"),
#		return undef;

	# xxx should be able to check naa and naan live against registry
	# yyy code should invite to apply for NAAN by email to ark@cdlib.org
	# yyy ARK only? why not DOI/handle?

	## $submh is auto-destroyed when we leave scope of this routine.
	##
	#my $submh = EggNog::Nog->new(Nog::ND_MINTER, $contact, $om,
	#	$mh->{minderpath}, $nog_opt);
	#$submh or
	#	addmsg($mh, "couldn't create sub-minder handler"),
	#	return undef;
	my $mdr = mkminder($mh, $minder, $minderdir);
	$mdr or
		#addmsg($mh, outmsg($mh)),
		return undef;			# outmsg() tells reason
	my $tagdir = fiso_uname($mdr);

	my $nog = $mh->{tied_hash_ref};

	$msg = $mh->{rlog}->out("M: mkminter $minder $template") and
		addmsg($mh, $msg),
		return undef;
# xxx log this in the caster's log

	# Now initialize lots of database info.  It is required that
	# $germ be set to zero if the corresponding option was set!
	#
	$$nog{"$A/type"} = $type;			# yyy new!!
	$$nog{"$A/germ"} = $germ;			# yyy new!!
#	$$nog{"$A/start"} = $start;			# yyy new!!
	$$nog{"$A/atlast_status"} = $atlast_status;	# yyy new!!
# xxx make sure less than oacounter ?  yyy or maybe it works anyway? TEST!
	$$nog{"$A/atlast"} = $atlast;			# yyy new!!
	$$nog{"$A/oklz"} = (defined($$nog_opt{oklz})	# yyy new!!
		? $$nog_opt{oklz} : ($type eq 'rand'
			? $def_rand_oklz : $def_seq_oklz));
	
	$$nog{"$A/generator_type"} = $generator_type;	# human friendly

#sub set_totals { my( $nog, $mask, $template, $total, $oacounter )=@_;
#			$$nog{"$A/mask"} = $newmask;
#			$$nog{"$A/template"} = $template;
#
#			# yyy are total and oatop ever different?
#			$$nog{"$A/total"} = $total;
#			$$nog{"$A/oatop"} = $total;
#
#   is this for random minter reset, or seq, or both?:
#			if ($$nog{"$A/type"} !~ /^seq/) {
#				# We're in a "random" type minter
#				# yyy calls dblock -- problem?
#	?			init_counters($nog);
#	?			$$nog{"$A/basecount"} += $oacounter;
#	?			$$nog{"$A/oacounter"} = $oacounter = 0;
#			}
#}
# xxx vvv attend to when minter blade expands
	$$nog{"$A/mask"} = $mask;	# now changed by genid on expand
	$$nog{"$A/template"} = $template;	# xxx changed by genid
	$$nog{"$A/original_template"} = $template;	# won't change
	$$nog{"$A/total"} = $total;	# now changed by genid on expand
		# total reflects total possible under current mask
		# without taking possible expansion into account
	$$nog{"$A/oatop"} = $total;	# +++
	$$nog{"$A/oacounter"} = 0;	# +++
	init_counters($nog);
	$$nog{"$A/lzskipcount"} = 0;	# changed by mint; see oklz
	$$nog{"$A/maskskipcount"} = 0;	# changed by mint; see mask char 'f'
	$$nog{"$A/basecount"} = 0;	# changed by genid on expand
	  # new variable to help keep history of total-total count (since
	  # we're now resetting total counts with expanding minters

	#init_counters($nog)		if $mask;
# xxx ^^^ attend to when minter blade expands

	$$nog{"$A/shoulder"} = $shoulder;
	$$nog{"$A/origmask"} = $mask;	# yyy save for in case mask changes
	$$nog{"$A/addcheckchar"} = ($mask =~ /k$/);	# boolean answer
	# xxxx are these right? does a finite $total imply wrap?
	#  xxx need padwidth?

	my $unbounded = $$nog{"$A/unbounded"} =
		$atlast !~ /^stop/;	# yyy document new!!
	my $expandable = $$nog{"$A/expandable"} =
		$atlast =~ /^add/;	# yyy document new!!

	# xxx $mask shortened by 1 char, maybe next should have a 1 subtracted
	$$nog{"$A/padwidth"} = ($expandable ? 16 : 2) + length($mask);
		# yyy kludge -- padwidth of 16 enough for most lvf sorting

	# Some variables:
	#   oacounter	overall counter's current value (last value minted)
	#   oatop	overall counter's greatest possible value of counter
	#   held	total with "hold" placed
	#   queued	total currently in the queue

	$$nog{"$A/held"} = 0;
	$$nog{"$A/queued"} = 0;

	# xxx will I need these after dups?
	$$nog{"$A/fseqnum"} = SEQNUM_MIN;	# see queue() and mint()
	$$nog{"$A/gseqnum"} = SEQNUM_MIN;	# see queue()
	$$nog{"$A/gseqnum_date"} = 0;		# see queue()

	my ($v1bdb, $dbfile, $built, $running) =
		EggNog::Minder::get_dbversion();

	$$nog{"$A/version"} = $VERSION;
	$$nog{"$A/dbversion"} = "With Nog version $VERSION, " .
		"using DB_File version $dbfile, built with Berkeley DB " .
		"version $built, running with Berkeley DB version $running.";

	# yyy should verify that a given NAAN and NAA are registered,
	#     and should offer to register them if not.... ?

	my $random_sample;			# undefined on purpose
	$expandable and
		$random_sample = int(rand(10));	# first sample less than 10
	my $sample1 = sample($nog, $random_sample);
	$expandable and
		$random_sample = int(rand(100000));	# second sample bigger
	my $sample2 = sample($nog, $random_sample);

	my $htotal = ($unbounded ? "unlimited" : human_num($total));
	my $kind = ($expandable ? " expandable" : "");
	my $what = ($unbounded ? "unlimited" : $total)
		. qq@ $generator_type spings of form $template
       A Nog minting database has been created that will generate
       @
		. ($unbounded ? qq@an unbounded number of spings
       with the$kind template "$template".@
		: $htotal . qq@ spings with the template "$template".@)
		. qq@
       Spings are "semi-opaque strings", eg, "$sample1" and "$sample2".@;

# XXX add DB_File version info to version line below!!
	$$nog{"$A/erc"} = 
qq@# Creation record for the sping generator in $mh->{dbname}.
# 
@	. fiso_erc($mh->{ruu}, $tagdir, $what)
	. qq@Version:   Nog $VERSION
Size:      @ . ($unbounded ? "unlimited" : $total) . qq@
Template:  @ . (! $template ? "(:none)" : $template) . qq@
Type:      $type
Atlast:    $atlast@
	;
	# xxx add warnings for dbv1 and nfs
	$noflock and			# global set inside dbopen
		$$nog{"$A/erc"} .= qq@
Note:      $noflock@;

	# yyy fix and add
	#$what .= durability($shoulder, $mask, $generator_type,
	#	$$nog{"$A/addcheckchar"}, $$nog{"$A/atlast"} =~ /^wrap/);

	my $readme = catfile($tagdir, "$mh->{fname_pfix}README");
	#my $readme = catfile($tagdir, "$oname.README");
	$msg = file_value(">$readme", $$nog{"$A/erc"});
	$msg and
		addmsg($mh, "Couldn't create $hname.README file: $msg"),
		return undef;
	# xxxx add namaste tag
	# yyy useful for quick info on a minter from just doing 'ls <minder>'??
	#        ? file_value(">$tagdir/T=$shoulder.$mask", "foo\n");

# XXXX must run report through formatter!
	my $report = qq@Created:   minter for $what  @ . qq@
       See $readme for details.\n@;

	#init_counters($nog)		if $mask;
	if ($om) {
		#$om->elem("dbreport", $report);
		#$msg = outmsg($mh)	and $om->elem("warning", $msg);
		outmsg($mh);		# if any messages, output them
	}
	#dbclose($mh);
	return $mdr;		# return name of new minter
	#return $report;

	# yyy should be using db-> ops directly? (for efficiency and?)
	#(old) $$nog{"$A/naa"} = $naa;
	#(old) $$nog{"$A/naan"} = $naan;
	#(old) $$nog{"$A/subnaa"} = $subnaa || "";
	#(old) $$nog{"$A/wrap"} = ($term eq "short");	# yyy follow through
	#(old) $$nog{"$A/firstpart"} = ($naan ? $naan . "/" : "") . $prefix;
	#(old) $$nog{"$A/genonly"} = $genonly;
}
# end of mkminter

# Given a proposed type from an uncertain source (eg, a user or our own
# reconstructed type), check and return broken out canonicalized type
# information as a three-element array ( $typenumber, $typename,
# $human_typename ).  The call succeeds if $typenumber does not contain an
# alpha character, otherwise $typenumber represents an error message and
# the other returned elements will be undefined.  $typenumber is used as
# the status to return when the given event occurs or the number of
# characters to "add".
#
sub atlast_type { my( $type, $minter_type, $confirm )=@_;

	# Check atlast type option, which may end in a number.
	#
	$type or
		return "no atlast type specified";
	$type =~ m/^(\D+)(\d*)$/ or
		return "unrecognized atlast specification '$type'";
	my ($typename, $typenumber) = ($1, $2);

	# Note that $typenumber will be defined, even if empty (because of 
	# * after \d).  If it contains one digits, it's all digits, and it
	# needs to be less than 256, which is all that fits in 8 bits of
	# status code and is a reasonable number of mask chars to repeat.
	# 
	$typenumber =~ /\d/ and	$typenumber >= 256 and
		return "digit string in '$type' should be less than 256";

	$typename =~ /^add$/ and
		# default numbers to "add" depending on generator type
		($typenumber eq "" and ($typenumber = $minter_type =~ /^r/ ?
			$def_rand_add_n : $def_seq_add_n)),
	1
	or $typename =~ /^stop$/ and
		# default status number to return on stop
		($typenumber eq "" and $typenumber = $def_stop_n),
	1
	or $typename =~ /^wrap$/ and
		# default status number to return on wrap
		($typenumber eq "" and $typenumber = $def_wrap_n),
	1
	or
		return "unknown atlast type '$type'"
	;
	if ($confirm) {			# call ourself to roundtrip verify
		my ($tnum, $tnam, $ht) =
			atlast_type( $typename.$typenumber, $minter_type );
		$tnum ne $typenumber || $tnam ne $typename and
			return "reconstruction error: $tnam$tnum not same " .
				"as $type$typenumber.";
	}
	return $typenumber, $typename;
}

# Return a cute statement about minter durability
# xxxx this is not really tested or known to be useful
#
sub durability { my( $shoulder, $mask, $generator_type, $checkchar, $wraps )=@_;

	# $wraps = 1 if minter wraps
	# $generator_type = "random" if minter is random
	# $checkchar = 1 if there is a terminal check char
	# yyy not sure if $mask is the same as $blade
	#
	# XXXX Try to create these properties automatically in minters!
	#    Document them in manual page as advice to handcrafted
	#    template makeers
	#
	# Capture the properties of this minter.
	#
	# There are seven properties, represented by a string of seven
	# capital letters or a hyphen if the property does not apply.
	# The maximal string is GRANITE (we first had GRANT, then GARNET).
	# We don't allow 'l' as an extended digit (good for minimizing
	# visual transcriptions errors), but we don't get a chance to brag
	# about that here.
	#
	# Note that on the Mohs mineral hardness scale from 1 - 10,
	# the hardest is diamonds (which are forever), but granites
	# (combinations of feldspar and quartz) are 5.5 to 7 in hardness.
	# From http://geology.about.com/library/bl/blmohsscale.htm ; see also
	# http://www.mineraltown.com/infocoleccionar/mohs_scale_of_hardness.htm
	#
	# These are far from perfect measures of identifier durability,
	# and of course they are only from the assigner's point of view.
	# For example, an alphabetical restriction doesn't guarantee
	# opaqueness, but it indicates that semantics will be limited.
	#
	# yyy document that (I)mpressionable has to do with printing, does
	#     not apply to general URLs, but does apply to phone numbers and
	#     ISBNs and ISSNs
	# yyy document that the opaqueness test is English-centric -- these
	#     measures work to some extent in English, but not in Welsh(?)
	#     or "l33t"
	# yyy document that the properties are numerous enough to look for
	#     a compact acronym, that the choice of acronym is sort of
	#     arbitrary, so (GRANITE) was chosen since it's easy to remember
	#
	# $pre and $msk are in service of the letter "A" below.

	my ($naan, $pre, $msk);
	$shoulder =~ m|\b(\w\d\d\d\d)/| and
		$naan = $1;
	$naan ||= "";
	($pre = $shoulder) =~ s/[a-z]/e/ig;
	($msk = $mask) =~ s/k/e/g;
	# xxx this next analysis is broken -- needs to look at addN
	$msk =~ s/^ze/zeeee/;		# initial 'e' can become many later on

	my $oknaan = $naan && $naan ne "00000" && $naan ne "99999";
	my $properties = 
		($oknaan ? "G" : "-")
		. ($generator_type =~ /^r/ ? "R" : "-")
		# yyy substr is supposed to cut off first char
		. (($pre . substr($msk, 1)) !~ /eee/ ? "A" : "-")
		. ($wraps ? "-" : "N")
		. ($shoulder !~ /-/ ? "I" : "-")
		. ($checkchar ? "T" : "-")
		# yyy "E" mask test anticipates future extensions to alphabets
		. (($shoulder =~ /[aeiouy]/i || $mask =~ /[^rszdek]/)
			? "-" : "E")		# Elided vowels or not
	;

	my $indent = "                    ";	# by measuring image below
	my $nsline = "(you" . ($oknaan
		? "r $naan\n$indent is a registered"
		:   " will\n$indent register a 5-digit")
			. " namespace at ark\@cdlib.org, right?)";

	# Create a human- and machine-readable report.
	#
	my @p = split(//, $properties);			# split into letters
	s/-/_ not/ || s/./_____/
		for (@p);
	return qq@
Durability:    (:$properties)
       This minter's durability summary is (maximum possible being "GRANITE")
         "$properties", which breaks down, property by property, as follows.
          ^^^^^^^
          |||||||_$p[6] (E)lided of vowels to avoid creating words by accident
          ||||||_$p[5] (T)ranscription safe due to a generated check character
          |||||_$p[4] (I)mpression safe from ignorable typesetter-added hyphens
          ||||_$p[3] (N)on-re-issuable strings (minter never resets)
          |||_$p[2] (A)lphabetic-run-limited to pairs to avoid acronyms
          ||_$p[1] (R)andomly sequenced to avoid series semantics
          |_$p[0] (G)lobally unique within a registered namespace $nsline
@;

}

=for removal
# Get the value of any named internal variable (prefaced by $A)
# given an open database reference.
#
sub getnoid { my( $mh, $varname )=@_;

	my $nog = $mh->{tied_hash_ref};

	return $$nog{"$A/$varname"};
}
=cut

sub mstat { my( $mh, $mods, $om, $cmdr, $level )=@_;

	$om ||= $mh->{om};
	my $db = $mh->{db};
	my $dbh = $mh->{tied_hash_ref};
	my $opt = $mh->{opt};
	my ($key, $value) = ("$A/", 0);
	my ($mtime, $size);
	use EggNog::Temper ':all';

	$level ||= "brief";
	if ($level eq "brief") {
		#$om->elem("minter", which_minder($cmdr, $mh->{minderpath}));
		$om->elem("minter", $mh->{minder_file_name});
		(undef,undef,undef,undef,undef,undef,undef,
			$size, undef, $mtime, undef,undef,undef) =
					stat($mh->{minder_file_name});
		$om->elem("modified", etemper($mtime));
		$om->elem("size in octets", $size);
		$om->elem("status", minder_status($dbh));
		$om->elem("spings generated",
			$dbh->{"$A/basecount"} + $dbh->{"$A/oacounter"});
		$om->elem("spings skipped (leading zero)",
			$dbh->{"$A/lzskipcount"});
		$om->elem("spings skipped (mask limitation)",
			$dbh->{"$A/maskskipcount"});
		$om->elem("spings minted",
			$dbh->{"$A/basecount"} + $dbh->{"$A/oacounter"}
				- $dbh->{"$A/lzskipcount"}
				- $dbh->{"$A/maskskipcount"});
		my $next_event =	# ids left until expand, stop, or wrap
			$dbh->{"$A/oatop"} - $dbh->{"$A/oacounter"};
		my $unbounded = $dbh->{"$A/unbounded"};
		$om->elem("spings left",
			$unbounded ?  "unlimited" : $next_event);
		$unbounded and $om->elem("spings left before " .
			($dbh->{"$A/expandable"} ? 'blade expansion ("' .
				$dbh->{"$A/atlast"} . '")' : "starting over"),
			$next_event);
		$om->elem("spings held", $dbh->{"$A/held"});
		$om->elem("spings queued", $dbh->{"$A/queued"});
		$om->elem("template", $dbh->{"$A/template"});
		my $random_sample = int(rand(1000));
		$om->elem("sample", sample($dbh, $random_sample));
		$dbh->{"$A/original_template"} ne $dbh->{"$A/template"} and
			$om->elem("original template",
				$dbh->{"$A/original_template"});
			
		return 1;
	}
}

# xxx Nog version needs work!
# Report values according to $level.  Values of $level:
# "brief" (default)	user vals and interesting admin vals
# "full"		user vals and all admin vals
# "dump"		all vals, including all identifier bindings
#
# yyy should use OM better
sub dbinfo { my( $mh, $mods, $level )=@_;

	my $nog = $mh->{tied_hash_ref};
	my $db = $mh->{db};
	my $om = $mh->{om};
	#my $db = $opendbtab{"bdb/$nog"};
	my ($key, $value) = ("$A/", 0);

	if ($level eq "dump") {		# take care of "dump" and return
		#print "$key: $value\n"
		$om->elem($key, $value)
			while ($db->seq($key, $value, R_NEXT) == 0);
		return 0;
	}
	# If we get here, $level is "brief" or "full".

	my $status = $db->seq($key, $value, R_CURSOR);
	if ($status) {
		addmsg($mh, "seq status/errno ($status/$!)");
		return 1;
	}
	if ($key =~ m|^$A/$A/|) {
		#print "User Assigned Values\n";
		$om->elem("Begin User Assigned Values", "");
		#print "  $key: $value\n";
		$om->elem($key, $value);
		while ($db->seq($key, $value, R_NEXT) == 0) {
			last
				if ($key !~ m|^$A/$A/|);
			#print "  $key: $value\n";
			$om->elem($key, $value);
		}
		#print "\n";
		$om->elem("End User Assigned Values", "");
	}
	#print "Admin Values\n";
	$om->elem("Begin Admin Values", "");
	#print "  $key: $value\n";
	$om->elem($key, $value);	# one-off from last test
	while ($db->seq($key, $value, R_NEXT) == 0) {
		last
			if ($key !~ m|^$A/|);
		#print "  $key: $value\n"
		$om->elem($key, $value)
			if ($level eq "full" or
				# $key !~ m|^$A/c\d| &&	# old circ status
				$key !~ m|^$A/saclist| &&
				$key !~ m|^$A/recycle/|);
	}
	$level eq "full" and
		#print durability(
		$om->elem("durability", durability(
			$$nog{"$A/shoulder"},
			$$nog{"$A/mask"},
			$$nog{"$A/generator_type"},
			$$nog{"$A/addcheckchar"},
			$$nog{"$A/atlast"} =~ /^wrap/		));
			#, "\n";
	$om->elem("End Admin Values", "");
	#print "\n";
	return 0;
}

# yyy eventually thought we would like to do fancy fine-grained locking with
#     BerkeleyDB features.  For now, lock before tie(), unlock after untie().
# xxxx maybe delete these?
sub dblock{ return 1;	# placeholder
}
sub dbunlock{ return 1;	# placeholder
}

# A no-op function to call instead of checkchar().
#
sub echo {
	return $_[0];
}

# XXX windows problem chars:   " * : < > ? \ |
# XXX ARK OK chars:   =   #   *   +   @   _   $
# XXX code64 chars:  ...  _  ~
# XXX DataCite DOI ok chars:  "a-z", "A-Z", "0-9" and "-._:/" (slash,
#				but only if followed by alphanumeric)
# XXX CrossRef DOI ok chars:  "a-z", "A-Z", "0-9" and "-._;()/"
# XXX for $nice>0 and sacrificing reverse mapping, change to permit choice
#     to (a) replace _ or ~ with
#     one letter (risk to uniqueness) (b) two letters (risk to length)
#     (c) skipN [skip up to N] (risk to time to generate)
# xxxx document
#    xxx or should this be called ff64 (filename friendly)
# Generate UUIDs encoded in modified Base 64 ("c64"), which uses _ (62)
# and ~ (63) for maximal friendliness in filenames and URLs.  For names
# friendly to XML, run with $niceness > 0.  Since we obtain uuids from
# Data::UUID, we map b64->c64 using tr|+/=|_~|d.
# Optionally, we re-run until we get ids of a given $niceness:
#   0 means don't care (don't re-run ever)
#   1 means replace + and / with +p and +s (don't re-run ever)
#     (reversible by detecting length and assuming + always precedes p or s
#   2 means must start with a letter, and reject ~ anywhere, (ie, re-run)
#   3 means same as 1 and reject _ anywhere. (ie, re-run)
# Beware -- $niceness > 0 can cause things to hang.
# Returns an array of ids.  Each id represents 128 bits that, once
# c64-encoded (6 bits per char), comes in at 22 chars (128/6 = 21.33).
# Note: XML element/attribute names can only start with letters or _
# and may contain digits and <.->
# xxx we have 4 unused bits -- can we add IETF class to it?
# xxx log misses/rejects here and in genid
# xxx need to add check chars
#
# xxx need to catch SIGNALs and stop gracefully with complete logs
# xxx more tests
# yyy create buffer of unnabbed good ones that can be used in times
#     of shortage?

# xxx unused for now
sub gen_c64 { my(   $mh, $mods, $number, $niceness ) =
		( shift, shift,   shift,     shift );

	my $om = $mh->{om};

	defined($number)	or $number = 1;		# caller might want 0
	# $niceness is a measure of how nice the id will be -- it's the
	# opposite of unix niceness since higher $niceness means we consume
	# more system resources.
	#      the more co
	defined($niceness)	or $niceness = 0;	# 0, 1, or 2
	$number > 0		or return undef;	# and flush non-ints

	my ($ug, $id);
	$ug = new Data::UUID;
	my $tries = 0;
	my $n = $number;

	while (1) {
		$tries++;			# for verbose option
		$id = $ug->create_b64();	# note: produces no _

		$niceness == 1 and
			$id =~ tr|=||d,
			$id =~ s|\+|+p|g,
			$id =~ s|/|+s|g,
			$om->elem(SPING, $id),
			next;

		# We use 'tr' with empty replacement list to detect chars
		# (to count chars, actually) more efficiently (in theory)
		# than using a regexp.  We detect chars pre-conversion,
		# ie, before converting / to ~ and + to _.
		#
		$niceness > 1 and $id !~ /^[A-Za-z]/ || $id =~ tr|/|| and
			#print("xxx $id\n"),
			# re-run until starts with alpha and has no /
			next;

		# If here, $id at least passes the $niceness level 2 test.
		#
		$niceness >= 3 and $id =~ tr|+|| and
			next;		# re-run until all alphanums
		$id =~ tr|+/=|_~|d;	# map + to _ and / to ~; delete =
		#push @ids, $id;
		$om->elem(SPING, $id);
	}
	continue {
		last	if $n-- <= 1;
	}
	#$opt{verbose} and
	#	print "rejected ", $tries - $number, " ids\n";
	#return @ids;
	return 1;
}

# usage: nog nab [ number ] [ uuid|hex|b64|c64 [ namespace name ] ]
sub nab { my(   $mh, $mods, $number ) =
	    ( shift, shift,   shift );

	my $om = $mh->{om};
	my ($kind, $namespace, $name);		# other possible args

	# Use defined() since caller might want 0 (eg, from a script).
	defined($number) or			# $number arg was absent
		$number = 1;
	$number =~ /^\d+$/ or			# $number arg absent and it
		$kind = $number,		# appears caller skipped it
		$number = 1;
	$number > 0 or				
		return undef;
	$kind ||= shift || 'c64';		# take $kind from arg list
	$kind = lc $kind;
	($namespace, $name) = (shift || '', shift || '');	# other args
	$namespace = lc $namespace;
	my $nsid =	($namespace eq 'dns' ?	'DNS' :
			($namespace eq 'url' ?	'URL' :
			($namespace eq 'oid' ?	'OID' :
			($namespace eq 'x500' ?	'X500' :
			undef))));
	# To be noticed, both $namespace and $name must be defined.
	$nsid and ! $name and	# namespace id not recognized or null name
		return undef;

	my $bgmn =	($kind eq 'c64' ?  'b64' :
			($kind eq 'hex' ?  'hex' :
			($kind eq 'b64' ?  'b64' :
			($kind eq 'uuid' ? 'str' :
			undef))));
	$bgmn or		# base generator method name not recognized
		return undef;
	my $gen_method = ($nsid ?  'create_from_name_' : 'create_')
				. $bgmn;

	my $ug = new Data::UUID;
	my $n = $number;

	# yyy probably should wrap this loop in an eval since $ug methods
	# have an annoying tendency to croak with usage info
	while (1) {
		my $id = $nsid ? $ug->$gen_method($nsid, $name) :
				$ug->$gen_method();

		# We use 'tr' with empty replacement list to detect chars
		# (to count chars, actually) more efficiently (in theory)
		# than using a regexp.  We detect chars pre-conversion,
		# ie, before converting / to ~ and + to _.
		#
		$kind eq 'c64' and	# map + to _ and / to ~; and delete =
			$id =~ tr|+/=|_~|d;
		#push @ids, $id;
		$om->elem(SPING, $id);
	}
	continue {
		last	if $n-- <= 1;
	}
	#$opt{verbose} and
	#	print "rejected ", $tries - $number, " ids\n";
	#return @ids;
	return 1;
}

# Generate the actual next id to give out.  May be randomly or sequentially
# selected.  This routine should not be called if there are ripe recyclable
# identifiers to use.  Returns array of (id, atlast_action, atlast_typenum).
# This routine and n2xdig comprise the real heart of the minter software.
#
sub genid { my( $mh )=@_;
	dblock();

	# Variables:
	#   oacounter	overall counter's current value (last value minted)
	#   oatop	overall counter's greatest possible value of counter
	#   saclist	(sub) active counters list
	#   siclist	(sub) inactive counters list
	#   c$n/value	subcounter name's ($scn) value

	my $nog = $mh->{tied_hash_ref};
	my $db = $mh->{db};
	my $oacounter = $$nog{"$A/oacounter"};
	my $hname = $mh->{objname};

	my ($atlast, $tnum);
	my $status;

	# yyy what are we going to do with counters for held? queued?

	if ($oacounter >= $$nog{"$A/oatop"}) {

		# We are here because if we proceeded normally we would
		# exceed the capacity of the current template, so we have
		# to figure out whether we will expand (default), stop,
		# or wrap.
		#
		# Usually we get here when the previous call actually
		# exhausted the template, but we don't take action until
		# just before the attempt to exceed capacity.  Consult stored
		# action pass back any status number associated with it so
		# that the process will exit with that status; this permits
		# the database creator say whether (eg, non-zero status)
		# and how they want to be notified of the event.
		#
		my $m;
		$atlast = $$nog{"$A/atlast"};
		# The next call returns 3 elements, but we only need 1st.
		($tnum) = atlast_type($atlast);
		if ($tnum =~ /[a-z]/i) {	# $tnum may be overloaded
			$m = "problem with action (" . $$nog{"$A/atlast"} .
				") defined after last generated sping: $tnum";
			addmsg($mh, $m);
			$mh->{rlog}->out("N: $m");
			return (undef, $atlast, $tnum);
		}
		# If we get here, $tnum should be a non-negative integer.

		if ($$nog{"$A/atlast"} =~ /^add/) {

			my $oldtemplate = $$nog{"$A/template"};
			my $oldmask = $$nog{"$A/mask"};
			# temporarily strip any final check char,
			#     because it makes no sense to replicate it
			# xxx warn about this on minter creation???
			$oldmask =~ s/k$//;
			# XXX document that if fewer than $tnum chars in
			# the mask, then just repeat the first (1) char,
			# eg, add3 and {dk} creates {ddk}, {dddk}, {ddddddk}
			length($oldmask) < $tnum and	# downgrade if not at
				$tnum = 1;	# least $tnum chars in template
			my $newmask = $$nog{"$A/mask"};
			my ($template, $shoulder, $total);
#			do {
				# xxx pattern [def] depends on current
				#     limited char repertoire symbols
				$newmask =~ s/^([def]{$tnum})(.*)/$1$1$2/;
				$template = $$nog{"$A/shoulder"} . "{$newmask}";
				$total = parse_template($template,
					$shoulder, $newmask, $m);
					# defines $m or defines $shoulder
					# and $newmask
#			} while ($total and $total <= $oacounter);
#			# yyy loop because oacounter may --start quite high

			unless ($total) {
				$m = "problem creating new template " .
					"($template) on action (" .
					$$nog{"$A/atlast"} . ") defined " .
					"after last generated id for old " .
					"template (" . $$nog{"$A/template"} .
					"): $m";
				addmsg($mh, $m);
				$mh->{rlog}->out("N: $m");
				return (undef, $atlast, $tnum);
			}

# xxx not safe, better to 
#    isolate those db changes that belong
#    together when either doing it the first
#    time via mkminter or any subsequent time
#sub set_totals { my( $nog, $mask, $template, $total, $oacounter )=@_;
#			$$nog{"$A/mask"} = $newmask;
#			$$nog{"$A/template"} = $template;
#
#			# yyy are total and oatop ever different?
#			$$nog{"$A/total"} = $total;
#			$$nog{"$A/oatop"} = $total;
#
#			if ($$nog{"$A/type"} !~ /^seq/) {
#				# We're in a "random" type minter
#				# yyy calls dblock -- problem?
#	?			init_counters($nog);
#	?			$$nog{"$A/basecount"} += $oacounter;
#	?			$$nog{"$A/oacounter"} = $oacounter = 0;
#			}
#
#}

			$$nog{"$A/mask"} = $newmask;
			$$nog{"$A/template"} = $template;

			# yyy are total and oatop ever different?
			$$nog{"$A/total"} = $total;
			$$nog{"$A/oatop"} = $total;

#			if ($$nog{"$A/type"} !~ /^seq/) {
				# We're in a "random" type minter
				# yyy calls dblock -- problem?
				init_counters($nog);
# XXXXX maybe these next two lines belong even in sequential minters
				$$nog{"$A/basecount"} += $oacounter;
				$$nog{"$A/oacounter"} = $oacounter = 0;
				# evercounted = basecount + oacounter
#			}
		# XXX $m doesn't make it to caller if skipping spings
		# XXX not shouldn't print $m except when $verbose?
			$m = "chars added (via $atlast) to template "
				. "'$oldtemplate' to create '$template'";
			addmsg($mh, $m, 'note');
			$mh->{rlog}->out("N: $m");
		}
		elsif ($$nog{"$A/atlast"} =~ /^stop/) {
			dbunlock();
		# XXX $m doesn't make it to caller if skipping spings
		# XXX not shouldn't print $m except when $verbose?
			$m = "spings exhausted (configured to stop at " .
				$$nog{"$A/oatop"} . ").";
			addmsg($mh, $m, 'note');
			$mh->{rlog}->out($m);
			return (undef, $atlast, $tnum);
		}
		elsif ($$nog{"$A/atlast"} =~ /^wrap/) {
		# XXX $m doesn't make it to caller if skipping spings
		# XXX not shouldn't print $m except when $verbose?
			$m = "resetting counter - previously issued " .
				"spings will be re-issued";
			addmsg($mh, $m, 'note');
			$m = temper() . ": $m";
			$mh->{rlog}->out("N: $m");
			# We don't return, even though we left a message.

			#if ($$nog{"$A/type"} =~ /^seq/) {
			#	$$nog{"$A/oacounter"} = 0;
			#}
			#else {
			#	# yyy calls dblock -- problem?
			#	init_counters($nog);
			#}

			init_counters($nog);
			$$nog{"$A/oacounter"} = $oacounter = 0;
		}
	}
	# If we get here, the counter may actually have just been reset.

	# Deal with the easy sequential generator case and exit early.
	#
	if ($$nog{"$A/type"} =~ /^seq/) {
		my $id = n2xdig($$nog{"$A/oacounter"}, $$nog{"$A/mask"});

		# Increment to reflect new total.  Important to use db->put
		# (instead of, eg, ++) or we can't detect or report an error
		# to callers whose mint fails simply because they don't have
		# write access to the minter.
		#
		#$$nog{"$A/oacounter"}++;	# incr to reflect new total
		$status = $db->put("$A/oacounter", $$nog{"$A/oacounter"} + 1);
		dbunlock();
		if ($status == 1) {
			addmsg($mh, "cannot store in $hname");
			return (undef, $atlast, $tnum);
		}
		return ($id, $atlast, $tnum);
	}

	# If we get here, the generator must be of type "random".
	#
	my $len = (my @saclist = split(/ /, $$nog{"$A/saclist"}));
	if ($len < 1) {
		dbunlock();
		addmsg($mh, "no active counters panic, " .
			"but $oacounter spings left?");
		return (undef, $atlast, $tnum);
	}

	# If we're not a sequential minter, next is the important
	# seeding of random number generator.
	# We need this so that we get the same exact series of
	# pseudo-random numbers, just in case we have to wipe out a
	# generator and start over.  That way, the n-th sping
	# will be the same, no matter how often we have to start
	# over.
	#
	# xxxx this doesn't work? for ActiveState Perl?
	#srand($$nog{"$A/oacounter"});

	if ($$nog{"$A/type"} =~ /^rand/) {	# if random, set seed

		# This block used to be called before genid, but that
		# meant, on template expansion, that it used the oacounter
		# value before it had been reset to 0, and therefore
		# spings for two identical templates, one of them born
		# that way and the other the result of an exansion, would
		# produce different orderings.  Not good.

		# normally set to counter value, but in
		# presence of a germ, use it as a multiplier with
		# counter+1 to create seed (+1 to prevent first
		# seed from being zero for every germ.
		# XXXXX BigInt or overflow problem? ??

		# xxx? perldoc says you should call srand only
		# once per process, but we will call it N times
		# if nog user says "mint N"
		srand(	$$nog{"$A/germ"} ?
			($$nog{"$A/germ"} *
				($$nog{"$A/oacounter"} + 1) %
					GERM_RANGE) :
			$$nog{"$A/oacounter"} );

	}

	my $randn = int(rand($len));	# pick a specific counter name
	my $sctrn = $saclist[$randn];	# at random; then pull its $n
	my $n = substr($sctrn, 1);	# numeric equivalent from the name
	#print "randn=$randn, sctrn=$sctrn, counter n=$n\t";
	my $sctr = $$nog{"$A/${sctrn}/value"};	# and get its value
	$sctr++;				# increment and

	# store new current value with write status check
	#$$nog{"$A/${sctrn}/value"} = $sctr;
	$status = $db->put("$A/${sctrn}/value", $sctr);
	# increment overall counter - some redundancy for sanity's sake
	#$$nog{"$A/oacounter"}++;
	$status ||= $db->put("$A/oacounter", $$nog{"$A/oacounter"} + 1);
	if ($status == 1) {	# hopefully ||= caught either error
		dbunlock();
		addmsg($mh, "cannot store in $hname");
		return (undef, $atlast, $tnum);
	}

	# deal with an exhausted subcounter
	if ($sctr >= $$nog{"$A/${sctrn}/top"}) {
		my ($c, $modsaclist) = ("", "");
		# remove from active counters list
		foreach $c (@saclist) {		# drop $sctrn, but add it to
			next if ($c eq $sctrn);		# inactive subcounters
			$modsaclist .= "$c ";
		}
		# update saclist
		#$$nog{"$A/saclist"} = $modsaclist;
		$status = $db->put("$A/saclist", $modsaclist);
		# and update siclist
		#$$nog{"$A/siclist"} .= " $sctrn";
		$status ||= $db->put("$A/siclist", $$nog{"$A/siclist"}
			. " $sctrn");
		if ($status == 1) {	# hopefully ||= caught either error
			dbunlock();
			addmsg($mh, "cannot store in $hname");
			return (undef, $atlast, $tnum);
		}
		#print "===> Exhausted counter $sctrn\n";
	}

	# xxx optimize with BigInt methods??  Do we need 'use bignum'?
	# $sctr holds counter value, $n holds ordinal of the counter itself
	my $id = n2xdig(
			$sctr + ($n * $$nog{"$A/percounter"}),
			$$nog{"$A/mask"});
	dbunlock();
	return ($id, $atlast, $tnum);
}

# XXXXXXXXX ??? change all admin info to be ???
# ZZZZZ this would be database change, to be noted by 'convertdb'
#    which could all future uses of $id as prefix for extended ids?
#     :/held_ids/$id
#     :/queued_ids/$id
#     :/pepper/$id
#     :/idmap/$ElementName (eg, "goto")
#     :/holdpattern/$idpattern
# Identifier admin info is stored in three places:
#
#    id\t:/h	hold status: if exists = hold, else no hold
#    id\t:/p	pepper
## (deprecated):
##    id\t:/c	circulation record, if it exists, is
##		    circ_status_history_vector|when|contact(who)|oacounter
##			where circ_status_history_vector is a string of [iqu]
##			and oacounter is current overall counter value, FWIW;
##			circ status goes first to make record easy to update


# XXXXX do big rethink of this
# Return string suitable for log format, eg, ANVL.
# Arguments expected in roughly who/what/when/where paradigm.
# XXX should do true anvl encoding of any | delimiters found
#     so values can be read back correctly
#
sub logfmt {

	return join("|", @_);
}

#=for deleting
## Simple ancillary counter that we currently use to pair a sequence number
## with each minted identifier.  However, these are independent actions.
## The direction parameter is negative, zero, or positive to count down,
## reset, or count up upon call.  Returns the current counter value.
##
## (yyy should we make it do zero-padding on the left to a fixed width
##      determined by number of digits in the total?)
##
#sub count { my( $nog, $direction )=@_;
#
#	$direction > 0
#		and return ++$$nog{"$A/seqnum"};
#	$direction < 0
#		and return --$$nog{"$A/seqnum"};
#	# $direction must == 0
#	return $$nog{"$A/seqnum"} = 0;
#}
#=cut

# A hold may be placed on an string to keep it from being minted/issued.
# Returns ref to array of failed single ids, undef on complete failure, or
# () on full success.
# 
sub hold { my( $mh, $mods, $lcmd, $on_off, @ids )=@_;

	my $nog = $mh->{tied_hash_ref};
	#my $contact = $mh->{ruu}->{who};
	my $db = $mh->{db};
	my $om = $mh->{om};

	#! defined($contact) and
	#	addmsg($mh, "error: contact undefined"),
	#	return undef;
	! defined($on_off) and
		addmsg($mh, qq@error: hold "set" or "release"?@),
		return undef;
	! @ids and
		addmsg($mh, qq@error: no Id(s) specified@),
		return undef;
	$on_off ne "set" && $on_off ne "release" and
		addmsg($mh, "error: unrecognized hold directive ($on_off)"),
		return undef;

	my $release = $on_off eq "release";
	# yyy what is sensible thing to do if no ids are present?
	# xxx maybe we should validate unless --force?
	my $spingerror = "";
	$$nog{"$A/genonly"} and
		#($spingerror = validate($nog, "-", @ids)) !~ /error:/ and
		($spingerror = validate($nog, "-", "", @ids)) !~ /error:/ and
			$spingerror = "";
	$spingerror and
		addmsg($mh, "error: hold operation not started -- one or "
			. "more ids did not validate:\n$spingerror"),
		return undef;
	my $status;

	# If we get here, all pre-conditions for success have been met
	# and any prior failures had nothing to do with single-id errors.
	#
	my @reterrs = ();	# () means no single-id errors so far
	for my $id (@ids) {
		if ($release) {		# no hold means key doesn't exist
			dblock();
			$status = hold_release($mh, $id);
		}
		else {			# "hold" means key exists
			dblock();
			$status = hold_set($mh, $id);
		}
		dbunlock();
		$status		or push(@reterrs, $id),

		# Incr/Decrement for each id rather than by scalar(@ids);
		# if something goes wrong in the loop, we won't be way off.

		# XXX should we refuse to hold if "long" and issued?
		#     else we cannot use "hold" in the sense of either
		#     "reserved for future use" or "reserved, never issued"
		#
	}
	my $m;
	$m = $mh->{rlog}->out("C: $on_off $lcmd " . join(" ", @ids)) and
		addmsg($mh, $m),
		return undef;
	return \@reterrs;
}

# Returns 1 on success, 0 on error.  Use dblock() before and dbunlock()
# after calling this routine.
# yyy don't care if hold was in effect or not
#
sub hold_set { my( $mh, $id )=@_;

	my $nog = $mh->{tied_hash_ref};
	$$nog{"$id\t$A/h"} = 1;		# value doesn't matter
	$$nog{"$A/held"}++;
	return 1;
}

# Returns 1 on success, 0 on error.  Use dblock() before and dbunlock()
# after calling this routine.
# yyy don't care if hold was in effect or not
# yyy noid only, not bind
#
sub hold_release { my( $mh, $id )=@_;

	my $nog = $mh->{tied_hash_ref};
	#$mh->{db}->del("$id\t$A/h");
# xxxx check return!!
	delete($$nog{"$id\t$A/h"});
	$$nog{"$A/held"}--;
	if ($$nog{"$A/held"} < 0) {
		my $m = "error: hold count (" . $$nog{"$A/held"}
			. ") going negative on id $id";
		addmsg($mh, $m);
		$mh->{rlog}->out("N: $m");
		return 0;
	}
	return 1;
}

## XXXXX feature from EZID UI redesign: list ids, eg, by user
## XXXXX feature from EZID UI redesign: sort, eg, by creation date
#
## Return $val constructed by mapping the element
## returns () if nothing found, or (undef) on error
## XXX so how does a return() differ from return(undef) ?
#
#sub id2elemval { my( $mh, $db, $id, $elem )=@_;
#
#	my $first = "$A/idmap/$elem\t";
#	my ($key, $value) = ($first, 0);
#	my $status = $db->seq($key, $value, R_CURSOR);
#	$status and
#		addmsg($mh, "id2elemval: seq status/errno ($status/$!)"),
#		return (undef);
#	$key !~ /^\Q$first/ and
#		return ();
#	# untaint $id
#	$id =~ m|^(.*)$| and
#		$id = $1;
#
#	# This loop exhaustively visits all patterns for this element.
#	# Prepare eventually for dups, but for now we only do first.
#	# XXX document that only the first dup works $db->seq. (& fix?)
#	#
#	my ($pattern, $newval, @dups);
#	while (1) {
#
#		# The substitution $pattern is extracted from the part of
#		# $key that follows the \t.
#		#
#		($pattern) = ($key =~ m|\Q$first\E(.+)|);
#		$newval = $id;
#
#		# xxxxxx this next line is producing a taint error!
#		# xxx optimize(?) for probable use case of shoulder
#		#   forwarding (eg, btree search instead of exhaustive),
#		#   which would work if the patterns are left anchored
#		defined($pattern) and
#			# yyy kludgy use of unlikely delimiters
#		# XXX check $pattern and $value for presence of delims
#		# XXX!! important to untaint because of 'eval'
#
#			# The first successful substitution stops the
#			# search, which may be at the first dup.
#			#
#			(eval '$newval =~ ' . qq@s$pattern$value@ and
#				return ($newval)),	# succeeded, so return
#			($@ and			# unusual error failure
#				addmsg($mh, "id2elemval eval: $@"),
#				return (undef))
#			;
#		db->seq($key, $value, R_NEXT) != 0 and
#			return ();
#		$key !~ /^\Q$first/ and		# no match and ran out of rules
#			return ();
#	}
#}

# Initialize sub-counters.
#
sub init_counters { my( $nog )=@_;

	# Variables:
	#   oacounter	overall counter's current value (last value minted)
	#               NB: oacounter counts only current template but
	#               not prior templates (pre-expansion); therefore
	#               the total number of spings for the minter is
	#               actually basecount plus oacounter
	#   saclist	(sub) active counters list
	#   siclist	(sub) inactive counters list
	#   c$n/value	subcounter name's ($n) value
	#   c$n/top	subcounter name's greatest possible value

	dblock();

	#$$nog{"$A/oacounter"} = 0;
	my $total = $$nog{"$A/total"};

	my $maxcounters = 293;		# prime, a little more than 29*10
	#
	# Using a prime under the theory (unverified) that it may help even
	# out distribution across the more significant digits of generated
	# strings.  In this way, for example, a method for mapping an
	# string to a pathname (eg, fk9tmb35x -> fk/9t/mb/35/x/, which
	# could be a directory holding all files related to the named
	# object), would result in a reasonably balanced filesystem tree
	# -- no subdirectories too unevenly loaded.  That's the hope anyway.

	$$nog{"$A/percounter"} =	# max per counter, last has fewer
		int($total / $maxcounters + 1);		# round up to be > 0

	my $n = 0;
	my $t = $total;
	my $pctr = $$nog{"$A/percounter"};
	my $saclist = "";
	while ($t > 0) {
		$$nog{"$A/c${n}/top"} = ($t >= $pctr ? $pctr : $t);
		$$nog{"$A/c${n}/value"} = 0;		# yyy or 1?
		$saclist .= "c$n ";
		$t -= $pctr;
		$n++;
	}
	$$nog{"$A/saclist"} = $saclist;
	$$nog{"$A/siclist"} = "";
	$n--;

	dbunlock();

	#print "saclist: $$nog{"$A/saclist"}\nfinal top: "
	#	. $$nog{"$A/c${n}/top"} . "\npercounter=$pctr\n";
	#foreach $c ($$saclist) {
	#	print "$c, ";
	#}
	#print "\n";
}

# This routine produces a new string by taking a previously recycled
# string from a queue (usually, a "used" string, but it might
# have been pre-recycled) or by generating a brand new one.
#
# Returns an array of ($id, $atlast, $tnum), where
#     $id is generated id, or undef on error
#     $atlast is "wrap", "stop" or "add"  xxx or addN?
#     $tnum is atlast typenumber, or suggested process exit status in
#         case of 'wrap' or 'stop'
# 
	# XXXXXX could use a way to analyze id and see if it has been minted
	#        (without, eg, needing a circ record to be able to tell)

sub mint { my( $mh, $mods, $lcmd, $pepper )=@_;

	my $nog = $mh->{tied_hash_ref};
	#my $contact = $mh->{ruu}->{who};
	my $db = $mh->{db};
	my $om = $mh->{om};
	$lcmd ||= 'mint';

	my $txnid;		# undefined until first call to tlogger
	$txnid = tlogger $mh, $txnid, "BEGIN $mh->{minder_file_name}: $lcmd";
	# yyy should really call this with a session handler ($sh) -- oh well

	# Check if the head of the queue is ripe.  See comments under queue()
	# for an explanation of how the queue works.
	#
	my $currdate = temper();		# 14 digits
	my $first = "$A/q/";
	#my $db = $opendbtab{"bdb/$nog"};

	# The following is not a proper loop.  Its purpose is to see if
	# we will get our id from the queue instead of generating a new
	# one.  Normally it should run once, but several cycles may be
	# needed to weed out anomalies with the id at the head of the
	# queue.  If all goes well and we found something to mint from
	# the queue -- in which case the queue head is "ripe" for harvest
	# -- then the last line in the loop exits the routine.  If we
	# drop out of the loop, it's because the queue wasn't ripe.
	# 
	my ($id, $m, $status, $key, $qdate);
	while (1) {
		$key = $first;
		$status = $db->seq($key, $id, R_CURSOR);
		$status and
			addmsg($mh, "mint: seq status/errno ($status/$!)"),
			return undef;
		# The cursor, key and value are now set at the first item
		# whose key is greater than or equal to $first.  If the
		# queue was empty, there should be no items under "$A/q/".
		#
		#($qdate) = ($key =~ m|$A/q/(\d{14})|);
		($qdate) =
			# XXX Note: dependancy on temper() output format!!
			($key =~ m|$A/q/(:?\d{14})|);
			#($key =~ m|$A/q/(\d\d\d\d.\d\d.\d\d.\d\d:\d\d:\d\d)|);
		! defined($qdate) and			# nothing in queue
			# this is our chance -- see queue() comments for why
			($$nog{"$A/fseqnum"} > SEQNUM_MIN and
				$$nog{"$A/fseqnum"} = SEQNUM_MIN),
			last;				# so move on
		# If the date of the earliest item to re-use hasn't arrived
		#$currdate < $qdate and
		$currdate lt $qdate and
			last;				# move on

		# If we get here, head of queue is ripe, so we remove it.
		# Any "next" statement from now on in this loop discards the
		# queue element.
		#
	# XXXX queue delete never worked? never was advertized
	# XXXXXXXXXXXXXXXXXXXXXXXX
	# XXXXX need to do this properly with a routine that is
	# exactly consistent with the queue subroutine, 
	# XXXX ie, need to delete the qposition key and log
		$status = $db->del($key);
		$status and
			addmsg($mh, "mint: del status/errno ($status/$!)"),
			return undef;
		if ($$nog{"$A/queued"}-- <= 0) {
			$m = "error: queued count (" . $$nog{"$A/queued"}
				. ") going negative on id $id";
			addmsg($mh, $m);
			$mh->{rlog}->out("N: $m");
			return undef;
		}

		# We perform a few checks first to see if we're actually
		# going to use this string.  First, if there's a hold,
		# remove it from the queue and check the queue again.
		#
		exists($$nog{"$id\t$A/h"}) and		# if there's a hold
			next;

# XXXX move comments below to documentation of new minter and change history

# Redoing this circulation record stuff and its associated complexity,
# much of it a by-product of the extra error conditions it introduces,
# which in turn require consistency checks; eg, circulation record claims
# status is something other than the minter structures (queue or hold
# tag) claims.  The circulation record also only recorded a lossy summary
# of events that might affect an id, not the complete history that a log
# file can record.  This change should have minimal external impact, as
# the circulation record was for internal use only.
# 
# Originally, the idea was to account rigorously for each id issued,
# but that can be achieved more efficiently and flexibly by the caller
# if we write out all significant events to the log file (noid.log).
# The caller will have its own accounting policies which noid cannot
# fully anticipate.
# 
# This change also means that noid minters won't slowdown in maturity.
# Because BerkeleyDB (DB_File) rebalances its BTree before each insertion
# (to achieve very high retrieval performance, which we don't need for
# circulation records), noid experiences a significant slowdown after
# inserting the millionth (or so) id.  Instead of inserting into the
# BTree, we append to a log file, which can be used to reconstruct the
# entire state of the minter.

# Incompatible:  can no longer pre-cycle using just 'queue' (have to use
#    hold also to prevent the subsequent minting of an string
#    xxx build test case to test this!! maybe invent 'reserve'?)


		# If we get here, our string has now passed its tests.

		$m = $mh->{rlog}->out("C: $lcmd") and
			addmsg($mh, $m),
			return undef;
		$m = $mh->{rlog}->out("N: $lcmd from queue") and
			addmsg($mh, $m),
			return undef;
		# XXXXXXX log test!! need to log the fact that we got it
		#         from the queue
		$m = "mint: " . logfmt($id, $currdate,
			"from queue", $$nog{"$A/oacounter"});
		$mh->{rlog}->out("N: $m");
		$om->elem(SPING, $id);

		tlogger $mh, $txnid, "END SUCCESS $lcmd: $id";

		return $id;		# yyy an array of 1?

	}

	# If we get here, we're not getting an id from the queue.
	# Instead we have to generate one.
	#
	# As above, the following is not a proper loop.  Normally it should
	# run once, but several cycles may be needed to weed out anomalies
	# with the generated id (eg, there's a hold on the id, or it was
	# queued to delay issue).
	# 
	my ($atlast, $tnum);
	my $oklz = $$nog{"$A/oklz"};
	my $lzskipped = 0;		# used to update {$A/lzskipcount}
	my $maskskipped = 0;		# used to update {$A/maskskipcount}
	while (1) {

		# The id returned in this next step may have a "+" character
		# that n2xdig() appended to it.  The checkchar() routine
		# will convert it to a check character.
		#
		($id, $atlast, $tnum) = genid($mh);

		defined($id) or		# use defined since "0" is a valid id
			return ($id, $atlast, $tnum);
		$id eq '' and				# empty string means
			$maskskipped++,			# n2xdig can't do it,
			next;				# so we must skip it
		! $oklz and				# if option says no
			substr($id, 0, 1) eq '0' and	# and there's a leading
			$lzskipped++,			# zero, skip this one
			next;

		# XXXXXX
		# here is where we screen for things like
		#   template chars 'a' (alpha only)
		# and re-call genid for another try

		# Prepend shoulder if there is one.
		#
		$$nog{"$A/shoulder"} and
			$id = $$nog{"$A/shoulder"} . $id;

		# Add check character if called for.
		#
		$$nog{"$A/addcheckchar"} and
			$id = &checkchar($id);

		# There may be a hold on an id, meaning that it is not to
		# be issued (or re-issued).
		#
		exists($$nog{"$id\t$A/h"}) and		# if there's a hold
			next;				# do genid() again

# XXXXX
# should end here with (a) check that it's not queued and (b) return $id;
# XXXXXX need to have a ':/queued_ids/$id' key to quickly tell if an $id
#        is in the queue; still need queue itself for position/timing

		# If the id we just generated is in the queue (clearly
		# not at the head of the queue, or we would have seen it
		# in the previous while loop), we'll generate another id.
		# 
		if (inqueue($nog, $id)) {
			$mh->{rlog}->out("skip: " . logfmt(
				"genid() gave $id, which was in the queue"));
			next;
		}

		# xxx move this line (and lines like it in this routine)
		#     to up before beginning the operation
		# xxx in its place put an N: line showing the result in the
		#    form N: who_asked | got what_id_minted | sub-counter used?
		$m = $mh->{rlog}->out("C: $lcmd") and
			addmsg($mh, $m),
			return undef;
		$m = "mint: " . logfmt($id, $currdate,
			"from genid()", $$nog{"$A/oacounter"});
		# yyy this next log line is commented out as too verbose
		#$mh->{rlog}->out("N: $m");
		$lzskipped and
			$$nog{"$A/lzskipcount"} += $lzskipped;
		$maskskipped and
			$$nog{"$A/maskskipcount"} += $maskskipped;
		$om->elem(SPING, $id);

		tlogger $mh, $txnid, "END SUCCESS $lcmd: $id";

		return ($id, $atlast, $tnum);
	}

# xxx could really use a routine to see if a given id has been minted
#     by reverse engineering the part of the idspace it belongs to and
#     checking if the associated counter is high enough; could use it to
#     issue a note when an id is produced before it would normally be
#     generated (because it was put ahead in the queue)
#	# yyy
#	# Note that we don't assign any value to the very important key = $id.
#	# What should it be bound to?  Let's decide later.

	# yyy
	# Often we want to bind an id initially even if the object or record
	# it identifies is "in progress", as this gives way to begin tracking,
	# eg, back to the person responsible.

}
# end of mint routine

# Convert a number to an extended digit according to $mask and $generator_type
# and return (without shoulder (eg, NAAN)).  A $mask character of 'k' gets
# converted to '+' in the returned spings; post-processing will eventually
# turn it into a computed check character.
#
# Returns converted number or, if 'f' (filtered extended digit) appears
# in the mask and the number can't be converted, return the empty string.
#
sub n2xdig { my( $num, $mask )=@_;
	my $s = '';
	my ($div, $remainder, $c);

	# Confirm well-formedness of $mask before proceeding.
	#
	$mask !~ /^[def]+k?$/
		and return undef;

	my $varwidth = 0;	# we start in fixed width part of the mask
	my @rmask = reverse(split(//, $mask));	# process each char in reverse
	my $schar;

	# Loop while either there's some $num left to output, or we still
	# have mask chars to match with a padding character.
	#
	while ($c = shift @rmask) {

		$c =~ /[ef]/ and
			$div = $alphacount
		or
		$c =~ /d/ and
			$div = $digitcount
		or
		$c =~ /k/ and
			next
		;
#=for later
## why is this slower?  should be faster since it does NOT use regexprs
#			! defined($c) ||	# terminate on r or s even if
#				$c eq 'r' || $c eq 's'
#				and last;	# $num is not all used up yet
#			$c eq 'e' and
#				$div = $alphacount
#			or
#			$c eq 'd' and
#				$div = $digitcount
#			or
#			$c eq 'z' and
#				$varwidth = 1	# re-uses last $div value
#				and next
#			or
#			$c eq 'k' and
#				next
#			;
#=cut
# XXXXXXXXXXXX under BigInt see if $x->digit(n) & $x->brsft() makes this faster
#		and check for other arithmetic optimizations

		$remainder = $num % $div;
		$num = int($num / $div);
		$schar = $xdig[$remainder];
		$c eq 'f' and $schar =~ /\d/ and	# mask with 'f' can't
			return '';			# convert all numbers
		$s = $schar . $s;
		#$s = $xdig[$remainder] . $s;
	}
	$mask =~ /k$/ and	# if it ends in a check character, represent
		$s .= "+";	# it with a plus sign in the new id's blade
	return $s;
}

# yyy templates should probably have names, eg, jk##.. could be jk4
#	or jk22, as in "./noid testdb/jk4 <command> ... "

# Reads template looking for errors and returns the total number of
# spings that it is capable of generating with current blade (before
# expansion.  Returns 0 on error.  Variables $shoulder,
# $mask, and $generator_type are output parameters.
#
# $message will always be set; 0 return with error, 1 return with synonym

# imake_db (or make_db) needs options for 
#  --stop, --wrap, --bigint, --record_minted, ...
#  --posthold regexp ('hold' on every matching id just after issuing)
#    eg, -posthold .   (hold after every id)
# --prehold regexp (hold every id matching), eg, --prehold ^x..,
#   for shoulder 'x', skip all ids of 3 chars in length

# "cast" a "die", ie, mint an id that is shoulder of a minter
# return new shoulder on success, "" on failure (see returned $message)
# sub cast { my( $contact, $shoulder, $message )=@_;
# 
# 	my $msg = \$_[2];	# so we can modify $message argument easily
# 	$$msg = "";
# 
# 	my ($caster, $report, $cast);
# 	#xxxxxxx get minderhome and def_caster, etc from noid
# 	$caster = catfile($minderhome, $def_caster);
# 	-f $caster or			# if caster doesn't exist, make it
# 		# xxxx imake_db has to become make_db with all the options
# 		($$msg = imake_db($caster, $caster_template)) and
# 			return "";
# 
# 	# Caster database should exist.  Open it.
# 	($cast = Nog::dbopen($caster, O_RDWR)) or
# 		($$msg = Nog::outmsg($cast)),
# 		return "";
# 
# 	if ($shoulder) {
# 		$$msg = "cannot specify shoulder at this time";
# 		return "";
# 
# 	# xxxxxxxxx
# 	# states of an id/di(e): issued, minted, held, queued
# 	# a "hold" can go on an unborn or born id, right?
# 	# xxx change? hold->reserve ? queue->recycle ?
# 		isboundorheld($cast, $shoulder) and
# 			($$msg = "shoulder already taken: $shoulder"),
# 			return "";
# 		hold($cast, $contact, "set", $shoulder) or
# 			($$msg = "couldn't place hold on $shoulder"),
# 			return "";
# 	}
# 	else {
# 		($shoulder = Nog::mint($cast, $contact)) or
# 			($$msg = Nog::outmsg($cast)),
# 			Nog::dbclose($cast),
# 			return "";
# 	}
# 
# 	Nog::dbclose($cast);
# 	return $shoulder;
# }

# Returns total number of mintable ids under this template, assuming the
# minter stops when limit is reached (no continuation).
#
sub parse_template { my( $template, $shoulderR, $maskR, $msgR  ) =
			( $_[0],     \$_[1],     \$_[2], \$_[3] );

	$$msgR = "";
	my $me = "parse_template";

	# Strip final spaces and slashes.  If there's a pathname,
	# save directory and final component separately.
	#
	$template ||= "";
	$template =~ s|[/\s]+$||;	# strip final spaces or slashes
	$template =~ s|^\s*||;		# strip initial spaces

	# yyy what does a template of "-" mean?
	! $template || $template eq "-" and
		$$msgR = "$me: no minting possible.",
		return 0;
	# critical shoulder/mask separation
	# XXX must support escaping of '{' and '}' chars!!
	# xxx should support multi-part masks, eg, foo{eed}bar{edk}
	$template !~ /^([^{]*){([^}]+)}(.+)?$/ and
		$$msgR = "$me: no template mask - can't generate spings.",
		return 0;
	my ($shoulder, $mask, $more) = ($1 || "", $2, $3);
	$more and
		$$msgR = "$me: extra chars ($more) not allowed after first " .
			"{} (yet).",
		return 0;

	$mask !~ /^[^k]+k?$/ and
		$$msgR = "$me: exactly one check character "
			. "(k) is allowed, and it may\nonly appear at the "
			. "end of a string of one or more mask characters.",
		return 0;

	$mask !~ /^[def]+k?$/ and
		$$msgR = "$me: the mask ($mask) may contain only the "
			. "letters 'd', 'e', or 'f'.",
		return 0;

	# Check shoulder for errors.
	#
	my $c;
	my $has_cc = ($mask =~ /k$/);
	for $c (split //, $shoulder) {
		if ($has_cc && $c ne '/' && ! exists($ordxdig{$c})) {
			$$msgR = "$me: the check character in your template, "
				. "$template, has reduced effectiveness "
				. "because the shoulder ($shoulder) contains "
				. "a character ($c) outside the recommended "
				. "repertoire: '$legalstring'.";
			#$$msgR = "$me: with a check character at the end of "
			#	. "$template, the shoulder ($shoulder) can only"
			#	. " contain characters from '$legalstring'.";
			#return 0;
		}
	}

	my $total = 1;
	for $c (split //, $mask) {
		# Mask chars it could be are: d e k
		$c =~ /d/ and
			$total *= $digitcount
		or
		$c =~ /e/ and
			$total *= $alphacount
		or
		$c =~ /f/ and
			$total *= $alphacount
		or
		$c =~ /k/ and
			next
		;
	}

	$$shoulderR = $shoulder;
	$$maskR = $mask;
	return $total;
}

# An string may be queued to be issued/minted.  Usually this is used
# to recycle a previously issued string, but it may also be used to
# delay or advance the birth of an string that would normally be
# issued in its own good time.  The $when argument may be "first", "lvf",
# "delete", or a number and a letter designating units of seconds ('s',
# the default) or days ('d') which is a delay added to the current time;
# a $when of "now" means use the current time with no delay.
# xxxx "now" sounds more immediate than vanilla -- is there better word?

# The queue is composed of keys of the form $A/q/$qdate/$seqnum/$paddedid,
# with the correponding values being the actual queued strings.  The
# Btree allows us to step sequentially through the queue in an ordering
# that is a side-effect of our key structure.  Left-to-right, it is
#
#	:/q/		$A/q/, 4 characters wide
#	$qdate		14 digits wide, or 14 zeroes if "first" or "lvf"
#	$seqnum		6 digits wide, or 000000 if "lvf"
#	$paddedid	id "value", zero-padded on left, for "lvf"
# 
# The $seqnum is there to help ensure queue order for up to a million queue
# requests in a second (the granularity of our clock).  [ yyy $seqnum would
# probably be obviated if we were using DB_DUP, but there's much conversion
# involved with that ]
#
# We base our $seqnum (min is 1) on one of two stored sources:  "fseqnum"
# for queue "first" requests or "gseqnum" for queue with a real time stamp
# ("now" or delayed).  To implement queue "first", we use an artificial
# time stamp of all zeroes, just like for "lvf"; to keep all "lvf" sorted
# before "first" requests, we reset fseqnum and gseqnum to 1 (not zero).
# We reset gseqnum whenever we use it at a different time from last time
# since sort order will be guaranteed by different values of $qdate.  We
# don't have that guarantee with the all-zeroes time stamp and fseqnum,
# so we put off resetting fseqnum until it is over 500,000 and the queue
# is empty, so we do then when checking the queue in mint().
#
# This key structure should ensure that the queue is sorted first by date.
# As long as fewer than a million queue requests come in within a second,
# we can make sure queue ordering is fifo.  To support "lvf" (lowest value
# first) recycling, the $date and $seqnum fields are all zero, so the
# ordering is determined entirely by the numeric "value" of string
# (really only makes sense for a sequential generator); to achieve the
# numeric sorting in the lexical Btree ordering, we strip off any
# shoulder prefix,
# right-justify the string, and zero-pad on the left to create a number
# that is 16 digits wider than the Template mask [yyy kludge that doesn't
# take any overflow into account, or bigints for that matter].
# 
# XXXXXXX document change: return undef on full pre-failure (before any ids
#       actually processed, and on success
# XXXXXXX no longer returns an array but ref to array of failed ids
# XXXXXXX and $om->elem() builds up the output
#     XXXXX return ref to array of failed ids, () on full success, undef
#     on full failure
#
sub queue { my( $mh, $mods, $lcmd, $when, @ids )=@_;

	my $nog = $mh->{tied_hash_ref};
	#my $contact = $mh->{ruu}->{who};
	my $db = $mh->{db};
	my $om = $mh->{om};

	! $$nog{"$A/template"} and
		addmsg($mh,
			"error: queuing makes no sense in a bind-only minter."),
		return undef;
	#! defined($contact) and
	#	addmsg($mh, "error: contact undefined"),
	#	return undef;
	! defined($when) || $when !~ /\S/ and
		addmsg($mh, "error: queue when? (eg, first, lvf, 30d, now)"),
		return undef;
	# yyy what is sensible thing to do if no ids are present?
	scalar(@ids) < 1 and
		addmsg($mh, "error: must specify at least one id to queue."),
		return undef;
	my ($seqnum, $delete) = (0, 0, 0);
	my ($fixsqn, $qdate);			# purposely undefined

	# You can express a delay in days (d) or seconds (s, default).
	#
	if ($when =~ /^(\d+)([ds]?)$/) {	# current time plus a delay
		# The number of seconds in one day is 86400.
		my $multiplier = (defined($2) && $2 eq "d" ? 86400 : 1);
		$qdate = temper(time() + $1 * $multiplier);
	}
	elsif ($when eq "now") {	# a synonym for current time
		$qdate = temper(time());
	}
	elsif ($when eq "first") {
		# Lowest value first (lvf) requires $qdate of all zeroes.
		# To achieve "first" semantics, we use a $qdate of all
		# zeroes (default above), which means this key will be
		# selected even earlier than a key that became ripe in the
		# queue 85 days ago but wasn't selected because no one
		# minted anything in the last 85 days.
		#
		$seqnum = $$nog{"$A/fseqnum"};
		#
		# NOTE: fseqnum is reset only when queue is empty; see mint().
		# If queue never empties fseqnum will simply keep growing,
		# so we effectively truncate on the left to 6 digits with mod
		# arithmetic when we convert it to $fixsqn via sprintf().
	}
	elsif ($when eq "delete") {
		$delete = 1;
	}
	elsif ($when ne "lvf") {
		addmsg($mh, "error: unrecognized queue time: $when");
		return undef;
	}

	defined($qdate) and		# current time plus optional delay
		#($qdate > $$nog{"$A/gseqnum_date"} and
		($qdate gt $$nog{"$A/gseqnum_date"} and
			$seqnum = $$nog{"$A/gseqnum"} = SEQNUM_MIN,
			$$nog{"$A/gseqnum_date"} = $qdate,
		1 or
			$seqnum = $$nog{"$A/gseqnum"}),
	1 or
		$qdate = "00000000000000",	# this needs to be 14 zeroes
	1;

	# xxx maybe we should validate unless --force?
	my $spingerror = "";
	if ($$nog{"$A/genonly"}) {
		($spingerror) = validate($nog, "-", "", @ids);
		$spingerror = "" if $spingerror !~ /error:/;
	}
	$spingerror and
		addmsg($mh, "error: queue operation not started -- one or "
			. "more ids did not validate:\n$spingerror"),
		return undef;
	my $shoulder = $$nog{"$A/shoulder"};
	my $padwidth = $$nog{"$A/padwidth"};
	my $currdate = temper();
	my ($m, $idval, $paddedid, $qposition);
	# If we get here, all pre-conditions for success have been met
	# and any prior failures had nothing to do with single-id errors.
	#
	my @reterrs = ();	# () means no single-id errors so far
	for my $id (@ids) {
		exists($$nog{"$id\t$A/h"}) and		# if there's a hold
			$m = qq@a hold has been set for "$id" and @
				. "must be released before the string can "
				. "be queued for minting.",
			$mh->{rlog}->out("N: error: $m"),
			$om->elem("error", $m),
			push(@reterrs, $id),
			next
		;

		my $inq = inqueue($nog, $id);
		if ($inq && ! $delete) {
			$m = qq@id "$id" cannot be queued @
				. "since it is queued already.";
			$mh->{rlog}->out("N: error: $m");
			$om->elem("error", $m);
			push(@reterrs, $id),
			next;
		}
		elsif (! $inq && $delete) {
			$m = "id $id cannot be unqueued "
				. "since it is not currently queued.";
			$mh->{rlog}->out("N: error: $m");
			$om->elem("error", $m);
			push(@reterrs, $id),
			next;
		}

		($idval = $id) =~ s/^$shoulder//;
		$paddedid = sprintf("%0$padwidth" . "s", $idval);
		$fixsqn = sprintf("%06d", $seqnum % SEQNUM_MAX);

		dblock();

		if ($delete) {		# finish off delete operation
			$qposition = $$nog{"$A/queued_ids/$id"};
			$m = "c: " . logfmt("$when $id",
				$currdate, $qposition, $$nog{"$A/oacounter"});
			$mh->{rlog}->out("N: $m");
			# xxx check status of these deletes?  ->del(key))
			# xxx needs more tests?
			delete($$nog{"$A/queued_ids/$id"});
			delete($$nog{$qposition});
			if ($$nog{"$A/queued"}-- <= 0) {
				$m = "error: queued count ("
					. $$nog{"$A/queued"}
					. ") going negative on id $id";
				$mh->{rlog}->out("N: $m");
				@reterrs = undef;
				last;
			}
			# XXXX only if verbose?
			$om->elem(SPING, $id);
			next;
		}
		# if we get here, we have an add operation

		$$nog{"$A/queued"}++;
		$qposition = "$A/q/$qdate/$fixsqn/$paddedid";
		$$nog{$qposition} = $id;
		# the rhs allows us to map from id to queue location
		$$nog{"$A/queued_ids/$id"} = $qposition;
		$m = "c: " . logfmt("queue $when $id",
			$currdate, $qposition, $$nog{"$A/oacounter"});
		$mh->{rlog}->out("N: $m");

		dbunlock();

		# XXXX only if verbose?
		$om->elem(SPING, $id);
		$seqnum and		# it's zero for "lvf" and "delete"
			$seqnum++;
	}
	dblock();
	$when eq "first" and
		$$nog{"$A/fseqnum"} = $seqnum,
	1 or
	#$qdate > 0 and
	$qdate gt "0" and
		$$nog{"$A/gseqnum"} = $seqnum,
	1;
	# XXX rlog more info, eg, qposition, oacounter?
	$m = $mh->{rlog}->out("C: $lcmd $when " . join(" ", @ids)) and
		addmsg($mh, $m),
		return undef;
	dbunlock();
	return \@reterrs;
}

#XXXXXX test this code!!
# xxx add method to print out the queue, since that's one check we don't do
# Double check that a given id is in the queue.
# 
sub inqueue { my( $nog, $id )=@_;

	return 0 if
		(! exists($$nog{"$A/queued_ids/$id"}));
	return 0 if
		($$nog{"$A/queued"} <= 0);
	return 1;
}

# Generate a sample id for testing purposes.
sub sample { my( $nog, $num )=@_;

	unless (defined $num) {	# need to come up with a random sample

		# If the upper limit of the current blade is smallish
		# (meaning less than the number mintable with two xdigits)
		# and if our blade expands, then bump up the limit we use
		# for sampling to make it more interesting.
		#
		my $upper = $$nog{"$A/total"};
		$upper <= $alphacount ** 2 and $$nog{"$A/expandable"} and
			$upper = 100000;
		$num = int(rand($upper));
	}
	my $mask = $$nog{"$A/mask"};
	my $shoulder = $$nog{"$A/shoulder"};
	my $func = ($$nog{"$A/addcheckchar"} ? \&checkchar : \&echo);

	# xxxxxx this produces blanks with 'f' template char and should
	# be called again until non-blank
	# xxx produces only sample on unexpanded templates
	#
	return &$func($shoulder . n2xdig($num, $mask));
}

sub scope { my( $mh, $nog )=@_;

	! $$nog{"$A/template"} and
		print("This minter does not generate spings, but it\n"
			. "does accept user-defined string and element "
			. "bindings.\n");
	my $total = $$nog{"$A/total"};
	my $totalstr = human_num($total);
	my $naan = $$nog{"$A/naan"} || "";
	$naan and
		$naan .= "/";

	my ($shoulder, $mask, $generator_type) =
	  ($$nog{"$A/shoulder"}, $$nog{"$A/mask"}, $$nog{"$A/generator_type"});

	print "Template ", $$nog{"$A/template"}, " will yield ",
		($total < 0 ? "an unbounded number of" : $totalstr), " $generator_type unique ids\n";
	my $tminus1 = ($total < 0 ? 987654321 : $total - 1);

	# See if we need to compute a check character.
	# XXX wrap this n2xdig in a call to generate one the works
	my $func = ($$nog{"$A/addcheckchar"} ? \&checkchar : \&echo);
	print
	"in the range "	. &$func($naan . n2xdig( 0, $mask)) .
	", "	 	. &$func($naan . n2xdig( 1, $mask)) .
	", "	 	. &$func($naan . n2xdig( 2, $mask));
	28 < $total - 1 and print
	", ..., "	. &$func($naan . n2xdig(28, $mask));
	29 < $total - 1 and print
	", "	 	. &$func($naan . n2xdig(29, $mask));
	print
	", ... up to "
		  	. &$func($naan . &n2xdig($tminus1, $mask))
	. ($total < 0 ? " and beyond.\n" : ".\n")
	;
	$mask !~ /^r/ and
		return 1;
	print "A sampling of random values (may already be in use): ";
	my $i = 5;
	print sample($nog) . " "
		while ($i-- > 0);
	print "\n";
	return 1;
}

# Check that string matches a given template, where "-" means the
# default template for this generator.  This is a complete check of all
# characteristics _except_ whether the string is stored in the
# database.
#
# XXXX document change: returns undef on error, and number of ids
# XXXX processed on success
# Returns an array of strings that are messages corresponding to any ids
# that were passed in.  Error strings that pertain to strings
# begin with "spingerr: ".
#
sub validate { my( $mh, $mods, $template, @ids )=@_;

	my ($first, $shoulder, $mask, $msg);

	my $nog = $mh->{tied_hash_ref};
	my $om = $mh->{om};

	! @ids and
		addmsg($mh, "error: must specify a template and at least "
			. "one string."),
		return undef;
		#return(());
	! defined($template) and
		# If $nog is undefined, the caller looks in outmsg(undef).
		addmsg($mh, "error: no template given to validate against."),
		return undef;
		#return(());

	my $automatically_valid = 0;		# yyy does this make sense?
	if ($template eq "-") {
		($shoulder, $mask) = ($$nog{"$A/shoulder"}, $$nog{"$A/mask"});
		$$nog{"$A/template"} or	# do blanket validation
			$automatically_valid = 1;	# yyy necessary?

		# push(@retvals, "template: " . $$nog{"$A/template"});
		#if (! $$nog{"$A/template"}) {	# do blanket validation
		#	my @nonulls = grep(s/^(.)/s: $1/, @ids);
		#	! @nonulls and
		#		return undef;
		#		#return(());
		#	#push(@retvals, @nonulls);
		#	#return(@retvals);
		#	return scalar(@ids);
		#}
	}
	elsif (! parse_template($template, $shoulder, $mask, $msg)) {
		# defines $msg or defines $shoulder and $mask
		addmsg($mh, "error: template $template bad: $msg");
		return undef;
		#return(());
	}

	my ($id, @maskchars, $c, $m, $varpart);
	my $should_have_checkchar = (($m = $mask) =~ s/k$//);
	my $naan = $$nog{"$A/naan"};
	ID: for $id (@ids) {
		! defined($id) || $id =~ /^\s*$/ and
			$om->elem("spingerr", "can't validate an empty sping"),
			next;
		$automatically_valid and
			$om->elem(SPING, $id),
			next;

		# Automatically reject ids starting with "$A/", unless it's an
		# "idmap", in which case automatically validate.  For an idmap,
		# the $id should be of the form $A/idmap/ElementName, with
		# element, Idpattern, and value, ReplacementPattern.
		#
		$id =~ m|^$A/| and
			$om->elem("spingerr", ($id =~ m|^$A/idmap/.+|
				? "s: $id"
				: "spingerr: strings must not start"
					. qq@ with "$A/".@)),
			next;

		$first = $naan;				# ... if any
		$first and
			$first .= "/";
		$first .= $shoulder;			# ... if any
		($varpart = $id) !~ s/^\Q$first// and
#yyy		    ($varpart = $id) !~ s/^$shoulder// and
			$om->elem("spingerr", "$id should begin with $first."),
			next;
		# yyy this checkchar algorithm will need an arg when we
		#     expand into other alphabets
		$should_have_checkchar && ! checkchar($id) and
			$om->elem("spingerr", "$id has a check character error"),
			next;
		## xxx fix so that a length problem is reported before (or
		# in addition to) a check char problem

		# yyy needed?
		#length($first) + length($mask) - 1 != length($id)
		#	and push(@retvals,
		#		"error: $id has should have length "
		#		. (length($first) + length($mask) - 1)
		#	and next;

		# Maskchar-by-Idchar checking.
		#
		@maskchars = split(//, $mask);
		for $c (split(//, $varpart)) {
			! defined($m = shift @maskchars) and
				$om->elem("spingerr", "$id longer than "
					. "specified template ($template)"),
				next ID;
			$m =~ /e/ && $legalstring !~ /$c/ and
				$om->elem("spingerr", "$id char '$c' conflicts"
					. " with template ($template)"
					. " char '$m' (extended digit)"),
				next ID
			or
			$m =~ /d/ && '0123456789' !~ /$c/ and
				$om->elem("spingerr", "$id char '$c' conflicts"
					. " with template ($template)"
					. " char '$m' (digit)"),
				next ID
			;		# or $m =~ /k/, in which case skip
		}
		defined($m = shift @maskchars) and
			$om->elem("spingerr", "$id shorter "
				. "than specified template ($template)"),
			next ID;

		# If we get here, the string checks out.
		$om->elem(SPING, $id);
		#push(@retvals, "s: $id");
	}
	return scalar(@ids);
	#return(@retvals);
}

1;

__END__

=head1 NAME

Nog - routines to mint and manage nice opaque strings

=head1 SYNOPSIS

 use EggNog::Nog;			    # import routines into a Perl script

 xxxxxx
 $dbreport = Nog::dbcreate(	    # create minter database & printable
 		$dbdir, $contact,   # report on its properties; $contact
		$template, $term,   # is string identifying the operator
		$naan, $naa, 	    # (authentication information); the
		$subnaa );          # report is printable

 $nog = Nog::dbopen(              # open a minter
                $dbname,
	        $flags );           # use DB_RDONLY for read only mode

 Nog::mint( $nog, $contact, $pepper );     # generate an string

 Nog::dbclose( $nog );		     # close minter when done

 Nog::checkchar( $id );      # if id ends in +, replace with new check
 			      # char and return full id, else return id
			      # if current check char valid, else return
			      # 'undef'

 Nog::validate( $nog,	      # check that ids conform to template ("-"
 		$template,    # means use minter's template); returns
		@ids );	      # array of corresponding strings, errors
			      # beginning with "spingerr:"

 $n = Nog::bind( $nog, $contact,	# bind data to string; set
		$validate, $how,	# $validate to 0 if id. doesn't
		$id, $elem, $value );	# need to conform to a template

 Nog::note( $nog, $contact, $key, $value );	# add an internal note

 Nog::egg_fetch( $nog, $verbose,	# fetch bound data; set $verbose
 		$id, @elems );		# to 1 to return labels

 print Nog::dbinfo( $nog,		# get minter information; level
 		$level );		# brief (default), full, or dump

 Nog::hold( $nog, $contact,		# place or release hold; return
 		$on_off, @ids );	# 1 on success, 0 on error
 Nog::hold_set( $nog, $id );
 Nog::hold_release( $nog, $id );

 Nog::parse_template( $template,  # read template for errors, returning
 		$shoulder,	   # namespace size 
		$mask,		   # or 0 on error; $message,
		$message );	   # $shoulder, & $mask are output params

 Nog::queue( $nog, $contact,	   # return strings for queue attempts
 		$when, @ids );	   # (failures start "error:")

 Nog::n2xdig( $num, $mask );	   # show string matching ord. $num

 Nog::sample( $nog, $num );	   # show random ident. less than $num

 Nog::scope( $nog );		   # show range of ids inside the minter

# print Nog::outmsg( $nog, $reset );   # print message from failed call
 	$reset = undef | 1;	   # use 1 to clear error message buffer

 Nog::addmsg( $nog, $message );  # add message to error message buffer

=head1 DESCRIPTION

This is very brief documentation for the B<nog> Perl module subroutines.
For this early version of the software, it is indispensable to have the
documentation for the B<nog> utility (the primary user of these routines)
at hand.  Typically that can be viewed with

	perldoc nog

while the present document can be viewed with

	perldoc Nog

The B<nog> utility creates minters (string generators) and accepts
commands that operate them.  Once created, a minter can be used to produce
persistent, globally unique names for documents, databases, images,
vocabulary terms, etc.  Properly managed, these strings can be used as
long term durable information object references within naming schemes such
as ARK, PURL, URN, DOI, and LSID.  At the same time, alternative minters
can be set up to produce short-lived names for transaction identifiers,
compact web server session keys (cf. UUIDs), and other ephemera.

In general, a B<nog> minter efficiently generates, tracks, and binds
unique identifiers, which are produced without replacement in random or
sequential order, and with or without a check character that can be used
for detecting transcription errors.  A minter can bind identifiers to
arbitrary element names and element values that are either stored or
produced upon retrieval from rule-based transformations of requested
identifiers; the latter has application in identifier resolution.  Nog
minters are very fast, scalable, easy to create and tear down, and have a
relatively small footprint.  They use BerkeleyDB (via Perl's DB_File
module) as the underlying database.

Identifiers generated by a B<noid> minter are also known as "noids" (nice
opaque identifiers).  While a minter can record and bind any identifiers 
that you bring to its attention, often it is used to generate, bringing
to your attention, identifier strings that carry no widely recognizable
meaning.  This semantic opaqueness reduces their vulnerability to era-
and language-specific change, and helps persistence by making for
identifiers that can age and travel well.

=begin later

=head1 HISTORY

Since 2002 Sep 3:
- seeded (using srand) the generator so that the same exact sequence of
    identifiers would be minted if we started over from scratch (limited
    disaster recovery assistance)
- changed module name from PDB.pm to Noid.pm
- changed variable names from pdb... to noid...
- began adding support for sequentially generated numbers as part of
    generalization step (eg, for use as session ids)
- added version number
- added copyright to code
- slightly improved comments and error messages
- added extra internal (admin) symbols "$A/..." (":/..."),
    eg, "template" broken into "prefix", "mask", and "generator_type"
- changed the number of counters from 300 to 293 (a prime) on the
    theory that it will improve the impression of randomness
- added "scope" routine to print out sample identifiers upon db creation

Since 2004 Jan 18:
- changed var names from b -> noid throughout
- create /tmp/errs file public write
- add subnaa as arg to dbopen
- changed $A/authority to $A/subnaa
- added note feature
- added dbinfo
- added (to noid) short calling form: noi (plus NOID env var)
- changed dbcreate to take term, naan, and naa
- added DB_DUP flag to enable duplicate keys

Plus many, many more changes...

=end

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<dbopen(3)>, L<perl(1)>, L<http://www.cdlib.org/inside/diglib/ark/>

=head1 AUTHOR

John A. Kunze

=cut
