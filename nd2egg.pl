#!/usr/bin/perl

use 5.006;
use strict;
use warnings;

# Author:  John A. Kunze, jak@ucop.edu, California Digital Library
# Copyright (c) 2013-2015 UC Regents
# 
# Permission to use, copy, modify, distribute, and sell this software and
# its documentation for any purpose is hereby granted without fee, provided
# that (i) the above copyright notices and this permission notice appear in
# all copies of the software and related documentation, and (ii) the names
# of the UC Regents and the University of California are not used in any
# advertising or publicity relating to the software without the specific,
# prior written permission of the University of California.
# 
# THE SOFTWARE IS PROVIDED "AS-IS" AND WITHOUT WARRANTY OF ANY KIND, 
# EXPRESS, IMPLIED OR OTHERWISE, INCLUDING WITHOUT LIMITATION, ANY 
# WARRANTY OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.  
# 
# IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE FOR ANY
# SPECIAL, INCIDENTAL, INDIRECT OR CONSEQUENTIAL DAMAGES OF ANY KIND,
# OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
# WHETHER OR NOT ADVISED OF THE POSSIBILITY OF DAMAGE, AND ON ANY
# THEORY OF LIABILITY, ARISING OUT OF OR IN CONNECTION WITH THE USE
# OR PERFORMANCE OF THIS SOFTWARE.
# ---------

use File::Spec::Functions;
use Text::ParseWords;
#use File::Path;
use File::OM;
#use DB_File;		# xxx needed? provides only O_RDWR?
use Fcntl;
use Config;
use File::Minder ':all';
use File::Cmdline ':all';
use File::Egg;
use File::Value ":all";
use Pod::Usage;
#use File::RUU;
use File::Rlog;
use File::Temper 'temper2epoch';

my $usage_text = << "EOF";

 Usage: $0 [ options ] noid_dump.txt

Reads a "db_dump -p" text dump of an old (2007) noid binder BerkeleyDB
database and writes it to an egg binder also BerkeleyDB).
Quoting from the db_dump documentation:

   The header information ends with single line HEADER=END....  Following
   the header information are the key/data pairs from the database....
   If the database being dumped is a Btree or Hash database, ..., the
   output will be paired lines of text where the first line of the pair
   is the key item, and the second line of the pair is its corresponding
   data item....  Each of these lines is preceded by a single space.

   If the -p option was specified to the db_dump utility or db_dump185
   utility, the key/data lines will consist of single characters
   representing any characters from the database that are printing
   characters and backslash (\) escaped characters for any that were not.
   Backslash characters appearing in the output mean one of two things:
   if the backslash character precedes another backslash character, it
   means that a literal backslash character occurred in the key or data
   item. If the backslash character precedes any other character, the next
   two characters must be interpreted as hexadecimal specification of a
   single character; for example, \0a is a newline character in the ASCII
   character set.

EOF

my $mh;				# global minder handler

# (contributed by brian d foy and Benjamin Goldberg)
# This subroutine will add commas to your number:
sub commify {
	local $_ = shift;
	1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
	return $_;
}

# XXX placeholder code -- no options supported yet
my %opt;			# global options hash
my @getoptlist = (	# yyy possible future options
	'ack',			# acknowledge changes with oxum
	'all',			# always fetch all elements (like :all always)
				# xxx can't turn this off locally?
	'verbose|v',
);

my $Sc = '|';			# field separator character
#my $CT = '__mc';		# creation time subelement
#my $PS = '__mp';		# permission string subelement
my $Ct = '._ec';		# creation time subelement
my $Ps = '._ep';		# permission string subelement

# main
{
	my $noid_tdb = shift;		# noid text db dump
	$noid_tdb or
		print("error: no noid text bdb dump given\n$usage_text"),
		exit 1;
	my $cmdr;
	($cmdr = $noid_tdb) =~ s/\.txt$// or
		print("error: noid text dump ($noid_tdb) doesn't end ",
			"in .txt\n$usage_text"),
		exit 1;
	open(FH, "< $noid_tdb") or
		print("$noid_tdb: $!\n"),
		exit 1;

	-e "$cmdr/egg.bdb" and
		system("rm -fr $cmdr");
	print "Creating $cmdr binder from scratch.\n";
	system("egg mkbinder -d $cmdr > /dev/null");

	my $v1bdb = get_dbversion(1);		# true if BDB V1
	# xxx bug in om->new?  shouldn't default outhandle be STDOUT
	#     ie, if I don't specify it?

	my $om = File::OM->new('anvl', { outhandle => *STDOUT } );

	my $minderpath = '.';
	$mh = File::Minder->new(
		File::Minder::ND_BINDER, 0, $om, $minderpath, undef)
	or
		outmsg("couldn't create minder handler"),
		exit 1;
	# For a few admin elements we just assign directly via hash,
	# which means they don't get the usual subelements.  yyyyy?
	#
	my $direct_assign = 0;
	use constant A => ':';

	mopen($mh, $cmdr, O_RDWR)
	or
		outmsg($mh),
		exit 1;
	my $dbh = $mh->{tied_hash_ref};

	# In the text dump, key and value lines are indented by one space,
	# while the few non-indented lines are just printed and skipped.
	#
	my ($key, $id, $elem, $bindid, $hex);
	my $tot = 0;			# total bindings
	my $m = 0;			# number of encodings
	my $recs = 0;			# number of element records
	my $notab = 0;			# number of "no tab" bindings
	my $odd = 0;			# odd "no tab" bindings
	my $bse = 0;			# extra backslash encoding count
	my $i;				# identifier
	my $n;				# name of element
	my $d;				# data to be bound to it
	$| = 1;				# unbuffer STDOUT so \r works below
	my ($ctime_temper, $ctime_epoch);
	my $extra_bindings = 0;		# that we will add
	my $perms_string = 'p:||76';	# perms string
	while (1) {
		$ctime_epoch = '';
		$direct_assign = 0;
		$key = <FH>;
		defined($key)	or last;		# EOF
		chop $key;
		$key =~ s/^ //	or next;		# non-indented
		$d = <FH>;		# $d is value paired with $key
		chop $d;
		$d =~ s/^ // or
			print("ERROR: non-indented value ($d) for data ",
				"($d)\n"),  next;	# non-indented line

		# Conversion step 1.
		#    Drop "hold" and "circulation" elements, which are
		#    deprecated minter concepts.  Holds end in "\09:/h".
		#    Circulation elements end in "\09:/c", but are typically
		#    paired with a value that contains a useful creation
		#    date in case we need to store record creation time.
		#
		## from NOID doc
		##    id\t:/c   circulation record, if it exists, is
		## circ_status_history_vector|when|contact(who)|oacounter
		##    where circ_status_history_vector is a string of [iqu]
		##    and oacounter is current overall counter value, FWIW;
		##    circ status goes first to make record easy to update

		$key =~ m{\\09:/h$} and		# skip "hold" elements
			$tot++,
			next;
		if ($key =~ m{\\09:/c$}) {	# "circulation" elements
			($ctime_temper) = $d =~ m/^i\|(\d+)/;
			$ctime_epoch = $ctime_temper
				? temper2epoch($ctime_temper)
				: '';
			$ctime_temper or
				print "ERROR: mal-formed circulation",
					" element ($d)\n";
		}

		$tot++;			# total keys we've begun processing
		$hex = 0;		# assume we don't have to ^-encode yet

		# Conversion step 2.
		#    Split key at tab to pull out i (id) and n (element name).
		#
		($i, $n) = $key =~ /(.*)\\09(.*)/;

		# Conversion step 3.
		#    A few admin elements don't have a tab.
		#    The old noid admin elements mostly concerned the minter,
		#    which we didn't then and won't now use.  The only two
		#    elements we'll keep are :/erc and :/version, after
		#    renaming them :/erc_original and :/version_original.
		#
		if (! $i || ! $n) {
			$notab++;
			$key =~ /^:/ or
				$odd++,
				print("warning: no tab key AND doesn't begin ",
					"with ':' --\n key=$key\n value=$d\n");
			$key ne ":/erc" && $key ne ":/version" and
				next;		# skip unless one of these
			$direct_assign = 1;
			$i ||= $key . "_original";
			$n ||= '';
			#
			# Make sure they're defined so we can fall
			# through without triggering errors in the
			# encoding steps below.
		}
		else {
			$i = 'ark:/' . $i;
		}

		# Conversion step 4.
		#    We have to make sure values stored in the old db safely
		#    clear the egg command line syntax encoding rules and
		#    ^hex-encode those that might be grabbed by the parser.
		#    To the last above add '^' since we have to watch for
		#    it in case one is in front of two digits by accident.
		#      any |;()[]=:    (in i or n) need to ^hex-encode
		#      initial &@<     (in i) need to ^hex-encode
		#      initial :&@     (in i, n, or d) need to ^hex-encode
		#    In other words,
		#      in i:       any |;()[]=:^   and  initial &@<
		#      in n:       any |;()[]=:^   and  initial &@
		#      in d:       initial :&@^
		#
		#$key =~ s/([|;()[]=:^])/sprintf '^%02x', ord $1/eg and
		#	$m++, $hex = 1;		# yes, we have to ^-encode

		$i =~ s/([|;()[]=:^])/sprintf '^%02x', ord $1/eg and
			$m++, $hex = 1;	
		$i =~ s/^([&@<])/sprintf '^%02x', ord $1/eg and
			$m++, $hex = 1;
		$n =~ s/([|;()[]=:^])/sprintf '^%02x', ord $1/eg and
			$m++, $hex = 1;	
		$n =~ s/^([&@])/sprintf '^%02x', ord $1/eg and
			$m++, $hex = 1;
		$d =~ s/^([:&@^])/sprintf '^%02x', ord $1/eg and
			$m++, $hex = 1;

		# Conversion step 5.
		#    First convert \\ to \5c and then \HH to ^HH.
		#    Do it for i, n, and d.  This introduces new instances
		#    of ^, so we do it AFTER the above step.
		#    Print no newline, since printing is controlled by
		#    \r format at bottom of the loop.
		#
		#$i =~ s/\\\\/\\5c/g and
		#	print("\\\\ encoding found in id: $i,");
		#$i =~ s/\\([0-9a-f][0-9a-f])/^$1/g and
		#	$hex = 1, $bse++, print("bse in id: $i,");
		#$n =~ s/\\\\/\\5c/g and
		#	print("\\\\ encoding found in element name: $n,");
		#$n =~ s/\\([0-9a-f][0-9a-f])/^$1/g and
		#	$hex = 1, $bse++, print("bse in element name: $n,");
		#$d =~ s/\\\\/\\5c/g and
		#	print("\\\\ encoding found in data: $d,");
		#$d =~ s/\\([0-9a-f][0-9a-f])/^$1/g and
		#	$hex = 1, $bse++, print("bse in data,");

		$i =~ s/\\\\/\\5c/g and
			print("\\\\ encoding found in id: $i,");
		$i =~ s/\\([0-9a-f][0-9a-f])/chr hex $1/eg and
			$bse++, print("bse in id: $i,");
		$n =~ s/\\\\/\\5c/g and
			print("\\\\ encoding found in element name: $n,");
		$n =~ s/\\([0-9a-f][0-9a-f])/chr hex $1/eg and
			$bse++, print("bse in element name: $n,");
		$d =~ s/\\\\/\\5c/g and
			print("\\\\ encoding found in data: $d,");
		$d =~ s/\\([0-9a-f][0-9a-f])/chr hex $1/eg and
			$bse++, print("bse in data,");

		#$recs >= 100	and last;	# yyy bail to test
		$tot % 100000 == 0 and
			print("\r", ($tot/1000000), "M keys... ");

		if ($n eq ':/c') {
			#$dbh->{"$i|__mc"} = $ctime_epoch;
			$dbh->{"$i$Sc$Ct"} = $ctime_epoch;
			#$dbh->{"$i|__mp"} = $perms_string;
			$dbh->{"$i$Sc$Ps"} = $perms_string;
			$extra_bindings++;	# :/c generates two bindings
			#print "circ $i: ", $dbh->{"$i|__mc"}, "\n";
			next;
		}
		# Should look like this:
		# i|__mc
		# 1425270481
		# i|__mp
		# p:||76
		# Note that directly assigned elements don't result
		# in automatic creation of important subelements
		# __mp (permissions) and __mc (creation date), but
		# they should exist after the first time that egg_set
		# is called.  We check for the existence of __mc and
		# add the best creation date if we have it.

		$direct_assign and
			($dbh->{$i} = $d),
			next
		;
		if ($n eq 'goto') {
			$recs++;	# crudely assume one target per record
			$n = '_t';	# the new name for target
		}

		#print "binding id $i\n";
		#if (($dbh->{"$i|__mp"} || '') ne $perms_string) {
		if (($dbh->{"$i$Sc$Ps"} || '') ne $perms_string) {
			# force perms to be like the others
			#delete $dbh->{"$i|__mp"};	# in case of dupes
			delete $dbh->{"$i$Sc$Ps"};	# in case of dupes
			#$dbh->{"$i|__mp"} = $perms_string;
			$dbh->{"$i$Sc$Ps"} = $perms_string;
			#($dbh->{"$i|__mc"} || '') ne $perms_string and
			($dbh->{"$i$Sc$Ct"} || '') ne $perms_string and
				#delete($dbh->{"$i|__mc"}),
				delete($dbh->{"$i$Sc$Ct"}),
				#$dbh->{"$i|__mc"} = time();
				$dbh->{"$i$Sc$Ct"} = time();
		}
		# If we get here, it's a regular assignment.
		# see bdx_add() for arg defs and signature
		File::Egg::egg_set($mh, { hx => $hex },
			'add',		# for the log
			0, 0, File::Egg::HOW_ADD,
			$i,
			$n,
			$d,
		) or
			outmsg($mh),
			print("Bailing out.\n"),
			exit 1		# xxx exit or continue?
		;
		#if ($n eq '_t') {
		#	print "$i|__mc: ",
		#		scalar(localtime($dbh->{"$i|__mc"})), "\n";
		#}
	}
	# Add some provenance info.  We don't use egg_set() for this and
	# other db-level admin elements.  Not sure why or why not, except
	# we'd have to design an admin element with subelements, and that
	# would then be subject to egg_set() overhead like creation and
	# permission subelements (but maybe that would be good?  So for
	# now we add directly via $dbh->{key} assignment, and this is how
	# we work for Egg and Nog dbs.
	#
	my $time = localtime();
	$dbh->{":/converted"} = "converted from a Noid Berkeley DB at $time.";

	# We want to adjust the bindings_count, and because dupes may be
	delete $dbh->{":/bindings_count"};	# in effect, first delete it.
	$dbh->{":/bindings_count"} = $tot + $extra_bindings;

	print "\nDone: ", commify($tot),
		" key/value pairs (with $extra_bindings extra added), ",
		commify($recs), " records, $m hex encodings\n";
	my $avg = $recs ? $tot / $recs : 0;
	print "There's an average of $avg key/value pairs per record.\n";
	print "Backslash encodings: $bse; odd bindings: $odd\n";
	# Nov3: Done: wrote 2788444 key/value pairs, 21 hex encodings

	# XXX to do: round trip comparison of new dump with old dump
# XXX bug in namaste, no newline at end of pairtree file, and what about
# contents of egg_1.00 file??

	close(FH);
}
