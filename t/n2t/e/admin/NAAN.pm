package NAAN;

# Author: John A. Kunze, California Digital Library.
# Copyright 2016-2021 UC Regents. Open source BSD license. 

use 5.10.1;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw( validate_naans );
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use Encode;		# to deal with unicode chars

# XXX bad practice -- non-re-entrant code, will be clobbered by other caller
my $lcnt = 0;		# current line number (line count)
my ($badseq1, $badseq2, %naans, %elems, %org_name, %org_acro);
# XXX horrible practice -- global changed by last caller
my $linenumbers = 1;	# whether errors come with line number of entry

sub lerr {	# line error
	my $lcnt = shift @_;
	return $linenumbers
		? "Entry starting line $lcnt: " . join('', @_)
		: join('', @_)
	;
}

sub element_check { my( $Rerrs, $k, $v )=@_;	# one key/value pair

	$k ||= '';
	if (! $k) {
		push @$Rerrs, lerr($lcnt, "missing key!");
		return;
	}
	$v ||= '';
	my ($year, $month, $day);
	$k =~ s/^\s*(.*?)\s*$/$1/;
	$v =~ s/^\s*(.*?)\s*$/$1/;
	++$elems{$k} > 1 and $k ne '!contact' and
		push @$Rerrs,
			lerr($lcnt, "multiple instances of element '$k'");
	if ($k eq 'naa') {
		$v and
			push @$Rerrs, lerr($lcnt,
				"element 'naa' should not have a value");
		return;
	}
	$k and ! $v and
		push @$Rerrs, lerr($lcnt, "missing value for $k");
	# Type-specific checks, with $k known to be defined.
	#
	if ($k eq 'what') {		# duplicate check
		++$naans{$v} > 1 and
			push @$Rerrs, lerr($lcnt, "NAAN $v duplicated");
		$v =~ /^(\d\d\d\d\d)$/ or
			push @$Rerrs, lerr($lcnt, "malformed NAAN ($v): ",
				"should be NNNNN");
	}
	elsif ($k eq 'who') {
		my ($oname) = $v =~ m/^\s*(.*?)\s*\(=\)/ or
			push @$Rerrs, lerr($lcnt,
				"Malformed organization name: $v");
		my ($oacro) = $v =~ m/.*\(=\)\s*(.*?)$/ or
			push @$Rerrs, lerr($lcnt,
				"Malformed organization acronym: $v");
		length($oacro) < 2 and
			push @$Rerrs, lerr($lcnt,
				"Organization acronym less than 2 chars: $v");
		$oacro =~ m/^([A-Z0-9-]+)$/ or
			push @$Rerrs, lerr($lcnt,
				"Organization acronym can only consist of digits, hyphens, and uppercase letters: $v");
		++$org_name{$oname} > 1 and
			push @$Rerrs, lerr($lcnt,
				"Organization name $oname duplicated");
		++$org_acro{$oacro} > 1 and
			push @$Rerrs, lerr($lcnt,
				"Acronym $oacro duplicated");
	}
	elsif ($k eq 'when') {
		$v =~ /^(\d\d\d\d)\.(\d\d)\.(\d\d)$/ or
			push @$Rerrs, lerr($lcnt, "malformed date ($v): ",
				"should be NNNN.NN.NN"),
			return
		;
		($year, $month, $day) = ($1, $2, $3);
		$year and $year !~ /^(?:19|20)/ and
			push @$Rerrs, lerr($lcnt, "malformed year ($year): ",
				"should be 19NN or 20NN");
		$month and $month < 1 || $month > 12 and
			push @$Rerrs, lerr($lcnt, "malformed month ($month): ",
				"should be between 01 and 12");
		$day and $day < 1 || $day > 31 and
			push @$Rerrs, lerr($lcnt, "malformed day ($day): ",
				"should be between 01 and 31");
	}
	elsif ($k eq 'where') {
		$v =~ m|/$| and
			push @$Rerrs, lerr($lcnt, "URL should not end in /");
	}
	elsif ($k eq 'how') {
		$v =~ m|ORGSTATUS| and
			push @$Rerrs, lerr($lcnt, "ORGSTATUS should be either NP or FP");
	}
}

sub validate_naans { my( $naanfile, $contact_info, $linenums )=@_;

	my ($c, $s, @uchars);
	open FH, "<:encoding(UTF-8)", $naanfile or
		die();
	my $Rerrs = [];		# this gets returned
	my $ecnt = 0;		# current entry (count)
	my $msg;
	defined($linenums) and
		$linenumbers = $linenums;

	$/ = "";		# paragraph mode
	while (<FH>) {		# read file an entry (block) at a time
		$badseq1 = $badseq2 = 0;
		if ($. == 1 and ! /^erc:/m) {
			push @$Rerrs,
				"First entry missing \"erc:\" header";
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
			push @$Rerrs, lerr($lcnt,
				"bad who-what-when-where-how-... sequence");
		$contact_info and $badseq2 and
			push @$Rerrs, lerr($lcnt,
				"bad how-why-contact... sequence");

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
				push @$Rerrs, lerr($lcnt,
					"Line $lcnt should be removed");
			}
			elsif ($s !~ /^
				\s*(!?.[^:\n]*)\s*	# key
				:
				\s*([^\n]*)\s*		# value
				$/x) {
				#\s*?([^\n]*?)\s*?\n	# value
				push @$Rerrs, lerr($lcnt, "missing colon");
			}
			else {
				element_check($Rerrs, $1, $2);
			}
			$s =~ /\P{ascii}/ or	# if there's no non-ascii
				next;		# present, skip the rest

# Not applicable since opening with :encoding(UTF-8)
#			# check for annoying non-ascii punctuation
#			@uchars = split '', decode('utf8', $s);
#			/\P{ascii}/ && /\p{Punctuation}/ && push(@$Rerrs,
#				lerr($lcnt,
#					"Line $lcnt: non-ascii punctuation: ",
#					encode('utf8', $_)))
#						for (@uchars);
		}
	}
	close FH;

	my @reserved =			# reserved NAANs, not assigned to orgs
		qw( 12345 99152 99166 99999 );

	my $numorgs = $ecnt - scalar @reserved;	# reduce to just count orgs

	my $errs = scalar(@$Rerrs);
	if ($errs) {
		$msg = "NOT OK - $naanfile: $numorgs orgs ($ecnt entries), "
			. "$errs errors",
		return(		# error, message, error list
			0,
			$msg,
			$Rerrs,
		);
	}

	# XXX need to add count of orgs in the new shared_naan shoulders
	# xxx de-dupe orgs for final count?
	#
	$msg = "OK - $naanfile: $numorgs orgs ($ecnt entries), $lcnt lines";
	return (1, $msg, $Rerrs);
}

1;
