# XXX change file_value to flvl?
use 5.10.1;
use Test::More qw( no_plan );

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

# Do "export EGG_DBIE=e" (=ie) to test exdb (both) paths,

my ($td, $cmd, $homedir, $tdata, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;

sub run_cmds_on_stdin { my( $cmdblock )=@_;

	my $msg = file_value("> $td/getcmds", $cmdblock, "raw");
	$msg		and return $msg;
	return `$cmd - < $td/getcmds`;
}

$ENV{EGG} = "$hgbase -d $td/foo";	# initialize --home and --testdata
$ENV{TMPDIR} = $td;			# for db_dump and db_load

{
remake_td($td, $tdata);
my $x;

#say "xxxxxx premature end. tdata=$tdata, env.egg=$ENV{EGG}"; exit;
#say "xxxxxx premature end. x=$x"; exit;

$x = `$cmd --verbose -p $td mkbinder foo`;
shellst_is 0, $x, "make binder named foo";

my $cmdblock;
$cmdblock = "
i.set a b
i.add a c
i.add a d
j.set u v
j.set x y
'\$t.^x.set' '\$u.|e' nasty
i.fetch
j.fetch
k.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/under i: 3.*under j: 2.*under k: 0/s,
	"new binder, set 3 ids with various elements";

$x = `$cmd -d $td/foo '\$t.^x.exists' '\$u.|e'`;
like $x, qr/^1\n/, "includes id|elem with nasty chars";

$x = `$cmd --verbose -p $td mkbinder bar`;
shellst_is 0, $x, "make new binder named bar";

my ($isbname1, $isbname2);

if ($indb) {
  $isbname1 = `$cmd --dbie i bname $td/foo`;	# indb system binder name
  $isbname1 =~ s/\n*$//;

  $isbname2 = `$cmd --dbie i bname $td/bar`;	# indb system binder name
  $isbname2 =~ s/\n*$//;

  #$x = `(cd $isbname1; db_dump egg.bdb) | (cd $isbname2; db_load egg.bdb)`;
  #$x = `(cd $isbname1; db_dump egg.bdb) | admegn binder_load $isbname2`;

  $x = `(cd $isbname1; db_dump egg.bdb) > $td/foo.dump`;
  shellst_is 0, $x,
  	"db_dump foo into $td/foo.dump, which is fed to ...";

  $x = `admegn binder_load $isbname2 < $td/foo.dump`;
  shellst_is 0, $x,
  	"admegn binder_load $isbname2";

  $x = `(cd $isbname2; db_dump egg.bdb) > $td/bar.dump`;
  shellst_is 0, $x,
  	"db_dump bar into $td/bar.dump";

  $x = `diff $td/foo.dump $td/bar.dump`;
  is $x, '', "binder bar is now identical to binder foo";

  #shellst_is 0, $x,
  #	"db_dump bar into $td/bar.dump";

  #$x = `(cd $isbname1; db_dump egg.bdb) | admegn binder_load $isbname2`;
  #like $x, qr/xxx/, "xxx";

}	# close if ($indb)

$cmdblock = "
i.set x y
j.purge
'\$t.^x.add' '\$u.|e' nastydupe
m.set u v
n.set v u
i.fetch
j.fetch
'\$t.^x.fetch'
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/under i: 4.*under j: 0.*under \$t\.\^x: 2/s,
	"updated foo binder with additions and deletions";

my $changed_ids = "i
j
\$t.^x
m
n
";

# quoting problems make putting it in a file easier than shell <<<
my $msg = file_value("> $td/changed_ids", $changed_ids, "raw");
like $msg, qr//, "saved changed_ids";

$x = `$cmd iddump $td/foo < $td/changed_ids > $td/iddump`;
$x = `cat $td/iddump`;
like $x, qr/# hexid: 69.*under i: 6.*under n: 3\n$/s,
	"iddump of changed_ids includes new counts for ids i and n";

like $x, qr/# hexid: 6a.*under j: 0.*\$t\.\^x/s,
	"... also includes purged id j and encoded nasty id";

$x = `$cmd idload $td/bar < $td/iddump`;
shellst_is 0, $x,
	"idload into $td/bar from $td/iddump";

if ($indb) {

  # we're going to do new dumps and comparisons
  $x = `(cd $isbname1; db_dump -p egg.bdb) > $td/foo.dump2`;
  shellst_is 0, $x,
  	"new db_dump saved in $td/foo.dump2";

  $x = `(cd $isbname2; db_dump -p egg.bdb) > $td/bar.dump2`;
  shellst_is 0, $x,
  	"new db_dump saved in $td/bar.dump2";

  $x = `cmp $td/foo.dump $td/foo.dump2`;
  shellst_is 1, $x,
  	"updated binder foo dump contains changes";

  $x = `diff $td/foo.dump2 $td/bar.dump2`;
  is $x, '',
  	"binder bar has been updated to be reflect binder foo changes";

  #shellst_is 0, $x,
  #	"db_dump bar into $td/bar.dump";

  #$x = `(cd $isbname1; db_dump egg.bdb) | admegn binder_load $isbname2`;
  #like $x, qr/xxx/, "xxx";

}	# close if ($indb)

say "xxxxxx premature end."; exit;
#say "xxxxxx premature end. x=$x"; exit;

remove_td($td, $tdata);
}

