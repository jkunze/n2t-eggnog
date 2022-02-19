#!/usr/bin/env perl

# Unlike most other test sets in this directory, these test run against
# the installed server. During focussed debugging on these tests, therefore,
# the developer will likely want to run "n2t --force rollout" before each
# run of "perl -Mblib t/egn_post_install_n2t.t".

# NB: this part of the eggnog source DEPENDS on wegn,
#     defined in another source code repo (n2t_create)

# xxx must test the ezid and oca and yamz production binders!!!
#      this only tests the non-prod stuff
# xxx add princeton test/NAAN check to redirect rules?
# xxx add test that inflection->cgi rewrite is working

use 5.10.1;
use Test::More;

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';
use EggNog::Temper 'etemper';

my $home = $ENV{HOME};
my $eghome = "$home/sv/cur/apache2";

my $which = `which wegn`;

# This exits without error since it's routinely skipped during 'make test'
grep(/\/blib\/lib/, @INC) and plan skip_all =>
    "why: should be run with installed code (eg, \"n2t test\" not with -Mblib)";

# XXX use exit 1 to get build to fail properly instead of silently
$which =~ /wegn/ or plan skip_all => "why: web client \"wegn\" not found";

# XXX use exit 1 to get build to fail properly instead of silently
# XXX should this bail with error status instead of skipping?
! -e "$home/warts/.pswdfile.n2t" and plan skip_all =>
    "why: no $home/.pswdfile.n2t file";

# XXX use exit 1 to get build to fail properly instead of silently
# XXX should this bail with error status instead of skipping?
! -e "$eghome/eggnog_conf" and plan skip_all =>
    "why: no $eghome/eggnog_conf file; have you run \"n2t rollout\"?";

my $c = `egg --home $eghome cfq class | grep .`;
chop $c;
foreach my $b ('ezid', 'oca', 'yamz') {
	my $f = "$eghome/binders/egg_n2t_${c}_public.real_${b}_s_${b}/egg.bdb";
# XXX use exit 1 to get build to fail properly instead of silently
	! -e $f and plan skip_all =>
		"why: critical '$b' binder missing ($f)"
# XXX should this bail with error status instead of skipping?
}

plan 'no_plan';		# how we usually roll -- freedom to test whatever

SKIP: {

my ($x, $y, $n);

my $ark1 = 'ark:/99999/fk8n2test1';
my $tgt1 = 'https://cdlib.org/';
my $tgt2 = 'https://cdlib.org/' . EggNog::Temper::etemper();
my $eoi = 'doi:10.5072/EOITEST';	# MUST register in normalized uppercase
my $eoi_tgt = 'https://crossref.org/';
my $eoi_ref = 'eoi:10.5072/EOITEST';	# normalized reference
my $eoi_ref_lc = 'eoi:10.5072/eoitest';	# unnormalized reference

my $snacchost = 'socialarchive.iath.virginia.edu';

# xxx add to t/apachebase.t
#         random timeofday value test for target to avoid effects
#         of having old values make tests pass that should fail

my $srvbase_u = 'http://localhost:18880';

# First test a simple mint.  Make sure to error out if server isn't even up.
$x = `wegn mint 1`;
$x =~ /failed.*refused/ and
	print("\n    ERROR: server isn't reachable! Is it started?\n\n"),
	exit 1;
like $x, qr@99999/fk4\w\w\w@, "minted id matches format";

$x = `wegn i.purge`;
$x =~ /error/i and
	print("\n    ERROR: main binder won't take simple purge -- panic!\n\n"),
	exit 1;
like $x, qr/egg-status:\s*0/, "main binder accepts simple purge";

#say "xxx x=$x, premature exit";
#exit;

ok -f "$home/warts/.pswdfile.n2t",
	"real passwords set up in ~/warts/ to occlude dummy passwords";

my $production_data = `egg -q --home $eghome cfq production_data && echo yes`;

if ($production_data eq "yes\n") {

	# Some kludgy tests based on what is hopefully permanent data.
	# NB: these test read the redirect Location but don't follow it.

	print "--- BEGIN production-data tests (potentially volatile)\n";

	$x = `wegn -v locate "ark:/87924/r4639m84b?embed=true"`;
	like $x, qr{^Location: https://repository.duke.edu/id/ark:/87924/r4639m84b\?embed=true}m,
		"Duke target redirect with SPT";

	# Location: http://merritt.cdlib.org/m/ark%3A%2F28722%2Fk2057s78h
# xxx Merritt records this as (because of double-encoding bug):
#               _t: http://merritt.cdlib.org/m/ark%253A%252F28722%252Fk2057s78h
# xxx why? possibly because of some undocumented behavior with RewriteMap??
# xxx see if this disappears with apache 2.4
	$x = `wegn -v locate "ark:/28722/k2057s78h"`;
	like $x, qr{^Location: http://merritt.cdlib.org/.*}m,
		"Merritt target redirect";

	# Location: http://bibnum.univ-lyon1.fr/nuxeo/nxfile/default/67ff978c-fd9b-4cef-8e44-5ce929ce1445/blobholder:0/THph_2015_CAYOT_Catherine.pdf
	$x = `wegn locate "ark:/47881/m6zw1j9d"`;
	like $x, qr{^Location: http://bibnum.*}m,
		"U Lyon target redirect";

	$x = `wegn locate "ark:/99152/h1023"`;
	like $x, qr{^Location: http://yamz.net/term/concept=h1023.*}m,
		"YAMZ target redirect";

	# xxx currently this perio.do works by SPT on a short id (.../p0)
	#     should it not work with a shoulder redirect rule?

	my $a0 = "ark:/99152/p0vn2frcz8h";
	# one identifier (p0) in the 99152 namespace.
	$x = `wegn locate "$a0"`;
	#$x = `wegn locate "ark:/99152/p0vn2frcz8h"`;
	like $x, qr{^Location: https://data.perio.do.*}m,
		"Perio.do target redirect";

	# YYY early use of curl, not wget! (wget/wegn won't return all headers?)
	$x = `curl --max-redirs 0 --silent -I "$srvbase_u/$a0" | grep -i 'Access-Control-' | sort`;
	like $x, qr{Allow-Methods:.*Allow-Origin:.*Expose-Headers:}si,
		'CORS supported headers present on redirect';

	print "--- END production-data tests (potentially volatile)\n";
}
else {
	say "--- SKIPPED tests requiring production data";
}

# Test two of long-time partner OCA/IA's ARKs to make sure that the new
# 2022 arrangement is working. It doesn't use the live IA service but
# does use some ARKs IA is known to have been minted at one time.
#
# IA is ok to test these two ARKs against their live service; in particular,
# curl -vL http://$EGNAPA_HOST/ark:/13960/t00000m0v
#  --> Location: https://www.archive.org/details/testsandreagents031780mbp
# curl -vL https://$EGNAPA_HOST/ark:13960/s2qwhrnc184
#  --> Location: https://archive.org/details/utesforgottenpeo0000rock
# Here's a third one to try:
# curl -vL https://$EGNAPA_HOST/ark:/13960/s2m3w6wn30f
#  --> https://archive.org/details/potts-euclid

$x = `wegn -v locate "ark:/13960/t00000m0v"`;
like $x, qr|^Location: https://ark.archive.org/ark:/13960/t00000m0v|m,
	"OCA target https redirect, old-style ARK, original t shoulder";

# XXX at some point N2T should forward new arks (no first slash) without adding
# the slash, ie, preserving the incoming style
# XXX ... or should that be an NMA option?
$x = `wegn -v locate "ark:13960/s2m3w6wn30f"`;
like $x, qr|^Location: https://ark.archive.org/ark:/13960/s2m3w6wn30f|m,
	"OCA target https redirect, new-style ARK, new s2 shoulder";

#$x = `crontab -l`;
#like $x, qr/replicate/, 'crontab replicates periodically';
#
#like $x, qr/restart/, 'crontab restarts server periodically';

# yyy retire soon
$x = `$home/sv/cur/build/eggnog/replay`;
like $x, qr/usage/i, 'replay (replicate) script is executable';

# xxx pretty minimal test
$x = `$home/local/bin/n2t`;
like $x, qr/usage/i, 'n2t script is executable';

# xxx pretty minimal test
$x = `$home/n2t_create/admegn`;
like $x, qr/usage/i, 'admegn script is executable';

## xxx wegn is bad at setting multiple word values!
#$x = `wegn $ark1.set x "this is apostrophes test"`;
#like $x, qr/^egg-status: 0/m,
#	"egg sets value containing apostrophe";
#
#$x = `wegn $ark1.fetch`;
#like $x, qr/^xxx/m,
#	"egg fetches apostrophe in value";

$x = `wegn -v $ark1.set _t $tgt1`;
like $x, qr/^egg-status: 0/m,
	"egg sets target URL for id $ark1";

$x = `wegn locate "$ark1"`;
like $x, qr/^Location: \Q$tgt1/m, "bound target value resolved";

$x = `wegn $ark1.set _t $tgt2`;
like $x, qr/^egg-status: 0/m, "egg sets new target URL $tgt2";

$x = `wegn $ark1.fetch`;
like $x, qr/^_t: \Q$tgt2/m, "new bound target value fetched";

$x = `wegn locate "$ark1"`;
like $x, qr/^Location: \Q$tgt2/m, "new bound target value resolved";

#print "XXX first x=$x\n";	######################
#exit;

# we test 3 times in a row to make sure that one resolver process is
# sensitive to changes (unlike when we used to use DB_File)
$tgt2 .= 'a';		# another new value
$x = `wegn $ark1.set _t $tgt2`;
like $x, qr/^egg-status: 0/m, "egg sets second new target $tgt2";

$x = `wegn $ark1.fetch`;
like $x, qr/^_t: \Q$tgt2/m, "second new bound target value fetched";

$x = `wegn locate "$ark1"`;
like $x, qr/^Location: \Q$tgt2/m, "second new bound target value resolved";

$tgt2 .= 'b';		# another new value
$x = `wegn $ark1.set _t $tgt2`;
like $x, qr/^egg-status: 0/m, "egg sets third new target $tgt2";

$x = `wegn $ark1.fetch`;
like $x, qr/^_t: \Q$tgt2/m, "third new bound target value fetched";

$x = `wegn locate "$ark1"`;
like $x, qr/^Location: \Q$tgt2/m, "third new bound target value resolved";

#print "OK to ignore that test until BDB interface code deployed\n";

# These next tests ensure that the public documentation examples in 
# https://wiki.ucop.edu/display/DataCite/Suffix+Passthrough+Explained
# work for suffix passthrough.
#
# NB: these tests ACTUALLY CHANGE a live production database, but
# in harmless ways, actually ensuring the documentation is correct.
#
# NB: XXX these tests may not work on a new system until a server
#     reboot, due to resolver bug (remove this note when fixed)
# 2019.10.02: changed www.cdlib.org to just cdlib.org (www. deprecated)
# xxx still need to remove www. from SPT documentation!

my $cdl_ark = 'ark:/12345/fk1234';		# ACTUAL real ARK!
my $cdl_tgt = 'https://cdlib.org/services';
my $cdl_ext = '/uc3/ezid/';

$x = `wegn $cdl_ark.set _t $cdl_tgt`;
like $x, qr/^egg-status: 0/m, "egg sets target for $cdl_ark";

$x = `wegn $cdl_ark.set erc.who CDL`;
$x = `wegn $cdl_ark.set erc.when 2014`;
like $x, qr/^egg-status: 0/m, "egg sets date for $cdl_ark";

$x = `wegn locate "ark:/12345-dev/fk1234"`;
like $x, qr|^Location: \Qhttps://cdlib-dev.org/services|m,
	"prefix extension for stored ARK";

$x = `wegn locate "$cdl_ark$cdl_ext"`;
like $x, qr/^Location: \Q$cdl_tgt$cdl_ext/m,
	"documented suffix passthrough 'locate' for cdl_ark $cdl_ark";

# this is a real test
$x = `wegn resolve "$cdl_ark"`;
like $x, qr/title.*Services.*California/m,
	"documented 'resolve' target for cdl_ark $cdl_ark";

# this is a real test
$x = `wegn resolve "$cdl_ark$cdl_ext"`;
like $x, qr/title.*EZID.*California/m,
	"documented suffix passthrough 'resolve' for cdl_ark $cdl_ark";

$x = `wegn resolve "$cdl_ark??"`;
like $x, qr|erc:.*who: CDL.*when: 2014.*persistence:|s,
	"?? inflection produces kernel plus persistence elements";

#my $yamz_ark = 'ark:/99152/dummy';		# don't clobber real term!
#my $yamz_tgt = 'https://yamz.net/term=dummy';
#my $ubdr = '@yamz@@yamz';	# user and binder for HUMB argument
#
#$x = `wegn $ubdr $yamz_ark.set _t $yamz_tgt`;
#like $x, qr/^egg-status: 0/m, "egg sets target for $yamz_ark";
#
#$x = `wegn $ubdr $yamz_ark.set erc.who id`;
#$x = `wegn $ubdr $yamz_ark.set erc.when 2018`;
#$x = `wegn $ubdr $yamz_ark.set erc.what association_between_string_and_thing`;
#like $x, qr/^egg-status: 0/m, "egg sets definition for $yamz_ark";
#
#$x = `wegn resolve "$yamz_ark?"`;
#like $x, qr|erc:.*who: id.*what: assoc.*when: 2018|s,
#	"? inflection produces kernel elements for non-ezid ark";

#$x = `wegn locate "$srch_ark$srch_ext"`;
#wegn resolve 'ark:/12345/fk1234??'
#  minter|binder=99999/fk4|ezid  user=ezid  host=localhost:18443
#  erc:
#  who: CDL
#  what: CDL Services Landing Page
#  when: 2014
#  where: ark:/12345/fk1234 (currently http://cdlib.org/services)
#  how: (:unav)
#  id created: 2017.05.21_21:25:03
#  id updated: 2014.05.29_17:48:06
#  persistence: (:unav)

my $wkp_ark = 'ark:/12345/fk1235';
my $wkp_tgt = 'https://en.wikipedia.org/wiki';
my $wkp_ext = '/Persistent_identifier';

$x = `wegn $wkp_ark.set _t $wkp_tgt`;
like $x, qr/^egg-status: 0/m, "egg sets target for $wkp_ark";
$x = `wegn locate "$wkp_ark$wkp_ext"`;
like $x, qr/^Location: \Q$wkp_tgt$wkp_ext/m,
	"documented suffix passthrough works for wkp_ark $wkp_ark";

my $srch_ark = 'ark:/12345/fk3';
#my $srch_tgt = 'https://www.google.com/#q=';
my $srch_tgt = 'https://www.google.com/search?q=';
my $enc_srch_tgt = 'https://www.google.com/search?q=';	# encoded form
my $srch_ext = 'pqrst';

$x = `wegn $srch_ark.set _t "$enc_srch_tgt"`;
like $x, qr/^egg-status: 0/m, "egg sets target for $srch_ark";
$x = `wegn $srch_ark.fetch`;
# test not strictly needed, but this one's tricky with encoding
like $x, qr/^_t: \Q$srch_tgt/m, "bound target $srch_tgt fetched";
$x = `wegn locate "$srch_ark$srch_ext"`;
like $x, qr/^Location: \Q$srch_tgt$srch_ext/m,
	"documented suffix passthrough works for srch_ark $srch_ark";

## yyy temporary and redundant with first test ???
## There's no way to usefully test production minting right now.  Every
## minter currently in production use connects directly via hardcoded URL:
##
#$x = `wegn mint 1`;
#like $x, qr@99999/fk4\w\w\w@, "minted id matches format";

# comment out to reduce noise temporarily
my $prd = 'n2t.net';
#$x = `wegn -s $prd@@ ark:/99999/fk8n2test1.set foo bar`;
#like $x, qr@egg-status: 0@, "signed cert check on production permits binding";

# comment out to reduce noise temporarily
#my $stg = 'ids-n2t-stg.cdlib.org';
#$x = `wegn -s $stg@@ ark:/99999/fk8n2test1.set foo bar`;
#like $x, qr@egg-status: 0@, "signed cert check on stage permits binding";

use EggNog::Binder ':all';
my $rrminfo = RRMINFOARK;

#my $hgid = `hg identify | sed 's/ .*//'`;
my $gitid = `git show --oneline | sed 's/ .*//;q'`;
chop $gitid;
#$x = `$wgcl "$srvbase_u/$rrminfo"`;
$x = `wegn locate "$rrminfo"`;
$x =~ qr{Location:.*dvcsid=\Q$gitid\E&rmap=}i or say STDERR
	"**** WARNING: SOURCE DVCSID DOESN'T MATCH INSTALLED DVCSID ****";

#like $x, qr{Location:.*dvcsid=\Q$hgid\E&rmap=}i,
#	'resolver info with correct dvcsid returned';

# see Resolver.pm for these, ($scheme_test, $scheme_target), something like
#      'xyzzytestertesty' => 'http://example.org/foo?gene=$id.zaf'
#
use EggNog::Resolver ':all';
my ($i, $q, $target);

#($i, $q) = ('987654', '-z-?');
#$target = $EggNog::Resolver::scheme_target;
#$target =~ s/\$id\b/$i/g;
#
# yyy this was meant to be an artificial test that didn't rely on actual
#     real prefix data, which is volatile and sort of unsuitable for
#     controlled testing
##$x = `wegn -v locate "$EggNog::Resolver::scheme_test:$i?$q"`;
#$x = `wegn -v locate "$EggNog::Resolver::scheme_test:$i"`;
##like $x, qr/response.*302 .*\nLocation: \Q$target?$q/,
#like $x, qr/response.*302 .*\nLocation: \Q$target/,
#	"test rule -- rule-based target redirect";

# Pseudo-location: http://escholarship.org/uc/item/123456789
# yyy still no $blade support for escholarship because we don't
#    recognize non-standard shoulders (no first digit convention)
$x = `wegn -v locate "ark:/13030/qt123456789"`;
like $x, qr{^Location: http://escholarship.org/uc/item/123456789}m,
	"Escholarship target redirect via post-egg Apache kludge";

$x = `wegn -v locate "ark:/13030/tf3000038j"`;
like $x, qr{^Location: http://ark.cdlib.org/ark:/13030/tf3000038j}m,
	"Legacy OAC redirect via post-egg Apache kludge";

($i, $q) = ('ab_262044', '-z-?');
$target = 'https://scicrunch.org/resolver/RRID:$id';
$i = uc $i;
$target =~ s/\$id\b/$i/g;

#print qq@wegn -v locate "RriD:$i?$q"\n@;
# xxx this test should be made to work
#$x = `wegn -v locate "RriD:$i?$q"`;
$x = `wegn -v locate "RriD:$i"`;
#like $x, qr/response.*302 .*\nLocation: \Q$target?$q/,
like $x, qr/response.*302 .*\nLocation: \Q$target/,
	"RRID rule -- rule-based target redirect";

# # pmid (alias for pubmed)
# ncbi    https://www.ncbi.nlm.nih.gov/pubmed/$id
# epmc    http://europepmc.org/abstract/MED/$id

($i, $q) = ('16333295', '-z-?');
$target = 'https://www.ncbi.nlm.nih.gov/pubmed/$id';
$i = uc $i;
$target =~ s/\$id\b/$i/g;

$x = `wegn -v locate "pmid:$i?$q"`;
#like $x, qr/response.*302 .*\nLocation: \Q$target/,
like $x, qr/response.*302 .*\nLocation: \Q$target?$q/,
	"PMID rule -- rule-based target redirect";

$x = `wegn -v locate "swh:2:rev:foo"`;
$target = 'https://archive.softwareheritage.org/browse/swh:2:rev:foo';
like $x, qr|response.*302 .*\nLocation: \Q$target\E |,
	"prefixed scheme with potentially confusing colons";

($i, $q) = ('9606', '-z-?');
$target = 'https://www.rcsb.org/pdb/explore/explore.do?structureId=$id';
#$target = 'http://www.pdbe.org/$id';
$i = uc $i;
$target =~ s/\$id\b/$i/g;

#$x = `wegn -v locate "pdb:$i?$q"`;
# xxx bug in query string re-attachment after prefix lookup
#     but why does pmid (above) work?
$x = `wegn -v locate "pdb:$i"`;
#like $x, qr/response.*302 .*\nLocation: \Q$target?$q/,
like $x, qr/response.*302 .*\nLocation: \Q$target/,
	"PDB rule -- rule-based target redirect";
#print "xxx disabled test: PDB rule -- rule-based target redirect\n";

$x = `wegn -v locate "igsn:SSH000SUA"`;
$target = 'http://hdl.handle.net/10273/SSH000SUA';
like $x, qr/response.*302 .*\nLocation: \Q$target/,
	"IGSN rule -- rule-based target redirect";

($i, $q) = ('9606', '-z-?');
$target = 'https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=$id';
$i = uc $i;
$target =~ s/\$id\b/$i/g;

#$x = `wegn -v locate "taxonomy:$i?$q"`;
$x = `wegn -v locate "taxonomy:$i"`;
# xxx bug in query string re-attachment after prefix lookup
#     but why does pmid (above) work?
#like $x, qr/response.*302 .*\nLocation: \Q$target?$q/,
like $x, qr/response.*302 .*\nLocation: \Q$target/,
	"TAXONOMY rule -- rule-based target redirect";
#print "xxx disabled test: TAXONOMY rule -- rule-based target redirect\n";

($i, $q) = ('6622', '-z-?');
$target = 'https://www.ncbi.nlm.nih.gov/gene/$id';
$i = uc $i;
$target =~ s/\$id\b/$i/g;

($i, $q) = ('0006915', '-z-?');
$target = 'http://amigo.geneontology.org/amigo/term/GO:$id';
$i = uc $i;
$target =~ s/\$id\b/$i/g;

$x = `wegn -v locate "amigo/go:$i"`;
#like $x, qr/response.*302 .*\nLocation: \Q$target?$q/,
like $x, qr/response.*302 .*\nLocation: \Q$target/,
	"prefix (amigo/go) with provider code -- rule-based target redirect";

$i = '16333295';
$target = 'https://www.ncbi.nlm.nih.gov/pubmed/16333295';
$x = `wegn -v locate "ncbi/pmid:$i"`;
like $x, qr/response.*302 .*\nLocation: \Q$target/,
    "prefix (ncbi/pmid) with provider code and alias -- rule-based redirect";

#intenz  https://www.ebi.ac.uk/intenz/query?cmd=SearchEC&amp;ec=$id
#expasy  http://enzyme.expasy.org/EC/$id
($i, $q) = ('1.1.1.1', '-z-?');
$target = 'https://www.ebi.ac.uk/intenz/query?cmd=SearchEC&ec=$id';
$i = uc $i;
$target =~ s/\$id\b/$i/g;

$x = `wegn -v locate "ec:$i"`;
#like $x, qr/response.*302 .*\nLocation: \Q$target?$q/,
like $x, qr/response.*302 .*\nLocation: \Q$target/,
	"EC -- rule-based target redirect";
#print "xxx disabled test: EC -- rule-based target redirect\n";

$x = `wegn -v locate "ark:/99166/w6foo"`;
like $x, qr/response.*303 .*\nLocation: http:..\Q$snacchost/,
	"SNACC target redirect with 303 status";

$x = `wegn locate "e/naan_request"`;
like $x, qr|Location: .*goo.gl/forms|,
	"NAAN request form is available";

#$x = `wegn resolve "robots.txt"`;
$x = `curl --silent "$srvbase_u/robots.txt"`;
like $x, qr|disallow:|i,
	"robots.txt is available and non-empty";

$x = `wegn resolve "e/cdl_ebi_prefixes.yaml"`;
like $x, qr|- namespace: pubmed|, "prefix registry file is available";

#RewriteRule ^/e/prefix_request(\.|\.html?)?\$ https://docs.google.com/forms/d/18MBLnItDYFOglVNbhNkISqHwB-pE1gN1YAqaARY9hDg [L]
$x = `wegn -v locate "e/prefix_request"`;
like $x, qr|response.*302 .*\nLocation: .*docs.google.com/forms/d/18MBLnItDYF|,
	"special redirect to prefix request form";

#RewriteRule ^/e/prefix_overview(\.|\.html?)?\$ https://docs.google.com/document/d/1qwvcEfzZ6GpaB6Fql6SQ30Mt9SVKN_MytaWoKdmqCBI [L]
$x = `wegn -v locate "e/prefix_overview"`;
like $x, qr|response.*302 .*\nLocation: .*docs.google.com/document|,
	"special redirect to prefix overview document";

$x = `wegn loc\@xref\@\@xref $eoi.set _t $eoi_tgt`;
like $x, qr/^egg-status: 0/m,
	"egg sets target URL in CrossRef binder for EOI/DOI $eoi";

$x = `wegn loc\@xref\@\@xref $eoi.fetch _t`;
like $x, qr/^_t: \Q$eoi_tgt/m, "new bound EOI target value fetched";

$x = `wegn locate "$eoi_ref"`;
like $x, qr/^Location: \Q$eoi_tgt/m, "bound EOI target value resolved";

## XXX remove this test when xref corrects this: single _ instead of double __
#$x = `wegn loc\@xref\@xref $eoi.set _mTm. $eoi_tgt/xxxmdata`;
#$x = `wegn loc\@xref\@xref $eoi.fetch _mTm.`;
#like $x, qr|^_mTm.: \Q$eoi_tgt/xxxmdata|m,
#	"xxx bound EOI default content negotiation (CN) target value fetched";

## XXX remove this test when xref corrects this: single _ instead of double __
#$x = `wegn -v --header=Accept:text/turtle locate "$eoi_ref"`;
#like $x, qr|^Location: \Q$eoi_tgt/xxxmdata|m,
#	"xxx default EOI CN target resolution triggered by Accept header";

my $rp = EggNog::Binder::RSRVD_PFIX;
my $Tm = EggNog::Binder::TRGT_METADATA;	# actually content negotiation

#$x = `wegn loc\@xref\@xref $eoi.set __mTm. $eoi_tgt/mdata`;
#$x = `wegn loc\@xref\@xref $eoi.fetch __mTm.`;
$x = `wegn loc\@xref\@\@xref $eoi.set $rp$Tm $eoi_tgt/mdata`;
$x = `wegn loc\@xref\@\@xref $eoi.fetch $rp$Tm`;
like $x, qr|^${rp}Tm.: \Q$eoi_tgt/mdata|m,
	"new bound EOI default content negotiation (CN) target value fetched";

# xxx wegn --header=... must have no whitespace in it
$x = `wegn -v --header=Accept:text/turtle locate "$eoi_ref"`;
like $x, qr|^Location: \Q$eoi_tgt/mdata|m,
	"default EOI CN target resolution triggered by Accept header";

$x = `wegn locate "$eoi_ref_lc"`;
like $x, qr/^Location: \Q$eoi_tgt/m,
	"bound EOI target value resolved, even with lowercase reference";

# xxx re-instate the purge for tidiness?
#$x = `wegn loc\@xref\@xref $eoi.purge`;
#like $x, qr/^egg-status: 0/m,
#	"purge test id $eoi from CrossRef binder";

$x = `wegn locate ark:/12148/foo`;
like $x, qr|^Location: http://ark\.bnf\.fr/.*foo|m, "BNF redirect";
#
$x = `wegn locate ark:/67531/foo`;
like $x, qr|^Location: http://digital\.library\.unt\.edu/.*foo|m,
	"UNT redirect";
#
$x = `wegn locate ark:/76951/foo`;
like $x, qr|^Location: http://ark\.spmcpapers\.com/.*foo|m, "SPMC redirect";

# xxx document this naked prefix resolution
$x = `wegn -v resolve 'ark:/12148:'`;
like $x, qr/Bibliothèque nationale de France/i,
	'prefix fetch on well-known NAAN preserves UTF-8';

my $hostname = `hostname -f`;
chop $hostname;
say "NB: For an end-user check, open this in your browser (eg, Cmd-Click):\n",
	"    https://$hostname/$cdl_ark";

$x = `n2t cron works`;
$x =~ /disabled/ and
	say STDERR "\nALERT! -- $x";

exit;

# XXX bug: https://n2t.net/ark:/99999/fk8testn2t gets Forbidden
# XXX bug: https://localhost:18443/ark:/99999/fk8testn2t gets Location http://jak-macbook.local:18880/e/api_help.html

#===
my $arkOCA = "ark:/13960/xt897";
my $tgtOCA = "http://foo.example.com/target4";

#my ($usr, $bdr) = ('oca', 'oca_test');
my ($usr, $bdr) = ('oca', 'oca_test');

$x = `wegn \@$usr\@$bdr $arkOCA.set _t $tgtOCA`;
$x = `wegn \@$usr\@$bdr $arkOCA.get _t`;
#$x = run_cmdz_in_body($td, $usr, $bdr, $cmdblock);
like $x, qr{_t: $tgtOCA}si,
	"set $bdr:$arkOCA to $tgtOCA";

$x = `wegn "t-$arkOCA"`;
like $x, qr{HTTP/\S+\s+302\s.*Location:\s*$tgtOCA}si,
	"OCA NAAN sent to OCA binder";
#===

}

