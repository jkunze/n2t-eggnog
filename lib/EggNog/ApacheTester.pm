package EggNog::ApacheTester;

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	prep_server update_server apachectl
	run_cmds_in_body run_cmdz_in_body run_ucmdz_in_body
	purge_test_realms
	crack_minter test_minters test_binders
	src_top webcl setpps get_user_pwd
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use Test::More;
use File::Value ':all';
use EggNog::ValueTester 'shellst_is';

#### start web server control code

my ($srvport, $srvbase_u, $ssvport, $ssvbase_u);
my ($api_script, $api_cwd, $perl5lib, $ldlibpath);
my ($apache_top, $src_top, $webcl);
my ($srvexec, $srvpre, $cf_file);
my @servers = ();	# list of servers started (later to be stopped)

sub update_server { my( $cfgdir )=@_;

	$src_top = `pwd -P`;	# NOTE: -P because we don't want symlinks
	chop $src_top;

	# Now we extract environment vars (EGNAPA_* and mongodb MG_*)
	# from a build_server_tree.cfg file, and insert them into this
	# (Perl's) environment, where they can then be accessed from test
	# scripts (via t/*.t).
	# yyy Not sure they actually need to be env vars before or after
	#
	# Important trick here for using the Bash config file (.cfg) to
	# set our own Perl process' environment variables:  we get the
	# bash script to parse everything in its config files and then
	# output the parsed values, one per line.  It might not
	# matter in the end that the values we get were in environment
	# variables (eg, we might call "set" simply to ask for all bash
	# variables), but what does matter for parsing right now is that
	# they come from bash strings so that they come to us on one line
	# (grep- friendly), and bash arrays do not come to us on one line.
	#
	map { /(^(?:EGNAPA|MG)_[^=]+)=(.*)/ and $ENV{$1} = $2 }
		split /\n/,
			` bash -c "./build_server_tree env $cfgdir" `;
			# ZZZ remove next 3
			#` bash -c "./build_server_tree env" `;
			#`bash -c "./build_server_tree env | grep '^EGNAPA_'"`;
			#` bash -c "source $sfile; env | grep '^EGNAPA_'" `;

	$ENV{EGNAPA_BUILDOUT_ROOT} or 
		print(STDERR "update_server: configuration error: ",
		    "EGNAPA_BUILDOUT_ROOT not set via config dir: $cfgdir\n"),
		return undef;

	# Throughout comments in this file, we refer to environment
	# variables in bash syntax, eg, $EGNAPA_TOP instead of
	# Perl's $ENV{EGNAPA_TOP}.  Now set global $cf_file which we
	# need later as an argument to the httpd command.  yyy
	#
	#$cf_file = "$ENV{EGNAPA_BUILDOUT_ROOT}/conf/httpd-other.conf";

	$cf_file = "$ENV{EGNAPA_BUILDOUT_ROOT}/conf/httpd.conf";

	my $config_extender = "./build_server_tree make $cfgdir ";

		#"./build_server_tree check $cfgdir >/dev/null 2>&1  &&  exit 0; 
		#	./build_server_tree build $cfgdir ";
		#"./build_server_tree check >/dev/null 2>&1    && exit 0; 
		#	./build_server_tree build";

	# XXX is the documentation true?
	# we make temporary extensions to the server
	# in $apache_top, writing them under $EGNAPA_BUILDOUT_ROOT and testing
	# against the new configuration.  We create files only if they're not
	# already there. xxx

	my $shell = $ENV{SHELL} || '/bin/bash';	# xxx needed?
	my $s = system($config_extender);
	$? and
		return undef;
	return 1;
}

sub prep_server { my( $cfgdir )=@_;

	$cfgdir or
		print(STDERR "prep_server: missing cfgdir argument\n"),
		return undef;
	my (@server_errs, $msg);
	update_server($cfgdir) or
		return "why: couldn't create server extensions for testing";

	$ENV{EGNAPA_TOP} or
		return "why: no Apache server (EGNAPA_TOP empty); " .
			"see build_server_tree";

	foreach my $v ( qw(PERL5LIB
			SHELL PERL_INSTALL_BASE
			EGNAPA_PORT_HPA EGNAPA_PORT_HPAS
			EGNAPA_PORT_HPR EGNAPA_PORT_HPRS
			EGNAPA_TOP EGNAPA_HOST EGNAPA_BUILDOUT_ROOT
			EGNAPA_BINDERS_ROOT EGNAPA_MINTERS_ROOT
			EGNAPA_SRVREF_ROOT
			EGNAPA_SSL_CERTFILE
			EGNAPA_SSL_KEYFILE
			EGNAPA_SSL_CHAINFILE
			) ) {
		$ENV{$v} or
			push @server_errs, "$v not defined";
	}
	$msg = join ", ", @server_errs;
	$msg and
		return "why: did you forget to set something in " .
			"build_server_tree.cfg?\n$msg";

	$apache_top = $ENV{EGNAPA_TOP};	# root of your Apache HTTP server

	# Now check if we have an apache httpd server to test.
	#
	$srvexec = "$apache_top/bin/httpd";
	-x $srvexec or				# ... or bail if not
		return "because there's no Apache server in $apache_top";

	# Key:
	# $apache_top = apache tree containing bin, conf, logs, etc
	#    eg, .../apache2
	# $apache_https_port = unused unprivileged port to test SSL with
	# $apache_http_port = unused unprivileged port to test regular http with
	# $minders_top = directory containing test minders
	#    eg, `pwd -P` -> .../src

	# yyy should use catfile for portability in pathnames?

	$perl5lib = $ENV{PERL5LIB};			# change for production

	# yyy $ldlibpath undefined for now ?needed only with BDB?

	#  permitting rollback => means running real_bind with one perl
	# and set of libs in PERL5LIB and INC, and beta_bind with another
	# set simultaneously.  This means two (at least) different
	# INSTALLBASE=... , eg, (mkperl to /n2t/local1,
	# mkperlalt to /n2t/local2, and /n2t/local symlink to one of them)

	my $script_px = "$src_top/blib/script/test_";
	# in production, $script_px might be "cgi-bin/"

	#$cgi_binder = "$src_top/blib/script/$exec_bind";
	#$cgi_binder = "${script_px}egg";
	# XXX change varnames and file names that include "noid"
	#$cgi_noid = "${script_px}nog";
	#$cgi_rmapper = "${script_px}rmapper";

	# --- Web Locations ---
	# Export these 4.
	#
	my $aptest = 'ZZZXXXXX';	# how to set real values for these 4?
	$srvport = $ENV{EGNAPA_PORT_HPA};
	$srvbase_u	= "http://$ENV{EGNAPA_HOST}:$srvport";
	$ssvport = $ENV{EGNAPA_PORT_HPAS};
	$ssvbase_u	= "https://$ENV{EGNAPA_HOST}:$ssvport";

##	(from Apache docs)
##	It is safer to avoid placing CGI scripts under the DocumentRoot in
##	order to avoid accidentally revealing their source code if the
##	configuration is ever changed. The ScriptAlias makes this easy by
##	mapping a URL and designating CGI scripts at the same time. If you do
##	choose to place your CGI scripts in a directory already accessible from
##	the web, do not use ScriptAlias. Instead, use <Directory>, SetHandler,
##	and Options as in:
##
##	<Directory /usr/local/apache2/htdocs/cgi-bin >
##	  SetHandler cgi-script
##	  Options ExecCGI
##	</Directory>
##
##	This is necessary since multiple URL-paths can map to the same
##	filesystem location, potentially bypassing the ScriptAlias and
##	revealing the source code of the CGI scripts if they are not restricted
##	by a Directory section.

	# --- Web-to-Filesystem ---
	#
	#$httpd_opts = "-f $cf_file";

	# Define base web client command.  Using wget
	#
	# xxx is wget/curl slower and not as portable as native Perl LWP module?
	#my $webcurl = 'curl -d @xxx -u user:pass ... 2>&1 ';
	# curl -u username:password -X POST -H 'Content-Type: text/plain' \
	#	--data-binary @metadata.txt
	# curl -u username:password --data-binary @metadata.txt
	# --user-agent="wget:<proxy2>"

	# XXX this should be a standalone client that can be used more
	#     generally, eg, "wegn"
	# XXX if $webcl ever becomes a Perl client, add perlbrew bit for
	#     Mac support
	$webcl = 'wget --output-document - '	# send http body to stdout
	#'--post-data=XXXX ' .
	#	. '--auth-no-challenge '	# ? might this help?
		. '--no-check-certificate '	# for https ?no harm if http?
		. '--server-response 2>&1 ';	# plus headers from stderr

	return ('', $src_top, $webcl,
		$srvport, $srvbase_u, $ssvport, $ssvbase_u,
	);
}

# This routine calls httpd directly instead of the usual system-supplied
# apachctl script; the latter screws up possibility of argument passing.
#
# Returns '' on success or an error message on failure.
#
sub apachectl { my( $action, $sroot, $force )=@_;

	# Jump in and do $action right away.  If starting, do more stuff.
	# If real production service, do not stop or start the server --
	# do not even call $srvexec.
	#
	$sroot ||= $apache_top;			# server root (global var)

	# XXX drop this next test?
	my $aptest = 'XXXXX';	# how to set real values for this?
	if ($aptest eq 'realprod') {
		my $x = `$webcl $srvbase_u`;	# simple request for root doc
		like $x, qr{HTTP/\S+\s+\d\d\d},
			'REAL PRODUCTION web server still lives';
		$x =~ qr{HTTP/\S+\s+\d\d\d} or
			return "error: $x";
		return '';
	}
	$srvpre ||= '';
	my $cmd = "$srvpre $srvexec -d $sroot -k $action -f $cf_file";
		# Don't use -E and startup errors helpfully reach the console.
	my $out = ` $cmd 2>&1 `;
	#	` $srvpre $srvexec -d $sroot -k $action -f $cf_file 2>&1 `;

	# !! NOTE: sometimes server startup hangs on the
	# Mac depending on Airport being on/off.  Switching Airport
	# on and off can seem to clear things up.

	shellst_is(0, $out, "apachectl $action ($srvport)");
	if ($out ne '' || ($? >> 8) != 0) {
		my $msg = "apachectl error: $out (result of $cmd)";
		#print STDERR $msg;	# as test harness too discreet?
		return $msg;
	}

	$action eq 'graceful-stop' || $action eq 'stop' and
		# diag("stopping server $sroot")
		return '';
	$action ne 'start' and
		return '';	# done unless we did 'start'

	# If we get here, we just started a server.
	#
	push(@servers, $sroot);		# remember server for later cleanup
	$SIG{INT} = \&catch_zap;	# catch interrupts to trigger cleanup
	
	my $x = `$webcl $srvbase_u`;	# simple test: request the root doc

	like $x, qr{HTTP/\S+\s+\d\d\d}, 'web server lives';
	$x =~ qr{HTTP/\S+\s+\d\d\d} or
		return "error: $x";

	return '';
}

# for when we need to bail out early and clean up all running servers
sub cleanexit {
	apachectl('stop', $_)	for (@servers);
}

sub catch_zap {
	my $signame = shift;
	cleanexit();
}

#### end web server control code

# Set pps string with user, password, and "on behalf of" user, the latter
# sent as 'Acting-For: joey' and arriving as 'HTTP_ACTING_FOR=joey'.
# 
# The user should be given as, eg, http://n2t.net/ark:/99166/... -> &P/...
#
sub setpps { my( $user, $pw, $actingfor ) = (shift||'', shift||'', shift||'');
	my $pps = '';
	$user and		$pps .= qq@--user=$user @;
	$pw and			$pps .= qq@--password=$pw @;
	$actingfor and		$pps .= qq@--header="Acting-For: $actingfor" @;
	return $pps;
}

# Return $login and $pwd for a given $user in a given $realm, as defined
# by $cfgdir configuration (build_server_tree.cfg) settings.
# yyy pwd=password confusing, given pwd=print working directory
#
#sub get_user_pwd { my( $realm, $user ) = ( shift, shift );
sub get_user_pwd { my( $realm, $user, $cfgdir ) = ( shift, shift, shift );

	$user ||= $realm;
	$cfgdir ||= 'web';		# yyy kludgy literal perhaps
	my $pwd = `wegnpw $user $cfgdir $realm`;
	chop $pwd;
	return ($user, $pwd);

#	$user ||= '';
#	my @flp = split ' ', $ENV{EGNAPA_PW};
#	my ($file, $login, $pwd);
#	while (($file, $login, $pwd) = (shift @flp, shift @flp, shift @flp)) {
#		$file or
#			return (undef, undef);
#		$file eq "pwdfile_$realm" and ! $user || $login eq $user and
#			return ($login, $pwd);
#	}
}

# Extract and return 2-element list: naan, shoulder
sub crack_minter { my( $fqshdr ) = ( shift||'' );
	$fqshdr =~ m{(\w+)/ark/(.+)} or
		print("crack_minter: bad fully-qualified shoulder: $fqshdr\n"),
		return (undef, undef);
	return ($1, $2);
}

# Called with two populators (users), $u1 and $u2, that have minters,
# this routine pre-processes a shoulder list to set up a test against
# a non-authorized minter.  It remembers one
# (the final, but order doesn't matter) $u1 minter and
# one (the final also) $u2 minter, so that in a subsequent loop it can
# pause and attempt to mint against the _other_ minter; the test will
# succeed if that attempt fails because of an authorization error.
# xxx binders and minters are a bit mixed up in the var names
#     we derive user name from binder name(?)
#
sub noauth_test { my( $pps, $popminder, $naanblade, $u1, $u2, @fqshoulders )=@_;

	my ($x, $u1binder, $u1naanblade, $u2binder, $u2naanblade);
	$popminder ||= '';
	$naanblade ||= '';
	unless ($u1binder && $u2binder) {
		for my $fqsr (@fqshoulders) {
			# important that this be local to loop
			my ($ppmdr, $nnbld) = crack_minter $fqsr;
			$ppmdr eq $u1 and
				($u1binder, $u1naanblade) = ($ppmdr, $nnbld)
			or
			$ppmdr eq $u2 and
				($u2binder, $u2naanblade) = ($ppmdr, $nnbld)
			;
		}
		ok $u1binder && $u2binder, "initialized noauth_test";
	}
	my ($pbinder, $nblade) = ('', '');
	$popminder eq $u1binder and $naanblade eq $u1naanblade and
		($pbinder, $nblade) = ($u2binder, $u2naanblade)
	or
	$popminder eq $u2binder and $naanblade eq $u2naanblade and
		($pbinder, $nblade) = ($u1binder, $u1naanblade)
	;
	$pbinder and $nblade or		# both have to have matched or we
		return 0;		# return without doing any noauth test

	# If we get here, which is exactly once per $popminder,
	# we'll test that we're unauthorized to use another's minter
	# and unauthorized to use another's binder.

	$x = `$webcl $pps "$ssvbase_u/a/$pbinder/m/ark/$nblade? mint 1"`;
	like $x, qr{HTTP/\S+\s+401\s+authorization.*ation failed}si,
		"authNd populator \"$popminder\" cannot mint from " .
			"a \"$pbinder\" minter";

	$x = `$webcl $pps "$ssvbase_u/a/$pbinder/b? i.set bow wow"`;
	like $x, qr{HTTP/\S+\s+401\s+authorization.*ation failed}si,
		"authNd populator \"$popminder\" cannot write on " .
			"a \"$pbinder\" binder";

	$x = `$webcl $pps "$ssvbase_u/a/$pbinder/b? version"`;
	like $x, qr{HTTP/\S+\s+401\s+authorization.*ation failed}si,
		"authNd populator \"$popminder\" cannot even reference " .
			"a \"$pbinder\" binder";

	return 1;
}

sub test_minters { my( $cfgdir, $u1, $u2, @fqshoulders )=@_;

	# Real processing loop.
	my $noauth_tests = 0;
	my ($x, $pps);
	my $user = undef;	# kludge for t/apachebase.t user/realm tests
	#$cfgdir eq 't/web' and
	$cfgdir eq 'web' and
	    	$user = 'testuser1';

	for my $fqsr (@fqshoulders) {

	    my ($popminder, $naanblade) = crack_minter $fqsr;

	    # set populator realm and user, eg, ezid/ezid
	    $pps = setpps get_user_pwd $popminder, $user, $cfgdir;

	    # use \w{4,7} in case someone hammers the minter during testing
	    # and it expands from 4 to 7 chars xxx but this is only for
	    # minters that persist between rebuilds, right? still relevant?
	    $x =
	      `$webcl $pps "$ssvbase_u/a/$popminder/m/ark/$naanblade? mint 1"`;
	    like $x,
		qr{HTTP/\S+\s+401\s+Authorization.*s: $naanblade\w{4,7}\n}si,
		  "populator/binder \"$popminder\" mints from $naanblade";

	    # We'll piggyback another use for the noauth_test, which is that
	    # it happens also to test exactly one
	    noauth_test($pps, $popminder, $naanblade,
			$u1, $u2, @fqshoulders) and
		$noauth_tests += 3;
	}

	is $noauth_tests, 6,
		"unauthorized minter traps sprung: $noauth_tests";
}

#pwdfile="\
#	pwdfile_pestx	testuser1	testpwd1a \
#	pwdfile_pestx	testuser2	testpwd2a \
#\
#	pwdfile_pesty	testuser1	testpwd1b \
#	pwdfile_pesty	testuser2	testpwd2b \
#"

# First arg is $binders_root directory.
# xxx add $cfgdir arg here and in t/*.t  (see /get_user and see /test_.in.ers

sub test_binders { my( $cfgdir, $binders_root, $indb, @binders )=@_;

    # A random specific user
    my $for_user = "http://n2t.net/ark:/99166/b4cd3";		# long form
    my $u = "&P/b4cd3";				# short, &P-compressed form

    # XXX kludge: relies on the binder name containing owner name up to '_'!
    #     kludge still in effect?
    #     eg, for exdb: egg_bgdflt.P/b4cd3_s_pesty?
    for my $b (@binders) {

	my ($x, $pps);
	#my $user = $b;
	#$user =~ s/_.*$//;	# xxx kludge!
	#my ($login, $pwd) = xget_user_pwd($user);
	my $realm = $b;
	$realm =~ s/_.*$//;	# xxx kludge! -- still needed?

	my $user = undef;	# kludge for t/apachebase.t user/realm tests
	#$cfgdir eq 't/web' and
	$cfgdir eq 'web' and
	    $user = 'testuser1';

	# set populator realm and user, eg, ezid/ezid
	my ($login, $pwd) = get_user_pwd $realm, $user, $cfgdir;

	$pps = setpps $login, $pwd, $for_user;
	#$pps = setpps get_user_pwd($user, $user), $for_user;
	my $remuser = "remote user: $login acting for $u";

	# This contains side tests: --verbose causes remote user to show,
	# and we test that (a) the user does show, (b) that the Acting-For
	# user shows, and (c) that the Acting-For user is &P-compressed.
	# 
	# REAL database change
	$x = `$webcl $pps "$ssvbase_u/a/$b/b? --verbose i.set bow wow"`;
	like $x, qr{Authorization Required.*HTTP/.+200.*\Q$remuser}si,
		"protected test binder \"$b\" sets an element";

	$x = `$webcl $pps "$ssvbase_u/a/$b/b? i.fetch bow"`;
	like $x, qr{Authorization Required.*bow:\s*wow}si,
		"protected binder \"$b\" returns that element";

	# REAL database change
	$x = `$webcl $pps "$ssvbase_u/a/$b/b? i.delete bow"`;
	like $x, qr{Authorization Req.*removed.*bow.*egg-status: 0}si,
		"protected binder \"$b\" allows deleting that element";

	if ($indb) {
	    # yyy "tail" not portable to Windows; prefer File::ReadBackwards
	    #$y = flvl("< $binders_root/$b/egg.rlog", $x);
	    $x = `tail -1 $binders_root/$b/egg.rlog`;
	    like $x, qr{^\*\Q$u }m,
	    	"previous operation's HTTP_ACTING_FOR user logged";
	}

	# XXX should perhaps add HTTP_ACTING_FOR to txnlog?

	$x = `$webcl $pps "$ssvbase_u/a/$b/b? <xyzzy>i.set bow wow"`;
	like $x, qr{rization Req.*HTTP/.+200.*not allowed.*egg-status: 1}si,
	    "\"$realm\" not allowed to switch binders via <> prefix";
    }
}

# Usage:     purge_test_realms($ids_array_ref, 'ezid', 'oca', ...)
#
# xxx not so true?
# Unlike binders created by other test scripts (oca_test, ezid_test,
# etc.), these binders persist between script calls, so if we should
# cleanup any values (before and after, for certainty) that we'll rely on.
# We need to be all the more careful in this cleanup when testing real
# binders.  Put all such ids into a var such as @cleanup_ids.
#
sub purge_test_realms { my( $cfgdir, $td, $cleanup_idsR, @realms )=@_;

	my ($binder, $cmdblk, $pps, $x);
	my $user = undef;	# kludge for t/apachebase.t user/realm tests
	#$cfgdir eq 't/web' and
	$cfgdir eq 'web' and
	    	$user = 'testuser1';
	foreach my $realm (@realms) {
		$cmdblk = join "\n", map "$_.purge", @$cleanup_idsR;
		#$pps = setpps xget_user_pwd $realm;
		$pps = setpps get_user_pwd $realm, $user, $cfgdir;
		#$pps = setpps get_user_pwd $realm, $realm;
		# XXX kludge: realm binder name assumed to be $realm.'_test'
		$binder = $realm . '_test';
		$x = run_cmds_in_body($td, $pps, $binder, $cmdblk);
		like $x, qr/egg-status: 0\n/i,
			"purged ${realm}_test for $realm realm";
	}
}

# Use this subroutine to get commands into http request body (stdin)
# where they will run remotely as bulk (batch) commands.  Call with:
#    $x = run_cmds_in_body($td, $flags, $binder, $cmdblock);
#
sub run_cmds_in_body { my( $td, $flags, $binder, $cmdblock )=
			 (shift, shift,   shift,     shift );

	my $msg = flvl("> $td/getcmds", $cmdblock);
	$msg		and return $msg;
	$flags .= " --post-file=$td/getcmds " . join(" ", @_);
	my $ret = `$webcl $flags "$ssvbase_u/a/$binder/b?-" < $td/getcmds`;
	return $ret;
}

# Use this subroutine to insert commands into an http(s) request body,
# with optional authentication info ($realm credentials), where they
# will run remotely as bulk (batch) commands.  If $realm specifies a
# populator (user), it fetches and uses their credentials.  Any other
# arguments are passed as flags to the web client (eg, "--verbose").
# Call with:
#
#  $x = run_cmdz_in_body($cfdgir, $td, $realm, $binder, $cmdblock);
#
sub run_cmdz_in_body { my( $cfgdir,   $td, $realm, $binder, $cmdblock )=
			 (   shift, shift,  shift,   shift,     shift );
			 # other args in @_ will be used as flags

	my $msg = flvl("> $td/getcmds", $cmdblock);
	$msg		and return $msg;
	my $flags = " --post-file=$td/getcmds " . join(" ", @_);
	$realm and
		$flags .= ' ' . setpps(get_user_pwd($realm, $realm, $cfgdir));
	my $ret = `$webcl $flags "$ssvbase_u/a/$binder/b?-" < $td/getcmds`;
	return $ret;
}

# a version that accepts a $user arg too
sub run_ucmdz_in_body { my( $cfgdir,   $td, $realm, $user, $binder, $cmdblock )=
			 (    shift, shift,  shift, shift,   shift,     shift );
			 # other args in @_ will be used as flags

	my $msg = flvl("> $td/getcmds", $cmdblock);
	$msg		and return $msg;
	my $flags = " --post-file=$td/getcmds " . join(" ", @_);
	$realm and
		$flags .= ' ' . setpps(get_user_pwd($realm, $user, $cfgdir));
	my $ret = `$webcl $flags "$ssvbase_u/a/$binder/b?-" < $td/getcmds`;
	return $ret;
}

# Convenience for debugging $webcl.  It looks for an internal server error
# in output returned by $webcl; if found, it adds the tail portion of the
# error log for a more complete picture of the error.
#
sub enhance { my( $ret ) = ( shift );

	my $n = "-5";
	$ret =~ /Internal Server Error/ and
		$ret .= "Tail $n of error_log:\n" .
			`tail $n $apache_top/logs/error_log`;
	return $ret;
}

#upi: testuser | testpass | &P/9   yyy
#use EggNog::RUU;   yyy
#$pps = "--user=admin --password=$EggNog::RUU::adminpass";
#$pps = "--user=$upw --password=$upw";

1;

=head1 NAME

ApacheTester - routines to support Apache testing for Egg.pm and Nog.pm

=head1 SYNOPSIS

 use EggNog::ApacheTester ':all';	    # import routines into a Perl script

 get_user_pwd ( $realm, $user, $cfgdir)     # get login name and password for
                                    # $user in a given populator $realm;
                                    # usually $user and $realm are same

 setpps( $user, $pw, $actingfor )   # return partial wget option string
                                    # sets Acting-For header with arg 3

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2013 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
