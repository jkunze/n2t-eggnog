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
Other information:	We're not in Kansas
Committed to data persistence?	Agree
EOT

#my $response_admin = "naan-registrar\@googlegroups.com, $provider";
my $request_file = 'request';
my $other_info_file = 'other_info';
my $new_naa_file = 'new_entry';
my $confirmer = 'worked_naan';
my $request_log = 'request_log';
my $reponame = 'naan_reg_priv';
my $default_naan = '98765';

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
    XXX heavily modified for the "-" stdin case, expecting
    XXX when invoked via web, there will never be a NAAN arg
    If any of the first 3 lines are empty, we're not doing this for real.
       line 1: email
       line 2: your name (given name then family name, eg, Sam Smith)
       line 3: NAAN
       lines 4-: form output

    The $cmd script converts a NAAN request form to a registry entry that
    is stored in the current directory under the filename, "$new_naa_file".

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

sub pr_head { my( $page_title )=@_;

	#my $html_head = << "EOT";
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
	say STDERR '<pre>';
	print STDERR ($from_vim ? "# Error: " : "Error: ");
	say STDERR @_;
	say STDERR '</pre>';
}

sub debug {
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

# Returns ($naa_entry, $orgname, $naan, $firstname, $email, $provider)

sub from_naa { my( $naa )=@_;

	if ($naa !~ m{ who:\s+(.*?)\s*\n
		 what:\s+(.*?)\s*\n
		 .*?\n
		 !contact:\s+[^,]*,\s+(\S+).*?\s*(\S+?@\S+)\s*\|.*?\n
		 .*?\n
		 (!provider:\s+(.+?)\n)?
			}xs) {
		perr("Malformed candidate NAAN entry: $_");
		return ('');
	}
		 #(!provider:\s+.*?(\S+?@\S+?)\n)?
		 #(!provider:\s+(.+?)\n)?

	my ($orgname, $naan, $firstname, $email, $provider) = 
		($1, $2, $3, $4, $5);
	$orgname =~ s/\s*\(=\).*//;
	return ($naa, $orgname, $naan, $firstname, $email, $provider);
}


sub from_request { my( $naan, $input )=@_;

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



	# Get parts of today's date.
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	$year += 1900;
	$mon = sprintf("%02d", $mon + 1);
	$mday = sprintf("%02d", $mday);

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
		perr("Looks like an incomplete request. Please go back "
			. "and check for a copy/paste error.\n$copy_err");
		return '';
	}

	# Get part of personal name (just a guess, so bears checking)
	($firstname, $lastname) = $fullname =~ /^\s*(.+)\s+(\S+)\s*$/ or
		perr("could not parse personal name \"$fullname\""),
		return '';
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
		say STDERR "Could not initialize directory for $naan";
		return '';
	}

	if ($other =~ /./) {	# if has real content, save to file for later
		#say STDERR "Note other info: |$other|";
		open OUT, ">", "$other_info_file" or
			perr("could not open $other_info_file for writing"),
			return '';
		say OUT "$other";
		close OUT;
	}
	else {	# else remove, since it might exist from prior testing run
		-e $other_info_file and
			unlink $other_info_file;	# yyy ignore return
	}
	# This is Submit case, so build up request to save in a file.
	my $request = '';
	$request .= "Date:\t$year.$mon.$mday\n";	# date processed
	$from_vim and			# if from vim, clothe naked NAAN with
		$request .= "Candidate NAAN:\t";	# label prepended
	$request .= $input;		# original request
	open OUT, ">", "$request_file" or
		perr("could not open $request_file for writing"),
		return '';
	say OUT "$request";
	close OUT;

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
	return ($naa_entry, $orgname, $firstname, $email, $provider);
}

# returns 1 on success, 0 on error

sub confirmed { my( $orgname, $naan, $provider, $email, $firstname, $safe_naa_entry )=@_;

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
	my $response_letter = << "EOT";
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
--------- CUT HERE ---------
</p>
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
In thinking about how to manage the namespace, you may find it helpful to consider the usual practice of partitioning it with reserved prefixes of, say 1-5 characters, eg, names of the form "ark:/$naan/xt3...." for each "sub-publisher" in an organization.
Opaque prefixes that only have meaning to information professionals are often a good idea and have precedent in schemes such as ISBN and ISSN.
</p><p>
The best starting place for information on ARKs (Archival Resource Keys) is the
<a href="https://arks.org">ARK Alliance</a> website. You may also find useful
information in the
<a href="https://wiki.lyrasis.org/display/ARKs/ARK+Identifiers+FAQ">ARKs FAQ</a>
(<a href="https://wiki.lyrasis.org/pages/viewpage.action?pageId=178880619">version française</a>,
<a href="https://wiki.lyrasis.org/pages/viewpage.action?pageId=185991610">version en español</a>)
and <a href="http://n2t.net/e/ark_ids.html">this ARK identifier overview</a>.
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
</p>
</body>
</html>
EOT

	#open OUT,
	#  "|mail -S ttycharset=UTF-8 -s 'NAAN request for $acronym' \
	#            jakkbl\@gmail.com"
	#  	or die("couldn't open pipe to email response");

	# save letter to a file
	open OUT, ">", "new_naa_response.html" or
		perr("could not open new_naa_response.html file"),
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

sub oinfo { my( $other_info_file )=@_;

	! -e $other_info_file and
		return '';
	my $other_info = `cat $other_info_file 2>&1`;
	if ($? >> 8) {
		perr("error opening $other_info_file: " .
			"$other_info");
		exit 1;
	}
	$other_info = "Other information from the requester: "
		. "$other_info\n";
	my $safe_other_info = encode_entities( $other_info );
	$safe_other_info =~ s|\n|<br/>|g;
	return $safe_other_info;
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

	#print $html_head;

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
	s/^\s*#.*\n//mg;	# drop comment lines

	# Split the input block into params added by CGI script
	# and params copied in from request form data.

	if (! s/^button: (.*)\nremail: (.*)\nrname: (.*)\nunaan: (.*)\nrequest: //) {
		pr_head("Missing form data");
		perr("missing form data (block $_");
		exit 2;
	}
	($button, $remail, $rname, $naan) = ($1, $2, $3, $4);
	#debug "from CGI rname=$rname, remail=$remail, naan=$naan";

	my ($naa_entry, $orgname, $firstname, $email, $provider);

	pr_head( $button eq 'Confirm' ? 'Final' : 'Review candidate' );

	if ($button eq 'Submit') {
		$naan ||= $default_naan;
		$orig_request = /^\s*$/		# if empty request
			? $request_default	# use default
			: $_			# else use supplied data
		;
		my $raw_orig_request = decode_entities( $orig_request );

		($naa_entry, $orgname, $firstname, $email, $provider) =
			from_request($naan, $raw_orig_request);

		$_ = $raw_orig_request;
	}
	elsif ($button eq 'Retest' or $button eq 'Confirm') {

		($naa_entry, $orgname, $naan, $firstname, $email, $provider) =
			from_naa( $_ );
		if (! $naa_entry) {
			perr("Malformed/bad candidate NAAN entry: $_");
			exit 1;
		}
		if (! init_dir($naan)) {
			say STDERR "Could not initialize directory for $naan";
			exit 1;
		}
	}
	if (! $naa_entry) {	# $naa_entry must be defined
		exit 1;
	}
	$naa_entry =~ s/\r//g;		# delete carriage returns (from web)

	if ($naan eq $default_naan) {	# then we're just in test/play mode
		$play_mode = 1;
		$remail = $default_remail;
		$rname = $default_rname;
	}
	else {
		my $grep = `grep "$naan" $cand_naans 2>&1`;
		my $gstat = $? >> 8;
		if ($gstat > 1) {
			perr("could not do: grep $naan $cand_naans: $grep");
			exit 1;
		}
		elsif ($gstat == 1 or $grep !~ /^$naan\s+(\S+)\s+(.*)\n$/) {
			perr( << "EOT" );
the <em>candidate_naans</em> file on github contained no line of the form

   <em>$naan YourEmail FirstName LastName</em>

Cannot proceed without such a line. (Did you remember to COMMIT?)
EOT
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

	### save $naa_entry
	open OUT, ">", "$new_naa_file" or
		perr("could not open $new_naa_file for writing"),
		exit 1;
	print OUT "$naa_entry";
	print OUT "\n";		# important separator for next entry to come
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

	my $validate = `cat $new_naa_file >> $main_naans 2>&1`;
	if ($? >> 8) {
		perr("could not append $new_naa_file to $main_naans: $validate");
		exit 1;
	}

	use lib "/apps/n2t/local/lib";
	use NAAN;
	my $contact_info = 1;	# 1 means contact info is present
	my $linenums = 0;
	my ($ok, $msg, $Rerrs) =
		NAAN::validate_naans($main_naans, $contact_info, $linenums);

	my $safe_validate = encode_entities( $msg );
	$safe_validate =~ s|\n|<br/>|g;

	my $safe_other_info = oinfo $other_info_file;

	if ($button eq 'Confirm') {
		if (! $ok) {
			perr "validation error: did you change something " .
				"since your last test?";
			exit 1;
		}
		if (! confirmed ($orgname, $naan, $provider, $email,
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
Status: &nbsp; &nbsp; &nbsp; $safe_validate
</p>
</form>
EOT

		exit 0;
	}
	# if we get here, we should display a Retest or Confirm button

	my $test_or_confirm;
	my $mesg = '';
	if (! $ok and scalar(@$Rerrs)) {
		$test_or_confirm = "Retest";
		say "<p>Errors:<ol>";
		for my $e (@$Rerrs) {
			say "<li>", encode_entities( $e ), "</li>";
		}
		say "</ol></p>";
		say "<p>Changes required.";
	}
	else {
		$test_or_confirm = "Confirm";
		if ($play_mode) {
			$mesg = " &nbsp; &nbsp; (not really, just a test " .
				"without making changes)";
		}
		else {
			$mesg = " &nbsp; &nbsp; (and send email " .
				"to $remail for forwarding to requester)";
		}
		say "<p>";
	}

#<input type="hidden" id="request" name="origrequest" value="$orig_request">
	say << "EOT";
$safe_other_info
<input type="submit" name="button" value="$test_or_confirm">
$mesg
<br/>
<!-- button=$button, remail=$remail, name=$rname -->
<br/>
Status: &nbsp; &nbsp; &nbsp; $safe_validate
</p>
</form>
EOT

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
