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
my $x;

$x = `$cmd`;
shellst_is 0, $x, "no args status is ok";

$x = `$cmd`;
like $x, qr/commands/si,
	'nog no args generates useful info';

$x = `$cmd gen`;
like $x, qr/^[a-z0-9_~]{22}\s*$/si,
	'"gen" generates a nice uuid';

$x = `$cmd gen 1`;
like $x, qr/^[a-z0-9_~]{22}\s*$/si,
	'"gen 1" same as "gen"';

$x = `$cmd gen 4`;
like $x, qr/^([a-z0-9_~]{22}\n){4}\s*$/si,
	'4 ids at once';

# yyy we won't test niceness levels greater than 0 because the testing
#     process can hang for a long time
#$x = `$cmd gen 1 1`;
#like $x, qr/^([a-z][a-z0-9_]){21}\n\s*$/si,
#	'nice level 1 means id starts with letter and has no ~';

remove_td($td);
}
