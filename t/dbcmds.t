use 5.010;
use Test::More qw( no_plan );

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

# Use this subroutine to get actual commands onto STDIN (eg, bulkcmd).
#
sub run_cmds_on_stdin { my( $cmdblock )=@_;

	my $msg = file_value("> $td/getcmds", $cmdblock, "raw");
	$msg		and return $msg;
	return `$cmd - < $td/getcmds`;
}

{
remake_td($td);
$ENV{EGG} = "$hgbase -d $td/foo";
my ($x, $y, $cmdblock);

$x = `$cmd --verbose mkbinder`;
like $x, qr/created.*foo/, 'make binder named foo';

$cmdblock = "
this.purge
this.set is 'dbsaved'
this.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^is: dbsaved$/m,
	"created tiny original binder";

$x = `$cmd --qs "--ua dbsave $td/dummysaved.bdb"`;
shellst_is 1, $x, "webmode dbsave fails";
like $x, qr{unauth},
	"because webmode dbsave is unauthorized";

# xxx dbsave and dbload built for the old DB_File.pm environment
# xxx should probably be updated for BerkeleyDB.pm and MongoDB.pm
$x = `$cmd dbsave $td/dummysaved.bdb`;
shellst_is 0, $x, "non-webmode dbsave proceeds";
like $x, qr{running /bin/cp}, "non-webmode dbsave is authorized";

$cmdblock = "
this.purge
this.set is 'not dbsaved'
this.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^is: not dbsaved$/m, "overwriting original binding";


# XXX the rest of these tests are disabled for now
# xxx dbsave and dbload were built for the old DB_File.pm environment
# xxx should probably be updated for BerkeleyDB.pm and MongoDB.pm
#system "sum $td/foo/*";
#
$x = `$cmd --qs "--ua dbload $td/dummysaved.bdb"`;
# shellst_is 1, $x, "webmode dbload fails";
# like $x, qr{unauth},
# 	"because webmode dbload is unauthorized";

#system "sum $td/foo/*";

# xxx dbsave and dbload built for the old DB_File.pm environment
# xxx should probably be updated for BerkeleyDB.pm and MongoDB.pm
$x = `$cmd dbload $td/dummysaved.bdb`;
# shellst_is 0, $x, "non-webmode dbload proceeds";
# like $x, qr{running /bin/mv}, "non-webmode dbload is authorized";

# $x = `$cmd this.fetch is`;
# like $x, qr/^is: dbsaved\n\n$/m, "original binding back after dbload";

#system "sum $td/foo/*";

#exit; #############

remove_td($td);
}
