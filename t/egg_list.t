use 5.010;
#use Test::More qw( no_plan );
use Test::More;

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

# Use this subroutine to get actual commands onto STDIN (eg, bulkcmd).
#
sub run_cmds_on_stdin { my( $cmdblock, $flags )=@_;

	$flags ||= '';
	my $msg = file_value("> $td/getcmds", $cmdblock, "raw");
	$msg		and return $msg;
	return `$cmd $flags - < $td/getcmds`;
}

# yyy? check mstat command ?

$exdb and plan skip_all =>
	"why: list/next functions not implemented for dbie=e case";

plan 'no_plan';		# how we usually roll -- freedom to test whatever

SKIP: {
remake_td($td);
$ENV{EGG} = "$hgbase -p $td -d $td/bar";
my ($cmdblock, $x, $y, $ark);

$x = `$cmd --verbose mkbinder bar`;
like $x, qr/created.*bar/, 'created new binder';

$cmdblock = "
ark:/12345/f8z1.set a b
ark:/12345/f8z10.set a b
ark:/12345/f8z12.set a b
ark:/12345/f8z11.set a b
ark:/12345/f9z0.set a b
ark:/12345/f9z1.set a b
ark:/12345/f9z2.set a b
ark:/12345/f9z3.set a b
# that's 8 on the 12345 NAAN
ark:/22345/f9z4.set a b
ark:/22345/f9z5.set a b
# that's 2 on the 22345 NAAN
ark:/32345/f9z6.set a b
ark:/32345/f9z7.set a b
ark:/32345/f9z8.set a b
# that's 3 on the 32345 NAAN
ark:/42345/f9z9.set a b
# that's 1 on the 42345 NAAN
list 3
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr|(^:/.+\n){3}|m,
	"list first 3 binder elements (internal admin elems)";

$x = `$cmd list - ark:/12345/f8`;
like $x, qr|^#.*\n(ark:/12345/f8.*\n){4}#|,
	"got all ids on f8 shoulder (4) with default max";

$x = `$cmd list 0 ark`;
like $x, qr|^#.*\n(ark:/.2345/.*\n){14}#|,
	"list infinite ids for key";

#print "x=$x\n"; exit;   ##################

$x = `$cmd list 0 ark:/1 ark:/4 xyzzy`;
like $x, qr|^#.*\n(ark:/.2345/.*\n){9}#|,
	"list infinite ids for two keys and one non-existent key";

$x = `$cmd next 0 :`;
like $x, qr|^#.*\n(ark:/.2345/.*\n){14}#|,
	"next-list infinite ids past admin key";


# XXXXXXXXXXXXXXXXXXXX wrong! currently the '|' subelem separator causes
#    'z1' to follow (not precede) 'z11'   (eg, because z1|... follows z11|...)
#like $x, qr|f8z11\n#|,
#	"last id is lexically last";

$x = `$cmd list 100 ark:/12345/f8 ark:/32345/`;
like $x, qr|^#.*\n(ark:/12345/f8.*\n){4}(ark:/32345/f9z.\n){3}#|,
	"listed all 7 ids on 2 shoulders separated by gap";

$x = `$cmd list 6 ark:/12345/f8 ark:/32345/`;
like $x, qr|^#.*\n(ark:/12345/f8.*\n){4}(ark:/32345/f9z.\n){2}#|,
	"listed just 6 ids on 2 shoulders separated by gap";

$x = `$cmd next 1 :/`;
like $x, qr|^#.*\nark:/12345/f8.*\n#|,
	"next-list first id after internal ids stop";

$x = `$cmd next 100 :/ ark:/12345/f8 ark:/32345/`;
like $x, qr|^#.*\n(ark:/12345/f8.*\n){4}(ark:/32345/f9z.\n){3}#|,
	"next-list all ids on 2 shoulders with gap";

#$x = `$cmd list 100 ark:/12345/f8z12`;
$x = `$cmd list 100 ark:/42345`;
like $x, qr|^#.*\nark:/42345/f9z9\n#|,
	"list with key that returns just one id before EOF";

$x = `$cmd list - xyzzy`;
like $x, qr|^#.*\n#.*0 ids|,
	"list zero ids for non-existent key";

$x = `$cmd next - ark xyzzy`;
like $x, qr|^#.*\n#.*0 ids|,
	"next-list zero ids for non-existent key";

$x = `$cmd list 100 ark:`;
like $x, qr|^#.*\n(ark:/\d2345/f[89].*\n){14}#|,
	"list all ids";

# 1. batch = "egg list 100000"         # initialization step
# 2. append batch >> List              # save batch in growing List
# 3. if length(batch) < 100000, exit   # done -- everything will be in List
# 4. K = batch[100000]                 # set K to last id in batch
# 5. batch = "egg next 100000 K"       # return starts at first id after K
# 6. go to step 2                      # and repeat until done

my ($last, $list) = ('', '');
my ($n, $batchsize) = (0, 5);
$x = `$cmd list $batchsize ark:`;			# step 1
while (1) {
	$list .= $x;					# step 2
	($n = () = $x =~ m|^ark:|gm) < $batchsize and	# step 3
		last;
	($last) = $x =~ qr|\n(.+)\n#.*\n$|;		# step 4
	$x = `$cmd next $batchsize $last`;		# step 5
}							# step 6
like $list, qr|^((#[^\n]*\n)?ark:[^\n]+\n(#[^\n]+\n\n)?){14}#[^\n]+\n\n$|s,
	"documented algorithm: list plus next to collect all ids";

remove_td($td);
}
