#!/bin/sh

PERL5LIB=/apps/n2t/sv/cv2/lib/perl5
PATH=/apps/n2t/sv/cv2/bin:/bin:/usr/bin:/sbin:/usr/sbin
export PERL5LIB PATH
#LC_ALL=C
#LANG=en_US.UTF-8
#export PERL5LIB PATH LC_ALL LANG

# Output necessary HTTP headers. Real output comes after that.
#echo "Content-type: text/plain; charset=UTF-8"
#echo ""

/usr/bin/env perl <<- 'EOS' 2>&1
use CGI;
my $cgi = CGI->new;
my %param = map { $_ => scalar $cgi->param($_) } $cgi->param() ;
print $cgi->header( -type => 'text/html; charset=UTF-8' );

open(PIPE, "| ./form2naa.pl --github -") or
	die("couldn't open pipe to form2naa.pl: $!");
# XXX only unaan is relevant
print PIPE
	"button: ",	$cgi->param('button'),	"\n", # Submit, Retest, Confirm
	"remail: ",	$cgi->param('remail'),	"\n", # responder email
	"rname: ",	$cgi->param('rname'),	"\n", # responder email
	"unaan: ",	$cgi->param('unaan'),	"\n", # unused NAAN
	"request: ",	$cgi->param('request'),	"\n", # request form data
;
EOS

# XXX run validate_naans twice:
#    once on received file, 
#    again on file modified with new NAA appended

#for my $k ( sort keys %param ) {
#    print join ": ", $k, $param{$k};
#    print "\n";
#}

exit;

# ================ below is dead code for mining
#
# This script runs in its own current directory.
# https://n2t-dev.n2t.net/e/admin/q2e.pl?unusednaan=12345&request=name%3A+value%0D%0Akey%3A+value

./form2naa.pl - << 'EOI' 2>&1
90909
Contact name:     Gautier Poupeau
Contact email address:    gpoupeau@ina.fr
Organization name:        Institut national de l'audiovisuel
Position in organization: Data architect
Organization address:     4 avenue de l'Europe, 94366 Bry-sur-Marne Cedex
Organization base URL:    http://www.ina.fr
Organization status:      For profit
Service provider: Sam Smith, ss@aaa.example.org, Acme Archiving
EOI

# #!/usr/bin/env perl
# ##
# ##  printenv -- demo CGI program which just prints its environment
# ##
# 
# print "Content-type: text/plain; charset=UTF-8\n\n";
# print "xxx Stub q2e.\n";
# my ($var, $val);
# foreach $var (sort(keys(%ENV))) {
#     $val = $ENV{$var};
#     $val =~ s|\n|\n|g;
#     $val =~ s|"|\"|g;
#     print "${var}=\"${val}\"\n";
# }
# EOS
# 
