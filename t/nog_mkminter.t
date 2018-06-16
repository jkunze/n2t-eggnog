use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "nog";
$td or			# if error
	exit 1;
$ENV{NOG} = $hgbase;		# initialize basic --home and --bgroup values

{
remake_td($td);
my ($x, $y);

$x = `$cmd --verbose -p $td mkminter fz`;
shellst_is 0, $x, "simple mkminter for minter named fz";

is +(-f "$td/fz/nog.bdb"), 1,
	'created minter upper directory and bdb file';

is +(-f "$td/fz/nog_README" && -f "$td/fz/nog.rlog"
		&& -f "$td/fz/nog_lock"), 1,
	'created minter README, log, and lock files';
# xxx create routine to auto-verify health of a minder, add namaste tags, etc

remake_td($td);
$x = `$cmd --verbose -p $td fz mkminter`;
shellst_is 0, $x, "mkminter with pre-command minter arg";

is +(-f "$td/fz/nog.bdb"), 1,
	'again created minter upper directory and bdb file';

remake_td($td);
$x = `$cmd --verbose -p $td fz.mkminter`;
shellst_is 0, $x, "mkminter as method of object-like minder";

is +(-f "$td/fz/nog.bdb"), 1,
	'again created minter upper directory and bdb file';

$x = `$cmd --verbose -p $td fz.mkminter`;
like $x, qr/error:.*exists/s,
	"mkminter for existing minter causes complaint";

remake_td($td);
$x = `$cmd --verbose -p $td set a b c`;
shellst_is 1, $x, "nog doesn't know 'bind' command";

$x = `$cmd --version`;
shellst_is 0, $x, "test of --version";

$x = `$cmd version`;
shellst_is 0, $x, "test of version command";

like $x, qr/This is "nog" version/, "was a nog version request";

remake_td($td);
$ENV{MINDERPATH} = $td;
$x = `$cmd mkminter fz`;
$y = flvl("< $td/fz/nog_README", $x);
like $x, qr|Creation record|, "MINDERPATH from env";

$ENV{MINDERPATH} = "$td/fz/nog_README";
$x = `$cmd mkminter fz`;
like $x, qr|error:.*$td/fz/nog_README/fz|, "bad MINDERPATH from env";

remake_td($td);
$ENV{NOG} = "$hgbase -p $td -d $td/bar";	# -p $td puts most minters below in $td
$x = `$cmd mkminter`;
$y = flvl("< $td/bar/nog_README", $x);
like $x, qr|Creation record|,
	"-d option passed from env, overriding MINDERPATH";

is +(-f "$td/bar/nog.bdb"), 1,
	'... and created bar minter upper directory and bdb file';

$x = `$cmd -d $td/fz mkminter`;
$y = flvl("< $td/fz/nog_README", $x);
like $x, qr|Creation record|, "-d on command overrides -d passed from env";

is +(-f "$td/fz/nog.bdb"), 1,
	'... and created fz minter upper directory and bdb file';

$x = `$cmd -d $td/fz zaf.mkminter`;
$y = flvl("< $td/zaf/nog_README", $x);
like $x, qr|Creation record|, "object-like minder overrides both";

is +(-f "$td/zaf/nog.bdb"), 1,
	'... and created zaf minter upper directory and bdb file';

$x = `$cmd -d $td/fz yaz mkminter`;
$y = flvl("< $td/yaz/nog_README", $x);
like $x, qr|Creation record|, "pre-command minder also overrides both";

is +(-f "$td/yaz/nog.bdb"), 1,
	'... and created yaz minter upper directory and bdb file';

$x = `$cmd -d $td/fz yaz mkminter zzf`;
$y = flvl("< $td/zzf/nog_README", $x);
like $x, qr|Creation record|, "post-command minder overrides all three";

is +(-f "$td/zzf/nog.bdb"), 1,
	'... and created zzf minter upper directory and bdb file';

# xxx try with combined shoulder and blade
remake_td($td);
$x = `$cmd -d $td/fz yaz mkminter -t rand --atlast stop "" de`;
$y = flvl("< $td/yaz/nog_README", $x);
like $x, qr|Creation record|,
	"null shoulder to mkminder correctly uses pre-command minter name";
}

{			# tests for when minder is missing
remake_td($td);
$ENV{NOG} = $hgbase;
$ENV{MINDERPATH} = $td;		# switch to just env variable influence
my $x;

$x = `$cmd -p $td --verbose mint 1`;
like $x, qr|creating default minter.*\n99999/df4..\d.\n|s,
	"implicit default minter created before minting its first id";

remake_td($td);

$x = `$cmd --verbose mkminter`;
like $x, qr|creating default.*99999/df4|,
	"first mkminter without arg creates default";

# XXX should match {ad}
$x = `$cmd mkminter`;
like $x, qr|creating new minter|,
	"second mkminter without arg creates a second minter";

# XXX should match {ad}
$x = `$cmd mkminter`;
like $x, qr|creating new minter|,
	"third mkminter without arg creates a third minter";

# XXX should be {ad}{eedk}
$x = `$cmd -d $td/50 mint 1`;
like $x, qr|^\w\d\w\w\d\w$|m, "get value from third minter matching {ed}{eedk}";

}

{		# tests with multiple minders
remake_td($td);
my ($x, $y);

$x = `$cmd mkminter $td/a/foo`;
like $x, qr|warning.*shoulder|s,
	"warning about shoulder with default template and check char";

$x = `$cmd mkminter -d $td/a/foo`;
$y = flvl("< $td/a/foo/nog_README", $x);
like $x, qr|Creation record|, "created minder in subdir a";

$x = `$cmd mkminter -d $td/b/foo`;
$y = flvl("< $td/b/foo/nog_README", $x);
like $x, qr|Creation record|, "created minder in subdir b";

$x = `$cmd mkminter -d $td/c/foo/nog.bdb`;
$y = flvl("< $td/c/foo/nog_README", $x);
like $x, qr|Creation record|,
	"created minder in subdir c, using fiso_dname extension";

$x = `$cmd mkminter -d $td/d/bar`;
$y = flvl("< $td/d/bar/nog_README", $x);
like $x, qr|Creation record|, "created minder in subdir d";

$ENV{NOG} = "$hgbase -p $td/a:$td/b:$td/c";

$x = `$cmd mkminter foo dde`;
like $x, qr|error:.*clobber|s, "complaint about clobbering existing minder";

my $minderhome = "$td/d";
$ENV{NOG} = "$hgbase -p $minderhome:$td/a:$td/b:$td/c";

$x = `$cmd mkminter foo dde`;
like $x, qr|error:.*3 instance|, "complaint about occluding existing minders";

$x = `$cmd --force --verbose mkminter foo dde`;
like $x, qr|created.*/d/foo/nog.bdb|, "make complaint disappear with --force";

$x = `$cmd rmminter xyzzy`;
like $x, qr|error:.*exist|, "removing a non-existent minder";

$x = `$cmd --force rmminter xyzzy`;
like $x, qr|^$|s,
	"remove complaint for non-existent minder disappears with --force";

# xxx retest after snag_dir used and test for first no terminal version number
#     and again later for terminal version num ber
my $trashmdr = "$minderhome/trash/foo1";	# xxx change foo1->foo

$x = `$cmd mshow`;
like $x, qr|^($td/.*\n){5}$|s, "show exactly 5 known minders";

$x = `$cmd rmminter foo`;
like $x, qr|moved.*trash.*$trashmdr|s, "removed minder by renaming to trash";

$x = `$cmd -d $trashmdr mint 1`;
like $x, qr|^foo\d\d\w$|m, "mint value from still functioning minter sitting in trash";

$x = `$cmd -d $trashmdr rmminter`;
like $x, qr|removed.*$trashmdr.*from trash|s, "removed minder from trash";

$x = `$cmd mshow`;
like $x, qr|^($td/.*\n){4}$|s, "show exactly 4 known minders";

$x = `$cmd -d ghost mint 1`;
like $x, qr|cannot find minter|, "error message for non-existent minter";

$x = `$cmd ghost.mint 1 `;
like $x, qr|cannot find minter|, "error message for non-existent minter";

# yyy keep pace with mkbinder tests
remove_td($td);
}
