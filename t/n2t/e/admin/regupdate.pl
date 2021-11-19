#!/usr/bin/perl

# This script exists to be easily callable behind a web server and to set up
# environment variables for a call to the Perl script that does the main work.

system("
	PERL5LIB=/apps/n2t/sv/cv2/lib/perl5 \
	PATH=/apps/n2t/sv/cv2/bin:/bin:/usr/bin:/sbin:/usr/sbin \
		/usr/bin/env perl ./regup.pl --github - 2>&1"); # or
#	die("couldn't run 'system ./regup.pl ...': $!");

#LC_ALL=C
#LANG=en_US.UTF-8
#export PERL5LIB PATH LC_ALL LANG

# Output necessary HTTP headers. Real output comes after that.
#echo "Content-type: text/plain; charset=UTF-8"
#echo ""

#/usr/bin/env perl ./regup.pl --github - 2>&1

#/usr/bin/env perl <<- 'EOS' 2>&1
#use CGI;
#my $cgi = CGI->new;
#my %param = map { $_ => scalar $cgi->param($_) } $cgi->param() ;
#print $cgi->header( -type => 'text/html; charset=UTF-8' );
#
#open(PIPE, "| ./regup.pl --github -") or
#	die("couldn't open pipe to regup.pl: $!");
## XXX only unaan is relevant
#print PIPE
#	"button: ",	$cgi->param('button'),	"\n", # NEW, UPDATE, Retest, Confirm
#	"remail: ",	$cgi->param('remail'),	"\n", # responder email
#	"rname: ",	$cgi->param('rname'),	"\n", # responder email
#	"unaan: ",	$cgi->param('unaan'),	"\n", # used or unused NAAN
#	"request: ",	$cgi->param('request'),	"\n", # request form data
#;
#EOS
