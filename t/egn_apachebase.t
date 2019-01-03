use 5.10.1;
use Test::More;

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';
use EggNog::ApacheTester ':all';

# the web server, creates binders and minters (see make_populator), etc.
#
#my $cfgdir = "t/web";		# this is a generic web server test
my $cfgdir = "web";		# this is a generic web server test

my $webclient = 'wget';
my $which = `which $webclient`;
$which =~ /wget/ or plan skip_all =>
	"why: web client \"$webclient\" not found";

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

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
my ($td2, $cmd2);
($td2, $cmd2, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "nog";

# This script calls egg, and we want the latest -Mblib and cleanest, eg,
$hgbase = "--home $buildout_root";	# and we know better in this case
$bgroup and
	$hgbase .= " --bgroup $bgroup";
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values
#$ENV{EGG} = "--home $buildout_root";	# wrt default config and prefixes

remake_td($td, $bgroup);
remake_td($td2, $bgroup);


#sub catch_int {
#	local $SIG{INT} = 'IGNORE';
#	#my $signame = shift;
#	my $x;
#	$x = apachectl('graceful-stop')	and print("$x\n");
#	exit;
#}
#$SIG{INT} = \&catch_int;

my ($x, $y);
$x = apachectl('start');
skip "failed to start apache ($x)"
	if $x;

# HTTP Authorization challenge that should match either Apache 2.2 or 2.4.
my $authz_chall = '401 \w*authoriz';

$x = `$webcl "$srvbase_u"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*server home page}si,
	'public http access to server home page authorized';

# sometimes no query string and no '?' would print the source code
$x = `$webcl "$ssvbase_u/a/pest/b"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*Usage: }s,
	"no query string (not even '?') returns usage info";
unlike $x, qr{^\s*use\s*strict;\s*$}m,
	"no query string (not even '?') gives no source code";

$x = `$webcl "$ssvbase_u/a/pest/b? --version"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*version:.*version}si,
	'open populator script starts up with version option';

$x = `$webcl "$ssvbase_u/a/pest/b? mkbinder foo"`;
like $x, qr{HTTP/\S+\s+401\s+unauthorized.*ation failed}si,
	'web-mode mkbinder is correctly unauthorized';

# xxx should be done via 401 and error message?
$x = `$webcl "$ssvbase_u/a/pest/b? -d pestx i.set a b"`;
like $x, qr{HTTP/\S+\s+200.*error:.*not allowed}si,
	'-d in query string is correctly shut out';

# xxx should be done via 401 and error message
$x = `$webcl "$ssvbase_u/a/pest/b? --minderp / i.set a b"`;
like $x, qr{HTTP/\S+\s+200.*error:.*not allowed}si,
	'--minderpath in query string is correctly shut out';

my $pps;				# passwords/permissions string

$pps = setpps get_user_pwd "pestx", "testuser1", $cfgdir;
#print "pps=$pps\n";

#$x = `$webcl $pps "$ssvbase_u/a/pestx/b? ark:/13030/fk8tt.set _t www.example.com"`;
#like $x, qr{xxx}, 'set target';
#
#$x = `$webcl "$srvbase_u/ark:/13030/fk8tt"`;
#like $x, qr{xxx www.example.com}, 'resolve to target';
#
#$x = apachectl('graceful-stop')	and print("$x\n");
#exit;	#########

$x = `$webcl $pps "$ssvbase_u/a/pestx/b? --verbose --version"`;
#like $x, qr{HTTP/\S+\s+401\s+Authorization.*version:}si,
like $x, qr{HTTP/\S+\s+$authz_chall.*version:}si,
	'verbose version collected from web server environment';

#say "xxx x=$x";
#$x = apachectl('graceful-stop')	and print("$x\n");
#exit;	#########

my $v = `$cmd --verbose --version`;
$v =~ s/^ ?[^ ].*\n*//gm;	# delete all but lines indented with 2 spaces

chop $x;
$x =~ s/.*\n(version: This.*)$/$1/s;	# delete up to line starting "version:"
$x =~ s/egg-status:.*/\n/s;	# delete everything starting with next status
$x =~ s/^ ?[^ ].*\n*//gm;
is $x, $v,
	'environment behind web matches command line environment';

# This test sets up the DB_PRIVATE test.
# yyy shouldn't this mkbinder be done in minder_builder_more?
$x = `$cmd -p $td mkbinder --verbose pest`;
$x = `$cmd -d $td/pest --verbose i.set a b`;
shellst_is 0, $x, "non-web-mode mkbinder and binding succeeds";

# yyy remove $td and $td2 from this script?
# Make sure $testdir exists and is empty
# xxx change to $ntd?
my $testdir = "$td/pest";
my $backdir = "$td/pestbak";
my $msg = `rm -fr $backdir 2>&1`;
my $errs = 0;
$msg and
	$errs++,
	print("Problem removing $backdir: $msg");

if ($indb) {

mkdir($backdir) or
	$errs++,
	print("Could not create dir $backdir.\n");
my $dbmsg = `db_hotbackup -h $testdir -b $backdir 2>&1`;
$dbmsg and
	$errs++,
	print($dbmsg);
ok $errs == 0,
	"DB_PRIVATE flag off (resolver sensitive to target changes)";

} # $indb

$x = `$webcl "$ssvbase_u/a/pest/b? rmbinder pest"`;
like $x, qr{HTTP/\S+\s+401\s+unauthorized.*ation failed}si,
	'web-mode rmbinder is correctly unauthorized';

$x = `$webcl "$ssvbase_u/a/pest/m? rmminter pest"`;
like $x, qr{HTTP/\S+\s+401\s+unauthorized.*ation failed}si,
	'web-mode rmminter is correctly unauthorized';

my @fqshoulders = (
	'pestx/ark/99999/fk6',
	'pestx/ark/b5072/fk9',
	'pesty/ark/99999/fk3',
);

$x = `$webcl "$ssvbase_u/a/pest/b? i.set moo cow"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*egg-status: 0}si,
	'open populator "pest" sets an element without a login/password';

$y = flvl("< $buildout_root/logs/transaction_log", $x);
$y and print "error: $y\n";
like $x, qr{BEGIN.*END SUCCESS}s,
	'transaction log working';

##########
#remove_td($td, $bgroup); remove_td($td2, $bgroup);
#$x = apachectl('graceful-stop')	and print("$x\n");
#exit;	#########

$x = `$webcl "$srvbase_u/e/x/feedback.pl"`;
like $x, qr{Stub feedback.}i,
	'publicly executable feedback form';

$x = `$webcl "$ssvbase_u/a/pest/b? --verbose i.fetch moo"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*remote user: \?.*moo:\s*cow}si,
	'open populator "pest" returns that element for still unknown user';

if ($indb) {		# rlog being phased out, esp for exdb case
$y = flvl("< $ntd/pest/egg.rlog", $x);
like $x, qr{^\? }m,
	'anonymous user logged as "?"';
}

# xxxxxx add indb arg as for test_binders?
test_minters $cfgdir, 'pestx', 'pesty', @fqshoulders;

# xxx should pull this list of binders from FS via "find"
my @binders = ( qw(pestx pesty) );

test_binders $cfgdir, $ntd, $indb, @binders;

# xxx document that doi minters are put under ark for convenience of the
#     check digit algorithm
# xxx why does .../ark: show in error log?
# xxxx should do feature that on failure runs check digit algorithm and
#      reports and possibly suggests alternates

#$x = apachectl('graceful-stop')	and print("$x\n");
#say "xxxxxxxxxx premature exit";
#exit;	#########

$pps = setpps get_user_pwd("pesty", "testuser1", $cfgdir), "joey";

$x = `$webcl $pps "$ssvbase_u/a/pesty/b? --verbose i.set hello there"`;
like $x, qr{$authz_chall.*remote user:.*joey}si,
	'user string found in Acting-For header';

my $user = "http://n2t.net/ark:/99166/b4cd3";
$pps = setpps get_user_pwd("pesty", "testuser1", $cfgdir), $user;

$x = `$webcl $pps "$ssvbase_u/a/pesty/b? --verbose i.set hello th+ere"`;
like $x, qr{$authz_chall.*remote user:.*&P/b4cd3}si,
	"Acting-For user ($user) gets &P-compressed";

$x = " <html> <body><h1>Read-protected extras file.</h1></body> </html> ";
$y = flvl("> $buildout_root/htdocs/e/pop/pesty/index.html", $x);
$x = `$webcl $pps "$ssvbase_u/e/pop/pesty/"`;
like $x, qr{$authz_chall.*Read-protected}si,
	"read-protected non-executable document area";

$x = `$webcl $pps "$ssvbase_u/a/pesty/b? i.fetch hello"`;
like $x, qr{$authz_chall.*hello:\s*th\+ere}si,
	"noid's old '+'-to-space decoding is no longer in effect";

remove_td($td, $bgroup);
remove_td($td2, $bgroup);

$x = apachectl('graceful-stop')	and print("$x\n");
exit;	#########


#==============================================
# XXXXX this next cmdblock sets up a number of subsequent tests that
# should eventually (before public source code release) be moved into
# a separate release area:
#  <binder> prohibition
#  URN tests
#  multi-binder resolution
#
# OTOH, some tests should perhaps be redundant between the more generic
# apachebase and a more specific durable instance: the generic tests
# provide examples and the specific tests shore up the generic tests.(?)
#
my $cmdblock;			# --post-file=FILE
my $urn = 'urn:uuid:1234';
my $ark = 'ark:/13030/b4cd3';
$cmdblock = "
<foo>myid.set this that
myid.set this that
myid.add this these
myid.fetch this
$ark.set _t $ssvbase_u/e
$ark.get _t
$urn.set _t $srvbase_u/e/apihelp.html
myid.fetch
";
$x = run_cmds_in_body($td, $pps, "pesty", $cmdblock);
like $x, qr{<binder> prefix.*\nthis: th.*\nthis: .*$ssvbase_u/e}si,
	"web bulk commands in request body, binder prefix turned down";

use EggNog::Binder 'SUPPORT_ELEMS_RE';
my $spat = EggNog::Binder::SUPPORT_ELEMS_RE;

like $x, qr{$spat:.*$spat:}si,
	"admin elements present in fetch of all elements (due to --all)";

# note: you can test if the rmap starts up at all from the shell with
#     $ td_EGNAPA_config/htdocs/a/pesty/rmap_pesty
# and then entering commands on stdin
#
$x = open(RMAPSCRIPT,
	"| $buildout_root/htdocs/a/pesty/rmap_pesty > $td/rmapout");
isnt $x, 0,
	"opened pipe to resolver map script";
print RMAPSCRIPT "$ark.resolve\n";
#print RMAPSCRIPT "$ark.get _t\n";
close(RMAPSCRIPT);

$y = flvl("< $ntd/rmapout", $x);
is $x, "redir302 $ssvbase_u/e\n\n",
	"raw resolver map script returns target URL";

#print "###### temporary testing stop ########\n"; exit;

$x = `$webcl "$srvbase_u/ark:/13030/b4cd3"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*extras directory}si,
	"resolve against 2nd populator (target https)";

$x = `$webcl "$srvbase_u/ark:/93030/b4cd3 "`;	# final ' ' means output error
$x .= `$webcl "$srvbase_u/ark:/13030/b4cd3"`;
like $x, qr{HTTP/\S+\s+400\s+Bad.*HTTP/\S+\s+200\s+OK.*extras directory}si,
	"resolution 'syntax' error doesn't disturb next resolution";

# XXX don't understand why this works; final ' ' on thing, but internal \n ?
$x = `$webcl "$srvbase_u/ark:/93030/b%0a4cd3"`;	# %0a creates two input lines
$x .= `$webcl "$srvbase_u/ark:/13030/b4cd3"`;
like $x, qr{HTTP/\S+\s+404\s+Not.*HTTP/\S+\s+200\s+OK.*extras directory}si,
	"split resolution command error doesn't disturb next resolution";

#$pps = setpps "testuser1", "testpwd1a";
$pps = setpps get_user_pwd("pestx", "testuser1", $cfgdir);

# XXX definitely not a test for apachebase.t
$ark = 'ark:/13960/f5gh6';
$x = `$webcl $pps "$ssvbase_u/a/pestx/b? $ark.set _t $srvbase_u"`;
$x = `$webcl "$srvbase_u/ark:/13960/dummy"`;
#$x = `$webcl "$srvbase_u/e/13960/dummy"`;
like $x, qr{HTTP/\S+\s+404\s+Not Found}si,
	"NAAN filtered to go against 1st populator";
# note: this creates an error_log entry (expected) that you can ignore

# this artificially tests a redirect that we won't use any more
$x = `$webcl $pps "$ssvbase_u/a/pest_x/b? $ark.get _t"`;
$x .= `$webcl "$srvbase_u/$ark"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*server home page}si,
	"NAAN filtered id resolves against 1st populator (target http)";

$x = `$webcl "$srvbase_u/r/pestx/$ark"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*server home page}si,
	"explicitly named resolver for 1st populator";

$x = `$webcl "$srvbase_u/$ark/e"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*extras directory}si,
	"suffix passthru from home dir to extras dir";

# XXX URN and api docs belong in n2t.t
$x = `$webcl "$srvbase_u/$urn"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*API correctly}si,
	"URN filtered to resolve against two populators matches on 2nd";

# xxx document: use of /r/ezid/<ark> to explicitly get one binder
$x = `$webcl "$ssvbase_u/r/pesty/$urn"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*API correctly}si,
	"explicitly named resolver for 2nd populator (via https)";

# <body><h1>How to ask for a single-binder resolution.</h1></body> </html>
$x = `$webcl "$srvbase_u/r"`;
like $x, qr{HTTP/\S+\s+200\s+OK.*single-binder resolution}si,
	'public https access to resolver info page (/r)';

$x = `$webcl "$srvbase_u/xyzzy"`;
like $x, qr{HTTP/\S+\s+404\s.*Not Found}si,
	"no results found fails correctly with resolverlist";
# note: this creates an error_log entry (expected) that you can ignore

# xxx test with and without password, and with open populator

$x = apachectl('graceful-stop')	and print("$x\n");
#remove_td($td, $bgroup);
#remove_td($td2, $bgroup);
}
