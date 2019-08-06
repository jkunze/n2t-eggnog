# xxx should do a version of this for noid
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

{
remake_td($td, $tdata);
my $x;

$x = `$cmd -p $td mkbinder foo`;
shellst_is 0, $x, "make binder named foo";

#$x = `$cmd -d $td/foo :hx id.set bar "z^0aa^0af"`;
#$x = `$cmd -d $td/foo id.get bar`;
#like $x, qr/^z\na\nf\n/,
#	"hex modifier puts newlines globally into a value";

$x = `$cmd -d $td/foo :hx id.set bar "z^0aa^0af"`;
$x = `$cmd -d $td/foo id.get bar`;
like $x, qr/^z\na\nf\n/,
	"hex modifier puts newlines globally into a value";

$x = `$cmd -d $td/foo :hx id.set "b^0aar" zaf`;
$x = `$cmd -d $td/foo --verbose :hx id.get "b^0aar"`;
like $x, qr/^zaf$/m,
	"hex modifier puts a newline into an element name";

$x = `$cmd -d $td/foo :hx id.fetch`;
like $x, qr/^b%0aar:\s*zaf$/m,
	"fetch of identifier shows encoded newline in the element name";

$x = `$cmd -d $td/foo :hx id.fetch "b^0aar"`;
like $x, qr/^b%0aar:\s*zaf\n/,
	"fetch of element also shows encoded newline in the element name";

$x = `$cmd -d $td/foo :hx :hx% :hx+ id.set bar "z^0aa%0af+20r"`;
$x = `$cmd -d $td/foo id.fetch bar`;
like $x, qr/^bar:\s*z\^0aa%250af r\n/,
	"last hex modifier overrides previous hex modifiers";
# note that % is always URL-encoded when output via ANVL (enabled by 'fetch')

#   Failed test 'last hex modifier overrides previous hex modifiers'
#   at t/modifiers.t line 40.
#                   'bar: z^0aa%0af r
# 
# '
#     doesn't match '(?^:^bar:\s*z\^0aa%250af r\n)'

use EggNog::Binder 'SUPPORT_ELEMS_RE';
my $spat = EggNog::Binder::SUPPORT_ELEMS_RE;

$x = `$cmd -d $td/foo :all id.fetch`;
like $x, qr{$spat:.*$spat:}si,
	":all modifier fetches admin elements";

$x = `$cmd -d $td/foo --all id.fetch`;
like $x, qr{$spat:.*$spat:}si,
	"--all flag (useful for api) fetches admin elements";

$x = `$cmd -d $td/foo --all :all id.fetch`;
like $x, qr{$spat:.*$spat:}si,
	"--all flag plus :all modifier fetches admin elements";

$x = `$cmd -d $td/foo --all :allnot id.fetch`;
unlike $x, qr{$spat:}si,
	"--all flag plus :allnot modifier doesn't fetch admin elements";

$x = `$cmd -d $td/foo id.fetch`;
unlike $x, qr{$spat:}si,
	"no flags or modifiers doesn't fetch admin elements";

$x = `$cmd -d $td/foo :hx id.set bigelem "# Creation record for the identifier generator in NOID/noid.bdb.^0a# ^0aerc:^0awho:       jak/noid^0awhat:      unlimited sequential identifiers of form .zd^0a       A Noid minting and binding database has been created that will bind^0a       any identifier and mint an unbounded number of identifiers^0a       with the template '.zd'.^0a       Sample identifiers would be '1' and '11279'.^0a       Minting order is sequential.^0awhen:      20100624002634^0awhere:     aretha.ucop.edu:/noid/nd/.^0aVersion:   Noid 0.424^0aSize:      unlimited^0aTemplate:  .zd^0a       A suggested parent directory for this template is 'noidany'.  Note:^0a       separate minters need separate directories, and templates can suggest^0a       short names; e.g., the template 'xz.redek' suggests the parent directory^0a       'noid_xz4' since identifiers are 'xz' followed by 4 characters.^0aPolicy:    (:------E)^0a       This minter's durability summary is (maximum possible being 'GRANITE')^0a         '------E', which breaks down, property by property, as follows.^0a          ^5e^5e^5e^5e^5e^5e^5e^0a          |||||||______ (E)lided of vowels to avoid creating words by accident^0a          ||||||__ not (T)ranscription safe due to a generated check character^0a          |||||__ not (I)mpression safe from ignorable typesetter-added hyphens^0a          ||||__ not (N)on-reassignable in life of Name Assigning Authority^0a             |||__ not (A)lphabetic-run-limited to pairs to avoid acronyms^0a          ||__ not (R)andomly sequenced to avoid series semantics^0a          |__ not (G)lobally unique within a registered namespace (currently^0a                     tests only ARK namespaces; apply for one at ark at cdlib.org)^0aAuthority: no Name Assigning Authority | no sub authority^0aNAAN:      no NAA Number^0awarning: no tab key AND doesn't begin with ':' --"`;
$x = `$cmd -d $td/foo id.fetch bigelem`;
like $x, qr/^bigelem: # Creation record.*doesn't begin with ':' --\n$/s,

	"big data value with hex modifier";

remove_td($td, $tdata);
}

# Use this subroutine to get actual commands onto STDIN (eg, bulkcmd).
#
sub run_cmds_on_stdin { my( $cmdblock, $flags )=@_;

	$flags ||= '';
	my $msg = file_value("> $td/getcmds", $cmdblock, "raw");
	$msg		and return $msg;
	return `$cmd $flags - < $td/getcmds`;
}

# yyy? check mstat command ?

{
remake_td($td, $tdata);
$ENV{EGG} = "$hgbase -p $td -d $td/bar";
my ($cmdblock, $x, $y);

$x = `$cmd --verbose mkbinder bar`;
like $x, qr/created.*bar/, 'created new binder';

$cmdblock = "
i.set @ @
@
@
i.fetch
i.purge
i.fetch
";
$x = run_cmds_on_stdin($cmdblock);
#like $x, qr/xxx\@:\s*\@.* i: 1\n.* i: 0\n/s,
like $x, qr/\@:\s*\@.* i: 1\n.* i: 0\n/s,
	"element named '\@' with data: '\@'";

# XXXX test (a) linecount probs with @ tokens and (b) skipping
#     tokens as commands on error

#exit; ###########

$cmdblock = "
j.purge
:hx j.set a b^20c^0ad
j.get a
";
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/\nb c\nd\n$/,
	"bulk mode hex modifier for value";

$cmdblock = '
j.purge
j|a.set @-
   b  

j|a.get
';
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/\n   b  \n$/,
	"one token from stdin";

$cmdblock = '
:hx j|a.set @-
c^0ad
e
f

j|a.fetch
';
$x = run_cmds_on_stdin($cmdblock);
like $x, qr/a: c\^0ad%0ae%0af\n\n$/,
	"one token from stdin and :hx doesn't touch it";

$cmdblock = '
j.set a @------boundary-----
some

paragraphs


here

-----boundary-----
j|a.get
';

$x = run_cmds_on_stdin($cmdblock);
like $x, qr/some\n\nparagraphs\n\n\nhere\n\n\n$/,
	"one token from stdin ending at string boundary";

$cmdblock = '
j|a.set @-10
z

y

xuvw
#eot
j|a.get
';

$x = run_cmds_on_stdin($cmdblock);
like $x, qr/z\n\ny\n\nxuvw\n$/,
	"two tokens from stdin ending at length counts";

#my $n = 100;
my $n = 1000000;

$cmdblock = "
j|a.set \@-$n
"
. ('b' x $n) 
. "
#eot
j|a.get
";

$x = run_cmds_on_stdin($cmdblock);

is length($x), $n + 2,
	"a $n-octet token taken from stdin";

##### #xxxx still need to fix line counts
#### XXXXX put modifiers into more than fetch and bind_del??

remove_td($td, $tdata);
}
