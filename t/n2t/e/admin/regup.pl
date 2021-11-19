#! /usr/bin/env perl

use 5.010;
use strict;
use warnings;

use utf8;
use open ':encoding(utf8)';
binmode(STDOUT, ":utf8");

use Text::ParseWords;
use YAML;
use Encode;
use Try::Tiny;          # for exceptions
use Safe::Isa;          # provides $_isa (yyy remind for what purpose?)
use HTML::Entities;

# Author:  John A. Kunze, jak@ucop.edu, California Digital Library
# Copyright (c) 2016-2021 UC Regents

my ($button, $remail, $rname, $naan, $request);	# $naan is unused naan
my $orig_request;
my $default_remail = 'curtis.curator@example.org';
my $default_rname = 'Curtis Curator';
my $msg;
my $play_mode = 0;

my $request_default = << 'EOT';
I would like	To request a new NAAN
Organization name:	Institut national des voisins
Are you a service provider?	No, or I'm not sure
Contact name:	Rip van Winkle
Contact email address:	rvw@catskills.us
Position in organization:	Data architect
Organization address:	4 avenue de la Guerre, 54321 Bry-sur-Marne
Organization base URL:	http://example.org
Organization status:	Not-for-profit
Organization acronym preferred: IV
Service provider contact information: Sam &quot;Sam&quot; Smith, ss@aaa.example.org, Acme Archiving
Committed to data persistence?	Agree
EOT

$request_default = << 'EOT';
I would like	To request a new NAAN
Organization name:	Acta Académica
Are you a service provider?	Yes
Service provider contact information:	Acta Académica, Pablo De Grande, pablodg@aacademica.org
Contact name:	Rodrigo Queipo
Contact email address:	contacto@aacademica.org
Position in organization:	archivist
Organization address:	Pedro Morán 2946, Buenos Aires, Argentina
Organization status:	Not-for-profit
Organization acronym preferred:	AA
Organization base URL:	https://aacademica.org
Other information:	If you can, please don't give my institution NAAN 66666.
Committed to data persistence?	Agree
EOT

$request_default = << 'EOT';
I would like	To request a new NAAN
Information about the memory organization
Organization name:	Journal of Cryptozoology
Organization acronym preferred:	JoC
Memory organization address:	oakland, CA 99999
Memory organization type:	Mass media (journalism, television, ...)
Memory organization status:	Not-for-profit
N2T resolver rule:	https://NLN.example.org/ojs/${nlid}
Organization homepage (URL):	https://NLN.example.org
Contact information
Are you a service provider?	No, or I'm not sure
Primary contact name:	Jan Jones
Primary contact email address:	janjjones@gmail.com
Primary contact position/role:	coder
Alternate contact name:	sam smith
Alternate contact email:	janjjones@gmail.com
Information about ARK usage plans
What are you planning to assign ARKs to using the requested NAAN?	documents (text or page images, eg, journal articles, technical reports)
supplemental data
Which of the following practices do you plan to implement when you assign ARKs on this NAAN?	No re-assignment. Once a base identifier-to-object association has been made public, that association shall remain unique into the indefinite future.
Opacity. Base identifiers shall be assigned with no widely recognizable semantic information. This can be achieved with a string generator such as Noid. Assigning ARKs based on a simple numerical counter is another option.
Check characters. A check character will be generated in assigned identifiers to guard against common transcription errors. This can be achieved with a string generator such as Noid.
Lowercase only. Any letters in assigned base identifiers will be lowercase.
Does the memory organization commit to data persistence?	Yes, this organization agrees to commit to data persistence.
Other information:	nothing else
EOT

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
#my $response_admin = "naan-registrar\@googlegroups.com, $provider";
my $request_file = 'request';
my $other_info_file = 'other_info';

my $op;			# operation context (NEW or UPDATE or '' (error))
my $saved_naa_file = '';
	my $NEW_NAA_OP = 'new_entry';		# a value of $saved_naa_file
	my $UPDATE_NAA_OP = 'update_entry';	# a value of $saved_naa_file
my $confirmer = 'worked_naan';
my $request_log = 'request_log';
my $reponame = 'naan_reg_priv';
my $default_naan = '98765';
my $example_naan = '12345';

my $home = "/apps/n2t";
my $workdirbase = "$home/naans";
my $validator = "$home/local/bin/validate_naans";

my $cmd = $0;
$cmd =~ s,.*/,,;		# drop path part
my $usage_text = << "EOT";
NAME
    $cmd - convert a NAAN request form to a registry entry

SYNOPSIS
    $cmd [ --github ] FormFile [ NAAN ]

DESCRIPTION
    Meant to be invoked via a web CGI process, this script converts a NAAN
    request form to a registry entry that is stored in the current directory
    under the filename, "$saved_naa_file".

    (This script was heavily adapted from an original script that was invoked
    with command line arguments and these lines expected on STDIN ("-"):
       line 1: email
       line 2: your name (given name then family name, eg, Sam Smith)
       line 3: NAAN
       lines 4-: form output
    )

    The documentation below is out of date. Proceed at your own risk.

    The FormFile is a file of form data in YAML (or CSV format, but CSV is
    not really tested). Data is usually entered via the
    https://goo.gl/forms/bmckLSPpbzpZ5dix1 form and delivered either by
    downloading a CSV file or pasting from an email generated from the
    filled-out form. If FormFile is given as '-', its contents are
    expected on stdin.

    If the NAAN is not given as a command argument, it should be given as
    head of a small block of form data in the FormFile. The block begins
    with the NAAN on a line by itself, and the remaining block lines should
    contain filled out form data up to a line starting "----". Unless the
    --github option is given, that block must be line 1 of FormFile; this
    option supports use of this script running in a github workflow (which
    allows the maintainer not to have to run under a Unix-like platform).
    
    Before calling, the caller will have selected the NAAN by editing the
    ./candidate_naans file and moving the top unassigned NAAN up over the
    line into the assigned NAANs part of the file.  As an example, the
    received form

      Contact name:	Gautier Poupeau
      Contact email address:	gpoupeau\@ina.fr
      Organization name:	Institut national de l'audiovisuel
      Position in organization:	Data architect
      Organization address:	4 avenue de l'Europe, 94366 Bry-sur-Marne Cedex
      Organization base URL:	http://www.ina.fr
      Organization status:	For profit
      Service provider contact information: Sam Smith, ss\@aaa.example.org, Acme Archiving

    with NAAN 99999 specified produces

      naa:
      who:    Institut national de l'audiovisuel (=) INA
      what:   99999
      when:   2016.09.23
      where:  https://www.ina.fr
      how:    FP | (:unkn) unknown | 2016 |
      !why:   ARK
      !contact: Poupeau, Gautier ||| gpoupeau\@ina.fr |
      !address: 4 avenue de l'Europe, 94366 Bry-sur-Marne Cedex
      !provider: Sam Smith, ss\@aaa.example.org, Acme Archiving

EOT

sub called_from_cgi {

	# First output necessary HTTP headers. Real output comes after that.
	#echo "Content-type: text/plain; charset=UTF-8"
	#echo ""

	use CGI;
	my $cgi = CGI->new;
	my %param = map { $_ => scalar $cgi->param($_) } $cgi->param() ;

	# This is needed to start the HTTP response.
	print $cgi->header( -type => 'text/html; charset=UTF-8' );
	print "\n";

#my $button = $cgi->param('button');
#
#say "XXX button=$button";
#exit;
	#open(PIPE, "| ./regup.pl --github -") or
	#	die("couldn't open pipe to regup.pl: $!");
	# XXX only unaan is relevant
	#print PIPE
	#	"button: ",	$cgi->param('button'),	"\n", # NEW, UPDATE, Retest, Confirm
	#	"remail: ",	$cgi->param('remail'),	"\n", # responder email
	#	"rname: ",	$cgi->param('rname'),	"\n", # responder email
	#	"unaan: ",	$cgi->param('unaan'),	"\n", # used or unused NAAN
	#	"request: ",	$cgi->param('request'),	"\n", # request form data
	#;

	## XXX only unaan is relevant?
	return (
		$cgi->param('button'),	# NEW, UPDATE, Retest, Confirm
		$cgi->param('remail'),	# responder email
		$cgi->param('rname'),	# responder email
		$cgi->param('unaan'),	# used or unused NAAN
		$cgi->param('request'),	# request form data
	);
}

sub pr_foot {

	print << "EOT";

</div>
</div>
</div>

<!-- Footer -->
<div class="row footer">
  <div class="col-xs-12 container-widest">
    <div class="row">
      <div class="col-xs-12 col-sm-12">
        <p class="text-sm" align=center>
	N2T.net is a service of the
	<a href="http://www.cdlib.org/">California Digital Library</a>
	(<a href="https://cdlib.org/contact/">contact us</a>),
	a division of the <a href="http://www.universityofcalifornia.edu/">
	University of California Office of the President</a>
	<br/>
        &copy; 2007-<script type="text/javascript">
	document.write(new Date().getFullYear());</script>
	The Regents of the University of California
	</p>
      </div>
    </div>
  </div>
</div>

</body>
</html>
EOT
}

sub pr_head { my( $page_title )=@_;

	print << "EOT";

<html lang="en">
<head>
    <!-- Basic Page Needs -->
  <meta charset="utf-8">
  <meta name="description" content="">
  <meta name="author" content="">

  <!-- Mobile Specific Metas -->
  <meta name="viewport" content="width=device-width, initial-scale=1">

  <!-- CSS -->
  <link rel="stylesheet" href="/e/css/flexboxgrid-6.3.1-min.css">
  <link rel="stylesheet" href="/e/css/styles.css">
  <link rel="stylesheet" href="/e/css/styles_rst.css">
  <link rel="shortcut icon" type="image/png" href="/e/images/favicon.ico?v=2"/>
  <link rel="icon" sizes="16x16 32x32" href="/e/images/favicon.ico?v=2">

  <title>$page_title NAAN entry</title>
</head>
<body>
<div class="content">
<header class="header row center-xs">
  <div class="col-xs-12 col-sm-10">
    <div class="row middle-xs header">
      <p class="col-xs header-logo-left center-horiz">
        <img src="/e/images/n2t_net_logo.png" alt="N2T.net logo"
	  width="auto" height="56"/>
      </p>
      <p class="col-xs header-logo-right center-horiz" style="font-size:1.4em;">
        RESOLVING
	<br/>
	Names to Things
      </p>
      <p align="right" class="single-space">
        <a href="/e/about.html">About</a><br/>
        <a href="/e/partners.html">N2T Partners</a><br/>
        <a href="/e/n2t_apidoc.html">API Documentation</a>
      </p>
    </div>
  </div>
</header>

<div class="container-narrowest">
<div class="section" id="naanq2e">
<h1>$page_title NAAN entry</h1>

EOT
}

my $no_gen = 1;			# yyy constant
my $from_vim = 0;
my $github = 0;
my $naan_restored = 0;
my $real_thing;
my ($workdir, $repodir, $main_naans, $cand_naans);

sub perr {
	print "\n";
	say STDERR '<pre>';
	print STDERR ($from_vim ? "# Error: " : "Error: ");
	say STDERR @_;
	say STDERR '</pre>';
}

sub debug {
	print "\n";
	say STDERR '<pre>';
	print STDERR ($from_vim ? "# debug: " : "debug: ");
	say STDERR @_;
	say STDERR '</pre>';
}

# Initialize working directory and set some globals:
#     $workdir, $main_naans, $cand_naans.

sub init_dir { my( $naan )=@_;

	if ($naan !~ /^[s\d][\d]+$/) {
		perr("Bad NAAN specified: $naan");
		perr("NAAN must be all digits (optionally preceded by 's') "
			. " or empty.");
		#perr("Please go back and resubmit.");
		return '';
	}

	$workdir = "$workdirbase/$naan";
	$repodir = "$workdir/$reponame";
	$main_naans = "$repodir/main_naans";
	$cand_naans = "$repodir/candidate_naans";
	if (! -d $workdir) {
		`mkdir -p $workdir 2>&1`;
		if ($? >> 8) {
			perr("could not do: mkdir - $workdir");
			exit 1;
		}
	}
	if (! chdir($workdir)) {
		perr("could not chdir to $workdir: $!");
		return '';
	}
	my $out = `pwd; ls`;
	$out = `
		rm -fr $reponame;
		git clone git\@github.com:jkunze/$reponame.git 2>&1;
	`;
	if ($? >> 8) {
		perr("could not clone git repo: $out");
		exit 1;
	}
	return $out;
}

# assemble and return comment lines in one block (string) from $naa
# yyy unused

sub scrape_comments { my( $naa )=@_;
	join "\n", grep /^#/, split /\n/m, $naa;
}

# Returns ($emsg, $naa_entry, $orgname, $naan, $firstname, $email, $provider)
# $emsg is error message, empty on success

# From curator form
sub from_cform { my( $naa )=@_;

	my $emsg = '';			# empty $emsg mean no error
	my $full_naa = $naa;
	$naa =~ s/^\s*#.*\n//mg;	# drop comment lines

	if ($naa !~ m{  who:\s+(.*?)\s*\n
			what:\s+(.*?)\s*\n
			.*?\n
			!contact:\s+[^,]*,\s+(\S+).*?\s*(\S+?@\S+)\s*\|.*?\n
			.*?\n
			(!provider:\s+(.+?)\n)?
	    }xs) {
		$emsg = "Malformed candidate NAAN entry formed: $naa";
		return ($emsg);
	}
		 #(!provider:\s+.*?(\S+?@\S+?)\n)?
		 #(!provider:\s+(.+?)\n)?

	my ($orgname, $naan, $firstname, $email, $provider) = 
		($1, $2, $3, $4, $5);
	$orgname =~ s/\s*\(=\).*//;
	return ($emsg, $full_naa, $orgname, $naan, $firstname, $email, $provider);
}

# Returns ($emsg, $naa_entry, $orgname, $firstname, $email, $provider)
# $emsg is error message, empty on success

sub fetch_naa { my( $naan )=@_;

	my $emsg = '';		# empty $emsg mean no error
	my $granvl_cmd = "$home/local/bin/granvl";
	$granvl_cmd .= qq@ -x 'v("what") eq "$naan"' $main_naans 2>&1 @;

	my $naa = `$granvl_cmd`;
	my $gstat = $? >> 8;
	if ($gstat > 1) {
		$emsg = "could not do: $granvl_cmd";
		return ($emsg);
	}
	chop $naa;
	if (! $naa) {
		$emsg = "No existing NAA found for $naan";
		return ($emsg);
	}
	my $full_naa = $naa;		# save original with comments
	$naa =~ s/^\s*#.*\n//mg;	# drop comment lines

	if ($naa !~ m{	who:\s+(.*?)\s*\n
			what:\s+(.*?)\s*\n
			.*?\n
			!contact:\s+[^,]*,\s+(\S+).*?\s*(\S+?@\S+)\s*\|.*?\n
			.*?\n
			(!provider:\s+(.+?)\n)?
	    }xs) {
		$emsg = "Malformed NAAN entry fetched: $naa";
		return ($emsg);
	}

	my ($orgname, $xnaan, $firstname, $email, $provider) = 
		($1, $2, $3, $4, $5);
	$orgname =~ s/\s*\(=\).*//;
	return ($emsg, $naa, $orgname, $xnaan, $firstname, $email, $provider);
}

sub save_request { my( $input )=@_;

	my $request = '';
	$request .= "Date:\t$year.$mon.$mday\n";	# date processed
	$from_vim and			# if from vim, clothe naked NAAN with
		$request .= "Curator-supplied NAAN:\t";	# label prepended
	$request .= $input;		# original request
	open OUT, ">", "$request_file" or
		perr("could not open $request_file for writing"),
		return '';
	say OUT "$request";
	close OUT;
}

# From user request form
sub from_uform { my( $naan, $input )=@_;

	$_ = $input;		# decoded form data

	s/\r//g;		# drop any CR's (pasted in from Windows)
	s/\n*$/\n/s;		# make sure it ends in just one \n
	# Make last char before tab be a :, replacing a : or ?, if any.
	# Also, some clients (Windows) may add a space before tab -- drop these
	s/[:?]? *\t+/: /g and	# YAML needs : and forbids tab-for-space, and
		# as long as we're not doing CSV fields, elide \n in front of
		s/\n([^:]*)$/ $1/m and	# lines with no colon (a contin. line),
		s/$/\n/;		# but make sure whole thing ends in \n

	# Flag annoying non-ascii punctuation (eg, ' and -). Unicode errors
	# happen that raise fatal exceptions happen too often to leave them
	# uncaught.

	# yyy Move this test earlier?
	my @uchars;
        try {
		@uchars = split '', decode('utf8', $_);
        }
        catch {
		# xxx why can't I block the exception with args to decode()?
		$msg = << 'EOT';
Oops, it looks like there are some unicode decoding errors that need to
be fixed. Usually this requires replacing characters that can look like
apostrophes ("'") and long hyphens ("-") with plain ASCII apostrophes and
hyphens. Please go back, try that, and resubmit.
EOT
		perr($msg);
		# xxx for some reason this doesn't work -- does it make sense?
		/\P{ascii}/ && /\p{Punctuation}/ && perr(
			"warning: non-ascii punctuation: ", encode('utf8', $_))
				for (@uchars);
                return '';
	};
	#my @uchars = split '', decode('utf8', $_);

	# Only look for CSV input when a flag is set (in a way yet TBD).
	my $csv_input = 0;
	# CSV fields:
	# "Timestamp","Contact name:","Contact email address:","Organization name:","Position in organization:","Organization address:","Organization base URL:","Organization status:","Service provider:","Organization acronym preferred:","Other information:"
	my $timestamp;			# unused field if it's a CSV parse
	my $h;				# hash if it's a YAML parse
	my ($fullname, $email, $orgname, $role, $address,
		$URL, $ostatus, $provider, $acronym, $other);
	my ($firstname, $lastname);
	my $copy_err;

	# Input is in request form (via Submit) or in ANVL form (via Retest or
	# Confirm). If the latter, we need to massage it into YAML first.

	# xxx very flawed test -- do real csv parse instead,
	#     or check for occurrences of "," ?
	#     often the org address has many commas -- don't check that field?
	if ($csv_input) {
		(			# assume input is in CSV-format
			$timestamp,			# unused field
			$fullname, $email, $orgname, $role, $address,
				$URL, $ostatus, $provider, $acronym, $other
		) = Text::ParseWords::parse_line(',', 0, $_);
		$copy_err = '';		# not actually checking for an error
		# xxx should limit to number of fields, eg, in face of
		# texty "Other info"
	}
	else {
		try {
			$h = Load($_);	# YAML parse, returning hash reference

			# If the first and last fields aren't present,
			# there's likely an incomplete copy/paste job.

			$copy_err = ! $h->{'Organization name'} ||
				    ! $h->{'Committed to data persistence'}
				    ? "Missing organization name or commitment."
				    : '';

			$fullname = $h->{'Contact name'} || '';
			$orgname = $h->{'Organization name'} || '';
			$acronym = $h->{'Organization acronym preferred'} || '';
			$ostatus = $h->{'Organization status'} || '';
			$URL = $h->{'Organization base URL'};
			$email = $h->{'Contact email address'};
			$address = $h->{'Organization address'};
			#$provider = $h->{'Service provider'} || '';
			$provider = $h->{'Service provider contact information'} || '';
			$role = $h->{'Position in organization'} || '';
			$other = $h->{'Other information'} || '';
		}
		catch {
			$copy_err = "YAML error, likely a copy paste problem.";
		}
	}
	# yyy check if YAML strips surrounding whitespace
	if ($copy_err) {
		return ("Looks like an incomplete request. Please go back "
			. "and check for a copy/paste error.\n$copy_err");
	}

	# Get part of personal name (just a guess, so bears checking)
	($firstname, $lastname) = $fullname =~ /^\s*(.+)\s+(\S+)\s*$/ or
		return ("could not parse personal name \"$fullname\"");
	unless ($acronym) {
		$acronym = $orgname;
		# drop stop words in English, French, and Spanish
		$acronym =~ s/\b(?:the|and|of|l[ae']|et|d[eu']|des)\b//g;
		# stop possessive 's' from showing up in the acronym
		# XXX bug: non-ascii being mistaken for word boundaries?
		#     eg, who:    Euro France Médias (=) EFM?D
		$acronym =~ s/\b's\b//g;
		$acronym =~ s/\b(.).*?\b/\U$1/g;	# first letter
		$acronym =~ s/\s//g;			# drop whitespace
	}

	my $bmodel =
		($ostatus eq 'For profit' ? 'FP' :
		($ostatus eq 'Not-for-profit' ? 'NP' :
			"ORGSTATUS: $ostatus"));
	#if ($bmodel !~ /^[FN]P$/) {
	#	push @err_list, "Change ORGSTATUS ($ostatus) to FP or NP";
	#}


	# yyy should lc hostname part
	$URL =~ s,[./]+\s*$,,;		# remove terminal / or . if any
	$URL =~ m,^https?://, or
		$URL = 'https://' . $URL;	# clothe a naked hostname
	my $provider_line = $provider;
	$provider_line and
		$provider_line = "\n!provider: $provider_line";

	if (! init_dir($naan)) {
		#say STDERR "Could not initialize directory for $naan";
		#return '';
		return ("Could not initialize directory for $naan");
	}

	if ($other =~ /./) {	# if has real content, save to file for later
		#say STDERR "Note other info: |$other|";
		open OUT, ">", "$other_info_file" or
			return ("could not open $other_info_file for writing");
			#perr("could not open $other_info_file for writing"),
			#return '';
		say OUT "$other";
		close OUT;
	}
	else {	# else remove, since it might exist from prior testing run
		-e $other_info_file and
			unlink $other_info_file;	# yyy ignore return
	}
	if (! save_request($input)) {		# save request to a file after
		return 'Failed to save request';	# printing own mesg
	}

	my $naa_entry = 
"naa:
who:    $orgname (=) $acronym
what:   $naan
when:   $year.$mon.$mday
where:  $URL
how:    $bmodel | (:unkn) unknown | $year |
!why:   ARK
!contact: $lastname, $firstname ($role) ||| $email |
!address: $address$provider_line

";
	return ('', $naa_entry, $orgname, $firstname, $email, $provider);
}

# returns 1 on success, 0 on error

sub confirmed { my( $op, $orgname, $naan, $provider, $email, $firstname, $safe_naa_entry )=@_;

	my $form_dest = $remail
		? "is being emailed to you"
		: "appears below"
	;

#	# save $naan in a file
#	`echo $naan > $working_naan 2>&1`;
#	if ($? >> 8) {
#		perr("could not save $naan in $working_naan");
#		exit 1;
#	}

	# $request_file was saved earlier
	`tr -d '\r' < $request_file >> $repodir/$request_log 2>&1`;
	if ($? >> 8) {
		perr("could not append $request_file to $repodir/$request_log");
		exit 1;
	}

	my $institution = $orgname;	# if org has a secondary name,
	$institution =~ s/ \(=\).*//;	# reduce it to a primary name
	#Subject: NAAN request for $acronym

	my $prov_text = $provider
		? "If the \"provider\" information,</p>\n"
		  . "<pre>     $provider</pre>\n"
		  . "<p>makes sense (requesters are often confused by this\n"
		  . "means), also CC the provider. "
		: "";

	my $response_letter;
	if ($op eq 'UPDATE') {
		$response_letter = << "EOT";
Subject: NAAN update request for $orgname
Content-Type: text/html; charset=utf-8

<html>
<head>
<title></title>
</head>
<body>
<p>
Proposed new entry:
</p>
<pre>
$safe_naa_entry
</pre>
</p>
<p>
Below the cut line is a proposed response email, intended to be sent to: $email
</p><p>
When proofreading, adjust the salutation to use the recipient's given
(first) name, and your signature is correct.
It is not uncommon that an update request comes from somone not listed as
the current contact person, in which case you should add an inquiry. Example:
</p><p>
<em>
Our registry shows Sherlock Holmes as the current contact person. Could you
confirm whether you should be listed as a contact person instead of or in
addition to him?
</em>
</p>
<p>
--------- CUT HERE ---------
</p>
<p>
Hi $firstname,
</p><p>
Thank you for helping to keep the NAAN registry up-to-date. The requested
change has been made. It may take up to 24 hours for changes to be recognized
by the N2T.net resolver.
</p><p>
All the best,
</p><p>
-$rname, on behalf of NAAN-Registrar\@googlegroups.com
</p>
</body>
</html>
EOT
	}
	else {
		$response_letter = << "EOT";
Subject: NAAN request for $orgname
Content-Type: text/html; charset=utf-8

<html>
<head>
<title></title>
</head>
<body>
<p>
Proposed new entry:
</p>
<pre>
$safe_naa_entry
</pre>
</p>
<p>
Below the cut line is a proposed response email, intended to be sent to: $email
<br/><br/>
Start to forward that email to the intended recipient, adding a CC to
NAAN-Registrar\@googlegroups.com and removing evidence of forwarding (eg,
your email agent may insert "Fwd: " into the Subject line).
$prov_text
Then remove any footer (eg, might be added by an email group).
</p><p>
Finally, proofread the rest. Among other things, check that (a) the salutation
makes sense (uses the recipient's given (first) name, (b) the organization name
is correct, and (c) your signature is correct. Also check that any service
provider is CC'd and all questions or anomalies arriving with the request have
been addressed by adding your own customized response text (usually in the
first paragraph).
</p>
<p>
----- CUT HERE ---- English version, followed by French, then Spanish ----
</p><p>
<p>
Hi $firstname,
</p><p>
Thanks for your request. The NAAN,
</p><p style="margin-left:4em">
$naan
</p><p>
has been registered for "$institution" and you may begin using it immediately. It may take up to 24 hours before your NAAN will be recognized by the N2T.net resolver.
</p><p>
Please note that $naan is intended for assigning ARKs to content that your institution directly curates or creates.
In case you work with other institutions that use your tools and services for content that they curate or create, those institutions should have their own NAANs.
</p><p>
In thinking about how to manage the namespace, you may find it helpful to consider the usual practice of partitioning it with reserved prefixes ("<a href="https://arks.org/about/shoulders/">shoulders</a>") of a letter followed by a number, eg, names of the form "ark:/$naan/x3...." for each "sub-publisher" in an organization.
Opaque prefixes that only have meaning to information professionals are often a good idea and have precedent in schemes such as ISBN and ISSN.
</p><p>
The best starting place for information on ARKs (Archival Resource Keys) is the
<a href="https://arks.org">ARK Alliance</a> website. You may also find useful
information in the
<a href="https://wiki.lyrasis.org/display/ARKs/ARK+Identifiers+FAQ">ARKs FAQ</a>
(<a href="https://wiki.lyrasis.org/pages/viewpage.action?pageId=178880619">version française</a>,
<a href="https://wiki.lyrasis.org/pages/viewpage.action?pageId=185991610">version en español</a>)
and <a href="https://arks.org/about/">this ARK identifier overview</a>.
The <a href="https://n2t.net/ark:/13030/c7cv4br18">ARK specification</a> is currently the best guide for how to create URLs that comply with ARK rules, although it is fairly technical.
There is a <a href="https://groups.google.com/group/arks-forum">public discussion group for ARKs</a>
(<a href="https://framalistes.org/sympa/info/arks-forum-fr">forum francophone</a>)
intended for people interested in sharing with and learning from others about how ARKs have been or could be used in identifier applications.
The best open source software for setting up your own ARK service implementation is currently <a href="http://n2t.net/e/noid.html">Noid</a>.
</p><p>
There's nothing else you need to do right now. As you may know, we're drafting
some <a href="https://n2t.net/ark:/13030/c7833mx7t">standardized persistence
statements</a> that name assigning authorities can begin testing (feedback is
welcome) and using if they wish.
</p><p>
-$rname, on behalf of NAAN-Registrar\@googlegroups.com
</p><p>
---- French version ----
</p><p>
Bonjour $firstname,
</p><p>
Merci pour votre demande. Le NAAN,
</p><p style="margin-left:4em">
$naan
</p><p>
a été enregistré pour "$institution" et vous pouvez commencer à l'utiliser immédiatement. Cela peut prendre jusqu'à 24 heures avant que votre NAAN soit reconnu par le résolveur N2T.net.
</p><p>
Veuillez noter que le numéro d'autorité nommante $naan est destiné à attribuer des ARK au contenu que votre institution conserve ou crée directement.
Si vous travaillez avec d'autres institutions qui utilisent vos outils et services pour du contenu qu'elles conservent ou créent, ces institutions doivent avoir leur propre NAAN.
</p><p>
Lorsque vous réfléchirez à la manière de gérer l'espace de nommage, il peut vous être utile de considérer la pratique habituelle consistant à le partitionner avec des préfixes réservés ("<a href="https://arks.org/about/shoulders/">shoulders</a>").
Par exemple, un préfixe constitué d'une lettre suivie d'un chiffre, formerait des noms de commençant par "ark:/$naan/x3 ..." pour chaque "sous-autorité" d'une organisation.
Les préfixes opaques qui n'ont de sens que pour les professionnels de l'information sont souvent une bonne idée et ont un précédent dans des systèmes tels que l'ISBN et l'ISSN.
</p><p>
Le meilleur point de départ pour obtenir des informations sur les ARK (Archival Resource Keys) est le <a href="https://arks.org/">site Web d'ARK Alliance</a>.
Vous pouvez également trouver des informations utiles dans la <a href="https://wiki.lyrasis.org/pages/viewpage.action?pageId=178880619">FAQ sur les ARK</a> et dans <a href="https://www.bnf.fr/fr/sommet-international-ark-journee-detude-et-dechanges-sur-lidentifiant-ark-archival-resource-key#bnf-ark-pour-les-d-butants">cette présentation de l'identifiant ARK</a>.
La <a href="https://n2t.net/ark:/13030/c7cv4br18">spécification ARK</a> (en anglais) est actuellement le meilleur guide pour savoir comment créer des URL conformes aux règles ARK, bien qu'elle soit assez technique.
Il existe un <a href="https://framalistes.org/sympa/info/arks-forum-fr">groupe de discussion francophone public</a> sur les ARK destiné aux personnes désireuses de partager et d'apprendre des autres sur la manière dont les ARK ont été ou pourraient être utilisés dans des applications de gestion d'identifiants.
Le meilleur logiciel libre pour mettre en œuvre votre propre service ARK est actuellement <a href="http://n2t.net/e/noid.html">Noid</a>.
</p><p>
Vous n'avez rien d'autre à faire pour l'instant. Comme vous le savez peut-être, nous sommes en train de rédiger des <a href="https://n2t.net/ark:/13030/c7833mx7t">déclarations de persistance normalisées</a> (en anglais) que les autorités chargées de l'attribution des noms peuvent commencer à tester (les commentaires sont les bienvenus) et à utiliser si elles le souhaitent.
</p><p>
-$rname, au nom de NAAN-Registrar\@googlegroups.com
</p><p>
---- Spanish version ----
</p><p>
<p>
Hola, $firstname,
</p> <p>
Gracias por su solicitud. El NAAN,
</p> <p style = "margin-left: 4em">
$naan
</p> <p>
se ha registrado para "$institution" y puede comenzar a usarlo de inmediato. Pueden pasar hasta 24 horas antes de que el sistema de resolución de N2T.net reconozca su NAAN.
</p> <p>
Tenga en cuenta que $naan está destinado a asignar ARK a contenido que su institución selecciona o crea directamente.
En caso de que trabaje con otras instituciones que utilizan sus herramientas y servicios para el contenido que ellos curan o crean, esas instituciones deben tener sus propios NAAN.
</p> <p>
Al pensar en cómo administrar el espacio de nombres, puede resultarle útil considerar la práctica habitual de dividirlo con prefijos reservados (<a href="https://arks.org/about/shoulders/">hombros</a> ) de una letra seguida de un número, por ejemplo, nombres de la forma "ark:/$naan/x3...." para cada "subeditor" en una organización.
Los prefijos opacos que solo tienen significado para los profesionales de la información suelen ser una buena idea y tienen precedente en esquemas como ISBN e ISSN.
</p> <p>
El mejor lugar de partida para obtener información sobre las ARK (claves de recursos de archivo) es la
sitio web de <a href="https://arks.org"> ARK Alliance </a>.
También puede resultarle útil información en el
<a href="https://wiki.lyrasis.org/display/ARKs/ARK+Identifiers+FAQ"> Preguntas frecuentes sobre ARK </a>
(<a href="https://wiki.lyrasis.org/pages/viewpage.action?pageId=178880619"> versión francesa </a>,
<a href="https://wiki.lyrasis.org/pages/viewpage.action?pageId=185991610"> versión en español </a>)
y <a href="https://arks.org/about/"> esta descripción general del identificador ARK </a>.
La <a href="https://n2t.net/ark:/13030/c7cv4br18"> especificación ARK </a> es actualmente la mejor guía sobre cómo crear URL que cumplan con las reglas ARK, aunque es bastante técnica.
Hay un <a href="https://groups.google.com/group/arks-forum"> grupo de debate público para ARK </a>
(<a href="https://framalistes.org/sympa/info/arks-forum-fr"> foro francófono </a>)
destinado a personas interesadas en compartir y aprender de otras personas sobre cómo se han utilizado o podrían utilizarse las ARK en aplicaciones de identificación.
El mejor software de código abierto para configurar su propia implementación de servicio ARK es actualmente <a href="http://n2t.net/e/noid.html"> Noid </a>.
</p> <p>
No hay nada más que deba hacer ahora mismo. Estamos redactando
algunas <a href="https://n2t.net/ark:/13030/c7833mx7t"> persistencia estandarizada
declaraciones </a> que las autoridades que asignan nombres pueden comenzar a probar (los comentarios son
bienvenido) y usarlo si lo desea.
</p> <p>
- $rname, en nombre de NAAN-Registrar\@googlegroups.com
</p>

</body>
</html>
EOT
	}

	#open OUT,
	#  "|mail -S ttycharset=UTF-8 -s 'NAAN request for $acronym' \
	#            jakkbl\@gmail.com"
	#  	or die("couldn't open pipe to email response");

	# save letter to a file
	open OUT, ">", "response.html" or
		perr("could not open response.html file"),
		return 0;
	print OUT $response_letter;
	close OUT;

	if ($remail and $remail ne $default_remail) {
		# send letter to admin address (may not work on some networks)
		open OUT, "|sendmail $remail" or
			perr("could not open pipe to email response"),
			return 0;
		print OUT $response_letter;
		close OUT;
	}
	else {
		print "----------------------\n";
		print $response_letter;
	}
	return 1;
}

sub oinfo { my( $info_file, $update_request )=@_;

	my $other_info;
	if ($update_request) {
		$other_info = $update_request;
	}
	elsif (! -e $info_file) {
		return '';
	}
	else {
		$other_info = `cat $info_file 2>&1`;
		if ($? >> 8) {
			perr("error opening $info_file: $other_info");
			exit 1;
		}
	}
	my $safe_other_info = encode_entities( $other_info );
	#$safe_other_info =~ s|(.*)\t|<b>$1</b>\t|g;
	#$safe_other_info =~ s|\n|<br/>|g;
	#$safe_other_info = "<br/> $safe_other_info <br/>\n";
	$safe_other_info = "<pre> $safe_other_info </pre>\n";
	if ($update_request) {			# UPDATE_NAA_OP
		$other_info = "Information from the requester:"
			. $safe_other_info;
	}
	else {					# NEW_NAA_OP
		$other_info = "Other information from the requester:"
			. $safe_other_info;
	}
	return $other_info;
}

# figure out and return (x, y), where x is which operation the curator
# the curator started with (NEW or UPDATE) and y is which file the request
# is save in (the filename persists and its existence informs us what the
# operation was in the case of Retest or Confirm).;a

sub which_op {

	if (-e $NEW_NAA_OP and -e $UPDATE_NAA_OP) {
		perr "both $NEW_NAA_OP and $UPDATE_NAA_OP exist";
		return ('', 'ERROR_BOTH');
	}
	-e $NEW_NAA_OP and
		return ('NEW', $NEW_NAA_OP);
	-e $UPDATE_NAA_OP and
		return ('UPDATE', $UPDATE_NAA_OP);
	perr "neither $NEW_NAA_OP nor $UPDATE_NAA_OP exist";
	return ('', 'ERROR_NEITHER');
}

# print HTML-formatted errors, one per line

sub out_errs { my( $Rerrs )=@_;

	my $numerrs = scalar(@$Rerrs);
	if (! $numerrs) {
		return 0;
	}
	say "<p>Errors:<ol>";
	for my $e (@$Rerrs) {
		say "<li>", encode_entities( $e ), "</li>";
	}
	say "</ol></p>";
	say "<p>Changes required. &nbsp; &nbsp; &nbsp; &nbsp;";
	return $numerrs;
}

sub confirm_mesg { my( $confirm_button )=@_;

	if ($confirm_button) {	# in context of a Confirm button?
		return '';
	}
	my $mesg;
	if ($play_mode) {
		$mesg = " &nbsp; &nbsp; (not really, just a test " .
			"without making changes)";
	}
	else {
		$mesg = " &nbsp; &nbsp; (and send email " .
			"to $remail for forwarding to requester)";
	}
	return $mesg;
}

# MAIN
{
	use open qw/:std :utf8/;
	$#ARGV < 0 || $ARGV[0] =~ /^--*h/ and	# eg, -help, --help
		print($usage_text),
		exit 0;
	if ($ARGV[0] =~ /^--github/) {
		$github = 1;
		$from_vim = 1;
		# yyy $from_vim behavior may become default in github actions
		shift;
	}

	my $FormFile = $ARGV[0];
	shift;
	$FormFile ne '-' and
		unshift @ARGV, $FormFile;

	# Get parts of today's date.
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	$year += 1900;
	$mon = sprintf("%02d", $mon + 1);
	$mday = sprintf("%02d", $mday);

	my $out = '';
	my $errs = 1;
	my $warnings = 1;

	# Read the input file.
	local $/;		# set input mode to slurp whole file at once
	$_ = <>;		# slurp entire file from stdin or named arg
	s/\n*/\n/;		# make sure it ends in just one newline

	# check for a block in the file and isolate it into $_ by
	# deleting everything around it
	s/^\s*\n//mg;		# drop blank lines

	# Split the input block into params added by CGI script
	# and params copied in from request form data.
	# XXX for now the only way to run the script is via web CGI

	($button, $remail, $rname, $naan) = called_from_cgi();

	# When we get here, $_ holds the request body.
	# In the Submit case, that's a raw request. In the UPDATE case, it's
	# also the raw request, but we still have to fetch the NAAN entry that
	# we will work on. In the Retest and Confirm cases, it's the entry
	# built from the request, plus any corrections applied to it.

	#debug "from CGI rname=$rname, remail=$remail, naan=$naan";

	my ($naa_entry, $orgname, $firstname, $email, $provider);
	my ($emsg, $update_request);

	pr_head( $button eq 'Confirm' ? 'Final' : 'Review candidate' );
say "XXXwyyy button=$button";

	if ($button eq 'NEW') {
		$saved_naa_file = $NEW_NAA_OP;
		$op = 'NEW';
		$naan ||= $default_naan;
		$orig_request = /^\s*$/		# if empty request
			? $request_default	# use default
			: $_			# else use supplied data
		;
		my $raw_orig_request = decode_entities( $orig_request );

		# this will call init_dir
		($emsg, $naa_entry, $orgname, $firstname, $email, $provider) =
			from_uform($naan, $raw_orig_request);
		if ($emsg) {
			perr "$emsg ($button): $_";
			exit 1;
		}
		$_ = $raw_orig_request;
	}
	elsif ($button eq 'UPDATE') {
		$saved_naa_file = $UPDATE_NAA_OP;
		$op = 'UPDATE';
		if (! $naan) {
			$naan = $example_naan;
			$play_mode = 1;
		}
		if (! init_dir($naan)) {
			say STDERR "Could not initialize directory for $naan";
			exit 1;
		}
		$update_request = $_;
		if (! save_request($update_request)) {	# save request to a file
			exit 1;
		}
		($emsg, $naa_entry, $orgname, $firstname, $email,
				$provider) =
			fetch_naa( $naan );
		if ($emsg) {
			perr "$emsg ($button): $_";
			exit 1;
		}
	}
	else {		# by elimination, $button must be Retest or Confirm
		($emsg, $naa_entry, $orgname, $naan, $firstname, $email,
				$provider) =
			from_cform( $_ );
		if ($emsg) {
			perr "$emsg ($button): $_";
			exit 1;
		}
		if (! init_dir($naan)) {
			say STDERR "Could not initialize directory for $naan";
			exit 1;
		}
		($op, $saved_naa_file) = which_op();
	}
	if (! $naa_entry) {	# $naa_entry must be defined
		exit 1;
	}
	$naa_entry =~ s/\r//g;		# delete carriage returns (from web)

	# if one of these well-known NAANs then we're just in test/play mode
	if ($naan eq $default_naan or $naan eq $example_naan) {
		$play_mode = 1;
		$remail = $default_remail;
		$rname = $default_rname;
	}
	else {
		my $grep = `grep "^$naan" $cand_naans 2>&1`;
		my $gstat = $? >> 8;
		if ($gstat > 1) {
			perr("could not do: grep '$naan' $cand_naans: $grep");
			exit 1;
		}
		if ($gstat == 1 or $grep !~ /^$naan\s+(\S+)\s+(.*)\s*\n$/) {
			perr( << "EOT" );
the <em>candidate_naans</em> file on github contained no line of the form

   <em>$naan YourEmail FirstName LastName</em>

Cannot proceed without such a line. (Did you remember to COMMIT?)
EOT
			$grep =~ /.\n/ and
				perr("Found this similar line |$grep|");
			exit 1;
		}
		($remail, $rname) = ($1, $2);
		#debug "grepped rname=$rname, naan=$naan";
		$play_mode = $rname =~ /Tester/i ? 1 : 0;
	}
# XXX need daemon to expire and remove directories over N weeks old

	my ($f1, $f2);	# first letter of first and second name, respectively
	($f1, $f2) = $rname =~ /^(.).*? +(.)/;	
	$out = `echo "# $naan $f1$f2: $orgname" > $confirmer 2>&1`;
	if ($? >> 8) {
		perr("could not save file: $confirmer");
		exit 1;
	}

	# Save $naa_entry in a file whose name reminds us whether this all
	# started with a NEW or UPDATE.

	open OUT, ">", "$saved_naa_file" or
		perr("could not open $saved_naa_file for writing"),
		exit 1;
	print OUT "$naa_entry";
	print OUT "\n";	# important separator for next entry to come
	close OUT;

	#say "<h3>Candidate NAAN entry</h3><p>";
	my $safe_naa_entry = encode_entities( $naa_entry );
	say << "EOT";
<pre>
<form id="entryform" action="/e/admin/q2e.pl">
<textarea name="request" cols="94" rows="13" id="request" form="entryform">
$safe_naa_entry
</textarea>
</pre>
EOT

	my ($save, $linenums);
	my $safe_other_info = '';

	#if ($saved_naa_file eq $NEW_NAA_OP) {
	if ($op eq 'NEW') {
		$save = `cat $saved_naa_file >> $main_naans 2>&1`;
		$linenums = 0;		# usually at end of file
		$safe_other_info = oinfo $other_info_file;
	}
	#elsif ($saved_naa_file eq $UPDATE_NAA_OP) {
	elsif ($op eq 'UPDATE') {
		# Replace relevant naa entry with modified entry.
		# Read from file to avoid nightmare quoting problems
		# worse than those below.
		# Here $pentry is a Perl-local instance of $naa_entry.
		$save = `perl -p000 -i'.bak' \\
			-E "BEGIN { open IN, '<', '$saved_naa_file' or \\
				 say(STDERR 'could not open $saved_naa_file for reading'), exit(1); \\
				 local \\\$/; \\
				\\\$pentry = <IN>; \\
			}" \\
			-E "/\\nwhat:\\s*$naan\\n/ and \\
				s.*\\\$pentrys;" \\
				$main_naans 2>&1`;
		$linenums = 1;		# where in file, potentially anywhere
		$safe_other_info = oinfo 1, $update_request;
	}
	if ($? >> 8) {
		perr("could not save $saved_naa_file to $main_naans: $save");
		exit 1;
	}

	use lib "/apps/n2t/local/lib";
	use NAAN;
	my $contact_info = 1;	# 1 means contact info is present
	my ($ok, $msg, $Rerrs) =
		NAAN::validate_naans($main_naans, $contact_info, $linenums);

	my $safe_validate = encode_entities( $msg );
	$safe_validate =~ s|\n|<br/>|g;

	if ($ok and $button eq 'Confirm') {
		if (! confirmed ($op, $orgname, $naan, $provider, $email,
					$firstname, $safe_naa_entry)) {
			perr "error in confirmation step";
			exit 1;
		}
		my $make_cmd;
		$make_cmd = $play_mode
			? "make confirm_naan"
			: "make confirm_naan diffs.txt all announce";
		$out = `(cd $reponame; env HOME=$home $make_cmd) 2>&1`;
		if ($? >> 8) {
			perr("error in: $make_cmd: $out");
			exit 1;
		}
		if ($play_mode) {
			my $msg = $remail eq $default_remail
				? " email sent but"
				: "";
			$out = "Test mode:$msg no changes made\n" . $out;
		}
		else {
			$out = "Success: check your email for a response " .
				"letter to modify and forward\n";
			#debug: "letter to modify and forward\n" . $out;
		}

		my $safe_out = encode_entities( $out );
		$safe_out =~ s|\n|<br/>|g;

		#debug "button=$button, remail=$remail, name=$rname";
		$safe_other_info and
			$safe_other_info = "NB: " . $safe_other_info;

		say << "EOT";
&nbsp; &nbsp; &nbsp; &nbsp; $safe_out
<br/>$safe_other_info
Final validation status: &nbsp; &nbsp; &nbsp; $safe_validate
</p>
</form>
EOT
		pr_foot();
		exit 0;
	}
	# elsif ! $ok and Confirm, then drop through to Test case
	# if we get here, we should display a Retest or Confirm button
# XXX or Test button for Update

	my $test_or_confirm;
	my $mesg = '';
	if ($op eq 'UPDATE') {		# XXX Test if it's first time...
		$test_or_confirm = $ok ? "Confirm" : "Test";
		out_errs $Rerrs;	# display errors, if any
		$mesg = confirm_mesg( ! $ok );
	}
	elsif (! $ok and scalar(@$Rerrs)) {
		$test_or_confirm = "Retest";
		out_errs $Rerrs;
		#say "<p>Errors:<ol>";
		#for my $e (@$Rerrs) {
		#	say "<li>", encode_entities( $e ), "</li>";
		#}
		#say "</ol></p>";
		#say "<p>Changes required.";
	}
	else {
		$test_or_confirm = "Confirm";
		$mesg = confirm_mesg();
		say "<p>";
		#if ($play_mode) {
		#	$mesg = " &nbsp; &nbsp; (not really, just a test " .
		#		"without making changes)";
		#}
		#else {
		#	$mesg = " &nbsp; &nbsp; (and send email " .
		#		"to $remail for forwarding to requester)";
		#}
	}

#<input type="hidden" id="request" name="origrequest" value="$orig_request">
	say << "EOT";
$safe_other_info
<input type="submit" name="button" value="$test_or_confirm">
$mesg
<br/>
<!-- button=$button, remail=$remail, name=$rname -->
<br/>
Validation status: &nbsp; &nbsp; &nbsp; $safe_validate
</p>
</form>
EOT
	pr_foot();
	exit 0;
}

__END__


########

#  Your Name:	Gautier Poupeau
#  Contact email address:	gpoupeau@ina.fr
#  Organization name:	Institut national de l'audiovisuel
#  Position in organization:	Data architect
#  Organization address:	4 avenue de l'Europe, 94366 Bry-sur-Marne Cedex
#  Organization base URL:	http://www.ina.fr
#  Organization status:	For profit

#+how:   NP | (:unkn) unknown | 2016 |
#+!why:  EZID ARK-only
#+!contact: Flynn, Allen ||| ajflynn@med.umich.edu | +1 734-615-0839
#+!address: 300 North Ingalls Street, 11th Floor, Suite 1161
