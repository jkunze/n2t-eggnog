use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd) = script_tester "egg";
my $egg_home = "--home $td";
$ENV{EGG} = $egg_home;

use File::Egg;
{
remake_td($td);
my $x;

$x = `$cmd --verbose -p $td mkbinder foo`;
shellst_is 0, $x, "simple mkbinder for binder named foo";

is +(-f "$td/foo/egg.bdb"), 1,
	'created binder upper directory and bdb file';

is +(-f "$td/foo/egg_README" && -f "$td/foo/egg_lock"), 1,
	'created binder README and lock files';

# xxx create routine to auto-verify health of a binder, add namaste tags, etc
use File::Namaste;
(undef, $x, undef) = File::Namaste::nam_get("$td/foo", 0);
is $x, "$td/foo/0=egg_$File::Egg::VERSION",
	"namaste dirtype tag created";

$x = `$cmd --verbose -p $td mkbinder foo/bar`;
shellst_is 0, $x, "mkbinder for compound binder name foo/bar";

$x = `$cmd --verbose -p $td mkbinder foo/zaf`;
shellst_is 0, $x, "mkbinder for 2nd compound binder name foo/zaf";

$x = `$cmd --verbose -p $td mkbinder foo/zaf`;
like $x, qr/error:.*clobber/s,
	"mkbinder for existing binder causes complaint";

$x = `$cmd --verbose -d $td/foo/bar a.set b c`;
shellst_is 0, $x, "bind status ok for compound binder";

$x = `$cmd --verbose -d $td/foo/zaf a.set b d`;
shellst_is 0, $x,
	"bind status ok for 2nd compound binder, same id/elem, different value";

my $y;
$x = `$cmd -d $td/foo/bar/egg.bdb a.get b`;
$y = `$cmd -d $td/foo/zaf a.get b`;

is $x, "c\n\n",
	"1st binder value good, with binder fiso_dname extension";

is $y, "d\n\n", "2nd binder value good (no conflict with 1st binder)";

remake_td($td);
$x = `$cmd --verbose -p $td mkbinder foo`;
shellst_is 0, $x, "mkbinder with pre-command binder arg";

is +(-f "$td/foo/egg.bdb"), 1,
	'again created binder upper directory and bdb file';

remake_td($td);
$x = `$cmd --verbose -p $td mkbinder foo`;
shellst_is 0, $x, "mkbinder as method of object-like minder";

is +(-f "$td/foo/egg.bdb"), 1,
	'again created binder upper directory and bdb file';

remake_td($td);
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

remake_td($td);
$ENV{MINDERPATH} = $td;
$x = `$cmd mkbinder --verbose foo`;
like $x, qr|created.*foo|, "MINDERPATH from env";

$ENV{MINDERPATH} = "$td/foo/egg_README";
$x = `$cmd mkbinder foo`;
like $x, qr|error:.*$td/foo/egg_README/foo|, "bad MINDERPATH from env";

remake_td($td);
# -p $td puts most binders below in $td
$ENV{EGG} = "$egg_home -p $td -d $td/bar";

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

{			# tests for when binder is missing
remake_td($td);
$ENV{EGG} = $egg_home;
$ENV{MINDERPATH} = $td;		# switch to just env variable influence
my $x;

$x = `$cmd --verbose a.set b c`;
like $x, qr|creating default.*binder1|, "implicit default binder created";

$x = `$cmd a.get b`;
like $x, qr|^c$|m, "implicit default binder stored a value";

remake_td($td);
$ENV{MINDERPATH} = $td;		# switch to just env variable influence

# XXX should this case be silent?  (eg, "hg init" is silent)
$x = `$cmd --verbose mkbinder`;
like $x, qr|creating default.*binder1|,
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

{		# tests with multiple binders
remake_td($td);
my $x;

$x = `$cmd --verbose mkbinder -d $td/a/foo`;
like $x, qr|created.*foo|, "created binder in subdir a";

$x = `$cmd --verbose mkbinder -d $td/b/foo`;
like $x, qr|created.*foo|, "created binder in subdir b";

$x = `$cmd --verbose mkbinder -d $td/c/foo`;
like $x, qr|created.*foo|, "created binder in subdir c";

$x = `$cmd --verbose mkbinder -d $td/d/bar`;
like $x, qr|created.*bar|, "created binder in subdir d";

$ENV{EGG} = "$egg_home -p $td/a:$td/b:$td/c";

$x = `$cmd mkbinder foo`;
like $x, qr|error:.*clobber|s, "complaint about clobbering existing binder";

my $minderhome = "$td/d";
$ENV{EGG} = "$egg_home -p $minderhome:$td/a:$td/b:$td/c";

$x = `$cmd mkbinder foo`;
like $x, qr|error:.*3 instance|, "complaint about occluding existing binders";

$x = `$cmd --force --verbose mkbinder foo `;
like $x, qr|created.*foo|, "make complaint disappears with --force";

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
remove_td($td);
}
