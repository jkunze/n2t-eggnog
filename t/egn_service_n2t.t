use 5.10.1;
use Test::More;

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';
use EggNog::ApacheTester ':all';

#my ($td, $cmd) = script_tester "egg";		# yyy needed?
#my ($td2, $cmd2) = script_tester "nog";		# yyy needed?

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
my ($td2, $cmd2);
($td2, $cmd2, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "nog";
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

# Tests for resolver mode look a little convoluted because we have to get
# the actual command onto STDIN in order to test resolver mode.  This
# subroutine makes it a little simpler.
#
sub resolve_stdin { my( $opt_string, @ids )=@_;
	my $script = '';
	$script .= "$_.resolve\n"
		for @ids;
	my $msg = file_value("> $td/getcmd", $script);
	$msg		and return $msg;
	return `$cmd --rrm $opt_string - < $td/getcmd`;
}

# Args ( $opt_string, $id1, $hdr1, $id2, $hdr2, ... )
sub resolve_stdin_hdr {
	my $opt_string = shift;
	my $script = '';
	my ($id, $hdr);
	while ($id = shift) {
		$hdr = shift || '';
		$hdr and
			$hdr = ' ' . $hdr;
		$script .= "$id.resolve$hdr\n";
	}
	my $msg = file_value("> $td/getcmd", $script);
	$msg		and return $msg;
	return `$cmd --rrm $opt_string - < $td/getcmd`;
}

# This set of tests runs off of a configuration directory that defines
# the web server, creates binders and minters (see make_populator), etc.
#
#my $cfgdir = "t/n2t";		# this is an N2T web server test
my $cfgdir = "n2t";		# this is an N2T web server test

my $webclient = 'wget';
my $which = `which $webclient`;
$which =~ /wget/ or plan skip_all =>
	"why: web client \"$webclient\" not found";

# xxx how many of these things returned by prep_server do we actually need?
my ($msg, $src_top, $webcl,
		$srvport, $srvbase_u, $ssvport, $ssvbase_u,
	) = prep_server $cfgdir;
$msg and
	plan skip_all => $msg;

! $ENV{EGNAPA_TOP} and plan skip_all =>
	"why: no Apache server (via EGNAPA_TOP) detected";

plan 'no_plan';		# how we usually roll -- freedom to test whatever

SKIP: {

# Make sure server is stopped in case we failed to stop it last time.
# We don't bother checking the return as it would usually complain.
#
apachectl('graceful-stop');

# Note: $td and $td2 are barely used here.
# Instead we use non-temporary dirs $ntd and $ntd2.
# XXX change t/apachebase.t to use these type of dirs
#
my $buildout_root = $ENV{EGNAPA_BUILDOUT_ROOT};
my $binders_root = $ENV{EGNAPA_BINDERS_ROOT};
my $minters_root = $ENV{EGNAPA_MINTERS_ROOT};
my ($ntd, $ntd2) = ($binders_root, $minters_root);

remake_td($td, $bgroup);
remake_td($td2, $bgroup);

# This script calls egg, and we want the latest -Mblib and cleanest, eg,
#$ENV{EGG} = "--home $buildout_root";	# wrt default config and prefixes
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

my ($x, $y);
$x = apachectl('start');
skip "failed to start apache ($x)"
	if $x;

# HTTP Authorization challenge that should match either Apache 2.2 or 2.4.
my $authz_chall = '401 \w*authoriz';

#
# This section tests server access to various documentation pages.
#

$x = `$webcl "$srvbase_u"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*Name-to-Thing.*Resolver}si,
	'public http access to server home page authorized';

# only want location info, not redirect
$x = `$webcl --max-redirect 0 "$ssvbase_u/e/naan_request"`;
like $x, qr{HTTP/\S+\s+302\s+.*goo.gl/forms}si,
	'pre-binder-lookup redirect for externally hosted content';

#say "webcl=$webcl";
#say "srvbase_u=$srvbase_u";
#$x = apachectl('graceful-stop'); #	and print("$x\n");
#print "######### temporary testing stop #########\n"; exit;

$x = `$webcl "$srvbase_u/e"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*extras directory}si,
	'public http access to extras directory authorized';

$x = `$webcl "$ssvbase_u"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*Name-to-Thing.*Resolver}si,
	'public https access to home page authorized';

$x = `$webcl "$ssvbase_u/e"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*extras directory}si,
	'public https access to extras dir authorized';

$x = `$webcl "$ssvbase_u/e/index.html"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*extras directory}si,
	'public https access inside extras directory is authorized';

$x = `$webcl "$ssvbase_u/e/n2t_vision.html"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*resolver vision}si,
	'resolver vision document is in place';

$x = `$webcl "$srvbase_u/e/api_help.html"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*API correctly}si,
	"stub API document is in place";

$x = `$webcl "$srvbase_u/a"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*api home page}si,
	'public http access to api help page (/a) is authorized';

$x = `$webcl "$ssvbase_u/a//"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*api home page}si,
	'public https access to api home page (/a//) is authorized';

#$x = `$webcl "$ssvbase_u/a/foo"`;
#like $x, qr{HTTP/\S+\s+200\s+OK.*use the API}si,
#	'incomplete API path returns help text';	# yyy 200 ok status?
#
#$x = `$webcl "$srvbase_u/a/foo"`;
#like $x, qr{Location:.*HTTP/\S+\s+200\s+OK.*use the API}si,
#	'http incomplete API path redirects to https to return help text';

# XXX make urn:uuid resolve
# xxx make CN with single underscore _mTm. work

my $pps;		# passwords/permissions string
my $fqsr;		# fully qualified shoulder

$pps = setpps get_user_pwd "ezid", "ezid", $cfgdir;

my $a1 = 'ark:/12345/bcd';
$x = `$webcl $pps "$ssvbase_u/a/ezid/b? $a1.set _t http://b.example.com"`;
like $x, qr{HTTP/\S+\s+200\s+.*egg-status: 0}si,
	'set resolution target';

use EggNog::Binder ':all';
my $rrminfo = RRMINFOARK;

# this test won't work in resolve.t, as it needs a running server
my $hgid = `hg identify | sed 's/ .*//'`;
chop $hgid;
#print "comm: $webcl \"$srvbase_u/$rrminfo\"\n";
$x = `$webcl "$srvbase_u/$rrminfo"`;
like $x, qr{Location:.*dvcsid=\Q$hgid\E&rmap=}i,
	'resolver info with correct dvcsid returned';
# fe80::c57:e454:73e5:9ed - - [22/Jan/2017:22:39:13 --0800] [jak-macbook.local/sid#7f83b4817728][rid#7f83b5012ca0/initial] (5) map lookup OK: map=map_ezid key=99999/__rrminfo__.resolve ac=*/*!!!ff=!!!ra=fe80::c57:e454:73e5:9ed!!!co=!!!re=!!!ua=Wget/1.15%20(darwin13.1.0) -> val=redir302 

# XXX server hung could mean a rewriterule infinite loop
my $q1 = 'ark:/12345/bcd?';
$x = `$webcl $pps "$ssvbase_u/a/ezid/b? $q1.set _t http://q.example.com"`;
like $x, qr{HTTP/\S+\s+200\s+.*egg-status: 0}si,
	'set resolution target on what looks like inflection';

$x = `$webcl $pps "$ssvbase_u/a/ezid/b? $a1.fetch"`;
like $x, qr{HTTP/\S+\s+200\s+.*_t: http://b.example.com}si,
	'fetch the resolution target that was just bound';

#my $date;
#my $secs = 80;
#$date = localtime;
#say "xxx $date sleeping $secs seconds to wait for write";
#sleep $secs;
#$date = localtime;
#say "xxx $date waking up now";

#$x = apachectl('graceful') and say("yyy apache graceful-restart");

#$x = apachectl('restart') and say("yyy apache restart");
#$exdb and
#	`mg restart`;

# xxx do separate normalization test
# ??? true still ??? xxx sometimes these tests hang when the network connection is poor
$x = `$webcl "$srvbase_u/$a1"`;
like $x, qr{Location:.*http://b.example.com}i,
	'resolution via redirect from rewritemap';

if ($exdb) {
  $x = apachectl('graceful-stop'); #	and print("$x\n");
  say "xxx webcl resolution cmd: $webcl \"$srvbase_u/$a1\"";
  say "XXXXXX temporary testing stop #########";
  exit 1;	# this should cause 'make test' to notice an error
}

#not ok 18 - resolution via redirect from rewritemap
#   Failed test 'resolution via redirect from rewritemap'
#   at t/egn_service_n2t.t line 206.
#                   '--2018-09-30 08:56:08--
#                   http://jak-macbook.local:8082/ark:/12345/bcd
# Resolving jak-macbook.local... fe80::81d:fa54:4f60:88b8, 127.0.0.1
# Connecting to jak-macbook.local|fe80::81d:fa54:4f60:88b8|:8082... connected.
# HTTP request sent, awaiting response...
#   HTTP/1.1 404 Not Found
#   Date: Sun, 30 Sep 2018 15:56:08 GMT
#   Server: Apache/2.2.29 (Unix) DAV/2 mod_ssl/2.2.29 OpenSSL/0.9.8zh
#   Content-Length: 212
#   Keep-Alive: timeout=5, max=100
#   Connection: Keep-Alive
#   Content-Type: text/html; charset=iso-8859-1
# 2018-09-30 08:56:08 ERROR 404: Not Found.
#
# '
#     doesn't match '(?^i:Location:.*http://b.example.com)'

# xxx sometimes these tests hang when the network connection is poor
#     consider reducing maxredirects 
$x = `$webcl "$ssvbase_u/$a1"`;
like $x, qr{Location:.*http://b.example.com}i,
	'HTTPS resolution via redirect from rewritemap';

# xxx sometimes these tests hang when the network connection is poor
#     consider reducing maxredirects 
# xxx document
$x = `$webcl "$srvbase_u/$q1"`;
like $x, qr{Location:.*http://q.example.com}i,
	'deliberately assigned inflection target trumps actual inflection';

$y = file_value("< $buildout_root/logs/transaction_log", $x);
like $y, qr/^$/, 'read transaction_log file';

like $x, qr/(?:BEGIN[^\n]*resolve.*END SUCCESS[^\n]*redir30\d )/s,
	'transaction_log records resolve BEGIN/END pair';

$pps = setpps get_user_pwd "yamz", "yamz", $cfgdir;

#$x = `$webcl $pps "$ssvbase_u/a/yamz/b? --verbose --version"`;
#like $x, qr{HTTP/\S+\s+401\s+Authorization.*xxxversion:}si,
#	'exec failure error message';

$x = `$webcl $pps "$ssvbase_u/a/yamz/b? --verbose --version"`;
like $x, qr{HTTP/\S+\s+$authz_chall.*version:}si,
	'verbose version collected from web server environment';

my $v = `$cmd --verbose --version`;
$v =~ s/^ ?[^ ].*\n*//gm;	# delete all but lines indented with 2 spaces
#my $v2 = `$cmd2 --verbose --version`;
#$v2 =~ s/^ ?[^ ].*\n//gm;

chop $x;
$x =~ s/.*\n(version: This.*)$/$1/s;	# delete up to line starting "version:"
$x =~ s/egg-status:.*/\n/s;	# delete everything starting with next status
#print "xxx x=$x+, v=$v+\n";
$x =~ s/^ ?[^ ].*\n*//gm;
#print "v = $v, x = $x";
is $x, $v,
	'environment behind web matches command line environment';

#$x = apachectl('graceful-stop')	and print("$x\n");
#exit;	#########

#
# This section tests server access to a minter.
#

# XXX for now, DOI minting takes place via special-NAAN ARKs:
#     10.nnnn -> bnnnn, 10.1nnnn -> cnnnn, 10.2nnnn -> dnnnn, ...
#     edge: 10.n -> b.000n, 10.nn -> b.00nn, 10.nnn -> b.0nnn
# xxx maybe we should eventually support real DOIs "doi:10.5072/fk9"

# XXXXXX make sure I have set up ezid_test for binding!

#    binders=( ezid  ezid_test  oca  oca_test )
# populators=( ezid  ezid       oca  oca      )

# XXX find a way to pull this from make_populators
# this uses form likely to come from a "find" inspection of minters_root dir
my @fqshoulders = (
        'ezid/ark/99999/fk4',		# fake ARKs
	'ezid/ark/b5072/fk2',		# fake DOIs
        'ezid/ark/99999/ffk4',		# extra fake ARKs
	'ezid/ark/b5072/ffk2',		# extra fake DOIs
	'oca/ark/99999/fk5',		# fake ARKs
	'oca/ark/99999/ffk5',		# extra fake ARKs
);

my @more_fqshoulders = (
        'yamz/ark/99999/fk6',		# fake ARKs
        'xref/ark/99999/fk7',		# fake ARKs
);

#my @even_more_fqshoulders = (
#        'yamz/ark/99999/fk6',		# fake ARKs
#        'purl/ark/99999/fk3',		# fake ARKs
#);

#my $fqasr = "ezid/ark/99999/fk4";	# fully qualified fake ARK shoulder
#my $fqdsr = "ezid/ark/b5072/fk2";	# fully qualified fake DOI shoulder

test_minters $cfgdir, 'ezid', 'oca', @fqshoulders;
test_minters $cfgdir, 'yamz', 'xref', @more_fqshoulders;
#test_minters $cfgdir, 'yamz', 'purl', @even_more_fqshoulders;

#$x = apachectl('graceful-stop')	and print("$x\n");
#exit;	#########

# set populator realm and user for quick yamz test; yyy another special case
# xxx shouldn't $naanblade be more like $naanshoulder?
my ($popminder, $naanblade) = crack_minter 'yamz/ark/99999/ffk6';
$pps = setpps get_user_pwd "yamz", "yamz", $cfgdir;
$x = `$webcl $pps "$ssvbase_u/a/$popminder/m/ark/$naanblade? mint 1"`;
like $x, qr{HTTP/\S+\s+$authz_chall.*s: $naanblade\w{4,7}\n}si,
	"populator/binder \"$popminder\" mints from $naanblade";

# We'll piggyback another use for the noauth_test, which is that

# xxx why does .../ark: show in error log?
# xxxx should do feature that on failure runs check digit algorithm and
#      reports and possibly suggests alternates

# Binder tests should be minimally disruptive: (a) unlikely to collide
# with existing identifiers and (b) removing as many traces as possible.
# xxx remember to delete
# xxx loop thru all binders?
# xxx remove oddball redirects
# xxx add naan-registry redirects?

my $cmdblock;
# XXX 97720 is for URNs
# xxx this is not how we do URNs in EZID
#my $urn = 'urn:uuid:1234';
my $ark = 'ark:/13030/b4cd3';

# XXX remember to do in production tests

my @cleanup_ids;			# add ids to clean up each time

# yyy no cross-http-https redirect tests yet
my ($usr, $bdr, $ark1, $ark2, $tgt1, $tgt2, $tgt3);

$ark1 = 'ark:/13030/b4cd3';
$ark2 = 'ark:/13030/f4gh3';
$tgt1 = "$srvbase_u/e";
$tgt2 = "$srvbase_u/";
$tgt3 = "$srvbase_u/e/api_help.html";

# xxx cleanup $urn?
@cleanup_ids = ($ark, $ark1, $ark2);
purge_test_realms($cfgdir, $td, \@cleanup_ids, 'ezid', 'oca', 'yamz');
# xxx is purge_test_realms still relevant in file (as opposed to real test)?

#my $for_user = "http://n2t.net/ark:/99166/b4cd3";
#$pps = setpps get_user_pwd("oca", "oca", $cfgdir), "fran";

# xxx test REMOTE_USER with and w/o authN
# xxx    multi-binder resolution
# xxx    doi support tests

# To be applied to oca_test.
#
$cmdblock = "
<foo>myid.set this that
myid.set this that
myid.add this these
myid.fetch this
myid.fetch
";

# xxx rename get_user_pwd getpw_realm_login ?

## Bind against oca_test
#$pps = setpps get_user_pwd("oca", "oca", $cfgdir), $for_user;
# XXXX use $ntd here or $td? but this really tmp file stuff
#$x = run_cmds_in_body($td, $pps, "oca_test", $cmdblock);

$x = run_cmdz_in_body($cfgdir, $td, "oca", "oca_test", $cmdblock);
like $x, qr{<binder> prefix.*\nthis: th.*\nthis: }si,
	"web bulk commands in request body, binder prefix turned down";

use EggNog::Binder 'SUPPORT_ELEMS_RE';
my $spat = EggNog::Binder::SUPPORT_ELEMS_RE;

like $x, qr{$spat:.*$spat:}si,
	"admin elements present in fetch of all elements (due to --all)";

$cmdblock =		# destined for oca_test
"# this next https should redirect to http.../e then to http.../e/
$ark1.set _t $tgt1
$ark1.get _t
";
($usr, $bdr) = ('oca', 'oca_test');
$x = run_cmdz_in_body($cfgdir, $td, $usr, $bdr, $cmdblock);
like $x, qr{_t: $tgt1}si,
	"set $bdr:$ark1 to $tgt1";

$cmdblock =		# destined for ezid_test
"$ark2.set _t $tgt2
$ark2.get _t
";
($usr, $bdr) = ('ezid', 'ezid_test');
$x = run_cmdz_in_body($cfgdir, $td, $usr, $bdr, $cmdblock);
like $x, qr{_t: $tgt2}si,
	"set $bdr:$ark2 to $tgt2";

####### this is about where the Apache Resolverlist Bugs happened ########
# yyy those tests were moved out to form t/resolverlist.t

$x = `$webcl "$srvbase_u/t-$ark2/e"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*extras directory}si,
	"suffix passthru from home dir to extras dir";

#$x = apachectl('graceful-stop'); #	and print("$x\n");
#print "######### temporary testing stop #########\n"; exit;

$x = `$webcl "$srvbase_u/ark:/12345/WontBeFound"`;
like $x, qr{HTTP/\S+\s+404\s+Not\s+Found}si,
	"not found page gets 404, eg, and not home page";

# xxx should pull this list of binders from FS via "find"
my @binders = ( qw(ezid ezid_test oca oca_test yamz yamz_test) );

test_binders $cfgdir, $ntd, $indb, @binders;

# <body><h1>How to ask for a single-binder resolution.</h1></body> </html>
$x = `$webcl "$srvbase_u/r"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*single-binder resolution}si,
	'public https access to resolver info page (/r)';

$x = `$webcl "$srvbase_u/t-ark:/13030/xyzzy"`;
#$x = `$webcl "$srvbase_u/t-$ark2/xyzzy"`;
like $x, qr{HTTP/\S+\s+404\s.*Not Found}si,
	"no results found fails correctly with resolverlist";
# note: this creates an error_log entry (expected) that you can ignore

my $arkOCA = "ark:/13960/xt897";
my $tgtOCA = "http://foo.example.com/target4";
$cmdblock =		# destined for oca_test
"
$arkOCA.set _t $tgtOCA
$arkOCA.get _t
";
($usr, $bdr) = ('oca', 'oca_test');
$x = run_cmdz_in_body($cfgdir, $td, $usr, $bdr, $cmdblock);
like $x, qr{_t: $tgtOCA}si,
	"set $bdr:$arkOCA to $tgtOCA";

$x = `$webcl "$srvbase_u/t-$arkOCA"`;
like $x, qr{HTTP/\S+\s+302\s.*Location:\s*$tgtOCA}si,
	"OCA NAAN sent to OCA binder";

my $arkYAMZ = "ark:/99152/xt898";
my $tgtYAMZ = "http://foo.example.com/target5";
$cmdblock =		# destined for yamz_test
"# this next https should redirect to http.../e then to http.../e/
$arkYAMZ.set _t $tgtYAMZ
$arkYAMZ.get _t
";
($usr, $bdr) = ('yamz', 'yamz_test');
$x = run_cmdz_in_body($cfgdir, $td, $usr, $bdr, $cmdblock);
like $x, qr{_t: $tgtYAMZ}si,
	"set $bdr:$arkYAMZ to $tgtYAMZ";

$x = `$webcl "$srvbase_u/t-$arkYAMZ"`;
like $x, qr{HTTP/\S+\s+302\s.*Location:\s*$tgtYAMZ}si,
	"YAMZ NAAN sent to YAMZ binder";


# xxx test with and without password, and with open binder

# XXXX needed?
purge_test_realms($cfgdir, $td, \@cleanup_ids, 'ezid', 'oca', 'yamz');

$x = apachectl('graceful-stop')	and print("$x\n");

remove_td($td, $bgroup);
remove_td($td2, $bgroup);
}
