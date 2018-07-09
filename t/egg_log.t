use 5.10.1;
use Test::More qw( no_plan );

# XXX one of the tests below relies on t/n2t/prefixes.yaml knowledge
#     move this out to t/service_n2t.t

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

my $txnlog = "$td/txnlog";

# Use this subroutine to get actual commands onto STDIN (eg, bulkcmd).
#
sub run_cmds_on_stdin { my( $cmdblock )=@_;

	my $msg = file_value("> $td/getcmds", $cmdblock, "raw");
	$msg		and return $msg;
	return `$cmd --txnlog $txnlog - < $td/getcmds`;
}

sub resolve_stdin { my( $opt_string, @ids )=@_;
	my $script = '';
	$script .= "$_.resolve\n"
		for @ids;
	my $msg = file_value("> $td/getcmd", $script);
	$msg		and return $msg;
	return `$cmd --rrm --txnlog $txnlog $opt_string - < $td/getcmd`;
}


{	# check mstat command
remake_td($td, $bgroup);
$ENV{EGG} = "$hgbase -p $td -d $td/bar --txnlog $txnlog";
my ($cmdblock, $x, $y);

$x = `$cmd --verbose mkbinder bar`;
like $x, qr/created.*bar/, 'created new binder';

#print "m=$x"; $x = `$cmd -d $td/bar mstat | grep bindings`; print "   b=$x";
$cmdblock = "
i.set a 1234567890
i.set a 12
i.set a 1234567890
# last one overwrites 1 binding
i.set b 1234567890
k.set c 11
k.add c 12
k.add c 13
k.add c 14
mstat
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/bindings: 10/s,
	'mstat reflects simple binder state with 6 bindings (+4 admin elems)';

$x = `$cmd k.set c foo`;		# overwrites 4 bindings
$x = `$cmd mstat`;
like $x, qr/bindings: 7/s,
	'down to 3 (+4) bindings after replacing 4 bindings with 1 binding';

remove_td($td, $bgroup);
}

# stub log checker
{
remake_td($td, $bgroup);
$ENV{EGG} = "$hgbase -d $td/foo --txnlog $txnlog";
my ($x, $y);

$x = `$cmd --version`;
my $v1bdb = ($x =~ /DB version 1/);

$x = `$cmd --verbose mkbinder`;
like $x, qr/created.*foo/, 'make binder named foo';

# yyy mkbinder doesn't create per-binder rlog file
#$y = file_value("< $td/foo/egg.rlog", $x);
#like $y, qr/^$/, 'read binder log file';
#
#like $x, qr/H: .*rlog.*M: mkbinder/si,
#	'creation reflected in binder log file';

#use EggNog::Temper ':all';
#while (my ($key, $value) = each %c64i) {
#	print "key=$key, value=$value\n";
#}

my $cmdblock;

$cmdblock = "
i.set a 3
i.set b c
i.add b e
i.add b e
i.purge
";
$x = run_cmds_on_stdin($cmdblock);
$y = file_value("< $td/foo/egg.rlog", $x);
like $x, qr/ H: .* C: i\|a.set 3.*(?: C: .*){4}i.purge/s,
	'bind value reflected in binder log file';

# NOTE: must precede @ in "" if it looks like possible array ref
$cmdblock = "
mline.set a \@-
this text first
this text second
this text third

mline.fetch
mline.purge
";
$x = run_cmds_on_stdin($cmdblock);	# run batch of commands; ignore return

my $dummyid = "dummyprefix:10.1234/5678";
$x = resolve_stdin("", $dummyid);	# do a failed resolution; ignore return

my $doi = "doi:10.1234/5678";
$x = resolve_stdin('', $doi);	# do a prefix-based resolution; ignore return

# now check effects of those commands on the log

$y = file_value("< $td/foo/egg.rlog", $x);
like $x, qr/mline.*%0athis.*%0athis/s,
	'multi-line bind correctly encoded in logfile (for EDINA replication)';

#$y = file_value("< $txnlog.rlog", $x);
$y = file_value("< $txnlog", $x);
like $y, qr/^$/, 'read txnlog file';

like $x, qr/(?:BEGIN[^\n]*set .*END SUCCESS[^\n]*set .*){3}/s,
	'txnlog file records 3 set BEGIN/END pairs';

like $x, qr/(?:BEGIN[^\n]*purge.*END[^\n]*purge.*){2}/s,
	'txnlog file records 2 purge BEGIN/END pairs';

like $x, qr/(?:BEGIN[^\n]*fetch .*END[^\n]*fetch .*)/s,
	'txnlog file records a fetch BEGIN/END pair';

like $x, qr/mline.*%0athis.*%0athis/s,
	'multi-line bind correctly encoded in transaction logfile';

like $x, qr/BEGIN resolve $dummyid.*end FAIL.*$dummyid/si,
	'BEGIN/END (fail) resolve pairs record same original form of id';

#say STDERR "xxx premature exit"; exit;

# we don't have proof its hardwired, but the resolver is started without
#     a --pfxfile filename, therefore it should fall back to hardwired
# yyy could use a less crude test
like $x, qr/BEGIN resolve $doi.*end SUCCESS.*$doi.*PFX doi/si,
	'BEGIN/END pairs indicate resolution via hardwired prefix';

#+jkunze jak-macbook-pro U12JDK2n H: egg 1.00 (Rlog 1.00)
#+jkunze jak-macbook-pro U12JDK2n M: mkbinder td_egg/foo
#+jkunze jak-macbook-pro U12JDK2n C: i|a.set 3
#+jkunze jak-macbook-pro U12JDK2n C: i|b.set c
#+jkunze jak-macbook-pro U12JDK2n C: i|b.add e
#+jkunze jak-macbook-pro U12JDK2n C: i|b.add e
#+jkunze jak-macbook-pro U12JDK2n C: i.purge

####################
#  XXXX many of these checks belong in another test file (not about logging)

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
	"purge all elements at once, report admin (2) and user elements (3)";

$cmdblock = "
0.purge
0.set 0 0
0.fetch 0
0.rm 0
0.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/purge under 0: 0\n0: 0\n.*# elements bound under 0: 0/s,
	"using 0 as id and 0 as element name";

$cmdblock = "
x^y.purge
x^y.set ^a|^c b
x^y.fetch
x^y.fetch ^a|^c
x^y.rm ^a|^c
x^y.fetch
x^y.purge
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/purge under x\^y: 0\n.*\^a\|\^c: b\n.*under x\^y: 1\n\^a\|\^c: b.*purge under x\^y: 2/s,
	"encoding ^ and | in id and element name for set, purge, fetch";

$cmdblock = "
ii.purge
ii.set x|y z
ii.fetch x|y
ii.fetch
ii.purge
";
$x = run_cmds_on_stdin($cmdblock);
like $x,
    qr/x\|y: z\n# id: ii\nx\|y: z\n.*under ii: 1\n.*purge under ii: 3\n+$/s,
	"element name encoded on set and fetch, not doubly encoded by purge";

$cmdblock = "
j.purge
:hx j|a.set ^20^20b^20^20
j|a.add c
j|a.add d
j|u.add v
j|x.add y
j.fetch
j.rm x
j.fetch
j.purge
j.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/a:   b  .*under j: 5.*under j: 4.*user.*under j: 6.*under j: 0/s,
	"add, rm, and purge using modifiers";

$cmdblock = "
.purge
:hx |.set b
:hx |.add c
.fetch
|.fetch
|.rm
.purge
.fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/"": b.*under "": 2.*"": b.*id: "".*under "": 0/s,
	"add, rm, and purge using empty identifier and element names";

$cmdblock = "
@.set @ x
i^j|k%l
a^b|c%d
@.fetch @
i^j|k%l
a^b|c%d
@.fetch
i^j|k%l
@.purge
i^j|k%l
";
$x = run_cmds_on_stdin($cmdblock);
is $x, "a^b|c%25d: x
# id: i^j|k%l
a^b|c%25d: x
# elements bound under i^j|k%l: 1
# admin + user elements found to purge under i^j|k%l: 3\n\n\n",
	"tokens displaying with mix of % and ^ encodings";

#say "x: $x";
#say STDERR "xxx premature exit";
#exit;

$cmdblock = "
purge
set f g
add f h
add f i
fetch
rm f
fetch
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/(?:f: [ghi]\n){3}.*under "": 3.*under "": 0/s,
	"set, add, and rm using implicit empty identifier";

$cmdblock = "
|.set foo
purge
uu.purge
exists
uu.exists
uu.set a b
uu.get a
uu.exists
uu|a.exists
uu|x.get
uu|x.exists
uu|x.set y
u.exists
u|x.exists
uu|x.get
uu|x.exists
uu.exists
uu.rm x
uu|x.exists
uu.exists
uu.rm a
# that removes all user elements, but not admin elements, so it still exists
uu.exists
set f g
get f
exists
|f.exists
|.exists
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/0.0.b.1.1.0.0.0.y.1.1.0.1.1.g.1.1.0.\n$/s,
	"various 'exists' tests: id|elem combos, empty ids, etc";

$cmdblock = "
i.purge
i.set a \"jklkkkkkkkkk kkkkkkkkkkk eeeeeeeeeeee rrrrrrrrrrrrrrrr tttttttttttt uuuuuuu ddddddddd wwwwwwwwwww ddddddddddddd\"
i.fetch a
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/^a: jklkkkkkkkkk kkkkkkkkkkk eeeeeeeeeeee rrrrrrrrrrrrrrrr tttttttttttt uuuuuuu ddddddddd wwwwwwwwwww ddddddddddddd$/m,
	"on fetch, long value doesn't text wrap";

remove_td($td, $bgroup);
}

# null txnlog checker
{
remake_td($td, $bgroup);
$ENV{EGG} = "$hgbase -d $td/foo --txnlog ''";
my ($x, $y);

$x = `$cmd --verbose mkbinder`;
like $x, qr/created.*foo/, 'make another binder named foo';

$x = `$cmd k.set a boggle`;		# overwrites 4 bindings
$x = `$cmd k.get a`;
like $x, qr/^boggle\n/, 'value bound';

$x = (! -e $txnlog ? 'nope' : 'exists');

is $x, 'nope', 'txnlog file not created when logging is turned off';

remove_td($td, $bgroup);
}
