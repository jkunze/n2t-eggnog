use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "nog";
$ENV{NOG} = $hgbase;		# initialize basic --home and --bgroup values

{
remake_td($td);
$ENV{MINDERPATH} = $td;
my ($x, $y);

$x = `$cmd mkminter -t seq --atlast stop --oklz 1 foo dd`;
$y = flvl("< $td/foo/nog_README", $x);
like $x, qr/Size:\s*100\n/, 'make 2-digit sequential minter, --oklz 1';

$x = `$cmd foo mint 1`;
like $x, qr/^foo00\n/, 'mint first id';

$x = `$cmd foo hold set foo01`;
shellst_is 0, $x, 'hold what would be next id';

$x = `$cmd foo mint 1`;
like $x, qr/^foo02\n/, 'mint next skips the id we just held';

$x = `$cmd -m anvl foo queue now foo01`;
shellst_is 1, $x, 'status for failed queue op';

like $x, qr/^error:.*hold.*release/s,
	'stopped when trying to put held id into queue';
#like $x, qr/^foo01\n/,
#	'try to put held id into queue (old code had no need to release hold?)';
# yyy apparently we _do_ need to release hold (old code bug)?

$x = `$cmd foo hold release foo01`;
shellst_is 0, $x, 'release hold on id';

$x = `$cmd foo queue now foo01`;
shellst_is 0, $x, 'status for successful queue op';

like $x, qr/^foo01\n/,
	'put held id into queue (after releasing hold)';

$x = `$cmd foo mint 1`;
like $x, qr/^foo01\n/, 'mint next takes from queue (no genid)';

$x = `$cmd foo mint 1`;
like $x, qr/^foo03\n/, 'mint next generates a new id';

# Consumed 4 out of 100.  Now do a little scaling on remaining 96 ids.

$x = `$cmd -m anvl foo mint 90`;
my @ids = grep(s/^s:\s*//, split("\n", $x));
is scalar(@ids), 90, "mint most of the remaining ids";

my $idlist = join(" ", @ids);
$x = `$cmd --verbose -m anvl foo queue now $idlist`;
like $x, qr/^note:\s*90 identifiers processed/m,
	'queue those remaining ids for reminting';

$idlist = join(" ", @ids[0..44]);
$x = `$cmd --verbose foo hold set $idlist`;
like $x, qr/^45 holds/m, 'hold half those ids';

$x = `$cmd -m anvl foo mint 90`;
shellst_is 1, $x, "mint beyond capacity";
# XXX status should indicate partial success only (not fail, not success)

# Should have 96 - 90 + 45
@ids = grep(s/^s:\s*//, split("\n", $x));
is scalar(@ids), 51, "got 96-90+45 ids";

$x = `$cmd mkminter -t seq --oklz 1 --atlast stop bar dd`;
$x = `$cmd bar.hold set bar05 bar01 bar02 bar03 bar00`;
shellst_is 0, $x, "pre-hold 5 'legacy' ids, not in order";

$x = `$cmd bar.mint 2`;
like $x, qr/bar04.*bar06/s, 'mint of first two skips legacy ids';

$x = `$cmd bar.queue --verbose now bar99 bar96 bar97 bar98`;
like $x, qr/4 identifier/, 'queue 4 high ids';

$x = `$cmd bar.mint 1`;
like $x, qr/bar99/, 'mint pulls first newly queued';

$x = `$cmd bar.queue delete bar97`;
like $x, qr/bar97/, 'queue delete';

$x = `$cmd bar.mint 3`;
like $x, qr/bar96\s+bar98\s+bar0/s, 'mint next 3 skips deleted';

remove_td($td);
}
