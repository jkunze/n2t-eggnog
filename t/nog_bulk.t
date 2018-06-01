use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "nog";
$td or			# if error
	exit 1;
$ENV{NOG} = $hgbase;		# initialize basic --home and --bgroup values

# Use this subroutine to get actual commands onto STDIN (eg, bulkcmd).
#
sub run_cmds_on_stdin { my( $cmdblock )=@_;

	my $msg = flvl("> $td/getcmds", $cmdblock);
	$msg		and return $msg;
	return `$cmd - < $td/getcmds`;
}

{
remake_td($td);
my $x;
$ENV{NOG} = "$hgbase -p $td";

$x = `$cmd mkminter fk9`;
$x = `$cmd fk9.mint 1`;
like $x, qr/^fk9.*\n$/, 'make minter for fk9 shoulder';

$x = `$cmd mkminter kf2`;
$x = `$cmd kf2.mint 1`;
like $x, qr/^kf2.*\n$/, 'make minter for kf2 shoulder';

$x = run_cmds_on_stdin("");
like $x, qr/^$/s, "null command on stdin";

my $cmdblock;

$cmdblock = "
   

";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^$/s, "3 blank lines on stdin";

$x = run_cmds_on_stdin("fk9.mint 2");
like $x, qr/^(?:fk9.*\n){2}$/, "simple one-command block";

$cmdblock = "
kf2.mint 3
kf2.queue now granola
kf2.mint 1
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^(?:kf2.*\n){3}(?:granola\n){2}$/,
	'second minter with varied commands in block';

$cmdblock = "
fk9.mint 1
fk9.mint 1
kf2.mint 1
fk9.mint 1
fk9.mint 1
kf2.mint 1
";

$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^(?:fk9.*\nfk9.*\nkf2.*\n){2}$/,
	'one command block, two different minters';

$ENV{NOG} = "$hgbase --verbose -p $td";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^(?:.*opening.*\n.*previously.*\n.*opening.*\n){2}$/s,
	'that command block called opened 6 times, re-using twice';

remove_td($td);
}
