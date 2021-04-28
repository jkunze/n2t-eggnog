#! /usr/bin/env perl

# Author: John A. Kunze, California Digital Library.
# Copyright 2016-2020 UC Regents. Open source BSD license. 

use 5.10.1;
use strict;
use warnings;

# MAIN

use NAAN;

my $naanfile = $ARGV[0];
$naanfile or
	die("No NAANsFile given");
# XXX do next line in Perl to remove shell dependency
my $contact_info =		# peek to see if file is anonymized
	`grep -q '^\!contact' $naanfile && echo 1`;
chop $contact_info;

say "XXX naanfile=$naanfile";
my ($ok, $msg, $Rerrs) = NAAN::validate_naans($naanfile, $contact_info);
if (! $ok) {
	say STDERR $msg;
	for my $e (@$Rerrs) {
		say STDERR "$e";
	}
	exit 1;
}
# else
say $msg;

## Now output two tiny files using file descriptors that caller redirects.
#
#my $rnumorgs = int($numorgs / 10) * 10;	# round number: truncate to nearest 10
#
#open(NORGS, ">&=4") and say NORGS "$numorgs"; close NORGS;
#open(RORGS, ">&=5") and say RORGS "$rnumorgs"; close RORGS;
##system("echo $numorgs > numorgs; echo $round_numorgs > round_numorgs");

exit;
