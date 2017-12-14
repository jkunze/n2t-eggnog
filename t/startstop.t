use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "nog";
$ENV{NOG} = $hgbase;		# initialize basic --home and --bgroup values

{	# do --type and --atlast combinations

$ENV{NOG} = "$hgbase -p $td";
my ($x, $y);

remake_td($td);		# seq stop
$x = `$cmd mkminter --type seq --oklz 1 --atlast stop zk d`;
shellst_is 0, $x, "mkminter seq stop 1-digit oklz";

$x = `$cmd zk.mint 15`;
shellst_is 1, $x, "overmint status complaint";

like $x, qr/(zk\d\n){10}.*exhausted/s,
	"minted 10 with overmint message complaint";

remake_td($td);		# seq wrap
$x = `$cmd mkminter --type seq --oklz 1 --atlast wrap zk d`;
shellst_is 0, $x, "mkminter seq wrap 1-digit, --oklz 1";

$x = `$cmd --wrap 0 zk.mint 15`;
shellst_is 0, $x, "overmint status non-complaint";

my $resets = ($x =~ s/^note:.*resetting.*\n(\s+.*\n)?//gm);
is $resets, 1, 'a reset occurred with non-error message (note)';
#print "xxx x was $x\n";

like $x, qr/^(zk\d\n){15}\s*$/s,
	"minted 15, no complaints";

like $x, qr/zk4.*zk4\s*$/s, 'final id minted was minted before';

remake_td($td);		# seq add1, oklz 1
$x = `$cmd mkminter --type seq --oklz 1 --atlast add1 zk d`;
$x = `$cmd zk.mint 15`;
shellst_is 0, $x, "overmint status non-complaint";

my $cadded = ($x =~ s/^.*chars added.*\n//gm);
is $cadded, 1, 'template expansion occurred';

remake_td($td);		# seq add1
$x = `$cmd mkminter --type seq --atlast add1 zk d`;
shellst_is 0, $x, "mkminter seq add1 1-digit, implied --oklz 0";

$x = `$cmd zk.mint 15`;
shellst_is 0, $x, "overmint status non-complaint";

like $x, qr/^(zk[1-9]\n){9}(zk[1-9]\d\n){6}\s*$/s,
	"minted 15, again no complaints";

like $x, qr/zk1\n.*zk15\s*$/s, 'final id minted has 2 digits';

remake_td($td);		# seq add (default: add1)
$x = `$cmd mkminter --type seq --atlast add zk d`;
shellst_is 0, $x, "mkminter seq add 1-digit";

$y = flvl("< $td/zk/nog_README", $x);
like $x, qr/^Atlast:\s*add1$/m, 'add defaulted to add1';

remake_td($td);		# seq (default: add1)
$x = `$cmd mkminter --type seq zk d`;
shellst_is 0, $x, "mkminter seq 1-digit";

$y = flvl("< $td/zk/nog_README", $x);
like $x, qr/^Atlast:\s*add1$/m, 'seq mask and no atlast defaulted to add1';

remake_td($td);		# rand (default: add3)
$x = `$cmd mkminter --type rand zk`;
shellst_is 0, $x, "mkminter rand 1-digit";

$y = flvl("< $td/zk/nog_README", $x);
like $x, qr/^Atlast:\s*add3$/m, 'rand no mask and no atlast defaulted to add3';

remake_td($td);		# type default: rand
$x = `$cmd mkminter zk2`;
shellst_is 0, $x, "mkminter, nought but shoulder given";

$y = flvl("< $td/zk2/nog_README", $x);
like $x, qr/^Atlast:\s*add3$/m, 'default add3';

like $x, qr/:\s*rand$/m, 'default rand';

like $x, qr/Template:\s*zk2\{eedk\}$/m, 'default mask';

my $n = 8409;
$x = `$cmd zk2.mint $n`;
shellst_is 0, $x, "(long test) $n minted up to next to last in template";

$x = `$cmd zk2.mint 2`;
shellst_is 0, $x, "minted two more ids to mask expansion";

like $x, qr/zk2\w\w\d\w\nzk2\w\w\d\w\w\d\w\n/,
	'2nd id (expanded) has 3 more chars than 1st';
}
