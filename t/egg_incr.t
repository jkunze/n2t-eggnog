use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

{
remake_td($td);
my $x;

$x = `$cmd --version`;
my $v1bdb = ($x =~ /DB version 1/);

$ENV{EGG} = "$hgbase -d $td/bindy";
$x = `$cmd mkbinder`;
shellst_is 0, $x, "make binder named bindy";

$x = `$cmd foo.set count 3`;
shellst_is 0, $x, 'simple set of elem "count" to 3 with bind status ok';

$x = `$cmd foo.incr count`;
shellst_is 0, $x, 'simple incr status ok';

$x = `$cmd foo.get count`;
like $x, qr/^4\n$/, 'incremented count to 4';

$x = `$cmd foo.incr count 5`;
$x = `$cmd foo.get count`;
like $x, qr/^9\n$/, 'incremented count by 5 to 9';

$x = `$cmd foo.decr count`;
$x = `$cmd foo.get count`;
like $x, qr/^8\n$/, 'decremented count to 8';

$x = `$cmd foo.decr count 6`;
$x = `$cmd foo.get count`;
like $x, qr/^2\n$/, 'decremented count by 6 to 2';

$x = `$cmd foo.decr count 2`;
$x = `$cmd foo.get count`;
like $x, qr/^0\n$/, 'decremented count by 2 to 0';

$x = `$cmd foo.set z 0`;
$x = `$cmd foo.get z`;
like $x, qr/^0\n$/, 'set to 0, gets 0';

$x = `$cmd foo.decr count`;
$x = `$cmd foo.get count`;
like $x, qr/^-1\n$/, 'decremented count to -1';

$x = `$cmd foo.incr a`;
$x = `$cmd foo.get a`;
like $x, qr/^1\n$/, 'incremented unset var to 1';

$x = `$cmd foo.decr b`;
$x = `$cmd foo.get b`;
like $x, qr/^-1\n$/, 'decremented unset var to -1';

$x = `$cmd foo.decr b`;
$x = `$cmd foo.get b`;
like $x, qr/^-2\n$/, 'decremented again to -2';

$x = `$cmd foo.incr b -1`;
$x = `$cmd foo.get b`;
like $x, qr/^-3\n$/, 'incremented by -1 to -3';

$x = `$cmd foo.decr b -9`;
$x = `$cmd foo.get b`;
like $x, qr/^6\n$/, 'decremented by -9 to result in 6';

$x = `$cmd foo.incr b -9876`;
$x = `$cmd foo.get b`;
like $x, qr/^-9870\n$/, 'incremented by -9876 to result in -9870';

$x = `$cmd foo.incr b +9976`;
$x = `$cmd foo.get b`;
like $x, qr/^106\n$/, 'incremented by +9876 to result in 106';

remove_td($td);
}
