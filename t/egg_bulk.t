# xxx before removing this file, mine it for tests
#     that don't belong here, eg, readonly mode

use 5.10.1;
use Test::More qw( no_plan );

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $tdata, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
$ENV{EGG} = $hgbase;		# initialize basic --home and --testdata values

# Use this subroutine to get actual commands onto STDIN (eg, bulkcmd).
#
sub run_cmds_on_stdin { my( $cmdblock )=@_;

	my $msg = file_value("> $td/getcmds", $cmdblock, "raw");
	$msg		and return $msg;
	return `$cmd - < $td/getcmds`;
}

=for later
{
remake_td($td, $tdata);
$ENV{MINDERPATH} = $td;
my ($x, $cmdblock);

$cmdblock = '
mkbinder
mkbinder
mkbinder
';

# XXXXX fixing this bug requires redoing some assumptions about
#       the $mh creation -- worth doing at some point
$x = run_cmds_on_stdin($cmdblock);
like $x, qr|xxx creating.*binder1|, "multiple mkbinders in one stream";

# xxx similar test/fix for mkminters
}
=cut

{
remake_td($td, $tdata);
my $x;
$ENV{EGG} = "$hgbase -d $td/foo";

$x = `$cmd --version`;
my $v1bdb = ($x =~ /DB version 1/);

$x = `$cmd --verbose mkbinder`;
like $x, qr/created.*foo/, 'make binder named foo';

$x = `$cmd i.set aaa bbb`;
$x = `$cmd i.fetch aaa`;
like $x , qr/aaa:.*bbb/, 'binder binds with non-bulk commands';

$x = run_cmds_on_stdin("i.fetch aaa");
like $x, qr/aaa:.*bbb/, "fetchable with one command in block from stdin";

$x = run_cmds_on_stdin("i.set aaa ccc");
$x = run_cmds_on_stdin("i.fetch aaa");
like $x, qr/aaa:.*ccc/s, "settable with one simple bulk command in block";

$x = run_cmds_on_stdin("");
like $x, qr/^$/s, "null command on stdin";

my $cmdblock;

$cmdblock = "
   
   -  

";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^$/s, "3 blank lines and one bulk mode '-' ignored on stdin";

$cmdblock .= "blech";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/unknown.*blech.*status.*line 5/s,
	"non-zero return status noted with line number";

$cmdblock = "
j.purge
j.set a b
j.add a c
j.add a d
j.add u v
j.add x y
j.fetch
j.purge
j.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/under j: 5.*user.*under j: 7.*under j: 0/s,
	"purge all elements at once, reporting only user elements";

# note use of 'quotes' to hide array variable interpolation of @
$cmdblock = '
j.purge
j|a.set @-
  b  

j|a.add c
j|a.add d
j|u.add v
j|x.add y
j.fetch
j.rm x
j.fetch
j.purge
j.fetch
';
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/a:   b  .*under j: 5.*under j: 4.*user.*under j: 6.*under j: 0/s,
	"add, rm, and purge plus modifier";

$cmdblock = "
i.fetch aaa
myid.set bar zaf
myid.add cat dog
myid.fetch
";
# First command (fetch) opens in readonly mode, while second (set)
# should force a re-open in rdwr mode.  Ultimately two closes should
# be required: once after i.fetch and again at handler teardown.

my $isbname = `$cmd --dbie i bname $td/foo`;	# indb system binder name
$isbname =~ s/\n*$//;			# do it before --verbose in effect!

$ENV{EGG} = "$hgbase --verbose -d $td/foo";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/aaa: ccc\n.*bar: zaf\ncat: dog\n/s,
	"four bulk commands exercising both readonly and rdwr modes";
# XXX an optimized mode could lock in rdwr mode for whole batch

like $x, qr|(?:\nclosing.*\Q$isbname\E/egg.bdb\n.*){2}|s,
	"different open modes means closing persistent mopen at least twice";

use EggNog::Binder;
my $pmax = $EggNog::Binder::PERSISTOMAX;
my ($n, $m, $p);
$cmdblock = "";
$n = 2 * $pmax + 3;		# times 2 should mean two close/re-opens
$cmdblock .= "beetle.set foo$_ bar$_\n"
	for (1 .. $n);
$cmdblock .= "beetle.fetch\n";

$x = run_cmds_on_stdin($cmdblock);
like $x, qr/(?:closing.*handler.*){2}beetle.*$n/s,
	"$n bulk reads on persistent mopen, with two close/re-opens";

$ENV{EGG} = "$hgbase -d $td/foo";
$cmdblock = q{j.set   "an elem  name" of\ shellwords\ \"for'   you'
j.fetch};

$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^an elem %20name:\s*of shellwords "for   you$/m,
	"shellwords tokenizes and bind encodes spaces in element name";

$cmdblock = q{j.set   "an elem  name" of\ shellwords\ \"for   you
j.fetch};
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^an elem %20name:\s*of shellwords "for$/m,
	"shellwords tokenizes with quotes, ignoring final extra token";

$cmdblock = q{k.set 'a    b  	c' "e  f  g"
k.fetch 'a    b  	c'
};
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^a %20%20%20b %20%09c:\s*e  f  g$/m,
#            a%20%20%20%20b%20%20%09c
	"element name quotes";

$cmdblock = q{u.set uuu vvv
#u.set ddd zzz

u.set eee fff\
#ggg
hhh

u.fetch

};
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/fffhhh.*vvv/s,
	"block with comments, blank lines and continuation lines";

# XXXXXXX bulkelems should use granvl!? w.o. needing --api
# XXX $n>201 triggers bug (v1 db_file), where key is stored in wrong order
# XXXXX see if bdb api fixes it
# $m>3276 triggers limit ~32767 token-size limit in shellwords,
# which returns () (note regex quantifier limit of 32766); but we use
# shellwords only if there are quotes and split (no limit) otherwise
#
($n, $m) = (201, 32760);	# creates tokens of size 327,600
$cmdblock = 'ourid.set ' . 'bigelement' x $n;	# 10-byte elem name
$cmdblock .= ' ' . 'mybigvalue' x $m . "\n";	# 10-byte elem value
$cmdblock .= "ourid.fetch\n";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/(?:bigelement){$n}:\s*(?:mybigvalue){$m}\n/,
	(10*$n) . "-byte element and one " . (10*$m) . "-byte token";

#($n, $m) = (201, 3276);
$p = 100;	# xxx gets very slow at 1000
$cmdblock = 'yerid.set ' . 'bigelement' x $n;
my $bigvalue = 'mybigvalue' x $m;			# a big token
$cmdblock .= " '" . ($bigvalue . ' ') x $p . "'\n";	# quote $p big tokens
$cmdblock .= "yerid.fetch\n";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/(?:bigelement){$n}:(?:\s*$bigvalue){$p}/,
	(10*$n) . "-byte element and $p " . (10*$m) . "-byte tokens";

=for documenting
         use Text::ParseWords;
         @words = &shellwords(q{this   is "a test" of\ quotewords \"for you});
         $i = 0;
         foreach (@words) {
             print "$i: <$_>\n";
             $i++;
         }
	 # note that single quote (') is also recognized

       produces:

         0: <this>
         1: <is>
         2: <a test>
         3: <of quotewords>
         4: <"for>
         5: <you>
=cut

remove_td($td, $tdata);
}
