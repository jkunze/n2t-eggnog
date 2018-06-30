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
my ($x, $y);

$x = `$cmd --verbose -p $td mkminter fk`;
shellst_is 0, $x, "make minter named fk";

is 1, (-f "$td/fk/nog.bdb"),
	'created minter upper directory and bdb file';

$x = `$cmd --verbose -d $td/fk mint 1`;
shellst_is 0, $x, "mint status ok with -d";

remake_td($td, $bgroup);
$x = `$cmd --verbose -p $td mkminter -t rand foo de`;
shellst_is 0, $x, "make minter with blade and -t rand";

$x = `$cmd -p $td foo mint 1`;
shellst_is 0, $x, "mint one id";

like $x, qr/^foo\d\w$/m, "form of identifier";

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter --type seq --atlast stop m1 d`;
$y = flvl("< $td/m1/nog_README", $x);
like $x, qr/Size:\s*10\n/, 'single digit sequential stopping template';

$x = `$cmd -p $td mkminter -t seq --atlast stop m2 dd`;
$y = flvl("< $td/m2/nog_README", $x);
like $x, qr/Size:\s*100\n/, '2-digit sequential stopping template';

$x = `$cmd -p $td -t seq mkminter m3 --atlast add1 ded`;
$y = flvl("< $td/m3/nog_README", $x);
like $x, qr/Size:\s*unlimited\n/, '3-digit unbounded sequential';

$x = `$cmd -p $td -t rand --atlast stop mkminter m4 eedde`;
$y = flvl("< $td/m4/nog_README", $x);
like $x, qr/Size:\s*2438900\n/, '6-digit random stopping template';

$x = `$cmd -p $td mkminter ab ddd -t rand --atlast stop`;
$y = flvl("< $td/ab/nog_README", $x);
like $x, qr/Size:\s*1000\n/, 'prefix vowels ok in general';

# template errors

# XXX should be able to do this without always setting --atlast
remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter -t rand --atlast stop ab dxdk`;
like $x, qr/parse_template: the mask .* may contain only the letters/,
	'bad mask char';

$x = `$cmd -p $td --type seq mkminter --atlast stop foo ddeek`;
like $x, qr/parse_template:.*check character.*reduced/,
	'bad shoulder char';
# xxx error message doesn't mention shoulder

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter --type rand --atlast stop ab dddk`;
#$y = flvl("< $td/ab/nog_README", $x);
#$x =~ s/\n/ /g;		# undo text wrap done by OM
like $x, qr/warning:.*check char.*reduced/s,
	'prefix vowels with check char produce warning';

remove_td($td, $bgroup);
}

{	# Set up a generator that we will test

my $x = `$cmd -p $td mkminter --type seq --atlast stop 8r9 dd`;
my $y = flvl("< $td/8r9/nog_README", $x);
like $x, qr/Size:\s*100\n/,
	'2-digit sequential minter (no leading zeroes)';

my $n = 1;
$x = `$cmd -p $td 8r9 mint 1`;
like $x, qr/8r910/, 'sequential mint test first (non-zero)';

$n = 99;
$x = `$cmd -d $td/8r9 mint 98`;
#$x = `$cmd -p $td 8r9.mint 1`;
like $x, qr/8r999/, 'sequential mint test last';

# XXXX cannot test this until we add wrap option
#$x = `$cmd -p $td 8r9.mint 1`;
#like $x, qr/8r900/, 'sequential mint test wraps back around to first id';

#remake_td($td, $bgroup);
#$x = `$cmd -p $td mkminter --type seq --atlast add1 99152/h{ddd}`;
#shellst_is 0, $x, "make --type 'seq' minter with 'add1'";
#
#$n = 1194;
#$x = `$cmd -p $td 99152/h --format ANVL mint $n`;
#print("xxxx spings x=$x\n");
#$x = `$cmd -p $td -m anvl 99152/h.dbinfo | grep -v '^%3a/c[0-9]'`;
#
#print("xxxx x=$x done\n");
#exit;

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter --type rand --atlast stop foo de`;
shellst_is 0, $x, "make minter with blade and --type rand";

$n = 290;	# number of ids possible from blade 'de' (10*29)
$x = `$cmd -p $td foo --format ANVL mint $n`;
shellst_is 0, $x, "mint all ids at once";

my (@xarray, @yarray);
@xarray = grep(/^s: foo\d\w$/, split "\n", $x);
is scalar(@xarray), $n, "minted at least $n ids";

$x = `$cmd -p $td foo.mint 1`;
shellst_is 1, $x, "correct status for minting beyond capacity";

# xxx bug to fix; repeat by removing --atlast stop in mkminter above
like $x, qr/exhausted/, "minter ran out";

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter --type rand foo de`;
shellst_is 0, $x, "make minter with blade, --type rand, and non-stopping";

$x = `$cmd -p $td foo.mint 291`;
shellst_is 0, $x, "correct status for minting just beyond initial capacity";

my %hash;
%hash = map {$_ => ($hash{$_} || 0) + 1} @xarray;
is grep(/^1$/, %hash), $n, "$n unique ids minted";

remake_td($td, $bgroup);
my @zarray;
$x = `$cmd -p $td mkminter --type rand --oklz 0 foo de`;
shellst_is 0, $x, "make minter --type rand --oklz 0";

$x = `$cmd -p $td foo.mint 291`;
@zarray = $x =~ m/^foo[^0]/mg;
is scalar(@zarray), 291, "that minter produces no leading zeroes";

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter --type rand --atlast add1 foo f`;
shellst_is 0, $x, "make minter --type rand with 'f' mask char (no digits)";

$x = `$cmd -p $td foo.mint 291`;
@zarray = $x =~ m/^foo[\w]+\n/mg;
is scalar(@zarray), 291, "and that minter produces no digits";

my $nskipped = 386;		# empirically observed; hope it's right
$x = `$cmd -p $td foo.mstat`;
like $x, qr/skipped.*mask.*: $nskipped/,
	"$nskipped spings skipped due to 'f' mask char";

#remake_td($td, $bgroup);
# XXX should be able to specify shoulder separate from minter name?
#$x = `$cmd -p $td br mkminter --type rand foo de`;

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter --type rand --atlast stop foo de`;
$x = `$cmd -m anvl -p $td foo mint $n`;
@yarray = grep(/^s: foo\d\w$/, split "\n", $x);
is scalar(@yarray), $n,
	'remaking same minter produces same number of ids';

1 while (($x = shift(@xarray)) and $x eq shift(@yarray));
is scalar(@yarray), 0,
	'remaking same minter produces identical quasi-random order';

remake_td($td, $bgroup);
#$x = `$cmd -p $td mkminter --type rand --atlast add2 foo dek`;
$x = `$cmd -p $td mkminter --type rand --atlast add1 foo ek`;
shellst_is 0, $x, "make random minter with --atlast add1";

$n = 29;			# number of spings before first expansion
$x = `$cmd -p $td -m anvl foo.mint $n`;

# XXX change id to $label globally
undef @xarray;
@xarray = grep(/^s: foo\d\w\w$/, split "\n", $x);
$y = `$cmd -p $td -m anvl foo.dbinfo`;
my ($oacounter) = $y =~ m@/oacounter: *(\d+)@;
is $oacounter, $n, "oacounter matches number ($n) of minted ids";

my $m = $n * $n;
$x = `$cmd -p $td -m anvl foo.mint $m`;		# mint up to 2nd expansion
undef @xarray;
@xarray = grep(/^s: foo\w\w\w$/, split "\n", $x);
my $top = scalar(@xarray);
is scalar(@xarray), $m,
	"mint $m spings on expanded template up to 2nd expansion point";

$y = `$cmd -p $td foo.mstat`;
my ($spings) = $y =~ m@spings minted: *(\d+)@;
is $spings, ($m + $n),
	"total minted correct after blade expansion";

remake_td($td, $bgroup);
$x = `$cmd -p $td mkminter --type rand --atlast add1 foo eek`;
$x = `$cmd -p $td -m anvl foo.mint $m`;		# mint on fresh minter
undef @yarray;
@yarray = grep(/^s: foo\w\w\w$/, split "\n", $x);
is scalar(@yarray), $top,
	"new minter matching previous expanded template mints $top spings";

my $matches = 0;
for (my $i = 0; $i < $top; $i++) {
	defined($yarray[$i]) or
		print("element $i of yarray undefined\n"),
		next;
	#print "$xarray[$i] $yarray[$i]\n";
	$xarray[$i] eq $yarray[$i] and
		#print("elements $i match\n"),
		$matches++;
}
is $matches, $top,
	"expanded template spings match same spings as unexpanded template";

#$y = `$cmd -p $td -m anvl foo.dbinfo`;
#($oacounter) = $y =~ m@/oacounter: *(\d+)@;
#is $oacounter, 1,
#	"oacounter reset to 1 after blade expansion";

#undef %hash;
#%hash = map {$_ => ($hash{$_} || 0) + 1} @xarray;
#is grep(/^1$/, %hash), $n, "$n unique ids minted";

remove_td($td, $bgroup);
}
