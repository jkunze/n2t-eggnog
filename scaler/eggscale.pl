#!/usr/bin/perl

use 5.006;
use strict;
use warnings;

# Author:  John A. Kunze, jakkbl@gmail.com, California Digital Library
# Copyright (c) 2014 UC Regents
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

my $numrecs_default = 10;
my $usage_text = << "EOF";

 Usage: $0 [ options ] binder [ N ]

Add N x 2 canned records to an egg binder, creating it if need be.  Records
come in pairs:  one for ARK and one for DOI.  N defaults to $numrecs_default.
Example:

	$0 scaletest 50000

EOF

# (contributed by brian d foy and Benjamin Goldberg)
# This subroutine will add commas to your number:
sub commify {
	local $_ = shift;
	1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
	return $_;
}

sub mint_ids { my( $minter, $numrecs, $seqidsR ) = ( shift, shift, shift );

	$minter		or return "mint_ids: no minter name";
	$numrecs	or return "mint_ids: no numrecs";
	$seqidsR	or return "mint_ids: no seqidsR";
	-e $minter or
		system("nog -d $minter mkminter --type seq") and
			return "mint_ids: couldn't create minter $minter";
	@$seqidsR = `nog -d $minter mint $numrecs` or
		return "mint_ids: problem minting from $minter";
	return '';
}

sub bind_ids { my( $binder ) = ( shift );

	my $status;
	-e $binder or
		system("egg -d $binder mkbinder") and
			return "bind_ids: couldn't create binder $binder";
	$status = `egg -d $binder -` or
		return "bind_ids: problem binding with $binder";
	print "bind status: $status";
	return '';
}

# XXX placeholder code -- no options supported yet
my %opt;			# global options hash
my @getoptlist = (	# yyy possible future options
	'ack',			# acknowledge changes with oxum
	'all',			# always fetch all elements (like :all always)
				# xxx can't turn this off locally?
	'verbose|v',
);

my $separator = '-';
my ($sping, $id);
my $arkbase = 'ark:/34231/c6st7mzj';
my $arktbase = 'http://e-archives.lib.purdue.edu/u?/earhart,2600';
my $doibase = 'doi:10.6084/m9.figshare.61786';
my $doitbase = 'http://figshare.com/articles/Bias_magnification_in_ecologic_studies:_a_methodological_investigation-5/61786';

# 10 bindings (9 bindings + 1 from do_ark)
my @arkmeta = (
'|_c.add @
1330038943
', '|_g.add @
ark:/99166/p9db7vp67
', '|_o.add @
ark:/99166/p98k74w2g
', '|_p.add @
erc
', '|_u.add @
1330038944
', '|erc.what.add @
Telegram, 1935 May 9, Washington, DC, to Amelia Earhart
', '|erc.when.add @
09/05/1935
', '|erc.who.add @
Vidal, Eugene
', '|erc.how.add @
document
',
);

# 10 bindings
my @doimeta = (
'|_c.add @
1339360392
', '|_g.add @
ark:/99166/p91n7xm8t
', '|_o.add @
ark:/99166/p9hq3rz4t
', '|_p.add @
datacite
', '|_t.add @
http://n2t.net/ezid/id/ark:/b6084/m9.figshare.61786
', '|_u.add @
1339360392
', '|datacite.creator.add @
Thomas F Webster
', '|datacite.publicationyear.add @
2011
', '|datacite.publisher.add @
Figshare
', '|datacite.title.add @
Bias magnification in ecologic studies: a methodological investigation-5
',
);

sub do_ark { my( $sping ) = ( shift );

	$id =  $arkbase . $separator . $sping;
	print(BDR "$id|_t.add @\n$arktbase/t-$sping\n");
	print(BDR $id, $_)
		for (@arkmeta);
}

sub do_doi { my( $sping ) = ( shift );

	$id =  $doibase . $separator . $sping;
	print(BDR $id, $_)
		for (@doimeta);
}

# main
{
	my $binder = shift;
	$binder or
		print("error: no binder name given\n$usage_text"),
		exit 1;
	-e "$binder/egg.bdb" or
		print("Creating $binder binder from scratch.\n"),
		system("egg mkbinder -d $binder > /dev/null") and
			exit 1;

	my $numrecs = shift || $numrecs_default;

	# In the text dump, key and value lines are indented by one space,
	# while the few non-indented lines are just printed and skipped.
	#
	my ($key, $elem, $bindid, $hex);
	my $tot = 0;			# total bindings
	my $m = 0;			# number of encodings
	my $recs = 0;			# number of element records
	my $notab = 0;			# number of "no tab" bindings
	my $odd = 0;			# odd "no tab" bindings
	my $bse = 0;			# extra backslash encoding count
	my $i;				# identifier
	my $n;				# name of element
	my $d;				# data to be bound to it
	#$| = 1;			# unbuffer STDOUT so \r works below

	my @seqids;
	$#seqids = $numrecs;		# XXXX right? pre-extend array (fast)
	my $msg = mint_ids "$binder.seqids", $numrecs, \@seqids;
	$msg and
		print($msg, "\n"),
		exit 1;

	open(BDR, "| egg -d $binder -m anvl - >> bind_out_$binder") or
		print("couldn't open $binder in bulk mode\n"),
		exit 1;

	my $num = 0;
	while ($num++ < $numrecs) {

		$sping = shift(@seqids) or
			print("ran off end of seqids\n"),
			exit 1;
		chop $sping;

		# do_ark
		$id =  $arkbase . $separator . $sping;
		print(BDR "$id|_t.add @\n$arktbase/t-$sping\n");
		print(BDR $id, $_)
			for (@arkmeta);

		# do_doi
		$id =  $doibase . $separator . $sping;
		print(BDR $id, $_)
			for (@doimeta);

		#print "target: $id|_t, $arktbase/t", $separator, $sping, "\n";

		##$recs >= 100	and last;	# yyy bail to test
		#$tot % 100000 == 0 and
		#	print("\r", ($tot/1000000), "M keys... ");
	}
	$id =  $arkbase . $separator . $sping;
	print(BDR $id, "|_t.fetch");
	close(BDR);

	# xxx print total in DB now
	#print "\nDone: ", commify($tot), " key/value pairs, ", commify($recs),
	#	" records, $m hex encodings\n";
	#my $avg = $recs ? $tot / $recs : 0;
	#print "There's an average of $avg key/value pairs per record.\n";
	#print "Backslash encodings: $bse; odd bindings: $odd\n";
}
