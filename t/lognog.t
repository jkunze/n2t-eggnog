use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd) = script_tester "nog";

{	# check mstat command
remake_td($td);
$ENV{MINDERPATH} = $td;
my ($x, $y);

$x = `$cmd mkminter -t seq --atlast stop fk d`;
$y = flvl("< $td/fk/nog_README", $x);
like $x, qr/10 sequential/, 'created 1-digit stopping minter, implied --oklz';

$x = `$cmd fk.mint 3`;
$x = `$cmd fk.mstat`;
like $x, qr/fk.*status: enabled.*skipped.*zero.*: 1.*minted: 3.*left: 6/s,
	'mstat reflects simple minter state';

$x = `$cmd mkminter c2`;
$y = flvl("< $td/c2/nog_README", $x);
like $x, qr/unlimited random/, 'created random unlimited minter';

$x = `$cmd c2.mint 3`;
$x = `$cmd c2.mstat`;
like $x, qr,$td/c2.*status: enabled.*left: unlimited.*expansion.*8407,s,
	'mstat reflects expansion event';

$x = `$cmd c2.mstatus`;
like $x, qr/^enabled\n/, 'mstatus with no args reports enabled status';

$x = `$cmd c2.mstatus disab`;
like $x, qr/^disabled\n/, 'mstatus with disab now reports disabled status';

$x = `$cmd c2.mstat`;
like $x, qr,$td/c2.*status: disabled.*left: unlimited.*expansion.*8407,s,
	'mstat reflects disablement';

remove_td($td);
}

{	# stub log checker
remake_td($td);
#$ENV{MINDERPATH} = $td;
$ENV{NOG} = "-p $td --txnlog $td/txnlog";
my ($x, $y);

$x = `$cmd mkminter -t seq --atlast stop fk ddeek`;
$y = flvl("< $td/fk/nog_README", $x);
like $x, qr/ sequential /, 'created minter';

# yyy this has already been covered above
$y = flvl("< $td/fk/nog.rlog", $x);
like $x, qr/H: .*rlog.*M: mkminter.*ddeek/si,
	'creation reflected in minter log file';

$x = `$cmd fk.mint 3`;
$y = file_value("< $td/fk/nog.rlog", $x);
like $x, qr/(C: mint.*){3}/s, 'mint reflected in minter log file';

## xxxxxxxx make better log message

$y = file_value("< $td/txnlog.rlog", $x);
like $y, qr/^$/, 'read txnlog file';

like $x, qr/(?:BEGIN[^\n]*mint.*END SUCCESS[^\n]*mint: .*){3}/s,
	'txnlog file records 3 mint BEGIN/END pairs';

remove_td($td);
}

