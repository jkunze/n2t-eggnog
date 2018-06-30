use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

use EggNog::Egg;
{
remake_td($td, $bgroup);
my $x;

$x = `$cmd --verbose -p $td mkbinder foo`;
shellst_is 0, $x, "simple mkbinder for binder named foo";

$indb and
is +(-f "$td/foo/egg.bdb"), 1,
	'created binder upper directory and bdb file';

$indb and
is +(-f "$td/foo/egg_README" && -f "$td/foo/egg_lock"), 1,
	'created binder README and lock files';

# xxx create routine to auto-verify health of a binder, add namaste tags, etc
use File::Namaste;
(undef, $x, undef) = File::Namaste::nam_get("$td/foo", 0);
$indb and
is $x, "$td/foo/0=egg_$EggNog::Egg::VERSION",
	"namaste dirtype tag created";

$x = `$cmd --verbose -p $td mkbinder foo/bar`;
shellst_is 0, $x, "mkbinder for compound binder name foo/bar";

$x = `$cmd --verbose -p $td mkbinder foo/zaf`;
shellst_is 0, $x, "mkbinder for 2nd compound binder name foo/zaf";

$x = `$cmd --verbose -p $td mkbinder foo/zaf`;
like $x, qr/error:.*already exists/s,
	"mkbinder for existing binder causes complaint";

$x = `$cmd --verbose -d $td/foo/bar a.set b c`;
shellst_is 0, $x, "bind status ok for compound binder";

$x = `$cmd --verbose -d $td/foo/zaf a.set b d`;
shellst_is 0, $x,
	"bind status ok for 2nd compound binder, same id/elem, different value";

my $y;
$x = `$cmd -d $td/foo/bar/egg.bdb a.get b`;
$y = `$cmd -d $td/foo/zaf a.get b`;

$exdb and
is $x, "d\n\n",
	"exdb: -d ignored, default binder used instead";

$indb and
is $x, "c\n\n",
	"1st binder value good, with binder fiso_dname extension";

is $y, "d\n\n", "2nd binder value good (no conflict with 1st binder)";

remake_td($td, $bgroup);
$x = `$cmd --verbose -p $td mint 1`;
shellst_is 1, $x, "binder doesn't know 'mint' command";

$x = `$cmd --version`;
shellst_is 0, $x, "test of --version";

$x = `$cmd version`;
shellst_is 0, $x, "test of version command";

like $x, qr/This is "egg" version/, "was a binder version request";

$x = `$cmd`;
shellst_is 0, $x, "no-args status";

like $x, qr/Usage:/s, "no-args output";

if ($indb) {

  remake_td($td, $bgroup);
  $ENV{MINDERPATH} = $td;
  $x = `$cmd mkbinder --verbose foo`;
  like $x, qr|created.*foo|, "MINDERPATH from env";
  
  $ENV{MINDERPATH} = "$td/foo/egg_README";
  $x = `$cmd mkbinder foo`;
  like $x, qr|error:.*$td/foo/egg_README/foo|, "bad MINDERPATH from env";
  
  remake_td($td, $bgroup);
  # -p $td puts most binders below in $td
  $ENV{EGG} = "$hgbase -p $td -d $td/bar";
  
  $x = `$cmd --verbose mkbinder`;
  like $x, qr|created.*bar|,
  	"-d option passed from env, overriding MINDERPATH";
  
  is +(-f "$td/bar/egg.bdb"), 1,
  	'... and created bar binder upper directory and bdb file';
  	#xxx print "x=$x\n";
  
  $x = `$cmd -d $td/foo --verbose mkbinder`;
  like $x, qr|created.*foo|, "-d on command overrides -d passed from env";
  
  is +(-f "$td/foo/egg.bdb"), 1,
  	'... and created foo binder upper directory and bdb file';
  	#xxx print "x=$x\n";
  
  # XXXX zaf not using -p!!!
  $x = `$cmd -d $td/foo --verbose mkbinder zaf`;
  like $x, qr|created.*zaf|, "object-like minder overrides both";
  
  is +(-f "$td/zaf/egg.bdb"), 1,
  	'... and created zaf binder upper directory and bdb file';
  
  #$x = `$cmd -d $td/foo --verbose mkbinder yaz`;
  #like $x, qr|created.*yaz|, "pre-command minder also overrides both";
  #
  #is +(-f "$td/yaz/egg.bdb"), 1,
  #	'... and created yaz binder upper directory and bdb file';
  
  $x = `$cmd -d $td/foo --verbose mkbinder oof`;
  like $x, qr|created.*oof|, "post-command minder overrides -d";
  
  is +(-f "$td/oof/egg.bdb"), 1,
  	'... and created oof binder upper directory and bdb file';
}
}

{			# tests for when binder is missing
remake_td($td, $bgroup);
$ENV{EGG} = $hgbase;
$ENV{MINDERPATH} = $td;		# switch to just env variable influence
my $x;
my $default_binder = $EggNog::Binder::DEFAULT_BINDER;

#$x = `$cmd --verbose a.set b c`;
#like $x, qr|creating default.*$default_binder|,
#	"implicit default binder created";

$x = `$cmd --verbose a.set b c`;
$x = `$cmd a.get b`;
like $x, qr|^c$|m, "implicit default binder created";
#like $x, qr|^c$|m, "implicit default binder stored a value";

$x = `$cmd bshow td_egg`;

$x = `$cmd -d $td/binder3 a.set b c`;
if ($exdb) {
  $x = `$cmd -d $td/binder3 a.get b`;
  like $x, qr|^c$|m, "no exdb binder name derived from directory";
}

$x = `$cmd bshow td_egg`;

remake_td($td, $bgroup);
$ENV{MINDERPATH} = $td;		# switch to just env variable influence

if ($indb) {
  # XXX should this case be silent?  (eg, "hg init" is silent)
  $x = `$cmd --verbose mkbinder`;
  like $x, qr|creating default.*$default_binder|,
  	"first mkbinder without arg creates default";
  
  $x = `$cmd --verbose mkbinder`;
  like $x, qr|created.*binder2|,
  	"second mkbinder without arg creates binder2";
  
  $x = `$cmd --verbose mkbinder`;
  like $x, qr|created.*binder3|,
  	"third mkbinder without arg creates binder3";
  
  $x = `$cmd -d $td/binder3 a.set b c`;
  $x = `$cmd -d $td/binder3 a.get b`;
  like $x, qr|^c$|m, "get value from binder3";
}

}

remove_td($td, $bgroup);

{		# tests with multiple binders
remake_td($td, $bgroup);
my $x;
my $minderhome;

$x = `$cmd --verbose mkbinder -d $td/a/foo`;

if ($exdb) {
  like $x, qr|cannot be empty|, "exdb: cannot use empty binder name";
}

if ($indb) {

  like $x, qr|created.*foo|, "created binder in subdir a";
  
  $x = `$cmd --verbose mkbinder -d $td/b/foo`;
  like $x, qr|created.*foo|, "created binder in subdir b";
  
  $x = `$cmd --verbose mkbinder -d $td/c/foo`;
  like $x, qr|created.*foo|, "created binder in subdir c";
  
  $x = `$cmd --verbose mkbinder -d $td/d/bar`;
  like $x, qr|created.*bar|, "created binder in subdir d";
  
  $ENV{EGG} = "$hgbase -p $td/a:$td/b:$td/c";
  
  $x = `$cmd mkbinder foo`;
  like $x, qr|error:.*already exists|s,
  	"complaint about clobbering existing binder";
  
  $minderhome = "$td/d";
  $ENV{EGG} = "$hgbase -p $minderhome:$td/a:$td/b:$td/c";
  
  $x = `$cmd mkbinder foo`;
  like $x, qr|error:.*3 instance|, "complaint about occluding existing binders";
  
  $x = `$cmd --force --verbose mkbinder foo `;
  like $x, qr|created.*foo|, "make complaint disappear with --force";
}

# XXX bug when using -d and rmbinder

$x = `$cmd rmbinder xyzzy`;
like $x, qr|error:.*exist|, "removing a non-existent binder";

$x = `$cmd --force rmbinder xyzzy`;
like $x, qr|^$|s,
	"remove complaint for non-existent binder disappears with --force";

# xxx retest after snag_dir used and test for first no terminal version number
#     and again later for terminal version num ber
my $trashmdr = "$minderhome/trash/foo1";	# xxx change foo1->foo

$x = `$cmd bshow`;
like $x, qr|^#.*\n($td/[^\n]*\n){5}#|s, "show exactly 5 known binders";

#say "xxx premature end"; exit;

$x = `$cmd rmbinder foo`;
like $x, qr|moved.*trash.*$trashmdr|s, "removed binder by renaming to trash";

$x = `$cmd -d $trashmdr a.set b c`;
$x = `$cmd -d $trashmdr a.get b`;
like $x, qr|^c$|m, "get value from still functioning binder sitting in trash";

$x = `$cmd -d $trashmdr rmbinder`;
like $x, qr|removed.*$trashmdr.*from trash|s, "removed binder from trash";

$x = `$cmd bshow`;
like $x, qr|^#.*\n($td/[^\n]*\n){4}#|s, "show exactly 4 known binders";

$x = `$cmd mkbinder -d $td/c/e/zaf`;
$x = `$cmd -d $td/c/e/zaf idx.set elemy valz`;
$x = `$cmd --minder e/zaf idx.get elemy`;
like $x, qr|valz|, "--minder searches for binder at bottom of path";

#$x = `$cmd --minder e/zaf idx.bring elemy`;
#like $x, qr|valz|, "--minder searches for binder at bottom of path";

$x = `$cmd -d ghost i.set a b`;
like $x, qr|cannot find binder|, "error message for non-existent binder";

$x = `$cmd "<ghost>i.set" a b`;
like $x, qr|cannot find binder|, "error message for non-existent binder";

# yyy keep pace with mkminter
remove_td($td, $bgroup);
}
