# xxx should do a version of this for noid
use 5.10.1;
use Test::More qw( no_plan );

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

# Basic protections tests, shell vs web mode
{
remake_td($td, $bgroup);
my $x;

$x = `$cmd -p $td mkbinder betty`;
shellst_is 0, $x, "shellmode (non-webtype) make binder named betty";

$x = `$cmd -p $td --qs "--ua mkbinder bar"`;
shellst_is 1, $x, "webmode make binder fails";
like $x, qr{unauth},
	"webmode mkbinder failed because unauthorized";

$x = `$cmd -d $td/betty foo.set bar zaf`;
like $x, qr{^$},
	"in shellmode, set id value";

# XXXXXX start section to rethink
#        these permissions don't make any sense right now
#        in light of how HTTP Basic works -- need to rethink
# xxxxxx don't worry if these tests fail

$x = `$cmd -d $td/betty --qs "--ua foo.get bar"`;
like $x, qr{Content-Type: text/plain; charset=UTF-8\n.*zaf}s,
	"in webmode, get that id value with default 'public' permission";

$x = `$cmd -d $td/betty --qs "--ua foo.set moodle cow"`;
like $x, qr{Content-Type: text/plain.*egg-status: 0}s,
	"webmode set id value fails (xxx not) with default public permission";

$x = `$cmd -d $td/betty --ack --qs "--ua foo.rm moodle"`;
like $x, qr{egg-status: 0},
	"remove id binding stopped (xxx not) in webmode";

# yyy we no longer use per-binder config files -- is that a good thing?
#my $cf = "$td/betty/egg_conf_default";
#$x = `2>&1 $EggNog::ValueTester::perl -pi -e "s,P/2.*\\D+40\$,P/2||61," $cf`;
#my $m = flvl("< $cf", $x);
#is $m, '',
#	"edited permission default in config file";
#like $x, qr/P\/2.*\|61$/m,
#	"edited it in fact to add public write";

#print "x=$x\n"; exit; #############

$x = `$cmd -d $td/betty --ack --qs "--ua foo.set moodle cow"`;
like $x, qr{oxum: 3.1\n}s,
	"set id value in webmode now works with new public permission";

$x = `$cmd -d $td/betty --ack --qs "--ua foo.add moodle sheep"`;
like $x, qr{oxum: 5.1\n}s,
	"add id value in webmode also works";

$x = `$cmd -d $td/betty --ack --qs "--ua foo.add moodle \@file"`;
like $x, qr{unauth}s,
	"webmode has no access to local server files";

# XXXXXX end rethink section

$x = `$cmd -d $td/betty --qs "--ua foo.fetch"`;
like $x,
 qr/^Content-Type:.*foo.*^bar:\s*zaf.*^moodle:.*cow.*^# elements.*: 3\n/ms,
 	"fetch bindings in webmode gets binding from non-webmode";

like $x,
 qr/^moodle:\s*sheep$/ms,
 	"and also gets webmode binding";

$x = `$cmd -d $td/betty --ack --qs "--ua foo.rm moodle"`;
like $x, qr{oxum: 8.2},
	"remove id binding succeeds in webmode with new permission";

$x = `$cmd -d $td/betty --qs "--ua foo.fetch"`;
unlike $x, qr/moodle/,
	"binding gone from next webmode fetch";

$x = `$cmd -d $td/betty --qs "--ua version"`;
like $x, qr{Content-Type: text/plain; charset=UTF-8\n.*\nversion:}s,
	"webmode version command";

# XXXXXX why does the error message for this next print some podded-out code??
#$x = `$cmd -d $td/betty --qs "--ua --mindex / version"`;

$x = `$cmd -d $td/betty --qs "--ua help"`;
$x =~ s/\n\n.+/\n/s;	# isolate a header block that is followed by content
like $x, qr{^Content-Type: text/plain; charset=UTF-8\n}m,
	"webmode help command";

$x = `$cmd -d $td/betty --qs "--ua man"`;
#$x =~ s/\n\n.+POD ERRORS.+/\n/s;	# isolate header followed by manpage-like stuff

$x =~ s/\n\nEGG\(1\).*//s;	# isolate header followed by manpage-like stuff
like $x, qr{^Content-Type: text/plain; charset=UTF-8$}m,
	"webmode man command";

$x = `$cmd -d $td/betty --qs "--ua xyzzy"`;
like $x, qr{egg-version: .*egg-status: 1}s,
	"unknown command produces egg-status of 1";

# XXX do version, help, and man for noid too

remove_td($td, $bgroup);
}
