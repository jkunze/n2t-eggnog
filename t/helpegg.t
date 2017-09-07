use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd) = script_tester "egg";
my $egg_home = "--home $td";
$ENV{EGG} = $egg_home;

{
remake_td($td);
my $x;

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

remove_td($td);
}
