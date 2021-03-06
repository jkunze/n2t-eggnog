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
$ENV{EGG} = $hgbase;		# initialize --home and --testdata values

{
remake_td($td, $tdata);
my $x;

#say "xxxxxx premature end. tdata=$tdata, env.egg=$ENV{EGG}"; exit;
#say "xxxxxx premature end. x=$x"; exit;

$x = `$cmd --version`;
my $v1bdb = ($x =~ /DB version 1/);

$x = `$cmd --verbose -p $td mkbinder foo`;
shellst_is 0, $x, "make binder named foo";

if ($indb) {

my $isbname = `$cmd --dbie i bname $td/foo`;	# indb system binder name
$isbname =~ s/\n*$//;

my $y;
$x = file_value("<$isbname/egg_README", $y);

if ($v1bdb) {
  like $y, qr/ordering.*not.*preserved/,
  	"note left about duplicate ordering not preserved";
}
else {
  like $y, qr/.../, "README file found";
  unlike $y, qr/ordering.*not.*preserved/,
  	"no note left about duplicate ordering preserved";
}

  is 1, (-f "$isbname/egg.bdb"), 'created binder upper directory and bdb file';
}	# close if ($indb)

$x = `$cmd -d $td/foo foo.set bar zaf   woof`;
shellst_is 0, $x, "simple set with bind status ok and -d";

like $x, qr/^$/, "simple set by default has no output";

$x = `$cmd -d $td/foo -m plain foo.fetch bar`;
shellst_is 0, $x, "fetch status ok";

like $x, qr/bar:\s*zaf\n/s,
	"fetch promotes plain format to anvl and ignores extra tokens";

#say "xxxxxx premature end. x=$x"; exit;

$x = `$cmd -d $td/foo FOO.set bar cow`;
$x = `$cmd -d $td/foo -m plain FOO.fetch`;
like $x, qr/bar:\s*cow\n/s,
	'id strings are case sensitive';

$x = `$cmd -d $td/foo foo.let eel cow`;
like $x, qr/^$/s, "simple let binding";

$x = `$cmd -d $td/foo foo.fetch`;
shellst_is 0, $x, "fetch status ok, no elems requested";

like $x, qr/bar:\s*zaf\neel:\s*cow/s, "fetch two bindings with -d";

$x = `$cmd --debug -d $td/foo foo.get bar`;
shellst_is 0, $x, "get status ok";

like $x, qr/^zaf$/m, "get simple binding with -d";

$x = `$cmd -d $td/foo foo.add bar xaf`;
like $x, qr/^$/, "add duplicate binding";

$x = `$cmd -d $td/foo --format anvl --ack foo.add bar yaf`;
like $x, qr/oxum: 3.1/, "another 3rd duplicate binding";

$x = `$cmd -d $td/foo foo.insert bar daf`;
like $x, qr/^$/, "insert a 4th duplicate binding";

# DB_File order of dups stored not preserved in V1 Berkeley DB
$x = `$cmd -d $td/foo foo.get`;

if ($v1bdb) {
  ok(($x =~ qr/daf\n/ && $x =~ qr/zaf\n/
  		&& $x =~ qr/xaf\n/ && $x =~ qr/yaf\n/),
  	"get duplicate binding for all elements v1 (order not preserved)");
}
else {
  like $x, qr/zaf\nxaf\nyaf\ndaf\n/s,
  	"get duplicate binding for all elements v1+ (order preserved)";
#print "xxxx x=$x\n";
}

$x = `$cmd -d $td/foo foo.set bar aaa`;
like $x, qr/^$/,
	"no complaint about set on top of duplicate bindings";

$x = `$cmd -d $td/foo -f -m anvl foo.let bar aaa`;
like $x, qr/error:/, "let stops when a value is already set";

$x = `$cmd -d $td/foo -f -m anvl foo.rm bar`;
$x = `$cmd -d $td/foo -f -m anvl --ack foo.let bar aaa`;
like $x, qr/oxum: 3.1/,
	"let proceeds and --ack talks when a value isn't already set";

$x = `$cmd -d $td/foo -m anvl foo.rm eel cow`;
like $x, qr/^$/s, "'rm foo cow' operation with ANVL";

$x = `$cmd -d $td/foo foo.fetch`;
unlike $x, qr/[zxy]af/s, "old element values wiped out";

like $x, qr/aaa/, "new values in place";

# yyy dropping --sif until we think it through more
#$x = `$cmd -d $td/foo --sif n foo.set bar that`;
#like $x, qr/error.*exists/s, "op to succeed only if elem doesn't exist";

# yyy dropping support for delete while doing exdb case (since it involves an
#     extra network roundtrip)
#$x = `$cmd -d $td/foo foo.delete that`;
#like $x, qr/^0 elements removed/s, "delete reports non-existent element";
$x = `$cmd -d $td/foo --ack foo.rm that`;
like $x, qr/^0\.0\n/s, "--ack detects non-existent element";

#xxx what should -f mean, if anything?
#$x = `$cmd -d $td/foo -f foo.delete that`;
#like $x, qr/0 elements/s, "force delete on non-existent element";

$x = `$cmd -d $td/foo foo.rm bar`;
like $x, qr/^$/s, "'foo.rm bar' operation";

$x = `$cmd -d $td/foo foo.fetch`;
like $x, qr/^#.*foo\n# elements.*: 0\n\n$/s, "now no element values";

$x = `$cmd -d $td/foo foo.xyzzy bar`;
like $x, qr/xyzzy.*Usage/s, "unknown method produces method list";

# yyy dropping --sif until we think it through more
## this is the old 'replace'
#$x = `$cmd --verbose -d $td/foo --sif X foo.set this that`;
#like $x, qr/error.*doesn.t exist/s, "op to succeed only if elem exists";

$x = `$cmd --verbose -d $td/foo goo.add star tar`;
$x = `$cmd --verbose -d $td/foo goo.get star`;
like $x, qr/^tar$/m, "use 'add' when nothing's yet set";

$x = `$cmd --verbose -d $td/foo boo.insert star tar`;
$x = `$cmd --verbose -d $td/foo boo.get star`;
like $x, qr/^tar\n/m, "use 'insert' when nothing's yet set";

$x = flvl(">$td/indirect", "is nice");
$x = `$cmd -d $td/foo rat.set fur \@$td/indirect`;
$x = `$cmd -d $td/foo rat.get fur`;
like $x, qr/^is nice\n/, "retrieved value set from file content";

$x = `$cmd -d $td/foo foo/1.set a slash`;
$x = `$cmd -d $td/foo foo/1.fetch`;
like $x, qr/slash/, "fetch against id with '/' works";

# fixes old bug in loop that fetched elements under an id but didn't
# properly quote the var in the regex with \Q ... \E
$x = `$cmd -d $td/foo foo.1.set c dot`;
$x = `$cmd -d $td/foo foo.1.fetch`;
unlike $x, qr/slash/,
	"fetch against id with regex char '.' no longer retrieves other ids";

$x = `$cmd -d $td/foo '\$t.^x.exists' '\$u.|e'`;
like $x, qr/^0\n/, "id|elem with nasty chars does not yet exist";

$x = `$cmd -d $td/foo '\$t.^x.set' '\$u.|e' nasty`;
$x = `$cmd -d $td/foo '\$t.^x.exists' '\$u.|e'`;
like $x, qr/^1\n/, "id|elem with nasty chars now exists";

$x = `$cmd -d $td/foo '\$t.^x.exists'`;
like $x, qr/^1\n/, "and so does its parent id";

#$x = `$cmd -d $td/foo '\$t.^x.get' '\$u.|e'`;
#like $x, qr/^nasty\n/s, "'set/get' op with nasty chars";

$x = `$cmd -d $td/foo '\$t.^x.fetch'`;
like $x, qr/\n\$u\.|e: nasty\n/, "'fetch' op with nasty chars";

$x = `$cmd -d $td/foo '\$t.^x.rm' '\$u.|e'`;
$x = `$cmd -d $td/foo '\$t.^x.get' '\$u.|e'`;
like $x, qr/^$/s, "'rm' op with nasty chars";

$x = `$cmd -d $td/foo '\$t.^x.set' '\$u.|e' nasty`;
$x = `$cmd -d $td/foo '\$t.^x.purge'`;
like $x, qr/under \$t\.\^x: 3\n/s, "'purge' op with nasty chars";

$x = `$cmd -d $td/foo '\$t.^x.purge'`;
like $x, qr/under \$t\.\^x: 0\n/s,
	"second purge finds no elements to purge";

# xxx the test for 'exists' is pretty poor, eg, it didn't catch that the second
# purge above actually found some elements before a bug was fixed
$x = `$cmd -d $td/foo '\$t.^x.exists'`;
like $x, qr/^0\n/, "and 'exists' believes that it's gone";

remove_td($td, $tdata);
}

