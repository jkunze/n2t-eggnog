use 5.10.1;
use Test::More qw( no_plan );

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $tdata, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
$ENV{EGG} = $hgbase;		# initialize basic --home and --testdata values

{
remake_td($td, $tdata);
my $x;

# Overload this test file with some cfq tests

$x = `$cmd cfq`;
shellst_is 0, $x, "no args cfq status is ok";

like $x, qr/usage/i, "no args produces cfq help text";

$x = `$cmd cfq xyzzy`;
shellst_is 1, $x, "non-existent key returns error status";

like $x, qr/undefined/i, "... and 'undefined' message text";

#one_check: 1		# one = true
#zero_check: 0		# zero value (false)
#false_check: false		# false = true
#empty_check:		# empty value (false)

$x = `$cmd cfq one_check`;
shellst_is 0, $x, "value of '1' key returns success";

$x = `$cmd cfq zero_check`;
shellst_is 1, $x, "value of '0' key returns failure";

like $x, qr/^0\n/, "... and 0 string";

$x = `$cmd -q cfq false_check`;
shellst_is 0, $x, "quiet check for value of 'false' returns success";

like $x, qr/^$/, "... and no string printed";

$x = `$cmd cfq empty_check`;
shellst_is 1, $x, "value of '' key returns failure";

$x = `$cmd help`;
shellst_is 0, $x, "no args help status is ok";

like $x, qr/Commands:.*\bset\b.*Other:.*resolution/si,
	'lists commands and other topics';

my $n = 100;
$x = `$cmd help set`;
like $x, qr/\bset\b.{$n,}/si,
	"help on set is at least $n bytes long";

$x = `$cmd help xyzzy`;
like $x, qr/unknown.*xyzzy.*Commands:.*Other:/si,
	'topic not found';

$x = `$cmd help usage`;
my $y = `$cmd usage`;
is $x, $y, 'help usage like usage';

remove_td($td, $tdata);
}
