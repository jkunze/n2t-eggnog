#! /usr/bin/env perl

# Author: John A. Kunze, California Digital Library.
# Copyright 2016-2020 UC Regents. Open source BSD license. 

use 5.10.1;
use strict;
use warnings;

use Encode;		# to deal with unicode chars
my $lcnt = 0;		# current line number (line count)
my $ecnt = 0;		# current entry (count)
my $errs = 0;		# error count
my ($badseq1, $badseq2, %naans, %elems, %org_name, %org_acro);

sub perr {
	print(STDERR "Entry starting line $lcnt: ",
		join('', @_), "\n");
	$errs++;
}

sub element_check { my( $k, $v )=@_;	# one key/value pair

	$k ||= '';
	$k or
		perr("missing key!"),
		return
	;
	$v ||= '';
	my ($year, $month, $day);
	$k =~ s/^\s*(.*?)\s*$/$1/;
	$v =~ s/^\s*(.*?)\s*$/$1/;
	++$elems{$k} > 1 and $k ne '!contact' and
		perr("multiple instances of element '$k'");
	if ($k eq 'naa') {
		$v and
			perr("element 'naa' should not have ",
				"a value");
		return;
	}
	$k and ! $v and
		perr("missing value for $k");
	# Type-specific checks, with $k known to be defined.
	#
	if ($k eq 'what') {		# duplicate check
		++$naans{$v} > 1 and
			perr("NAAN $v duplicated");
		$v =~ /^(\d\d\d\d\d)$/ or
			perr("malformed NAAN ($v): ",
				"should be NNNNN");
	}
	elsif ($k eq 'who') {
		my ($oname) = $v =~ m/^\s*(.*?)\s*\(=\)/ or
			perr("Malformed organization name: $v");
		my ($oacro) = $v =~ m/.*\(=\)\s*(.*?)$/ or
			perr("Malformed organization acronym: $v");
		++$org_name{$oname} > 1 and
			perr("Organization name $oname duplicated");
		++$org_acro{$oacro} > 1 and
			perr("Acronym $oacro duplicated");
	}
	elsif ($k eq 'when') {
		$v =~ /^(\d\d\d\d)\.(\d\d)\.(\d\d)$/ or
			perr("malformed date ($v): ",
				"should be NNNN.NN.NN"),
			return
		;
		($year, $month, $day) = ($1, $2, $3);
		$year and $year !~ /^(?:19|20)/ and
			perr("malformed year ($year): ",
				"should be 19NN or 20NN");
		$month and $month < 1 || $month > 12 and
			perr("malformed month ($month): ",
				"should be between 01 and 12");
		$day and $day < 1 || $day > 31 and
			perr("malformed day ($day): ",
				"should be between 01 and 31");
	}
	elsif ($k eq 'where') {
		$v =~ m|/$| and
			perr("URL should not end in /");
	}
	elsif ($k eq 'how') {
		$v =~ m|ORGSTATUS| and
			perr("ORGSTATUS should be either NP or FP");
	}
}

my $naanfile = $ARGV[0];
$naanfile or
	die("No NAANsFile given");
# XXX do next line in Perl to remove shell dependency
my $contact_info =		# peek to see if file is anonymized
	`grep -q '^\!contact' $naanfile && echo 1`;
chop $contact_info;

my ($c, $s, @uchars);
open FH, "< $naanfile" or
	die();
$/ = "";		# paragraph mode
while (<FH>) {		# read file an entry (block) at a time
	$badseq1 = $badseq2 = 0;
	if ($. == 1 and ! /^erc:/m) {
		print STDERR
			"First entry missing \"erc:\" header\n";
		$errs++;
	}
	# if entry is first or is just all comment and blank lines
	# yyy . matches \n in -00 mode even without /s flag ?
	if ($. == 1 or /^(?:\s*#.*\n|\s*\n)*$/) {
		$lcnt += tr|\n||;	# counts \n chars
		next;
	}
	$ecnt++;

	# Need to validate either the full file (internal only,
	# with contact info) or anonymized file (no "!" fields).
	#
	$badseq1 = $. != 1 && ! m{	# not first entry and
		who:\s+.*?\s*\n		# not in proper order
		what:\s+.*?\s*\n
		when:\s+.*?\s*\n
		where:\s+.*?\s*\n
		how:\s+.*?\s*\n
	}xs;
	$contact_info and $badseq2 = $. != 1 &&
				/^!/m && ! m{	# if any "!" fields,
		how:\s+.*?\s*\n			# check their ordering
		!why:\s+.*?\s*\n
		!contact:\s+.*?\s*\n
	}xs;
	$badseq1 and
		perr("bad who-what-when-where-how-... sequence");
	$contact_info and $badseq2 and
		perr("bad how-why-contact... sequence");

	undef %elems;			# reinitialize
	# This loop will eat up the entry we're working on.  We
	# assume 1 elem per line (ie, no ANVL continuation lines).
	while (s/^(.*?)\n//) {	# process entry a line at a time
		$lcnt++;
		$s = $1;		# $s is line just removed
		$s =~ /^\s*#/ and	# skip comment lines
			next;
		$s =~ /^\s*$/ and	# skip blank lines
			next;
		# yyy don't yet do strict \t-only this version
		if ($s =~ /^!# Move this.*---/i) {
			print STDERR
				"Line $lcnt: this line should be removed\n";
			$errs++;
		}
		elsif ($s !~ /^
			\s*(!?.[^:\n]*)\s*	# key
			:
			\s*([^\n]*)\s*		# value
			$/x) {
			#\s*?([^\n]*?)\s*?\n	# value
			print STDERR
				"Line $lcnt: missing colon\n";
			$errs++;
		}
		else {
			element_check($1, $2);
		}
		$s =~ /\P{ascii}/ or	# if there's no non-ascii
			next;		# present, skip the rest

		# check for annoying non-ascii punctuation
		@uchars = split '', decode('utf8', $s);
		/\P{ascii}/ && /\p{Punctuation}/ && print(STDERR
			"Line $lcnt: non-ascii punctuation: ",
			encode('utf8', $_), "\n") && $errs++
						for (@uchars);
	}
}
close FH;

=for removal

# check that every NAAN mentioned in shoulders file is also in
# the NAAN registry

my $shfile = $ARGV[1];
open FH, "sed -n 's,^:: ark:/*\\([0-9][0-9]*\\).*,\\1,p' $shfile |" or
	die();

$/ = "\n";
while (<FH>) {
	chop;
	! $naans{$_} and $errs++, print(STDERR
		"NAAN $_ from shoulders database missing from ",
			"NAAN registry\n");
}
close FH;

=cut

my @reserved =				# reserved NAANs, not assigned to orgs
	qw( 12345 99152 99166 99999 );

my $numorgs = $ecnt - scalar @reserved;		# reduce to just count orgs

if ($errs) {
	print("NOT OK - $naanfile: $numorgs orgs ($ecnt entries), $errs errors\n");
	exit 1;
}

# XXX need to add count of orgs in the new shared_naan shoulders
# xxx de-dupe orgs for final count?
#
print("OK - $naanfile: $numorgs orgs ($ecnt entries), $lcnt lines\n");

# Now output two tiny files using file descriptors that caller redirects.

my $rnumorgs = int($numorgs / 10) * 10;	# round number: truncate to nearest 10

open(NORGS, ">&=4") and say NORGS "$numorgs"; close NORGS;
open(RORGS, ">&=5") and say RORGS "$rnumorgs"; close RORGS;
#system("echo $numorgs > numorgs; echo $round_numorgs > round_numorgs");

exit;
