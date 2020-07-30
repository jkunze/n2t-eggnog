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

say "XXX this is incomplete in terms of new bsync2remote";

$x = `$cmd --verbose -p $td mkbinder foo`;
shellst_is 0, $x, "make binder named foo";

# need "" to quote inner '', but that means we also need \ to escape @ in ""
my $cmdblock;
$cmdblock = "
i.set a b
i.add a c
i.add a d
'\$t.^x.set' '\$u.|e' nasty
# set an id named \@
\@.set a t
\@
j.set u v
j.set x y
i.fetch
j.fetch
k.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/under i: 3.*under j: 2.*under k: 0/s,
	"new binder, set some ids with various elements";

$x = `$cmd -d $td/foo '\$t.^x.exists' '\$u.|e'`;
like $x, qr/^1\n/, "includes id|elem with nasty chars";

$x = `$cmd --verbose -p $td mkbinder bar`;
shellst_is 0, $x, "make new binder named bar";

my ($isb_foo, $isb_bar);

if ($indb) {
  $isb_foo = `$cmd --dbie i bname $td/foo`;	# indb system binder name
  $isb_foo =~ s/\n*$//;

  $isb_bar = `$cmd --dbie i bname $td/bar`;	# indb system binder name
  $isb_bar =~ s/\n*$//;

  #$x = `(cd $isb_foo; db_dump egg.bdb) | (cd $isb_bar; db_load egg.bdb)`;
  #$x = `(cd $isb_foo; db_dump egg.bdb) | admegn binder_load $isb_bar`;

  $x = `(cd $isb_foo; db_dump -p egg.bdb) > $td/foo.dump`;
  shellst_is 0, $x,
  	"db_dump -p foo into $td/foo.dump, which is fed to ...";

  $x = `admegn binder_load $isb_bar < $td/foo.dump`;
  shellst_is 0, $x,
  	"admegn binder_load $isb_bar";

  $x = `(cd $isb_bar; db_dump -p egg.bdb) > $td/bar.dump`;
  shellst_is 0, $x,
  	"db_dump -p bar into $td/bar.dump";

  $x = `diff $td/foo.dump $td/bar.dump`;
  is $x, '', "binder bar is now identical to binder foo";

  #shellst_is 0, $x,
  #	"db_dump bar into $td/bar.dump";

  #$x = `(cd $isb_foo; db_dump egg.bdb) | admegn binder_load $isb_bar`;
  #like $x, qr/xxx/, "xxx";

}	# close if ($indb)

my $changetime = `date '+%Y.%m.%d_%H:%M:%S'`;	# starttime of changes
chop $changetime;

# XXX bug: this next doesn't log properly -- need to fix
# '\$t.^x.add' '\$u.|e' nastydupe

# Second round of commands. These are the changes we'll make.
$cmdblock = "
i.set x y
j.purge
'^\$txyz'.rm a
m.set u v
# this next causes id to be read from next line, ie, \@
\@.purge
\@
n.set v u
# test some difficult characters (@ and &) with idload for encoding bugs
# currently @ or :hx are required to prevent expansion of @ and & tokens
o.set @ @
@
&
i.set z a
i.fetch
j.fetch
'\$t.^x.fetch'
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/under i: 5.*under j: 0.*under \$t\.\^x: 1/s,
	"updated foo binder with additions and deletions";

# XXX first id should be "\$t.^x", but there is a bug in how we encode
#     and decode logged ids; do we need a special encoding just for logs?

my $sorted_changed_ids = "\@
^\$txyz
i
j
m
n
o
";

# XXX logging bug: we only log user and not binder name! for public binder
#     accesses we can (for now) assume user => binder name (eg, ezid=>ezid)
my $rwind = '^==* report window .* to \([0-9].*\)$';
#my $changed_ids = `tlog --mods $changetime $td/logs/transaction_log \\
#	| sed -n -e 's/^.=mod== [^ ][^ ]* //p' -e 's/$rwind/# end: \\1/p'`;
my $changed_ids = `tlog --iddump $changetime $td/logs/transaction_log`;

my $report_end_time;	# in practice, a tlog parameter for next harvest
$changed_ids =~ s/^# next harvest: (\S+) \S+\n//m and
	$report_end_time = $1;
like $report_end_time, qr/^\d\d\d\d\.\d\d\.\d\d\_\d\d:\d\d:\d\d\.?\d*$/,
	"report end time captured";

## ======== 2020.07.29_17:20:08 to 2020.07.29_17:20:08.933651
## from log ['td_egg/logs/transaction_log']
# +n2t @
# +n2t ^$txyz
# +n2t i
# +n2t j
# +n2t m
# +n2t n
# +n2t o
## report end time: 2020.07.29_17:20:08.933651
##      7 mods from 2020.07.29_17:20:08 to 2020.07.29_17:20:08.933651
## next harvest: 2020.07.29_17:20:08.933651 /apps/n2t/sv/cur/apache2/logs/transaction_log

$changed_ids =~ s/^#.*\n//gm;
$changed_ids =~ s/^ (\S+) //gm;		# drop binder name, eg, "+n2t"

is $changed_ids, $sorted_changed_ids,
	"transaction_log has all the changed_ids";

#say "xxxxxx premature end. changed_ids=$changed_ids"; exit;

my $msg;
# quoting problems make putting it in a file easier than shell <<<
$msg = file_value("> $td/changed_ids", $changed_ids, "raw");
is $msg, '', "saved changed_ids harvested from transaction_log";

$x = `$cmd iddump $td/foo < $td/changed_ids > $td/iddump`;
$msg = file_value("< $td/iddump", $x);
like $x, qr/# hexid: 69.*under i: 7.*under n: 3\n/s,
	"iddump of changed_ids includes new counts for ids i and n";

like $x, qr/\$txyz.*# hexid: 6a.*under j: 0/s,
	"... also includes purged id j and encoded nasty id";

$x = `$cmd idload $td/bar < $td/iddump`;
shellst_is 0, $x,
	"idload into $td/bar from $td/iddump";

unlike $x, qr/error: /i, "no idload errors reported";

if ($indb) {

  # we're going to do new dumps and comparisons
  $x = `(cd $isb_foo; db_dump -p egg.bdb) > $td/foo.dump2`;
  shellst_is 0, $x,
  	"new db_dump saved in $td/foo.dump2";

  $x = `(cd $isb_bar; db_dump -p egg.bdb) > $td/bar.dump2`;
  shellst_is 0, $x,
  	"new db_dump saved in $td/bar.dump2";

  $x = `cmp $td/foo.dump $td/foo.dump2`;
  shellst_is 1, $x,
  	"updated binder foo dump contains changes";

  $x = `diff $td/foo.dump2 $td/bar.dump2`;
  is $x, '',
  	"binder bar was updated to reflect all binder foo changes";

}	# close if ($indb)

#say "xxxxxx premature end."; exit;

remove_td($td, $tdata);
}

