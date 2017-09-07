use 5.010;
use Test::More;

# NB: there's no dependency on build_server_tree because some server
# functionality is contrived within the tests below.

# yyy case-insensitive ARK id match as backup?
# yyy case-insensitive ARK shoulder match as backup?

plan 'no_plan';		# how we usually roll -- freedom to test whatever

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';
use File::Binder ':all';

my ($td, $cmd) = script_tester "egg";
my $egg_home = "--home $td";
$ENV{EGG} = $egg_home;

# Tests for resolver mode look a little convoluted because we have
# to get the actual command onto STDIN in order to test resolver mode.
# This subroutine makes it a little simpler.
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
		#$script .= "$id.resolve $hdr\n";
	}
	my $msg = file_value("> $td/getcmd", $script);
	$msg		and return $msg;
	return `$cmd --rrm $opt_string - < $td/getcmd`;
}

#=for later
{		# some simple ? and ?? tests
remake_td($td);

$ENV{EGG} = "$egg_home -p $td -m anvl";
my $x;

#my $ark = 'bar';
#$x = `$cmd $ark.set where 'ark:/99999/fk8gh891'`;
my $ark = 'ark:/99999/fk8gh891';
$x = `$cmd $ark.set who 'Smith, J.'`;
$x = `$cmd $ark.add who 'Wong, W.'`;
$x = `$cmd $ark.set what 'Victory and Defeat'`;
$x = `$cmd $ark.set when '1998'`;
$x = `$cmd $ark.fetch :brief`;
like $x, qr/Smith.*Victory.*1998.*$ark/s, ':brief element set';

$x = `$cmd $ark.fetch :support`;
like $x, qr/Smith.*Victory.*1998.*Calif.*support-what:.*cdlib.org/s,
	':support element set';

# xxx do content negotiation
$x = `$cmd -m anvl $ark.show :brief`;
like $x, qr/,\s*"Victory.*:\s*Victory/s, 'citation support';

$ENV{EGG} = $egg_home;
}
#=cut

{
remake_td($td);
my $x;

$x = `$cmd --version`;
my $v1bdb = ($x =~ /DB version 1/);

$x = `$cmd -p $td mkbinder foo`;
shellst_is 0, $x, "make binder named foo";

my $url;
$url = 'ark:/98765/foo';	# yyy not a well-named variable?
#$url = 'http://a.b.c/foo';
#$url = "foo";

$x = `$cmd -d $td/foo $url.set _t zaf`;
shellst_is 0, $x, "set _t";

# yyy do we still rely on OM in "plain" mode not doing only one
#        newline between elems, but in tests we need to chop extra
#        newline when the command ends?
# xxxx   how to make '|' work for value separators for dups (one day)?

#$x = resolve_stdin("-d $td/foo", $url);

my $sai = 'doi:10.12345/R2';
$x = resolve_stdin("-d $td/foo", $sai);
like $x, qr{redir302 http://doi.org/10.12345/R2},
   "redirect prefix selection drops through to scheme via hardwired prefix";

# --pfx_file=''	 forces special case of hardwired prefixes
$x = resolve_stdin("-d $td/foo --pfx_file ''", $sai);
like $x, qr{redir302 https?://doi.org/10.12345/R2\n},
	"forced hardwired prefix block knows about the doi prefix";

#print "premature end.  url=$url + \?\n";
#exit; ##############

$x = `$cmd -d $td/foo $sai.set _t zaf`;
$x = resolve_stdin("-d $td/foo",
	$url,
	$sai,
	$sai,
	$sai . 'D245/67',
);
shellst_is 0, $x, "get resolve mode _t status";

like $x, qr/^redir302 zaf\n/, "got _t value";

like $x, qr{redir302 zaf},
	"target defined on shoulder-as-id (SAI) prevents drop-through";
like $x, qr{redir302 zaf.*redir302 zaf}s,
	"SAI test works twice in a row";
#$x = resolve_stdin("-d $td/foo", $sai . 'D245/67');
like $x, qr{redir302 zafD245/67},
	"SPT on shoulder-as-id target";

my $host = '';	# yyy was $host meant to be empty?

$x = `$cmd -d $td/foo "$host".delete _t`;		# delete target
$x = `$cmd -d $td/foo ":idmap//ft([^x]+)x(.*)".set _t "\\\$2/g7h/\\\$1"`;
my $rurl = "http://g.h.i/ft89xr2t";
$x = resolve_stdin("-d $td/foo", $rurl);
like $x, qr,r2t/g7h/89,, "rule-based idmap substitution";

$x = `$cmd -d $td/foo "$host".delete _t`;		# delete target
my $nurl = 'http://www.ncbi.nlm.nih.gov/pubmed/';
$x = `$cmd -d $td/foo ":idmap/http://n2t.net/pmid:".set _t "$nurl"`;
$rurl = "http://n2t.net/pmid:1234567";
$x = resolve_stdin("-d $td/foo", $rurl);
like $x, qr,\b\Q${nurl}1234567,, "rule-based pmid mapping";

$x = `$cmd -d $td/foo $url.set _t "301 zaf"`;
$x = resolve_stdin("-d $td/foo", $url);
like $x, qr/^redir301 zaf\n$/,
	"got _t value with local redirect code";

$x = `$cmd -d $td/foo $url.set _t "999 zaf"`;
$x = resolve_stdin("-d $td/foo", $url);
like $x, qr/^redir302 zaf\n$/,
	"got _t value with 302 redirect for unrecognized value";

$x = `$cmd -d $td/foo $url.set _t "410 zaf"`;
$x = resolve_stdin("-d $td/foo", $url);
like $x, qr/^redir410 zaf\n$/,
	"got _t value with local 410 redirect code";

$x = `$cmd -p $td mkbinder fon`;
shellst_is 0, $x, "make binder named fon";

$x = resolve_stdin("-d $td/foo --resolverlist=$td/fon:$td/foo", $url);
like $x, qr|^redir410 zaf\n$|, "got _t value again with resolverlist";

$x = `$cmd -d $td/fon $url.set _t nersc`;
$x = resolve_stdin("-d $td/fon", $url);
like $x, qr|^redir302 nersc\n$|, "now have different _t value from fon binder";

$x = `$cmd -d $td/fon $url.add _t skink`;
$x = resolve_stdin("-d $td/fon", $url);
like $x, qr|^inflect multi "nersc" "skink"|,
	"multiple _t values passed to inflect";

$x = resolve_stdin_hdr("-d $td/fon",
	$url, "!!!ac=text/turtle!!!",
	"$url\?", '',
	"$url\?\?", '',
	"$url/", '',
	"$url./", '',
);
like $x, qr|^inflect "cn.text/turtle" |,
	"script called for content negotiation";

# xxx test when id set actually includes(overrides) inflection
$x =~ s/^.*\n//;				# remove top line
like $x, qr|^inflect "\?" |, "script called for ? inflection";

$x =~ s/^.*\n//;				# remove top line
like $x, qr|^inflect "\?\?" |, "script called for ?? inflection";

$x =~ s/^.*\n//;				# remove top line
like $x, qr|^inflect "/" |, "script called for / inflection";

#print "premature end.  url=$url + \?\n";
#exit; ##############

$x =~ s/^.*\n//;				# remove top line
like $x, qr|^inflect "\./" |, "script called for ./ inflection";

my $rp = File::Binder::RSRVD_PFIX;	# reserved sub-element prefix

$x = `$cmd -d $td/fon $url.set ${rp}Ti. newt`;
$x = resolve_stdin("-d $td/fon", "$url\?");
like $x, qr|^redir302 newt\n|, "default target redirect for ? inflection";

$x = `$cmd -d $td/fon $url.set "${rp}Ti.?" nowt`;
$x = resolve_stdin("-d $td/fon", "$url\?");
like $x, qr|^redir302 nowt\n|, "specific target redirect for ? inflection";

$x = `$cmd -d $td/fon $url.set "${rp}Ti.??" nought`;
$x = resolve_stdin("-d $td/fon", "$url\?\?");
like $x, qr|^redir302 nought\n|, "specific target redirect for ?? inflection";

$x = resolve_stdin_hdr("-d $td/fon", $url, "!!!ac=text/turtle!!!");
like $x, qr|^inflect "cn.text/turtle" |,
	"script called for content negotiation";

$x = `$cmd -d $td/fon $url.set ${rp}Tm. newt`;
$x = resolve_stdin_hdr("-d $td/fon", "$url", "!!!ac=text/turtle!!!");
like $x, qr|^redir303 newt\n|, "default target redirect for text/turtle CN";

$x = `$cmd -d $td/fon $url.set ${rp}Tm.application/rdf+xml newt`;
$x = resolve_stdin_hdr("-d $td/fon", "$url", "!!!ac=application/rdf+xml!!!");
like $x, qr|^redir303 newt\n|,
	"specific target redirect for application/rdf+xml CN";

my $rrminfo = RRMINFOARK;

print "XXX disabled resolverlist test1 for now\n";
#$x = resolve_stdin("-d $td/foo --resolverlist=$td/fon:$td/foo", $url);
#like $x, qr/^redir302 nersc\n$/,
#	"got _t with resolverlist, but 1st value hides 2nd";

print "XXX disabled resolverlist test2 for now\n";
#$x = `$cmd -d $td/fon $url.rm _t`;
#$x = resolve_stdin("-d $td/fon --resolverlist=$td/fon:$td/foo", $url);
#like $x, qr/^zaf\n$/,
#	"after removing 1st value, resolverlist gets 2nd value again";

$ENV{EGG} = "$egg_home -d $td/foo";

use File::Resolver;
my $urn = "urn:uuid:430c5f08-017e-11e1-858f-0025bce7cc84";
my $urn_shadow = File::Resolver::id2shadow($urn);

$x = `$cmd $urn_shadow.set this that`;
$x = `$cmd $urn.get this`;
like $x, qr/^that\n\n$/, 'URN shadow takes an element';

my $urn_t = 'http://www.cdlib.org/';
$x = `$cmd $urn_shadow.set _t $urn_t`;
$x = resolve_stdin('', $urn);
like $x, qr/^redir302 $urn_t\n/, 'URN shadow does URN resolution';

my $arkbase = "ark:/00224/foo";
$x = `$cmd -d $td/foo $arkbase.set _t zaf`;
$x = resolve_stdin('', $arkbase);
#shellst_is 0, $x, "get resolve mode _t extension status";
like $x, qr|^redir302 zaf\n|, 'set ark base target';

my $arkurl = $arkbase . "/bar";		# extend it
#$x = resolve_stdin("--verbose", $arkurl);
$x = resolve_stdin('', $arkurl);
shellst_is 0, $x, "get resolve mode _t extension status";

like $x, qr|^redir302 zaf/bar\n|, "got _t extension value";

$arkurl = $arkbase . "/bar//zif?zaf=ab&cd";
$x = resolve_stdin('', $arkurl);
like $x, qr,^redir302 zaf/bar//zif\?zaf=ab\&cd\n,,
	"got _t bigger extension value";

my $arkid = "ark:/13030/fk12 345";		# note internal space
$x = resolve_stdin('', $arkurl, $arkid, $arkurl);
#$x =~ s/\n\n$//;				# trim two extra newlines
like $x, qr,^redir302 zaf.*\nerror: .*\nredir302 zaf.*\n$,,
	"an error in --rrm mode doesn't disturb subsequent resolutions";

#print("resolve: $arkurl, $arkid, $arkurl\n");
#print "x=$x";
#print "####### temporary stop ########\n"; exit;
#exit;

# Now some real world tests.

#my $host = "http://foo.example.com/";
$host = '';				# !! empty $host is more like it
my $shdr = "ark:/12345/xt2";
my $xtra = "rv8b";
my $nonxshdr = "ark:/12345/xt1$xtra";	# sorts before others for better test
my $nonxnaan = "ark:/12335/xt2$xtra";	# sorts before others for better test
my $noslash  = "ark:12345/xt2$xtra";
my $obj =  "$shdr$xtra";
my $ext = "/chap3/sect5//para4.txt.1.bak";
$arkurl = $host . $obj . $ext;

# A range of different targets so we can distinguish in testing.
my $ht = "http://host.example.com";
my $ot = "http://obj.example.com";
my $shdt = "http://obj.example.com/datasets/";
my $ct = "http://chap.example.com";
my $st = "http://sect.example.com";
my $st2 = "http://sect2.example.com";
my $st3 = "http://ezid.cdlib.org/id";

$x = `$cmd "$host$obj".set _t "$ot"`;
$x = `$cmd "$host$obj/chap3/".set _t "$ct"`;		# note terminal /
$x = `$cmd "$host$obj/chap3/sect5".set _tt "$st"`;	# note two t's

# Next line removes target at $obj and adds a target at $shdr.
$x = `$cmd "$host$obj".rm _t`;
$x = `$cmd "$host$shdr".set _t "$shdt"`;

#$x = resolve_stdin("--verbose", $arkurl);
$x = resolve_stdin('', $arkurl);
like $x, qr/\Q$shdt$xtra$ext/,		# xxx should be using \Q throughout
	'stops at first-digit shoulder to do spt';
# contains obj.example.com/datasets/rv8b/chap3

$x = resolve_stdin('', $host . $noslash . $ext);
like $x, qr/\Q$shdt$xtra$ext/,
	'ark:NNNNN normalization to ark:/NNNNN on resolution';

$x = `$cmd "$host$obj".set _t "$ot"`;	# restore what we removed earlier

$x = resolve_stdin("--verbose", "$host$nonxshdr");
like $x, qr/skipping chopback; no keys start/,
	'non-existent shoulder skips chopback call';

#$x = `$cmd "$host$nonxnaan".set _t "$ot"`;	# restore what we removed earlier
#my $nonxnaan = "ark:/12335/xt2$xtra";	# sorts before others for better test
#$x = resolve_stdin("--verbose", "$host$nonxnaan");
#like $x, qr/skipping chopback; no keys start/,
#	'non-existent shoulder skips chopback call';

# xxx then do URN
# xxx then do non-existent NAAN

$x = resolve_stdin('', $arkurl);
like $x, qr/$ot.*$ext/, 'long url suffix and suffix passthrough (spt)';

$x = `$cmd "$host$shdr".set _t_am n`;		# set no SPT flag
$x = resolve_stdin("--verbose", $arkurl);
like $x, qr/ancestor processing disallowed at shoulder/,
	'spt stopped by "_t_am n" element (flag) set on shoulder';

$x = `$cmd "$host$shdr".rm _t_am`;		# unset no SPT flag
$x = resolve_stdin('', $arkurl);
like $x, qr/$ot.*$ext/,
	'spt resumed after removing _t_am flag from shoulder';

$x = `$cmd "$host$obj".set _t_am n`;		# set no SPT flag
$x = resolve_stdin("--verbose", $arkurl);
like $x, qr/ancestor processing disallowed at id/,
	'spt stopped by "_t_am n" element (flag) set on shoulder';

$x = `$cmd "$host$obj".rm _t_am`;		# unset no SPT flag
$x = resolve_stdin('', $arkurl);
like $x, qr/$ot.*$ext/,
	'spt resumed after removing _t_am flag from id';

$x = `$cmd "$host$obj/chap3".set _t "$ct"`;	 # no terminal /
$x = resolve_stdin('', $arkurl);
like $x, qr,$ct/sect5,, "spt matches don't occur on terminal delims";

$x = `$cmd "$host$obj/chap3/sect5".set _t "$st"`;	# note one t
$x = resolve_stdin('', $arkurl);
like $x, qr,$st//para4,, "element must match exactly in spt";

$x = `$cmd "$host$obj/chap3/sect5".add _t "$st2"`;	# add dup
$x = resolve_stdin('', $arkurl);

if ($v1bdb) {
  ok(($x =~ qr/sect.example/ && $x =~ qr/sect2.example/),
  	"dup targets with spt");
#print "xxx x=$x\n";
}
else {
  like $x, qr,sect.example.* .*sect2.example,,
  	"dup targets with spt in order";
}

$url = "http://e.d.f/ark:/12345/xyzzy";
$x = resolve_stdin('', $url);
like $x, qr,^redir302 \n$,,
	"completely not found resolves to empty redirect";

# test that chopping doesn't back up past the object
$x = `$cmd "$host$obj".set _t ""`;		# "removes" intermediate target
$x = `$cmd "$host$obj/chap3".delete _t`;		# delete target
$x = `$cmd "$host$obj/chap3/sect5".delete _t`;	# delete target
#$x = `$cmd set "$host$obj/chap3/sect5" _t ""`;	# delete target
$x = `$cmd "$host".set _t "$ht"`;		# shouldn't chop back here
$x = resolve_stdin('', $url);
like $x, qr,^redir302 \n$,, "no chopping back past object name";

#$x = `$cmd "$host".delete _t`;			# delete target
#$x = `$cmd ":idmap//ft([^x]+)x(.*)".set _t "\\\$2/g7h/\\\$1"`;
#$url = "http://g.h.i/ft89xr2t";
#$x = resolve_stdin('', $url);
#like $x, qr,r2t/g7h/89,, "rule-based idmap substitution";

$url = "http://a.b.c/elmer";

$x = `$cmd $url.set _t zaf`;
$x = `$cmd $url.add _t paf`;

$x = resolve_stdin('', $url);
if ($v1bdb) {
  like $x, qr/("zaf" "paf"|"paf" "zaf")\n$/,
  	"multiple targets without spt";
}
else {
  like $x, qr/inflect multi "zaf" "paf"/, "multiple targets without spt";
}

$ENV{EGG} = $egg_home;
remove_td($td);
}
