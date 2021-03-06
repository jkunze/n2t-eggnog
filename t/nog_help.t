use 5.10.1;
use Test::More qw( no_plan );

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $tdata, $hgbase, $indb, $exdb) = script_tester "nog";
$td or			# if error
	exit 1;
$ENV{NOG} = $hgbase;		# initialize basic --home and --testdata values

{
remake_td($td, $tdata);
my $x;

$x = `$cmd help`;
shellst_is 0, $x, "no args help status is ok";

like $x, qr/Commands:.*\bmint\b.*Other:.*algorithm/si,
	'lists commands and other topics';

my $n = 100;
$x = `$cmd help mint`;
like $x, qr/\bmint\b.{$n,}/si,
	"help on mint is at least $n bytes long";

$x = `$cmd help xyzzy`;
like $x, qr/unknown.*xyzzy.*Commands:.*Other:/si,
	'topic not found';

$x = `$cmd help usag`;
my $y = `$cmd usage`;
is $x, $y, 'help usage like usage';

remove_td($td, $tdata);
}
