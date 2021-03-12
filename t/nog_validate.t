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

{	# Validate tests -- short
remake_td($td, $tdata);
$ENV{MINDERPATH} = $td;
$ENV{NOG} = "$hgbase --format ANVL";
my ($x, $y);

$x = `$cmd mkminter --type rand --atlast stop fk edek`;
$y = flvl("< $td/fk/nog_README", $x);
like $x, qr/Size:\s*8410\n/, 'make 2-digit random minter';

my $id = "fk491f";
$x = `$cmd fk mint 1`;
like $x, qr/^s: $id\n/, 'first quasi random id is same as always';

$x = `$cmd fk validate - $id`;
like $x, qr/^s:\s*$id\n/, 'validate id that we just minted';

$x = `$cmd fk validate - fk492f`;
like $x, qr/^spingerr:/, 'detect single digit change';

$x = `$cmd fk validate - fk419f`;
like $x, qr/^spingerr:/, 'detect transposition of adjacent digits';

$x = `$cmd validate "fk{edek}" fk491f`;
like $x, qr/^s:\s*$id\n/, 'supplied template and no minter';

$x = `$cmd validate "{edeed}" 12345 b3th5`;
like $x, qr/12345.*b3th5/s, 'supplied template, 2 ids, no shoulder';

$x = `$cmd validate "{edeed}" 12345 b3th54 b3th5`;
like $x, qr/12345.*spingerr:\s*b3th54.*b3th5/s,
	'supplied template, 3 ids, middle one bad';

$x = `$cmd validate "x{edeed}y" 12345`;
like $x, qr/error:.*template/s, 'bad template';

remove_td($td, $tdata);
}
