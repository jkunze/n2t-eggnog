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
remake_td($td, $bgroup);
my ($x, $y, $n);

$x = `$cmd -p $td mkminter zk`;
shellst_is 0, $x, "make minter named zk";

is 1, (-f "$td/zk/nog.bdb"),
	'created minter upper directory and bdb file';

$x = `$cmd -d $td/zk mint 1`;
shellst_is 0, $x, "mint status ok with -d";

$x = `$cmd -d $td/zk -m anvl mint 10`;
is grep(/^s:/, split("\n", $x)), 10, "minted 10 ids";

like $x, qr/s:\s*zk\w\w\d\w\n/, "default minter template used";

#print "x=$x\n"; exit; #################

$x = `$cmd -p $td mkminter 99999/br`;
shellst_is 0, $x, "mkminter for compound minter name 99999/br";

$x = `$cmd -d $td/99999/br mint 1`;
shellst_is 0, $x, "mint status ok for compound minter";

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter 99999/br`;
shellst_is 0, $x, 'mkminter for compound minter name 99999/br';

$x = `$cmd -p $td mkminter 99999/fb`;
shellst_is 0, $x, 'mkminter for 2nd compound minter name 99999/fb';

$x = `$cmd -m anvl -d $td/99999/br mint 2`;
shellst_is 0, $x, 'mint status ok for compound minter';

like $x, qr|^s: 99999/br\w\w\d\w\n$|m, 'form of identifier';

$x = `$cmd -m anvl -p $td 99999/br dbinfo full`;
like $x, qr/GRANITE/, 'durability summary';

# XXXXXXX why does turning off dupes with O_RDONLY work?

$y = `$cmd -d $td/99999/fb mint 3`;
shellst_is 0, $x, 'mint status ok for compound minter, different stop';

$x = `$cmd -d $td/99999/br mint 1`;
$y = `$cmd -m anvl -d $td/99999/fb mint 1`;

isnt $x, $y, 'next minter values differ';

$x = `$cmd -m anvl -d $td/99999/br mint 1`;
like $x, qr/^s: /m, 'value checks out';

$x =~ s|99999/br||;
$x =~ s|.\s*$||s;
$y =~ s|99999/fb||;
$y =~ s|.\s*$||s;
is $x, $y,
	"caught-up minter's next value the same, minus check char and shoulder";

remove_td($td, $bgroup);
}

{
remake_td($td, $bgroup);		# rand stop with bad start

$ENV{NOG} = "$hgbase -p $td";
my ($x, $y);

# yyy --start option removed from nog; easier for user to implement
#       by just minting and tossing N spings before releasing the minter
#$x = `$cmd mkminter --type rand --start 10 --atlast stop zk d`;
#shellst_is 1, $x, "mkminter rand stop 1-digit with excessive start";
#
#like $x, qr/would exceed/, "start exceeds total with bounded minter";

#remake_td($td, $bgroup);		# rand stop
$x = `$cmd mkminter --type rand --atlast stop zk d`;
shellst_is 0, $x, "mkminter rand stop 1-digit";

$x = `$cmd -m anvl zk.mint 15`;
shellst_is 1, $x, "overmint status complaint";

like $x, qr/(s: zk\d\n){10}.*exhausted/s,
	"minted 10 with overmint message complaint";

remake_td($td, $bgroup);		# rand stop with status
$x = `$cmd mkminter --type rand --atlast stop7 zk d`;
shellst_is 0, $x, "mkminter rand stop with user-specified status";

$x = `$cmd zk.mint 15`;
shellst_is 7, $x, "overmint status complaint";

remake_td($td, $bgroup);		# rand wrap
$x = `$cmd mkminter --type rand --atlast wrap5 zk d`;
shellst_is 0, $x, "mkminter rand wrap 1-digit";

$x = `$cmd --format anvl zk.mint 22`;
shellst_is 5, $x, "overmint status same as configured";

#print "x=$x\n";

my $resets = ($x =~ s/^.*resetting.*\n(\s+.*)?//gm);
is $resets, 2, 'two resets occurred';

like $x, qr/^(s: zk\d\n){22}\s*$/s, "minted 22, no complaints";

like $x, qr/zk4.*zk4/s, 'minted at least 2 of a given id';

remake_td($td, $bgroup);		# rand add1
$x = `$cmd mkminter --type rand --atlast add1 zk d`;
shellst_is 0, $x, "mkminter rand add1 1-digit";

$x = `$cmd -m anvl zk.mint 20`;
shellst_is 0, $x, "overmint status non-complaint";

my $cadded = ($x =~ s/^.*chars added.*\n//gm);
is $cadded, 1, 'template exansion message';

like $x, qr/^(s: zk\d\n){10}(s: zk\d\d\n){10}\s*$/s,
	"minted 20, no complaints, last id has 2 digits";

$y = $x;	# save sequence to test against different germ (8 not 0)
remake_td($td, $bgroup);		# rand8 add1
$x = `$cmd mkminter --germ 9 --type rand --atlast add1 zk d`;
shellst_is 0, $x, "mkminter germ 9 rand add1 1-digit";

$x = `$cmd zk.mint 20`;
shellst_is 0, $x, "overmint status non-complaint (again)";

isnt $x, $y, "rand (germ 9) sequence differs from rand (germ 0) sequence";

$y = $x;	# save sequence to test against different seed (99 not 8)
remake_td($td, $bgroup);		# rand99 add1
$x = `$cmd mkminter --type rand --germ 99 --atlast add1 zk d`;
shellst_is 0, $x, "mkminter rand (germ 99) add1 1-digit";

$x = `$cmd zk.mint 20`;
shellst_is 0, $x, "again overmint status non-complaint";

isnt $x, $y, "germ 99 sequence differs from germ 9 sequence";

#remake_td($td, $bgroup);		# seq start 5 add1
#$x = `$cmd mkminter --type seq --start 5 --atlast add1 zk d`;
#shellst_is 0, $x, "mkminter seq start 5 add1 1-digit";
#
#$x = `$cmd -m anvl zk.mint 20`;
#shellst_is 0, $x, "overmint status non-complaint";
#
#like $x, qr/^s:\s*zk5/, "sequence starts at 5";
#
#remake_td($td, $bgroup);		# seq start 135 add1
##$x = `$cmd mkminter --type seq --start 135 --atlast add1 zk d`;
#shellst_is 0, $x, "mkminter seq start 135 add1 1-digit";
#
#$x = `$cmd zk.mint 20 -m anvl`;
#shellst_is 0, $x, "overmint status non-complaint";
#
#like $x, qr/^s:\s*zk135/, "sequence starts at 135 after two atlast events";

# xxx do --germ N arg, where N (def 0) == -1 -> random and -2 -> truly random
#     -1 def for 'deal'
# xxx test stop and wrap status settings

	remove_td($td, $bgroup);
	exit;

# XXXXXXXXXXXXXXXXXXXX incorporate these tests below

$x = `$cmd -p $td mint 1`;
shellst_is 0, $x, "mint with minderpath and implicit minter creation";

like $x, qr/implicit/, "verbose option and implicit creation worked";

$x = `$cmd -p $td mint 1`;
shellst_is 0, $x, "2nd mint with minderpath";

unlike $x, qr/implicit/, "no new minter created";

$ENV{NOG} = "$hgbase -p /tmp --verbose";
$x = `$cmd -p $td mint 1`;
shellst_is 0, $x, "3rd mint with args from env";

like $x, qr/minter set to.*$td/,
	"--verbose from env but -p overridden on command line";

#like $x, qr/$td/, "but -p was overridden by command args";

$ENV{NOG} = $hgbase;
$ENV{MINDERPATH} = "/tmp:$td:/usr";
$x = `$cmd mint 1`;
shellst_is 0, $x, "mint with MINDERPATH env var";

unlike $x, qr/implicit/, "same minter as before";

remake_td($td, $bgroup);

# cleared out existing minter, but $ENV{MINDERPATH} = "/tmp:$td:/usr";
$x = `$cmd mint 1`;
shellst_is 0, $x, "mint with MINDERPATH env var";

like $x, qr/implicit.*\/tmp/, "new minter in /tmp";
# if this test fails, it may be because /tmp minter wasn't removed last time

use File::Path;
my $def_mdr = "d5";
$x =~ qr/implicit.*\/tmp/ and $def_mdr ne "" and
	rmtree "new minter in /tmp";
	eval { rmtree("/tmp/$def_mdr"); };
	$@	and die "/tmp/$def_mdr: couldn't remove: $@";

$x = `$cmd -d ./fooble mint 1`;
shellst_is 2, $x, "complaint with mint for non-existent named minter";

#like $x, qr/implicit.* \.\/fooble/, "implicit creation in current dir";

remove_td($td, $bgroup);
}

