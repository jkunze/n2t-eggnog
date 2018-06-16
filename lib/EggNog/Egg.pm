package EggNog::Egg;

# Author:  John A. Kunze, jak@ucop.edu, California Digital Library
#		Originally created, UCSF/CKM, November 2002
# 
# Copyright 2008-2012 UC Regents.  Open source BSD license.

use 5.010;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	exdb_get_dup indb_get_dup id2elemval egg_inflect
	flex_enc_exdb flex_enc_indb
	PERMS_ELEM OP_READ
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Path;
use File::OM;
use File::Value ":all";
use File::Copy;
use File::Find;
use EggNog::Temper ':all';
use EggNog::Binder ':all';	# xxx be more restricitve
use EggNog::Log qw(tlogger);
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;

our @suffixable = ('_t');	# elems for which we call suffix_pass

use constant HOW_SET		=>  1;
use constant HOW_ADD		=>  2;
use constant HOW_INSERT		=>  3;
use constant HOW_EXTEND		=>  4;
use constant HOW_INCR		=>  5;
use constant HOW_DECR		=>  6;

use constant NEXT_LIST_CMD_MAX	=>  1000;	# enough? too many?

use constant PKEY		=>  '_id';	# exdb primary key, which
	# happens to be a MongoDB reserved key that enforces uniqueness

our %md_kernel_map;
our %md_type_map;
our $unav = '(:unav)';
our $reserved = 'reserved';		# yyy ezid; yyy global
our $separator = '; ';			# yyy anvl separator
our $SL = length $separator;

# xxx test bulk commands at scale -- 2011.04.24 Greg sez it bombed
#     out with a 1000 commands at a time; maybe lock timed out?

# xxxThe database must hold nearly arbitrary user-level identifiers
#    alongside various admin variables.  In order not to conflict, we
#    require all admin variables to start with ":/", eg, ":/oacounter".
#    We use "$A/" frequently as our "reserved root" prefix.

# We use a reserved "admin" prefix of $A for all administrative
# variables, so, "$A/oacounter" is ":/oacounter".
#
my $A = EggNog::Binder::ADMIN_PREFIX;
my $Se = EggNog::Binder::SUBELEM_SC;	# indb case
my $So = '|';				# sub-element separator on OUTPUT
my $EXsc = qr/(^\$|[.^])/;		# exdb special chars, mongo-specific

use Fcntl qw(:DEFAULT :flock);
use File::Spec::Functions;

#use DB_File;
use BerkeleyDB;
use constant DB_RDWR => 0;		# why BerkeleyDB doesn't define this?

our $noflock = "";
our $Win;			# whether we're running on Windows

# Legal values of $how for the bind function.
# xxx document that we removed: purge replace mint peppermint new
# xxxx but put "mint" back in!
# xxx implement append and prepend or remove!
# xxx document mkid rmid
# xxx valid_hows is unused -- remove here and in Nog.pm?
my @valid_hows = qw(
	set let add another append prepend insert delete mkid rm
);

#
# --- begin alphabetic listing (with a few exceptions) of functions ---
#

# xxxxx genonly seems to be there to relax validation,
#       which is a direction we want to go further in
#	$$noid{"$A/genonly"} && $validate
#		#&& ! validate($noid, "-", $id) and
#		&& ! validate($noid, "-", "", $id) and
#			return(undef)

#if (! defined($$noid{"$id\t$elem"})) {		# currently unbound
	#if ($oldvalcnt == 0) {				# currently unbound
	#	grep(/^$how$/, qw( replace append prepend delete )) == 1 and
	#		addmsg($bh, qq@error: for "bind $how", "$oid $oelem" @
	#			. "must already be bound."),
	#		dbunlock(),
	#		return(undef);
	#	# Note: cannot set to "" while R_DUP flag is set without
	#	# creating an extra value, so comment out next line and
	#	# use $oldval to deal with previous settings.
	#	#
	#	# $$noid{"$id\t$elem"} = "";	# can concatenate with impunity
	#}
	#else {						# currently bound
	#	grep(/^$how$/, qw( new mint peppermint )) == 1 and
	#		addmsg($bh, qq@error: for "bind $how", "$oid $oelem" @
	#			. " cannot already be bound."),
	#		dbunlock(),
	#		return(undef);
	#}
	# We don't care about bound/unbound for:  set, add, insert, purge

# XXXX want mkid and mkbud to be soft if exists, like open WRITE|CREAT
#  xxx and rlog it
sub mkid {
}

# MUCH FASTER way to query mongo for existence
# https://blog.serverdensity.com/checking-if-a-document-exists-mongodb-slow-findone-vs-find/

# XXX exdb version of this?

# calls flex_enc_indb

sub egg_exists { my( $bh, $mods, $id, $elem )=@_;

	my $db = $bh->{db};
	my $opt = $bh->{opt};
	my $om = $bh->{om};

	defined($id) or
		addmsg($bh, "no identifier name given"),
		return undef;

	my ($exists, $key);
	my $irfs;		# ready-for-storage versions of id, elem, ...
	if (defined $elem) {	# do "defined $elem" since it might match /^0+/
		# xxx are there situations (eg, from_rawidtree that
		#     should prevent us calling this?
		EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id, $elem) or
			addmsg($bh, "instantiate failed from exists"),
			return undef;
# xxx indb-specific
		$irfs = flex_enc_indb($id, $elem);
		$key = $irfs->{key};		# only need encoded key
		$exists = defined( $bh->{tied_hash_ref}->{$key} )
				? 1 : 0;
	}
	else {					# else no element was given
		# xxx are there situations (eg, from_rawidtree that
		#     should prevent us calling this?
		EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id) or
			addmsg($bh, "instantiate failed from exists no elem"),
			return undef;
# xxx indb-specific
		$irfs = flex_enc_indb($id);
		$key = $irfs->{key};		# only need encoded key
		$exists = defined( $bh->{tied_hash_ref}->{$key . PERMS_ELEM} )
				? 1 : 0;
	# xxxx need policy on protocol-breaking deletions, eg, to permkey
	}

	my $st = $om->elem("exists", $exists);
	# XXX this om return status is being ignored

	return 1;
}

# xxx purge bug? why does the @- arg get ignored (eg, doesn't eat up the
# lines that follow)?
# i.set a b
# i.set b c
# i.set c d
# i.purge @-
# # admin + unique elements found to purge under i: 5
# element removed: i|__mc
# element removed: i|__mp
# element removed: i|a
# element removed: i|b
# element removed: i|c

# calls flex_enc_indb

sub egg_purge { my( $bh, $mods, $lcmd, $formal, $id )=@_;

	my $sh = $bh->{sh};
	my @elems = ();
	my $om = $bh->{om};

	my $txnid;		# undefined until first call to tlogger
	$txnid = tlogger $sh, $txnid, "BEGIN $id.$lcmd";

	# A possibility of redundancy since we also check authz in egg_del,
	# but purge has special sweeping powers and it's only one extra check.
	#
	#$bh->{ruu}->{remote} and		# check authz only if on web
# XXXX bring this in line with other authz sections! (or delete)
#	$id_p = $dbh->{$id_permkey} or		# protocol violation!!
#		addmsg($bh, "$id: id permissions string absent"),
#		return undef;
#	# xxx faster if we pass in permstring $id_p here?
#	! authz($bh->{ruu}, $WeNeed, $bh, $id, $key) and
#		unauthmsg($bh, "xxxb"),
#		return undef;
#######
	#$bh->{remote} and			# check authz only if on web
	#	$id =~ /^:/ ||	# yyy ban web attempts to change admin values
	#	! authz($bh->{ruu}, OP_DELETE, $bh, $id) and
	#		unauthmsg($bh),
	#		return undef;

	EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id) or
		addmsg($bh, "instantiate failed from purge"),
		return undef;

	my $ret;
	if ($sh->{exdb}) {
		my $erfs = flex_enc_exdb($id);		# ready-for-storage id
		my $msg;
		my $ok = try {
			my $coll = $bh->{sh}->{exdb}->{binder};	# collection
	# xxx make sure del and purge are done for exdb
	# xxx ALL elems should be arrays, NOT returning them
	# xxx who calls flex_enc_exdb?
			# in delete_many, "many" refers to records/docs,
			# but with our uniqueness constraint, delete_one
			# should be sufficient yyy right?
			# yyy deleting everything as if $mods->{all} = 1;
			$ret = $coll->delete_many(
				#{ PKEY() => $id },	# query clause
				{ PKEY() => $erfs->{id} },	# query clause
			)
			// 0;		# 0 != undefined
		}
		catch {
			$msg = "error deleting id \"$id\" from "
				. "external database: $_";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and 	# test undefined since zero is ok
			addmsg($bh, $msg),
			return undef;
		# xxx do we check $ret for return?
	}
	if (! $sh->{indb}) {
		# xxx leave now
		tlogger $sh, $txnid, "END SUCCESS $id.$lcmd";
		return $ret;
	}
# no longer need to flex_enc_indb before get_rawidtree
#	my $irfs;		# ready-for-storage versions of id, elem, ...
#	$irfs = flex_enc_indb($id);			# we want side-effect
#	$id = $irfs->{id};		# need encoded $id

	# Set "all" flag so get_rawidtree() returns even admin elements.
	#
	$mods->{all} = 1;			# xxx downstream side-effects?
	# NB: arg3 undef means don't output results
	# calling with UNencoded $id
	get_rawidtree($bh, $mods, undef, \@elems, undef, $id) or
		addmsg($bh, "rawidtree returned undef"),
		return undef;

	#$out_id = $id ne '' ? $id : '""';
	#$out_id =~		# "flex_dec_indb" as needed
	#	s/\^([[:xdigit:]]{2})/chr hex $1/eg;

	my $out_id;			# output ready form
	$out_id = flex_dec_for_display($id);
	my $retval;
	$om and ($retval = $om->elem('elems',		# print comment
		" admin + user elements found to purge under $out_id: " .
			scalar(@elems), "1#"));
		#" admin + unique elements found to purge under " .
		#($id ne '' ? $id : '""') . ": " . scalar(@elems), "1#"));

	tlogger $sh, $txnid, "END SUCCESS $id.$lcmd";
	my $msg;
	$msg = $bh->{rlog}->out("C: $id.$lcmd") and
		addmsg($bh, $msg),
		return undef;

	# Give '' instead of $lcmd so that egg_del won't create multiple
	# log events (for each element), as we just logged one 'purge'.
	#
	my $delst;

	my $prev_elem = "";	# initialize to something unlikely
	for my $elem (@elems) {
		$elem eq $prev_elem and	# prior egg_del call deleted all dupes
			next;		# so skip another call to avoid error
		$retval &&= (
			# calling with UNencoded $id and $elem
			$delst = egg_del($bh, $mods, '', $formal, $id, $elem), 
			($delst or outmsg($bh)),
		$delst ? 1 : 0);
	}
	## begin loop: control (by statement modifier) at the bottom
	#	$retval &&= (
	#		$delst = egg_del($bh, $mods, '', $formal, $id, $_), 
	#		($delst or outmsg($bh)),
	#	$delst ? 1 : 0)
	#for (@elems);

	return $retval;
}

# get element as an array of dupes
# xxx assumes "rfs" args

##====
#		if ($sh->{fetch_exdb}) {	# if EGG_DBIE is e or ei
#			my $result;
#			# yyy binder belongs in $bh, NOT to $sh!
#			#     see ebopen()
#			my $coll = $bh->{sh}->{exdb}->{binder};	# collection
#			my $msg;
#			my $ok = try {
## xxx flex_enc_exdb $id before lookup
#				$result = $coll->find_one(
#					{ PKEY()	=> $id },
#				)
#				// 0;		# 0 != undefined
#			}
#			catch {
#				$msg = "error fetching id \"$id\" " .
#					"from external database: $_";
#				return undef;
#				# returns from "catch", NOT from routine
#			};
#			! defined($ok) and # test undefined since zero is ok
#				addmsg($bh, $msg),
#				return undef;
#			# yyy using $result how?
#			#use Data::Dumper "Dumper";
#			#print Dumper $result;
##====
sub exdb_get_dup { my( $bh, $id, $elem )=@_;

	# yyy not error checking the args
	my ($result, $msg);
	my $ok = try {				# exdb_get_dup
		my $coll = $bh->{sh}->{exdb}->{binder};	# collection
		$result = $coll->find_one(
			{ PKEY() => $id },	# query
			{ $elem => 1 },		# projection
					# _id returned by default
		)
		// 0;		# 0 != undefined
	}
	catch {
		$msg = "error fetching id \"$id\" from external database: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and 	# test for undefined since zero is ok
		addmsg($bh, $msg),
		return undef;
	$result && $result->{$elem} or	# if nothing found, return empty array
		return ();
#say STDERR "xxx result->elem($elem): $result->{$elem}";
	my $ref = ref $result->{$elem};
	$ref eq 'ARRAY' and		# already is array ref, so return array
		return @{ $result->{$elem} };
	$ref ne '' and
		addmsg($bh, "unexpected element reference type: $ref"),
		return undef;
	return ( $result->{$elem} );	# make array from scalar and return it
}

## xxx should convert remaining calls to this into calls to {in,ex}db_get_dup
## xxx assumes $id and $elem args are already encoded "rfs"
#sub egg_get_dup { my( $bh, $id, $elem )=@_;
#
#	my $sh = $bh->{sh};
#	my $exdb = $sh->{exdb};
#	my (@indups, @exdups, $ret);
#	my $wantlist = wantarray();
#
#	$sh->{fetch_indb} and		# set by EggNog::Session::config
#	# xxx who calls/called flex_encode?
#		@indups = indb_get_dup($bh->{db},
#			$id . $Se . $elem);
#		# yyy if error?
#
#
#	if ($sh->{fetch_exdb}) {		# set by EggNog::Session::config
##		try {
##			my $coll = $bh->{sh}->{exdb}->{binder};	# collection
##	# xxx make sure del and purge are done for exdb
##	# xxx ALL elems should be arrays, NOT returning them
##	# xxx who calls flex_encode?
#
#			# We could use find_id() Perl method, but there aren't
#			# parallel Perl methods for update, delete, etc., so 
#			# we preserve parallelsim with the *_one() methods.
#
##			$ret = $coll->find_one(
##				{ PKEY() => $id },	# query
##				{ $elem => 1 },		# projection
##						# _id returned by default
##			);
##		}
##		catch {
##			addmsg($bh, "exception fetching id \"$id\" from "
##				. "external database: $@");
##			return undef;
##		};
##		@exdups = ( $ret->{ $elem } );
#
#		@exdups = exdb_get_dup($bh, $id, $elem);
#		# yyy if error?
#		#use Data::Dumper "Dumper"; print Dumper $ret;
#
#	       #$sh->{ietest} and $exdups[0] ne $indups[0] and $sh->{txnlog} and
#		#	$sh->{txnlog}->out("ERROR: difference alert " .
#		#		"for id \"$id\", element \"$elem\"");
#
#		# it is not an error to call tlogger with $txnid of ''
#		$sh->{ietest} and $exdups[0] ne $indups[0] and tlogger($sh, '',
#			"ERROR: difference alert for id \"$id\", " .
#			"element \"$elem\"");
#			# yyy only checking first dupe in ietest
#			# yyy no $txnid -- ok?
#	}
#
#	$sh->{fetch_indb} and		# if ietest, indb takes precedence
#		return $wantlist ? @indups : scalar(@indups);
#	return $wantlist ? @exdups : scalar(@exdups);
#}

#use Carp;
# return array of dupes for $key in list context
#     in scalar context return the number of dupes
# xxx assumes "rfs" args
sub indb_get_dup { my( $db, $key )=@_;

	my $wantlist = wantarray();
	#confess "indb_get_dup";		# prints stack trace
	my $cursor = $db->db_cursor();
	! $cursor and
		return $wantlist ? () : 0;
	my $value;
	my $status = $cursor->c_get($key, $value, DB_SET);
	$status != 0 and
		$cursor->c_close(),
		undef($cursor),
		return $wantlist ? () : 0;	# nothing found
	my @array = ();
	push @array, $value;
	# yyy no error check, assume non-zero == DB_NOTFOUND
	while (($status = $cursor->c_get($key, $value, DB_NEXT_DUP))					!= DB_NOTFOUND) {
		push @array, $value;
	}
	$cursor->c_close();
	undef($cursor);
	return $wantlist ? @array : scalar(@array);
}

# yyy currently returns 0 on success (mimicking BDB-school return)
# xxx this is called only once, so we can easily split it into two;
#     {ex,in}db_del_dup and pass in appropriatedly flex_encoded args

# xxx add encoding tests for del and resolve
# XXXXXXXXX next: call flex_encode in indb case and rerun all tests!

# Assumes $id and $elem are already encoded "rfs"

sub indb_del_dup { my( $bh, $id, $elem )=@_;

	my ($instatus, $result) = (0, 1);	# default is success
	my $db = $bh->{db};

	# xxx check that $elem is non-empty?
	my $key = "$id$Se$elem";
	$instatus = $db->db_del($key);
	$instatus != 0 and addmsg($bh,
		# xxx these should be displaying UNencoded $id and $elem
		"problem deleting elem \"$elem\" under id \"$id\" " .
			"from internal database: $@");
		#return undef;
	# yyy check $result how?
	! $result || $instatus != 0 and
		return -1;
	return 0;
}

# yyy currently returns 0 on success (mimicking BDB-school return)
# xxx assumes $id and $elem are already encoded "rfs"
# xxx this is called only once, so we can easily split it into two;
#     {ex,in}db_del_dup and pass in appropriatedly flex_encoded args

# Assumes $id and $elem are already encoded "rfs"

sub exdb_del_dup { my( $bh, $id, $elem )=@_;

	my ($instatus, $result) = (0, 1);	# default is success

	# xxx check that $elem is non-empty?
	# XXX who calls arith_with_dups?

	# XXX binder belongs in $bh, NOT to $sh!
	my $coll = $bh->{sh}->{exdb}->{binder};	# collection
	my $msg;
	my $ok = try {
		$result = $coll->update_one(
			{ PKEY()		=> $id },
			{ '$unset'	=> { $elem => 1 } }
		)
		// 0;		# 0 != undefined
	}
	catch {
		# xxx these should be displaying UNencoded $id and $elem
		$msg = "error deleting elem \"$elem\" under " .
			"id \"$id\" from external database: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and 	# test undefined since zero is ok
		addmsg($bh, $msg),
		return undef;

	# yyy check $result how?
	! $result || $instatus != 0 and
		return -1;
	return 0;
}

# yyy currently returns 0 on success (mimicking BDB-school return)
# xxx assumes $id and $elem are already encoded "rfs"
# xxx this is called only once, so we can easily split it into two;
#     {ex,in}db_del_dup and pass in appropriatedly flex_encoded args
sub egg_del_dup { my( $bh, $id, $elem )=@_;

	my ($instatus, $result) = (0, 1);	# default is success
	my $db = $bh->{db};

# xxx add encoding tests for del and resolve
# XXXXXXXXX next: call flex_encode in indb case and rerun all tests!

# xxx who calls flex_encode? no one?
	# xxx check that $elem is non-empty?
	# XXX who calls arith_with_dups?
	if ($bh->{sh}->{indb}) {
		my $key = "$id$Se$elem";
		$instatus = $db->db_del($key);
		$instatus != 0 and addmsg($bh,
			"problem deleting elem \"$elem\" under id \"$id\" " .
				"from internal database: $@");
			#return undef;
	}
	if ($bh->{sh}->{exdb}) {
		# XXX binder belongs in $bh, NOT to $sh!
		my $coll = $bh->{sh}->{exdb}->{binder};	# collection
		my $msg;
		my $ok = try {
			$result = $coll->update_one(
				{ PKEY()		=> $id },
				{ '$unset'	=> { $elem => 1 } }
			)
			// 0;		# 0 != undefined
		}
		catch {
			$msg = "error deleting elem \"$elem\" under " .
				"id \"$id\" from external database: $_";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and 	# test undefined since zero is ok
			addmsg($bh, $msg),
			return undef;
	}
	# yyy check $result how?
	! $result || $instatus != 0 and
		return -1;
	return 0;
}

# Remove an element (bind=bind).
# $formal is true if we behave as if called by "delete" (whatever
#   that means) -- xxx does it mean rm is as if "--quiet"?
# xxx $elem or @elems?  yyy pluralize?

# This routine is called by egg_purge with UNencoded $id and $elem

sub egg_del { my( $bh, $mods, $lcmd, $formal, $id, $elem )=@_;

	my $sh = $bh->{sh};
	my $db = $bh->{db};
	my $dbh = $bh->{tied_hash_ref};
	my $opt = $bh->{opt};
	my $om = $bh->{om};

	# xxx check args? or only if ! $opt->{IknowWhatImDoing}?
	# xxx no check on defined($id)
	defined($elem) or
		addmsg($bh, "no element name given"),
		return undef;

	if (! $mods->{did_rawidtree}) {
		EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id, $elem) or
			addmsg($bh, "instantiate failed from fetch"),
			return undef;
	}

	my $key = $id . $Se . $elem;		# UNencoded
	my ($erfs, $irfs);	# ready-for-storage versions of id, elem, ...

	$bh->{sh}->{exdb} and
		$erfs = flex_enc_exdb($id, $elem);
	$bh->{sh}->{indb} and
		$irfs = flex_enc_indb($id, $elem);

	! egg_authz_ok($bh, $id, OP_DELETE) and
		return undef;

	# an empty $lcmd means we were called by purge -- don't log
	my $txnid;		# undefined until first call to tlogger
	$lcmd and
		$txnid = tlogger $sh, $txnid, "BEGIN $id.$lcmd $elem";

#	if (! $mods->{did_rawidtree}) {
#		EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id, $elem) or
#			addmsg($bh, "instantiate failed from delete"),
#			return undef;
#		$irfs = flex_enc_indb($id, $elem);
#		($key, $id, $elem) =
#			($irfs->{key}, $irfs->{id}, $irfs->{elems}->[0]);
#	}
#	else {
#		$key = "$id$Se$elem";
#	}

	# yyy should rawidtree call (for purge) egg_del?
	#     -- it already does so for fetch...

	# yyy need policy on protocol-breaking deletions, eg, to permkey
	# yyy $WeNeed really should be named $perms_required or $ineed

	my ($oldvalcnt, $oxum, @oldlens);
	if ($bh->{opt}->{ack}) {
		#@oldlens = map length, $db->get_dup($key);
		#@oldlens = map length, indb_get_dup($db, $key);
		@oldlens = map length, $irfs
			? indb_get_dup($db, $irfs->{key})
			: exdb_get_dup($bh, $id, $elem)
		;
		$oldvalcnt = scalar(@oldlens);
		my $octets = 0;
		$octets += $_
			for @oldlens;
		$oxum = "$octets.$oldvalcnt";
		# Now defined($oxum) iff $bh->{opt}->{ack}.  A little odd,
		# $oxum might be 0.0 since we still don't if id|elem exists.
	}
	else {
		#$oldvalcnt = $db->get_dup($key);
		#$oldvalcnt = indb_get_dup($db, $key);
		$oldvalcnt = $irfs
			? indb_get_dup($db, $irfs->{key})
			: -1		# we're ignoring it in exdb case
		;
	}
	# xxx dropping this for now
	# XXXX is this the right message/behavior?
	#sif($bh, $elem, $oldvalcnt) or		# check "succeed if" option
	#	addmsg($bh, "proceed test failed"),
	#	return undef;

	dblock();	# no-op

# xxx test del/purge/exists with encodings
	# Somehow we decided that rm/delete operations should succeed
	# after this point even if there's nothing to delete. Maybe
	# that's because our indb doesn't throw an exception, but now
	# no longer try to delete a non-existent value because our exdb
	# would throw an exception.
# xxx is above comment true?

	my $status = 0;		# default is success
	my ($emsg, $imsg);

	#$oldvalcnt and		# if there's at least one (even -1) value
	#	$status = egg_del_dup($bh, $id, $elem);		# then delete

	# if there's at least one (even -1) value, then delete
	if ($oldvalcnt and $erfs) { 
		$status = exdb_del_dup($bh, $erfs->{id}, $erfs->{elems}->[0]);
		$emsg = ($status != 0				# error
			? "couldn't remove key ($erfs->{key}) ($status)"
			: '');
		$emsg and 
			addmsg($bh, $emsg);
	}
	if ($oldvalcnt and $irfs) { 
		$status = indb_del_dup($bh, $irfs->{id}, $irfs->{elems}->[0]);
		$imsg = ($status != 0 && $status != DB_NOTFOUND()	# error
			? "couldn't remove key ($irfs->{key}) ($status)"
			: '');
		$imsg and 
			addmsg($bh, $imsg);
	}
	$emsg || $imsg and 
		dbunlock(),
		return undef;
	if ($status == 0) {		# if element both found and removed
		$irfs and
			arith_with_dups($dbh, "$A/bindings_count", -$oldvalcnt),
			($dbh->{"$A/bindings_count"} < 0 and addmsg($bh,
				"bindings count went negative on $irfs->{key}"),
				return undef),
		;
		# Note that if a problem shows up and you fix it, you won't
		# likely enjoy the results until you recreate the binder
		# to re-initialise the bindings_count.
	}
	dbunlock();

	my $oxstatus;
	defined($oxum) and		# $oxstatus
		$oxstatus = $om->elem("oxum", $oxum);

	# yyy Kludgy protocol to allow 'egg_purge' to pass empty $lcmd
	# to signify that we shouldn't log (as it logged one 'purge').
	#
	#$lcmd and $msg = $bh->{rlog}->out("C: $id$Se$elem.$lcmd") and
	# XXXXXX NOTE: cannot abandon id|elem.OP syntax
	#        without major complication to the logging syntax!!
	# yyy no need for this log line if $status == 0 above

	# an empty $lcmd means we were called by purge -- don't log
	$lcmd and
		tlogger $sh, $txnid, "END SUCCESS $id.$lcmd $elem";

	# xxx document that "delete" means "rm" but with echo
	$formal or		# silence is golden
		return 1;
	# If we get here, "echo" is set, which means talk about it
	# xxx or does it mean we do a temporary promotion to anvl?
	# xxx do something with the $status, $oxstatus, $omstatus return!
	# XXX change "element" to "dupe"
	# XXX where does --ack fit in?
# xxx $key??
	my $omstatus = $om->elem("ok", ($oldvalcnt == 1 ?
		# XXX need way to DISPLAY id + elem, and this next looks like a
		#     mistake but it's not
		#"element removed: $key" :
		"element removed: $id$So$elem" :
		($status == 1 ? "element doesn't exist" :
# xxx display these properly or not at all?
			"$oldvalcnt elements removed: $id$So$elem")));
			#"$oldvalcnt elements removed: $key")));
	return 1;
}

# Check user-specified existence criteria.
# XXXXXX hold back releasing this:
#      problems with conception, utility, and logging
#      eg, should be renamed 'pif' (proceed, not succeed)
#          needs to enter rlog for accuracy
#          what's the relationship to 'let'?
#          what's existence mean?
# xxx! document sif=(x|n)
sub sif { my( $bh, $elem, $oldvalcnt )=@_;

	my $sif = lc ( $bh->{opt}->{sif} || "" );
	$sif eq "x" && $oldvalcnt == 0 and addmsg($bh,
		qq@error: element "$elem" doesn't exist but you said sif=x@),
		return undef;
	$sif eq "n" && $oldvalcnt != 0 and addmsg($bh,
		qq@error: element "$elem" exists but you said sif=n@),
		return undef;
	return 1;
}

=for consideration what ezid encodes

	# python"[%'\"\\\\&@|;()[\\]=]|[^!-~]"
	#s{ ([|^]) }{ sprintf("^%02x", ord($1)) }xeg

	$slvalue =~ 			# kludgy, specific to EZID encoding
	 	s{ ([%'"\\&@|;()[\]=]|[^!-~]) }
		 { sprintf("%%%02x", ord($1))  }xego;

	my $eid = $id;			# encoded id
	$eid =~ 			# kludgy, specific to EZID encoding
	 	s{ ([%'"\\&@|;()[\]=:<]|[^!-~]) }	# adds : and < to above
		 { sprintf("%%%02x", ord($1))  }xego;

=cut

# Circumflex-encode, internal db (indb) version.
# Return hash with ready-for-storage (efs) versions of
#   key		# for storage
#   id		# identifier
#   elems	# array: elem, subelem, subsubelem, ...

sub flex_enc_indb { my ( $id, @elems )=@_;

	my $irfs = {};	# hash that we'll return with ready-for-storage stuff
	if ($id =~ m|^:idmap/(.+)|) {
		my $pattern = $1;	# note: we don't encode $pattern
					# xxx document
		my $elem = $elems[0];
		$elem =~ s{ ([$Se^]) }{ sprintf("^%02x", ord($1)) }xeg;
		$irfs->{key} = "$A/idmap/$elem$Se$pattern";
		$irfs->{id} = $id;		# unprocessed
		$irfs->{elems} = [ $elem ];	# subelems not supported
		return $irfs;
	}
	# if we get here we don't have an :idmap case

	$irfs->{key} =
		join $Se, grep
		s{ ([$Se^]) }{ sprintf("^%02x", ord($1)) }xoeg || 1,
		$id, @elems;
	$irfs->{id} = $id;		# modified
	$irfs->{elems} = \@elems;	# modified
	return $irfs;
}

# Circumflex-encode, external db (exdb) version.
# Return hash with ready-for-storage (rfs) versions of
#   key		# for :idmap	xxx untested
#   id		# identifier
#   elems	# array: elem, subelem, subsubelem, ...

sub flex_enc_exdb { my ( $id, @elems )=@_;

	my $erfs = {};	# hash that we'll return with ready-for-storage stuff
	if ($id =~ m|^:idmap/(.+)|) {
		my $pattern = $1;	# note: we don't encode $pattern
					# xxx document
		my $elem = $elems[0];
		$elem =~ s{ $EXsc }{ sprintf("^%02x", ord($1)) }xeg;
		$erfs->{key} = "$A/idmap/$elem$Se$pattern";
		$erfs->{id} = $id;		# unprocessed
		$erfs->{elems} = [ $elem ];	# subelems not supported
		return $erfs;
	} # XXX untested!
	# if we get here we don't have an :idmap case

	$erfs->{key} =
		join $Se, grep
		s{ $EXsc }{ sprintf("^%02x", ord($1)) }xoeg || 1,
		$id, @elems;
	$erfs->{id} = $id;		# modified
	$erfs->{elems} = \@elems;	# modified
	return $erfs;
}

# Take encoded string and return circumflex-decoded string.  Does not
# modify its argument.  You'll get faster execution by not calling this
# routine and just copying its one-liner into your code where needed,
# which is why it's mostly not called.
# yyy no need for different {ex,in}db versions of this?
#
sub flex_dec { my $s = shift;

	$s =~ s/\^([[:xdigit:]]{2})/chr hex $1/eg;
	return $s;
}

# Take encoded string (eg, identifier or element name) and return
# a circumflex-decoded string suitable for human display.
# Does not modify its argument.
#
sub flex_dec_for_display { my( $s )=@_;

# XXX do a version that takes multiple args and inserts '|' between them
#     suitable for calling with $id, $elem --> foo|bar
	$s eq '' and			# make an empty string
		$s = '""';		# a bit more visible
	$s =~ s/\^([[:xdigit:]]{2})/chr hex $1/eg;
	return $s;
}


=for removal

# Return the lookup key.
# Special identifiers begin with ":".  Transform any special identifier
# to its "true" (in the db) name.  Right now that means a user-entered Id
# of the form :idmap/Idpattern.  In this case, change it to a database
# Id of the form "$A/idmap/$elem", and change $elem to hold Idpattern;
# this makes lookup faster and easier.
#
# XXX this is similar to how we'll put in :- and : element support!
# yyy transform other ids beginning with ":"?
# xxx $bh is unused -- remove?

sub buildkey { my( $bh, $id, $elem )=@_;

#print "xxx start id=$id, elem=$elem\n";
	$id =~ m|^:idmap/(.+)| and
		return "$A/idmap/$elem|$1";

	# hex-encode with ^ to permit | in identifier
	$id =~ s{ ([|^]) }{ sprintf("^%02x", ord($1)) }xeg;
#print "xxx end id=$id, elem=$elem\n";
	# hex-encode with ^ to permit | in element name
	defined($elem) and
		$elem =~ s{ ([|^]) }{ sprintf("^%02x", ord($1)) }xeg,
		return "$id$Se$elem";
	return ($id ? $id : "|" );		# $cursor->c_get doesn't like ""

	#return
	#	(defined($elem) ? "$id$Se$elem"	:
	#	($id		? $id		:
	#			  "|"		# $cursor->c_get doesn't like ""
	#	));
	#addmsg($bh, qq@$id: id cannot begin with ":"@
	#	. qq@ unless of the form ":idmap/Idpattern"@),
	#return undef;
}

=cut

# expect name/value to be rest of file
# xxx temporary
sub getbulkfile { my( $bh )=@_;		# ':-' as element name

	#my $value;
	#my $msg = file_value("< -", $value);
	#$msg and 
	#	addmsg($bh, msg),
	#	return undef;
	#return $value;

	# Read all of STDIN into array "@input_lines".
	my @input_lines = <STDIN>;

# XXX should do proper ANVL input processing
	# Remove all newlines.
	chomp		foreach (@input_lines);

	# Ignore any leading lines that start with a pound sign
	# or contain nothing but white space.
	# yyy rewrite for clarity?
	while (scalar(@input_lines) > 0) {
		if ((substr($input_lines[0], 0, 1) eq "#") ||
			($input_lines[0] =~ /^\s*$/)) {
			shift @input_lines;
			next;
			}
		last;
	}

	# If we don't have any lines, there's a problem.
	if (scalar(@input_lines) == 0) {
		addmsg($bh, "error: no non-blank, non-comment input");
		return (undef, undef);
	}

	# There must be an element and a colon on the first line.
	unless ($input_lines[0] =~ /^\s*(\w+)\s*:\s*(.*)$/) {
		addmsg($bh, "error: missing element or colon on ",
			"first non-blank, non-comment line");
		return (undef, undef);
	}

	# Save the element, and any part of the value that there
	# might be on the first line.
	my $elem = $1;
	my $value = $2;

	# Remove the first line from the array.
	shift @input_lines;

	# Append any additional lines to the value.
	foreach (@input_lines) {
		$value .= "\n" . $_;
	}

	## Put on the final newline.
	#$value .= "\n";

	return ($elem, $value);
}

=for removal

# xxx temporary XXX should do real anvl parse!
# get element/value pairs from stdin (':' as element name)
sub getbulkelems { my( $bh, $mods, $lcmd, $delete, $polite, $how, $id )=@_;

	# To slurp paragraph, apparently safest to use local $/, which
	local $/;			# disappears when scope exits.
	$/ = "\n\n";			# Means paragraph mode.
	my $para = <STDIN> || "";	# xxx what if "0" is read
	chop $para;	# yyy needed?
	$para =~ s/^#.*\n//g;		# remove comment lines
	$para =~ s/\n\s+/ /g;		# merge continuation lines
	my @elemvals = split(/^([^:]+)\s*:\s*/m, $para);
	shift @elemvals;		# throw away first null
	my ($bound, $total, $octets) = (0, 0, 0);
	my ($elem, $value);
	my $ack = $bh->{opt}->{ack};
	while (1) {
		($elem, $value) = (shift @elemvals, shift @elemvals);
		! defined($elem) && ! defined($value) and
			last;
		$total++;
		! defined($elem) and
			addmsg($bh,
				"error: $id: bad element associated "
					. qq@with value "$value".@),
			last;
		! defined($value) and
			$value = "",
		1 or
			chop $value
		;
		EggNog::Egg::egg_set($bh, $mods, $lcmd,
				$delete, $polite, $how, $id, $elem, $value) and
			$bound++,
			($ack and $octets += length($value));
		# else Noid::Binder will have left msg with addmsg
	}
	$ack and
		$bh->{om}->elem("oxum", "$octets.$bound");
	# yyy summarize for log $total and $bound
	return $bound == $total ? 1 : undef;	# one error is an error
}

=cut

=for removal

# Write what the action taken to the playback log as raw ANVL assigment
# appended to a who|when| string.
# Returns empty string on success, message on failure.
# Log line format is
#      who|where|when|what|id|elem.CMD data
# where
#   who		is from contact
#   when	is from temper
#   what	is one of "raw" or "note"
#   id		is the identifier
#   name	is the element name
#   data	is the data value
#
sub wlog { my( $bh, $preamble, $cmd )=(shift, shift, shift);

	my $logfhandle = $bh->{log} or
		return "log file not open";
	print($logfhandle $preamble, " ", $cmd, "\n") or
		return "log print failed: $!";
	return "";

	#my $message = $preamble;
	#defined($i) and
	#	($i =~ m/[\s\n]/ &&
	#		$i =~ s{([\s\n])}{		# %-encode whitespace
	#			sprintf("%%%02x", ord($1))
	#		}xeg),
	#	$message .= " $i";
	#defined($n) and
	#	($n =~ m/[\s\n]/ &&
	#		$n =~ s{([\s\n])}{		# %-encode whitespace
	#			sprintf("%%%02x", ord($1))
	#		}xeg),
	#	$message .= " $n";
	#defined($d) and
	#	($d =~ m/[\r\n^]/ &&		# XXXXXX align with hex codes
	#		$d =~ s{([\r\n])}{		# %-encode newlines
	#			sprintf("^%02x", ord($1))
	#		}xeg),
	#	$message .= " $d";
	#defined($n) and
	#	$n =~ s{([\s\n])}{	# %-encode whitespace that would spoil
	#		sprintf("%%%02x", ord($1))	# tokenizing by rlog
	#	}xeg,
	#	$message .= " " . $n;
	#defined($d) and
	#	$message .= " << " . length($d) . "\n$d\n";
}


# OLD/deprecated
# OPs are
#  i|e|se=OP
#  <i>.edel e		delete all dups for element, if any
#  <i>.eset e val	delete all dups, if any, and add a new dup
#  <i>.eadd e val	add a new dup
# <i>.eset e << 45
# <45 octets of value>\n
# \n
# i.edel e
#
sub xwlog { my( $bh, $op, $elem, $val )=(shift,shift,shift,shift);

	my $logfhandle = $bh->{log} or
		return "log file not open";
	my $message = $op;
	defined($elem) and
		$elem =~ s{([\s\n])}{	# %-encode whitespace that would spoil
			sprintf("%%%02x", ord($1))	# tokenizing by rlog
		}xeg,
		$message .= " " . $elem;
	defined($val) and
		$message .= " << " . length($val) . "\n$val\n";
	print($logfhandle $message, "\n") or
		return "log print failed: $!";
	return "";
}

=cut

# $dbh is a tied hash ref, but with dups enabled we can't use hash slots
# with simple ++, --, +=, -= constructs.  Instead we have to delete the
# existing value before resetting to avoid creating a dup.
# yyy No meaningful return.
#
sub arith_with_dups { my( $dbh, $key, $amount )= (shift, shift, shift);

	my $n = $dbh->{$key} || 0;	# important: uninitialized means zero
	delete($dbh->{$key});		# delete tied hash slot first
	$dbh->{$key} = $n + $amount;	# to avoid this creating a dup
	return $n;
}

# Stub routine to see if we're authorized to create the given element under
# the given id.  Right now, it's just whether we can create it period.
# If you're not remote or if you're admin, fine.  Anything else, you get
# your or the public permissions.
#
# Ideally, lookup the id for a stem match against one of the shoulders
# that the user can /extend/take/create on.  We don't have a shoulder
# database accessible to us right now, so we just pretend that the
# caller knows what they're doing and we say "yes" you're authorized.
#
# Return 1 on success, or undef and a message on failure.
# $WeNeed is the operation, $id is the raw id, $opd is the id+elem operand
# xxx how to distinguish shoulders: "__mtype: shoulder?
#        (__mtype: naan?) if #matches > 1, weird error
#
# XXXXXX shoulder() not currently called by anyone
sub shoulder { my( $bh, $WeNeed, $id, $opd ) = ( shift, shift, shift, shift );

# XXXX yuck -- what a mess -- clean this up
#	my $agid = $bh->{ruu}->{agentid};
$bh->{rlog}->out("D: shoulder WeNeed=$WeNeed, id=$id, opd=$opd, remote=" .
  "$bh->{remote}, ruu_agentid=$bh->{ruu}->{agentid}, otherids=" .
  join(", " => @{$bh->{sh}->{ruu}->{otherids}}));

	$bh->{remote} or		# if from shell, you are approved
		return 1;

	# xxx lookup shoulder stuff now... (not yet) in $bh->{shoulder_mh}?
	#     return ('', $msg) on error
	# for now just fall through to global authorization

	! authz($bh->{sh}->{ruu}, $WeNeed, $bh, $id, $opd) and
		#unauthmsg($bh, "xxxz"),
		return undef;
	return 1;
}

# set element to value in external db (Mongo)

use MongoDB;

# Called by egg_set.
# First arg example:  $bh->{sh}->{exdb}->{binder}, eg, egg.ezid_s_ezid

# This routine assumes $id and $elem args have been flex_encoded
# The goal of this routine is to construct a set of hashes to submit
# to $collection->update_one(). Here's an annotated example.
#
# {		# filter_doc to select what doc to update
#	PKEY() => $id,			# primary key
#	$elem => { '$exists' => 0 }	# in case we're not clobbering
# }, {		# update_doc to specify actions to perform
#	'$set' => {
#		CTIME_EL_EX() => $optime,	# update time
#		$elem => [ $val ],	# in case we're clobbering
#	'$push' => { $elem => $val };	# add a dup if we're not clobbering
# }, {		# options/flags
#	upsert	=> ! $polite		# prevents creating duplicate document
#	NB: we also use reserved _id, which should enforce doc uniqueness too
# }

# NB: different from indb (BDB Btree case): field names are not sorted

sub exdb_set_dup { my( $bh, $id, $elem, $val, $flags )=@_;

	$flags ||= {};
	my $optime = $flags->{optime} || time();
	my $delete = $flags->{delete} || 0;		# default
	my $polite = $flags->{polite} || 0;		# default

	my $result;
	my $coll = $bh->{sh}->{exdb}->{binder};		# collection
# xxx to do:
# rename $sh->{exdb} to $sh->{exdb_session}
#   move ebopen artifacts to $bh->{exdb}
# add: flex_dec_exdb on fetch and resolve!
# add: consider sorting on fetch to mimic indb behavior with btree
# generalize egg_del/purge
# generalize egg_exists
# yyy big opportunity to optimize assignment of a bunch of elements in
#     one batch (eg, from ezid).


	my $filter_doc = { PKEY() => $id };		# initialize
	my $upsert = 1;					# default
	if ($polite) {
		$filter_doc->{$elem} = { '$exists' => 0 };
		$upsert = 0;	# causes update to fail if $elem exists
	}

	my $update_doc = {};
	my $to_set = { CTIME_EL_EX() => $optime };	# initialize
	if ($delete) {
		$to_set->{$elem} = [ $val ];		# to be set
	}
	else {
		$update_doc->{'$push'} = { $elem => $val };
	}
	$update_doc->{'$set'} = $to_set;
	my $msg;
	my $ok = try {
		$result = $coll->update_one(
			$filter_doc,
			$update_doc,
			{ upsert => $upsert }
		)
		// 0;		# since 0 != undefined
	}
	catch {
		$msg = "error setting id \"$id\" in external database: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and 	# test undefined since zero is ok
		addmsg($bh, $msg),
		return undef;

	if ($polite and $result and $result->{matched_count} < 1) {
		addmsg($bh, "cannot proceed on an element ($elem) that " .
			"already has a value");
		return undef;
	}
	return $result;		# yyy is this a good return status?

#use Data::Dumper "Dumper"; print Dumper $result;
#use Data::Dumper "Dumper"; print Dumper $bh;
}

# Called by egg_fetch.
# First arg example:  $bh->{sh}->{exdb}->{binder}, eg, n2t.idz
# xxx haven't thought about duplicate values
# returns undef on error, empty string on "not found" yyy ?

sub exdb_find_one { my( $bh, $coll, $id, $elem, $val )=@_;

	my $query = {
		PKEY()	=> $id,
	};
	#defined($id) and
	#	$query->{PKEY()} = $id;
	defined($elem) and defined($val) and
		$query->{"'$elem'"} = $val;

	my ($result, $msg);
	my $ok = try {
		$result = $coll->find_one( $query )
		// 0;		# 0 != undefined; we're ok if nothing found
	}
	catch {
		$msg = "error looking up id \"$id\" in external database: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and 	# test undefined since zero is ok
		addmsg($bh, $msg),
		return undef;
	$result //= '';			# converts undef to empty string
	return $result;			# yyy is this a good return status?
}

# dummy (for now) Egg auth check
sub egg_authz_ok { my( $bh, $id, $op )=@_;

	! $bh->{remote} and
		return 1;
	return 1;

=for consideration

	## yyy this $WeNeed is really "what perms when OR'd with permstring
	##     will allow me to proceed at a minimum?
	##     but who is it that know that write=>extend?
	## yyy $WeNeed really should be named $perms_required or $ineed
	## yyy $delete really should be named $overwrite or $owrite
	#my $WeNeed =		# operation as input to authz()
	#	$delete ? OP_WRITE : OP_WRITE|OP_EXTEND;

	#===== begin authorization check
	$id =~ /^:/ and		# if it's an admin value and we're on the
			$bh->{remote} and	# web, don't authorize
		unauthmsg($bh),		# xxx convey more detailed message?
		return undef;

	my ($id_p, $opd_p);		# id and operand permissions strings
	my $id_permkey = $id . PERMS_ELEM;
	my $optime = time();

	if (! defined $dbh->{$id_permkey}) {	# if no top-level permkey,
		######
		# This is where an id is "created".
		######
		# our protocol takes that to mean the id doesn't exist.
		#
		# this asks if we have permission to create under this shoulder
#ZXXX disable	shoulder($bh, $WeNeed, $id, $key) or
#ZXXX disable		unauthmsg($bh, "xxxa $WeNeed, $id, $key"),
#ZXXX disable			#"$bh->{ruu}->{msg}"),
#ZXXX disable		return undef;

		#($id_p, $opd_p) =	# does this shoulder let us create?
		#$id_p or	# if empty $id_p then $opd_p is an error msg
		#	unauthmsg($bh, "xxxa $WeNeed, $id, $key"),
		#			# xxx lose msg in $opd_p
		#		# xxxa 16, id, id|can
		#	return undef;

		# Authorized, so now create permission string and ctime
		$dbh->{$id_permkey} =
# ZXXXX needs a kind of effective uid here! = proxy2 || remote_user
			"p:$bh->{sh}->{ruu}->{agentid}||76";
			# anything but delete
		$dbh->{$id . CTIME_ELEM} = $optime;
		#$dbh->{$id . CTIME_ELEM} = time();
		# yyy should call time() only once per op? and share,
		#     eg, with rlog?
		$bh->{sh}->{indb} and
			# XXX NOT setting arith_with_dups numbers in external db
			arith_with_dups($dbh, "$A/bindings_count", +2);
		# If we get here, we're authorized.
	}
	elsif (! $bh->{remote}) {	# only need to do authz if on web
		# Fall through -- you are authorized.
		# xxxx this !$bh->{remote} is really an are-you-admin check
	}
	else {	# else permkey must have already existed, so check it
		# xxx temporarily disable this message until EZID db updated
		#$id_p = $dbh->{$id_permkey} or		# protocol violation!!
		#	$bh->{rlog}->out($bh,
		#		"D: $id: id permissions string absent");
#ZXXX disable		addmsg($bh, "$id: id permissions string absent"),
#ZXXX disable		return undef;
#ZXXX disable	# xxx faster if we pass in permstring $id_p here?
#ZXXX disable	! authz($bh->{ruu}, $WeNeed, $bh, $id, $key) and
#ZXXX disable		# xxx $bh->{rlog}->out("D: WeNeed=$WeNeed, id=$id, opd=$opd, ruu_agentid=" .
#ZXXX disable		# XXX soon, don't do unauthmsg, so as not to
#ZXXX disable		#	interfere with Greg's code
#ZXXX disable		unauthmsg($bh, "xxxb"),
#ZXXX disable		return undef;
	}
	#===== end authorization check

=cut

}

#####################################################################
#
# Core routines for all database modification: egg_set and egg_del
#
#####################################################################

sub egg_set { my( $bh, $mods, $lcmd, $delete, $polite,  $how,
						 $id, $elem, $value )=@_;

	# Considered the idea of accumulating all remaining arguments in
	# one collective $value, but that complicates the processing and
	# explanation of indirect tokens.  We reject any other arguments
	# silently.  yyy probably better to return error message

	my $incr_decr =		# increment or decrement don't require $value
		$how eq HOW_INCR  ||  $how eq HOW_DECR;

	! defined($value) and $incr_decr and
		$value = '';	# if none, increment/decrement use a default

	defined($id) or
		addmsg($bh, "no identifier name given"), return undef;
	defined($elem) or
		addmsg($bh, "no element name given"), return undef;
	defined($value) or
		addmsg($bh, "no value given"), return undef;

	# Do some tests that tell us how much or little we need to bind now.
	# Some settings may have a big effect on performance.  Eg, in the
	# presence of large value tokens on stdin, if all we're doing is
	# logging and not binding key/value pairs in BDB, then we can avoid
	# unnecessary instantiation in memory and just copy stdin to the log.
	# yyy add other tests
	#
	my $args_in_memory = 0;
	$mods->{on_bind} ||= $bh->{on_bind};	# default actions if needed
	$mods->{on_bind} & BIND_KEYVAL and	# yyy drop BIND_KEYVAL?
		# yyy does not expand beyond single value token,
		#     eg, id.set a b @ -> a: b @
		# yyy instantiate NEEDs $elem not to be null
		(EggNog::Cmdline::instantiate($bh,
				$mods->{hx}, $id, $elem, $value) or
			return undef),
		$args_in_memory = 1,
	1 or
	! $mods->{on_bind} and
		addmsg($bh, "configuration doesn't permit any binding"),
		return undef
	;

	$bh->{sh}->{exdb} and
		exdb_set( $bh, $mods, $lcmd, $delete,
			$polite, $how, $incr_decr, $id, $elem, $value ) ||
				return undef;
	$bh->{sh}->{indb} and
		indb_set( $bh, $mods, $lcmd, $delete,
			$polite, $how, $incr_decr, $id, $elem, $value ) ||
				return undef;
	return 1;
}

sub indb_set { my( $bh, $mods, $lcmd, $delete, $polite,  $how,
						$incr_decr,
						$id, $elem, $value )=@_;

	my $sh = $bh->{sh};
	my $dbh = $bh->{tied_hash_ref};
	my $db = $bh->{db};
	my $om = $bh->{om};
	# yyy what if om is undefined?  || ... default to what?

	# yyy do bulk defs for $value
	# yyy document default values for element and value

	# ready-for-storage versions of id, elem, ...
	# yyy rename $irfs -> $rfs?
	my $irfs = flex_enc_indb($id, $elem);
	my $key;
# xxx consider dropping this assignment and using $irfs->* as needed
	($key, $id, $elem) = ($irfs->{key}, $irfs->{id}, $irfs->{elems}->[0]);

	! egg_authz_ok($bh, $id, OP_WRITE) and
		return undef;

	my $optime = time();

# xxx requires the ready-for-storage $id
	# an id is "created" if need be
	#if (! egg_init_id($bh, $id, $optime)) ...
# xxx split this next into {ex,in}db cases
	#if (! egg_init_id($bh, $irfs->{id}, $optime)) 
	if (! egg_init_id($bh, $id, $optime)) {
		addmsg($bh, "error: could not initialize $id");
		return undef;
	}

	my $slvalue = $value;		# single-line log encoding of $value
	$slvalue =~ s/\n/%0a/g;	# xxxxx nasty, incomplete kludge
					# xxx note NOT encoding $elem

	# Not yet a real transaction in the usual sense, but
	# more of something that has a start and an end time.

	my $txnid;		# undefined until first call to tlogger
	$txnid = tlogger $sh, $txnid, "BEGIN $id$Se$elem.$lcmd $slvalue";

# xxx call either {ex,in}db_get_dup here, with rfs args
	my $oldvalcnt = indb_get_dup($db, $key);
	! defined($oldvalcnt) and
		return undef;
	my $oldval;
	# yyy make this a command modifier, not an option, and rlog it!
	# yyy what if $elem is buried inside $id?
	# yyy shouldn't there be some sort of message with the undef??
#	sif($bh, $elem, $oldvalcnt) or		# check "succeed if" option
#		return undef;

	# yyy to add: possibly other ops (* + - / **)
	if ($incr_decr) {

		$oldvalcnt > 1 and
			addmsg($bh, "incr/decr not allowed on element " .
				"($elem) with duplicate values ($oldvalcnt)"),
			return undef;
		$oldval = $dbh->{$key} || 0;	# if unset, start with zero
		$oldval =~ /^[-+]?\d+$/ or
			addmsg($bh, "incr/decr not allowed unless existing " .
				"value ($oldval) is a decimal number"),
			return undef;
		my $amount = 1;
		$value ne "" and
			$amount = $value;
		$amount =~ /^[-+]?\d+$/ or
			addmsg($bh, "incr/decr amount ($amount) must be a " .
				"decimal number"),
			return undef;
		# Now compute the new value that we'll be setting.
		$value = $how eq HOW_INCR ?
			$oldval + $amount : $oldval - $amount;
			#"how_incr $amount" : "how_decr $amount";
			#$oldval + int($amount) : $oldval - int($amount);
	}

	# permit 'set' to overwrite dups, but don't permit 'let' unless
	#    there is no value set

	$polite and $oldvalcnt > 0 and $how eq HOW_SET and
		addmsg($bh, "cannot proceed on an element ($elem) that " .
			"already has a value"),
		return undef;

	dblock();	# no-op

	# yyy do more tests with dups
	# with "bind set" need first to delete, including any dups

	# Delete value (and dups) if called for (eg, by "bind set").
	#   delete() is a convenient way of stomping on all dups
	#
	if ($delete and $oldvalcnt > 0) {
		if ($bh->{sh}->{indb}) {
			$db->db_del($key) and
				addmsg($bh, "del failed"),
				return undef;
			arith_with_dups($dbh, "$A/bindings_count", -$oldvalcnt);
			#$dbh->{"$A/bindings_count"} < 0 and addmsg($bh,
			#	"bindings count went negative on $key"),
			#	return undef;
		}
	}

	# The main event.

	my $status = $db->db_put($key, $value);
	$status < 0 and
		addmsg($bh, "couldn't set $id$Se$elem ($status): $!");
	$status != 0 and 
		dbunlock(),
		return undef;
	arith_with_dups($dbh, "$A/bindings_count", +1);

	my $msg;
	if ($mods->{on_bind} & BIND_PLAYLOG) {
		# NB: Must keep writing this rlog because EDINA replication
		# depends on it!

		# XXX NOT setting doing this for external db. DROP for indb?
		$bh->{sh}->{indb} and
			$msg = $bh->{rlog}->out("C: $id$Se$elem.$lcmd $slvalue");
		tlogger $sh, $txnid, "END SUCCESS $id$Se$elem.$lcmd ...";
		$msg and
			addmsg($bh, $msg),
			return undef;
	}
	$bh->{opt}->{ack} and			# do oxum
		$om->elem("oxum", length($value) . ".1"); # yyy ignore status
		#$status = $om->elem("oxum", length($value) . ".1");

	dbunlock();
	return 1;
}

# *** exdb: db.mycollection.count() to count docs in a collection
sub exdb_set { my( $bh, $mods, $lcmd, $delete, $polite,  $how,
						$incr_decr,
						$id, $elem, $value )=@_;

# xxx consider merging this routine back into egg_set and leaving early
#    if not indb also
	my $sh = $bh->{sh};
	my $exdb = $sh->{exdb};
	my $dbh = $bh->{tied_hash_ref};
	my $db = $bh->{db};
	my $om = $bh->{om};
	# yyy what if om is undefined?  || ... default to what?

	# yyy do bulk defs for $value
	# yyy document default values for element and value

	# ready-for-storage versions of id, elem, ...
	my $rfs = flex_enc_exdb($id, $elem);

	#! egg_authz_ok($bh, $id, OP_WRITE) and
	# yyy encoded $id
	! egg_authz_ok($bh, $rfs->{id}, OP_WRITE) and
		return undef;

	my $optime = time();

	# an id is "created" if need be
	#if (! egg_init_id($bh, $id, $optime)) ...
	# yyy pass in encoded $id
	if (! egg_init_id($bh, $rfs->{id}, $optime)) {
		# xxx do we need to call egg_init_id for exdb case at all?
		addmsg($bh, "error: could not initialize $id");
		return undef;
	}

	my $slvalue = $value;		# single-line log encoding of $value
	$slvalue =~ s/\n/%0a/g;	# xxxxx nasty, incomplete kludge
					# xxx note NOT encoding $elem
	# Not yet a real transaction in the usual sense, but
	# more of something that has a start and an end time.

	# yyy UNencoded $id and $elem
	my $txnid;		# undefined until first call to tlogger
	$txnid = tlogger $sh, $txnid, "BEGIN $id$Se$elem.$lcmd $slvalue";

	# xxx ditch 'sif', even in indb case? or implement this
	#    with $set operator? if with $set, how?
	#sif($bh, $elem, $oldvalcnt) or		# check "succeed if" option
	#	return undef;

	if ($incr_decr) {
		addmsg($bh, "incr/decr not yet supported for the exdb case"),
		return undef;

		# See indb case for code to implement
		# note that in indb case we only did this on _first_ dup,
		#     so ok to do same in exdb case
		# in exdb case, will every value be an array of one or more?
		#    or will some be scalars and others be arrays?
		#
		# if incr_decr:
		#   (use mongo aggregation framework?)
		#   if element ! exists, then create with 0+incr value
		#   if element exists, then incr by amount
	}

#	$polite and $oldvalcnt > 0 and $how eq HOW_SET and
#		addmsg($bh, "cannot proceed on an element ($elem) that " .
#			"already has a value"),
#		return undef;
#
#	# yyy do more tests with dups
#	# with "bind set" need first to delete, including any dups
#
#	# Delete value (and dups) if called for (eg, by "bind set").
#	#   delete() is a convenient way of stomping on all dups
#	#
#	if ($delete and $oldvalcnt > 0) {
#		if ($bh->{sh}->{indb}) {
#			$db->db_del($key) and
#				addmsg($bh, "del failed"),
#				return undef;
#			arith_with_dups($dbh, "$A/bindings_count", -$oldvalcnt);
#			#$dbh->{"$A/bindings_count"} < 0 and addmsg($bh,
#			#	"bindings count went negative on $key"),
#			#	return undef;
#		}
#	}

	# The main event.

	dblock();	# no-op

	# permit 'set' to overwrite dups, but don't permit 'let' unless
	#    there is no value set

	#if (! exdb_set_dup($bh, $id, $elem, $slvalue, $optime)) 
	if (! exdb_set_dup($bh, $rfs->{id}, $rfs->{elems}->[0], $slvalue, {
			optime => $optime,
			delete => $delete,
			polite => $polite,
			how => $how,			# yyy necessary?
			incr_decr => $incr_decr,	# yyy necessary?
	})) {
		dbunlock();
		addmsg($bh, "couldn't set $id$Se$elem");
		return undef;
	}

	#my $msg;
	if ($mods->{on_bind} & BIND_PLAYLOG) {		# yyy drop BIND_PLAYLOG?
		# yyy dropping this for exdb
		# NB: Must keep writing this rlog because EDINA replication
		# depends on it!

		# XXX NOT setting doing this for external db. DROP for indb?
		#$bh->{sh}->{indb} and
		#	$msg = $bh->{rlog}->out("C: $id$Se$elem.$lcmd $slvalue");
		tlogger $sh, $txnid, "END SUCCESS $id$Se$elem.$lcmd ...";

		#$msg and
		#	addmsg($bh, $msg),
		#	return undef;
	}
	$bh->{opt}->{ack} and			# do oxum
		$om->elem("oxum", length($value) . ".1"); # yyy ignore status

	dbunlock();
	return 1;
}

# xxx assumes being called with ready-for-storage $id
#     at least in indb case
#  ?? maybe not in exdb case
# xxx split this into {ex,in}db cases
# create id if it's not been created already
sub egg_init_id { my( $bh, $id, $optime )=@_;

	my ($dbh, @pkey);
	my $sh = $bh->{sh};
	my $id_permkey = $id . PERMS_ELEM;
	my $id_value = "p:$sh->{ruu}->{agentid}||76";	# anything but delete
	# yyy needs a kind of effective uid here! = proxy2 || remote_user

	if ($sh->{indb} and ($dbh = $bh->{tied_hash_ref}) and
			! defined $dbh->{$id_permkey}) {	# if no permkey
		$dbh->{ $id_permkey } = $id_value;
		$dbh->{ $id . CTIME_ELEM } = $optime;
		arith_with_dups($dbh, "$A/bindings_count", +2);
		# yyy no error check
	}
	if ($sh->{exdb}) {
# XXX do we need to do egg_init_id at all in exdb case?
# XXXXXX arrives with wrong (indb) encoding!
		@pkey = exdb_get_dup($bh, $id, PERMS_EL_EX);
		scalar(@pkey) and		# it exists,
			return 1;		# so nothing to do
		# XXX NOT setting arith_with_dups numbers in external db
		# xxx do I need to normalize elem name & value?
		! exdb_set_dup($bh, $id, PERMS_EL_EX, $id_value, {
				optime => $optime, delete => 1 }) and
			return undef;
	}
	return 1;
}

sub get_id_record { my( $db ) = shift;
}

# This routine returns a two element array consisting of the total
# numbers of ids output and bindings encountered, or (undef, undef)
# on error.
sub next_list { my( $bh, $mods, $max, $nextkey, @inkeys )=@_;

	# xxx ignoring $mods for now
	defined($max) or
		$max = '-';
	$max eq '-' and			# if not given, select the default
		$max = NEXT_LIST_CMD_MAX;
	$max =~ /^\d+$/ or
		addmsg($bh, "list: maximum ($max) must be an integer or '-'"),
		return (undef, undef);
	#
	# If we get here, $max will be a non-negative integer.

	scalar(@inkeys) or
		return (list_ids_from_key($bh, $mods, $max, $nextkey, undef));
	#
	# If we get here, at least one "in key" was specified, ie, a key
	# that we should be "in" (under, descendant of) before we list.

	my ($totali, $totalb) = (0, 0);	# total numbers of ids and bindings
	for my $inkey (@inkeys) {

		# If $nextkey was given, skip the current $inkey
		# if (a) $inkey (eg, a shoulder) is not an initial
		# substring of $nextkey and (b) $nextkey is lexically
		# "gt" than (or "after") $inkey.
		#
		defined($nextkey) and $nextkey gt $inkey and
				index($nextkey, $inkey) != 0 and
			next;

		# Each $inkey contributes $localmax ids towards $max,
		# which we use so as not to overrun $max.  Remember that
		# $max == 0 requests an unlimited number of ids.
		#
		my $localmax = $max > 0 ? $max - $totali : 0;
		my ($ni, $nb) =		# numbers of ids and bindings found
			list_ids_from_key($bh, $mods,
				$localmax, $nextkey, $inkey);
		defined($ni) or			# note: zero return is ok
			return (undef, undef);	# but undefined is an error

		$ni and			# if we found any ids at all, switch
			$nextkey = undef;	# to "list" mode from now on
		$totali += $ni;		# keep running total towards $max
		$totalb += $nb;		# keep running total towards $max
		$max or			# if $max is unlimited continue
			next;

		# If we get here, $max and $localmax are limited.
		$ni > $localmax and
			addmsg($bh, "list_ids_from_key returned $ni ids " .
				"but only $localmax were requested " .
				"(key $inkey)"),
			return (undef, undef);
		$totali >= $max and	# should be == (never >), but be safe
			last;		# we've returned $max keys
	}
	#
	# If we get here we've output $max keys or we ran out before $max.

	return ($totali, $totalb);
}

# Assumes caller has checked that $max will be a non-negative integer.
# This routine returns a two element array consisting of the total
# numbers of ids output and bindings encountered, or (undef, undef)
# on error.
sub list_ids_from_key { my( $bh, $mods, $max, $nextkey, $inkey )=@_;

	# xxx ignoring $mods for now
	my $om = $bh->{om};
	my $db = $bh->{db};
	my $cursor = $db->db_cursor();

	# NB: this obtains a read cursor, which would also be created by
	# a loop with "each %hash", and that should block all write ops.
	# Be careful holding the cursor open too long!
	#
	# From BerkeleyDB Perl doc:
	# "So the rule is -- you CANNOT carry out a write operation using
	# a read-only cursor (i.e. you cannot use c_put or c_del) whilst
	# another write-cursor is already active."
	# "The workaround for this issue is to just use db_put instead of
	# c_put", ie, write without using a write-cursor.
	#
	# "Remember, that apart from the actual database files you
	# explicitly create yourself, Berkeley DB will create a few
	# behind the scenes to handle locking - they usually have names
	# like "__db.001". It is therefore a good idea to use the -Home
	# option, unless you are happy for all these files to be written
	# in the current directory."

	# YYY for lock testing:
	#  1. make sure a 2nd writer blocks until 1st writer finishes
	#  2. make sure a reader doesn't block writer? or nor for very long?
	#  3. make sure a long "list 0" dump doesn't block writers

	my ($iflag, $match_regex, $cur_id, $key, $value, $s);
	my ($num_bdngs, $num_ids, $total_num_bdngs) = (0, 0, 0);

	if (defined $nextkey) {		# if $nextkey was given, first we
		$key = $nextkey;	# move cursor past end of $nextkey
		my $skipping_regex = qr/^\Q$nextkey\E/;
		#for (	$s = $db->seq($key, $value, R_CURSOR);
		#	$s == 0;			# while not EOF
		#	$s = $db->seq($key, $value, R_NEXT) )
		for (	$s = $cursor->c_get($key, $value, DB_SET_RANGE);
			$s != DB_NOTFOUND;		# while not EOF
			$s = $cursor->c_get($key, $value, DB_NEXT) )
		{
			$key =~ $skipping_regex or
				last;
		}
		#$iflag = R_CURSOR;	# leave cursor and $s ready to go below
		$iflag = DB_SET_RANGE;	# leave cursor and $s ready to go below
	}
	elsif (defined $inkey) {		# if given, start at 
		$key = $inkey;			# user-supplied key
		#$iflag = R_CURSOR;			# user-supplied key
		$iflag = DB_SET_RANGE;			# user-supplied key
	}
	else {					# else list all ids
		#$iflag = R_FIRST;
		$iflag = DB_FIRST;
		$key = '';			# quells complaint from c_get()
	}
	$match_regex = defined($inkey)
		? qr/^\Q$inkey\E/	# pre-compute regex
		: undef;		# no regex -- as if in "list" mode

	# Initialize main "for" loop.
	#
	defined($nextkey) or			# If no $nextkey, get our first
		$s = $cursor->c_get($key, $value, $iflag); # candidate binding.
		#$s = $db->seq($key, $value, $iflag);	# candidate binding.
	#
	# If we get here, $s will be defined, either by the $nextkey search
	# or the line above.
	# 
	$s == DB_NOTFOUND and			# if not found,
		$cursor->c_close(),
		undef($cursor),
		return (0, 0);			# return early
	$s < 0 and
		goto SEQ_ERROR;
	#$s > 0 and				# if not found,
	#	return (0, 0);			# so return early
	$s == 0 and				# If not EOF initialize cur_id.
		($cur_id = $key) =~ s/\|.*//;	# Drop subelem to make cur_id.
	if ($s == 0 and $inkey) {		# See if we're already past
		$key =~ $match_regex or		# what user asked for; if so
		# xxx faster: don't use regex
			$cursor->c_close(),
			undef($cursor),
			return (0, 0);		# return early
	}
	for (	;				# loop initialized above
		$s == 0;			# while not EOF
		$s = $cursor->c_get($key, $value, DB_NEXT) ) # get next binding
		#$s = $db->seq($key, $value, R_NEXT) )	# get next binding
	{
		# xxx faster: don't use regex
		$key =~ /^\Q$cur_id\E(?:\|.*)?$/ and	# if no new id
			$num_bdngs++,			# count for this id
			next;				# get next binding

		# if we get here, a new id has appeared
		$num_ids++;				# count last id found
		$total_num_bdngs += $num_bdngs;		# keep running total

		if ($inkey) {	# is the new id past what user wants?
			# xxx faster: don't use regex
			$key =~ $match_regex or
				last;
		}
		# Check if we reached our limit (if any) for this catch.
		$max and $num_ids >= $max and
			last;	# last id will be output after end of loop

		$om->elem('id', $cur_id);
		#
		# If we get here, we've finished with the previous id.
		# Now start initializing to prep for the next id.
		#
		$num_bdngs = 1;				# reset bindings count
		# xxx faster: don't use regex
		($cur_id = $key) =~ s/\|.*//;	# drop subelem to make cur_id
	}
	#$s < 0 and
	#	goto SEQ_ERROR;

	# Same bits of code below as above, but this minor redundancy for
	# very last id saves tests in and speeds up the main loop above.
	#
	#$s != 0 and			# if we hit EOF inside an id,
	$s == DB_NOTFOUND and		# if we hit EOF inside an id,
		$num_ids++,			# it hasn't been counted yet
		($total_num_bdngs += $num_bdngs),	# final total
	1
	or
	$s < 0 and
		goto SEQ_ERROR
	;
	$num_ids and		# output final id, if any ids at all
		$om->elem('id', $cur_id);

	$cursor->c_close();
	undef($cursor);
	return ($num_ids, $total_num_bdngs);

   SEQ_ERROR:
	#addmsg($bh, "error $s from db->seq; fwiw, \$! says: $!");
	# magic $s can be either a number or a string depending on context

	# NB: another way to close the cursor is to just let it go out of
	# scope.  yyy try this later?
	$cursor->c_close();
	undef($cursor);
	addmsg($bh, "list_ids_from_key: cursor->c_get: $s");
	return (undef, undef);
}

sub mstat { my( $bh, $mods, $om, $cmdr, $level )=@_;

	$om ||= $bh->{om};
	my $db = $bh->{db};
	my $dbh = $bh->{tied_hash_ref};
	my $hname = $bh->{humname};		# name as humans know it
	my ($mtime, $size);

	$level ||= "brief";
	if ($level eq "brief") {
		$om->elem("binder", $bh->{minder_file_name});
		(undef,undef,undef,undef,undef,undef,undef,
			$size, undef, $mtime, undef,undef,undef) =
					stat($bh->{minder_file_name});
		$om->elem("modified", etemper($mtime));
		$om->elem("size in octets", $size);
		# xxx next ok?
		#$om->elem("binder", which_minder($cmdr, $bh->{minderpath}));
		$om->elem("status", minder_status($dbh));
		$om->elem("bindings", $dbh->{"$A/bindings_count"});
		return 1;
	}
}

# xxx bind list [pattern]
#     ?list matching elems  ?list matching ids?
#     ?list each id X where elem A has r'ship R to elem B in id Y

# Binder version!
# Report values according to $level.  Values of $level:
# "brief" (default)	user vals and interesting admin vals
# "full"		user vals and all admin vals
# "all"		all vals, including all identifier bindings
#
# yyy dbinfo should promote default format to anvl
# yyy should use OM better
sub dbinfo { my( $bh, $mods, $level )=@_;

	my $db = $bh->{db};
	my $om = $bh->{om};
	my ($key, $value) = ("$A/", 0);
	my $cursor = $db->db_cursor();

	if ($level eq "all") {		# take care of "all" and return
		#print "$key: $value\n"
		$om->elem($key, $value)
			while ($cursor->c_get($key, $value, DB_NEXT) == 0);
			# yyy no error check, assume non-zero == DB_NOTFOUND
			#while ($db->seq($key, $value, R_NEXT) == 0);
		$cursor->c_close();
		undef($cursor);
		return 1;
	}
	# If we get here, $level is "brief" or "full".

	#my $status = $db->seq($key, $value, R_CURSOR);
	my $status = $cursor->c_get($key, $value, DB_SET_RANGE);
	# yyy no error check, assume non-zero == DB_NOTFOUND
	if ($status) {
		$cursor->c_close();
		undef($cursor);
		addmsg($bh, "$status: no $key info");
		return 0;
	}
	if ($key =~ m|^$A/$A/|) {
		#print "User Assigned Values\n";
		$om->elem("Begin User Assigned Values", "");
		#print "  $key: $value\n";
		$om->elem($key, $value);
		#while ($db->seq($key, $value, R_NEXT) == 0) {
		# yyy no error check, assume non-zero == DB_NOTFOUND
		while ($cursor->c_get($key, $value, DB_NEXT) == 0) {
			last
				if ($key !~ m|^$A/$A/|);
			#print "  $key: $value\n";
			$om->elem($key, $value);
		}
		#print "\n";
		$om->elem("End User Assigned Values", "");
	}
	#print "Admin Values\n";
	$om->elem("Begin Admin Values", "");
	#print "  $key: $value\n";
	$om->elem($key, $value);	# one-off from last test
	#while ($db->seq($key, $value, R_NEXT) == 0) {
	# yyy no error check, assume non-zero == DB_NOTFOUND
	while ($cursor->c_get($key, $value, DB_NEXT) == 0) {
		last
			if ($key !~ m|^$A/|);
		#print "  $key: $value\n"
		$om->elem($key, $value)
			if ($level eq "full" or
				# $key !~ m|^$A/c\d| &&	# old circ status
				$key !~ m|^$A/saclist| &&
				$key !~ m|^$A/recycle/|);
	}
	$om->elem("End Admin Values", "");
	#print "\n";
	$cursor->c_close();
	undef($cursor);
	return 1;
}

# xxx dbsave and dbload built for the old DB_File.pm environment
# xxx should probably be updated for BerkeleyDB.pm and MongoDB.pm
sub dbsave { my( $bh, $mods, $destfile )=@_;

	$bh->{remote} and		# no can do if you're on web
		unauthmsg($bh),
		return undef;
	$destfile or
		addmsg($bh, "save where? no destination given"),
		return 0;

	my $cmd = "/bin/cp -p $bh->{minder_file_name} $destfile";
	$bh->{om}->elem("note", "running $cmd");
	my $rawstatus = system($cmd);
	my $status = $rawstatus >> 8;

	$status and		# 0 is success, non-zero failure
		addmsg($bh, "$cmd failed (status $status): $!"),
		return 0;
	return 1;
}

# xxx dbsave and dbload built for the old DB_File.pm environment
# xxx should probably be updated for BerkeleyDB.pm and MongoDB.pm
sub dbload { my( $bh, $mods, $srcfile )=@_;

	$bh->{remote} and		# no can do if you're on web
		unauthmsg($bh),
		return undef;
	$srcfile or
		addmsg($bh, "load from where? no source given"),
		return 0;
	-f $srcfile or
		addmsg($bh, "source ($srcfile) is not a file"),
		return 0;

	my $bname = $bh->{minder_file_name};
	my $cmd = "/bin/mv -f $bname $bname.old; /bin/mv $srcfile $bname";
	$bh->{om}->elem("note", "running $cmd");
	my $rawstatus = system($cmd);
	my $status = $rawstatus >> 8;

	$status and		# 0 is success, non-zero failure
		addmsg($bh, "$cmd failed (status $status): $!"),
		return 0;
	return 1;
}

sub cullrlog { my( $bh, $mods )=@_;

	$bh->{remote} and		# no can do if you're on web
		unauthmsg($bh),
		return undef;

	my ($status, $msg) = $bh->{rlog}->cull;
	$status or
		addmsg($bh, "cullrlog failed: $status"),
		return 0;
	$msg and		# if non-empty, it's probably "nothing to cull"
		addmsg($bh, $msg, 'note');
	return 1;
}

# yyy eventually thought we would like to do fancy fine-grained locking with
#     BerkeleyDB features.  For now, lock before tie(), unlock after untie().
# xxxx maybe delete these?
sub dblock{ return 1;	# placeholder
}
sub dbunlock{ return 1;	# placeholder
}

# A no-op function to call instead of checkchar().
#
sub echo {
	return $_[0];
}

# Record user (":/:/...") values in admin area.
sub note { my( $bh, $mods, $key, $value )=@_;

	#my $contact = $bh->{ruu}->{contact};
	my $db = $bh->{db};
	my $om = $bh->{om};

	dblock();
	my $status = $db->db_put("$A/$A/$key", $value);
	#xxx update bindings_count
	dbunlock();
	if ($status) {
		addmsg($bh, "db->db_put status/errno ($status/$!)");
		return 0;
	}
	return 1;
}

# marks txnlog, eg, just before converting a live database, so that that
# log records _after_ the mark can be processed

sub logmark { my( $bh, $mods, $string )=@_;

	# xxx this must be converted to real "open session" protocol

	#=== start boilerplate
	my $sh = $bh->{sh} or
		return undef;
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($bh, $msg);	# failed to configure
		return undef;
	}
	#=== end boilerplate

	my $txnid;		# undefined until first call to tlogger
	$txnid = tlogger $sh, $txnid, "MARK $string";
	return 1;
}

# print args after possible substitution
# don't log

sub egg_pr { my( $bh, $mods )=(shift, shift);
	# remaining args are concatenated

	# yyy before processing $() and ${}, must warn Greg!
	my $om = $bh->{om};
	return $om->elem('', join( ' ' => @_ ));
}

# XXX deprecated
#
# Strict protocol for id modification.
# xxx protocol: before setting _anything_ extending id, check id|__mp
#   if you don't find it (even as ! remote), set it now!
#     -- but how do you know you have permission on that shoulder?
#     xxx to do: lookup shoulder permissions:  find a proper substring
#   if you do find it, see if you have permission
#   if changing permissions, remember to delete dupes first!
# 
# XXX retrieve top_level __mp just once and cache in $bh, right?
#
# xxx add this protocol to egg_del
# xxx need a better way than WeAreOnWeb to mean "non-admin mode"
####### Need to enforce protocol for creation and perms.
####### Need speed.
####### authz() builds bigpermstring and checks it
####### authy() tries to combine create, write, read and optimization
#######     in one routine
####### ?? can we push authy stuff into authz?
####### Returns: 1=authorized, 0= unauthorized, -1=other error
#
# This routine exists to enforce the protocol we need to observe to keep
# an identifier properly associated with permissions. (I think yyy).
# Can we proceed with $id and $key with the operation that $WeNeed?
# If $WeNeed OP_WRITE|OP_EXTEND, also "create the id",
# which means, set the permissions string for the first time.
# Return $dbh on success, undef on error.
#
# XXXX authy not currently called by anyone
sub authy { my( $WeNeed, $bh, $id, $key ) = ( shift, shift, shift, shift );

	my $dbh = $bh->{tied_hash_ref};
	# strictly observed protocol -- missing perms means id doesn't exist!!
	$bh->{remote} and			# check authz only if on web
			$id =~ /^:/ and		# can't change admin values
		unauthmsg($bh),		# xxx convey more detailed message?
		return undef;

	my ($id_p, $opd_p);		# id and operand permissions strings
	my $id_permkey = $id . PERMS_ELEM;

	if (! defined $dbh->{$id_permkey}) {	# if no top-level permkey,
		# our protocol takes that to mean the id doesn't exist.
		#print("xxxkkk doesn't exist $id\n");
# xxxx what if we're reading and not updating?  now exit!!
		#print("xxxkkk exists $dbh->{$id_permkey}\n");
		($id_p, $opd_p) = shoulder($bh, $WeNeed, $id, $key);
		$id_p or	# if empty $id_p then $opd_p is an error msg
			unauthmsg($bh),		# xxx lose msg in $opd_p
			return undef;
		$dbh->{$id_permkey} = $id_p;
		# $dbh->{$id . CTIME_ELEM} = time(); # xxx should call time()
		# 		#  only once per op and share, eg, with rlog
		return $dbh;
	}

	# if here, then permkey must have already existed
	# xxx temporarily disable this message until EZID db updated
	#$id_p = $dbh->{$id_permkey} or	# protocol violation!!
	#	addmsg($bh, "$id: id permissions string absent"),
	#	return undef;
	# xxx faster if we pass in permstring here?
	! authz($bh->{sh}->{ruu}, $WeNeed, $bh, $id, $key) and  # xxx not called
		unauthmsg($bh),
		return undef;

	return $dbh;

	# XXX withdraw this initial optimization -- too tricky, eg, what
	#     if perms are changed by one user but other user still can
	#     proceed based on cached value
	#$WeNeed & $bh->{last_need_authz} and
	#		$id eq $bh->{last_id_authz} and
	#	return $dbh;		# authorized before and now again
	#	#
	#	# If the last id authorized was the same as this one, and
	#	# if it was for the same or weaker need, then we can skip
	#	# the authorization checks below.
	#	# XXX any op that changes perms must set last_id_auth

	##$bh->{ruu}->{remote} and		# check authz only if on web
	#$bh->{remote} and			# check authz only if on web
	#	$id =~ /^:/ ||	# yyy ban web attempts to change admin values
	#	! authz($bh->{ruu}, $WeNeed, $bh, $id, $key) and
	#		unauthmsg($bh),
	#		return undef;
}

# This is much like 'fetch' except that it prepares a package of HTML
# or RDF.  If HTML, it embeds Turtle and ANVL in HTML comments.
# 
sub show { my( $bh, $mods, $id, @elems )=@_;

	@elems or			# yyy sets or individual elements
		@elems = (':brief');
	# need special output multiplexor to gather a string and some vals
	my $som = File::OM->new('anvl') or	# auto-destroyed on return
		addmsg($bh, "couldn't create string output multiplexer"),
		return undef;

	my @vals;
	$bh->{cite} = 1;	# total kludge to get title quotes
	my $xerc = EggNog::Egg::egg_fetch($bh, undef, $som, undef, \@vals, $id, @elems);
	$bh->{cite} = undef;	# total kludge to get title quotes
	# XXX need one of these for HTML?
	my $citation = join(", ", @vals);
	# see, eg, http://datashare.ucsf.edu/dvn/dv/CIND/faces/study/StudyPage.xhtml?globalId=hdl:TEST/10011&studyListingIndex=6_b75aa0d196115a2b53fa22df13c6

	# xxx kludgy to call print directly instead of OM?
	print "# Please cite as\n#  $citation\n\n";
	my $erc = EggNog::Egg::egg_fetch($bh, undef, $bh->{om}, undef, undef, $id, @elems);
	#$bh->{om}->elem("erc", $erc);
	# yyy no role for OM here?

	#print html_head("What is $id?");
	#print html_erc($erc);
	#print "<p>\n$citation\n</p>\n";
	##print html_tail();

	return 1;
}

# delete first key found in $h from $keylist and
# return corresponding key and value as 2-element list

sub pop_meta { my ($h )=(shift);	# remaining args are keys
	my ($val, $key);
	foreach $key (@_) {
		say "xxx pop $key";
		! $h->{ $key } and
			next;
		$val = $h->{ $key };	# found a value to save
		delete $h->{ $key };	# and delete
		return ($key, $val);
		# yyy not deleting possible other
		# yyy not dealing with duplicates
	}
	return ($key, $unav);
}

sub format_metablob { my($rawblob, $h, $om, $profile, $target)=@_;

	# yyy ignoring $profile, assume $rawblob is ANVL lines
	my ($key, $val);
	my @blobkeyvals = ();			# string blob to return
	push @blobkeyvals, pop_meta($h, $unav,
			qw(who erc.who dc.creator datacite.creator));
	push @blobkeyvals, pop_meta($h, $unav,
			qw(what erc.what dc.title datacite.title));
	push @blobkeyvals, pop_meta($h, $unav,
			qw(when erc.when dc.date datacite.publicationyear));
	return $rawblob;
}

sub md_map_init {
	# hash in pairs
	%md_kernel_map = ( qw(
  who who  erc.who who  dc.creator who  datacite.creator who
  what what  erc.what what  dc.title what  datacite.title what
  when when  erc.when when  dc.date when  datacite.publicationyear when
  where where  erc.where where  dc.identifier where  datacite.identifier where
  how how  erc.how how  dc.type how  datacite.resourcetype how
	) );

# yyy  erc =? electronic resource communication
# DataCite resourceTypeGeneral: Audiovisual Collection Dataset Event Image InteractiveResource Model PhysicalObject Service Software Sound Text Workflow Other
#     <resourceType resourceTypeGeneral="Text">Project</resourceType>
#   normalize to lowercase for mapping, eg, Text/Project->text/project->project
# Dublin Core types: Collection Dataset Event Image InteractiveResource MovingImage PhysicalObject Service Software Sound StillImage Text 
	# pairs map foreign types to ERC types
	%md_type_map = ( qw(
	) );
	return 1;
}

# Called by resolver (and CLI for testing)
# Returns arguments we'll pass to bash script to return resolution results.
# If $om->{outhandle} is defined, just use it for output, otherwise
# return a list of two strings with (a) formatted kernel elements and
# (b) formatted and sorted non-kernel elements.

sub egg_inflect { my ($bh, $mods, $om, $id)=@_;

	defined($id) or
		addmsg($bh, "no identifier specified to inflect"),
		return undef;

	# $st holds accumlated strings/statuses returns from $om calls, if any
	my $p = $om ? $om->{outhandle} : 0;  # whether 'print' status or small
	my $s = '';                     # output strings are returned to $s
	my $st = $p ? 1 : '';           # returns (stati or strings) accumulate

	! egg_authz_ok($bh, $id, OP_READ) and
		return undef;

	# yyy should we record inflect call in txnlog?
	my ($elemsR, $valsR) = ([], []);

	# * $id below might be best like a $rid (root id (no suffix))
	# 3rd arg below (OM) is undefined because, unlike egg_fetch,
	# we only want the results in $elemsR and $valsR for now

	my $rawblob = get_rawidtree($bh, $mods, undef,	# undefined OM
			$elemsR, $valsR, $id) or
		return '';

	my ($profile, $idstatus);	# _p, _s
	my ($key, $val);
	my $target = '';		# _t
	my @pairs = ();

	foreach (@$elemsR) {		# for each element name ($_)

		$key = $_;	# want to modify $key w.o. modifying alias
		$val = shift @$valsR;		# corresponding value
		if ('_' eq substr $_, 0, 1) {		# if $_ starts with _

			if ($_ eq '_t') {
				$target and
					$target .= $separator.$val,
				1 or
					$target .= $val,
				;
				next;			# don't push
			}
			elsif ($_ eq EggNog::Binder::RSRVD_PFIX.'c') {
				# n2t internal creation date
				$key = 'id created';
				$val = etemper( $val );
			}
			elsif ($_ eq '_u') {		# ezid internal
				$key = 'id updated';
				$val = etemper( $val );
			}
			elsif ($_ eq '_s' and $val eq $reserved) {
				return 'Reserved';	# don't push
			}
			elsif ($_ eq '_s') {
				$key = 'status';
			}
			else {
				next;			# skip other internals
				# yyy make other internal elems human readable
			}
			push @pairs, $key, $val;
			next;
		}

		# split up erc blobs like this one
		# erc: who: Proust, Marcel%0Awhat: Remembrance of Things Past
		# yyy to do: split up xml blobs

		if ($key eq 'erc') {
			my @erc = split /(?:%0A|\n)/i, $val;	# can be empty
			push @pairs, map		# only grab non-empties
				{ m/^([^:]+?)\s*:\s*(.*)/ }	# add subelems
				#{ /:/ and split /\s*:\s*/ }	# add subelems
					@erc;
			next;				# don't push erc blob
		}

# #From https://stackoverflow.com/questions/156683/what-is-the-best-xslt-engine-for-perl
# (modules installed with cpanm on mac, and yum on dev,stg,prd)
# use XML::LibXSLT;
# use XML::LibXML;
#
# my $parser = XML::LibXML->new();
# my $xslt = XML::LibXSLT->new();
#
# my $source = $parser->parse_file('foo.xml');
# my $style_doc = $parser->parse_file('bar.xsl');
#
# my $stylesheet = $xslt->parse_stylesheet($style_doc);
#
# my $results = $stylesheet->transform($source);
#
# print $stylesheet->output_string($results);

		if ($key eq 'datacite') {
			# see datacite.xsl file from ezid code base
			# xxx xml2anvl($val, 'datacite.xsl')
			push @pairs, $key, $val;	# yyy stop pushing xml
			next;				# blob when exploded
		}
		push @pairs, $key, $val;
	}

	# Now that blobs have been expanded, reprocess from the top,
	# extracting kernel elements to put in front of the rest.
	# Use md_kernel_map to determine whether an element belongs
	# in one of 5 categories: who, what, when, where, how
	# NB: we use $separator between values when there are multiple values.

	my %kernel = ();
	! %md_kernel_map and		# if not already done,
		md_map_init();		# initialize metadata crosswalk hashes

	$kernel{where} = $id;		# initialize 'where' element
	$target and
		$kernel{where} .= " (currently $target)";

	my $mk;					# mapped key
	my %nonkernel;
	while ($key = shift @pairs) {		# eg, key=dc.title, key=format
		$val = shift @pairs;
		# if it maps to the kernel, eg, dc.title -> what
		if ($mk = $md_kernel_map{$key}) {
			$kernel{$mk} and		# eg, $kernel{what}
				$kernel{$mk} .= $separator.$val,
			1 or
				$kernel{$mk} = $val,
			;
			# if it was originally a kernel element, drop it
			#$mk eq $key || $mk eq "erc.$key" and
			$mk eq $key || $key eq "erc.$mk" and
				next;		# skip element copy at bottom
		}
		$nonkernel{$key} and
			$nonkernel{$key} .= $separator.$val,
		1 or
			$nonkernel{$key} = $val,
		;
	}
	$nonkernel{persistence} ||= $unav;

	# yyy kludge to get "erc:" record header by adding fake 'erc' element
	$kernel{erc} = ' ';		# use space so empty value test fails
	for $mk (qw( erc who what when where how )) {	# order-preserving list
		($s .= $om->elem($mk, ($kernel{$mk} || $unav))); # see comments
		($p && (($st &&= $s), 1) || ($st .= $s));  # elsewhere on this
	}
	my $briefblob = $s;			# what's constructed so far

	$om->elem('NB', ' non-kernel elements',	# send note not to string $s
		"1#");				# but to output as a comment
	for $key (sort keys %nonkernel) {
		# see get_rawidtree comments elsewhere on this
		($s .= $om->elem($key, $nonkernel{$key}));
		($p && (($st &&= $s), 1) || ($st .= $s));
	}
	return $p ? $st : ($s, $briefblob);
}

#XXXXXXXXXX; TODO;
#Regularize flex_enc_... across exdb and indb
#so that indb doesn't pollute $id and $elem for the exdb case
#BETTER: push flex_enc calls deep into *db_get_dup/*db_set_dup where they
#  won't conflict
#  done: correctly done for $id _inside_ get_rawidtree()
# indb_set (?? doesn't exist)
# xxx must implement exists() for exdb case

sub exdb_elem_output { my( $om, $key, $val )=@_;

	my $p = $om ? $om->{outhandle} : 0;  # whether 'print' status or small
	my $s = '';                     # output strings are returned to $s
	my $st = $p ? 1 : '';           # returns (stati or strings) accumulate

	my $out_elem = $key ne '' ? $key : '""';
	$out_elem =~	# "flex_dec_exdb" as needed
		s/\^([[:xdigit:]]{2})/chr hex $1/eg;
	my @vals = ref($val) eq 'ARRAY' ? @{ $val } : ( $val );
	foreach my $val (@vals) {
		$s = $om->elem($out_elem, $val);
		($p && (($st &&= $s), 1) || ($st .= $s));
	}
	return $st;	# yyy verify if this is the correct thing to return
}

# ? get/fetch [-r] ... gets values?
# ? getm/fetchm [-r] ... gets names minus values?
# ? getm/fetchm [-r] ... gets metadata elements (not files)?

# --format (-m) tells whether we want labels
# -r tells whether we recurse
# xxx old: $verbose is 1 if we want labels, 0 if we don't
# yyy do we need to be able to "get/fetch" with a discriminant,
#     eg, for smart multiple resolution??

#our @suffixable = ('_t');		# elems for which we call suffix_pass

# xxx can we use suffix chopback to support titles that partially match?
#
# Rewrite rules redirect any query string ?, ??, ?foo... to a CGI (bind):
# They also catch any Accept header and redirect
#    n2t.net/_/bind?<orig_REQUEST>

# (what about / or .) query string to a cgi.
# Resolver answers first w.o. suffix pt.
# Resolver later(?) tryies suffix pt?
# Resolver captures any terminal pattern matching ? ?? / . or THUMP-like string
#
#
# HH = http://host.example.org
# HH/xxx?    -> capture any terminal pattern matching ? ?? / .
# HH/xxx??
# HH/xxx/
# HH/N/xxx.

# yyy 2011.10.20 returns undef on error (eg, $id undefined),
#     or 0 if $id doesn't exist (XXX we don't bind $id yet! see mkid!)
#     or the return from $om if $om is defined (eg, a formatted string)
#     or 1 if $om isn't defined
#     yyy get_rawidtree must return same!
#     yyy and what about suffix_pass?
#     For non-error cases, if $valsR is defined, on return it will be set
#     to refer to an array of values corresponding to each bound element
#     that was found (eg, empty if no bound elements found)
# Use $om to build formatted string return.  Leave $om undefined and it
#     won't be called.
# Use $valsR as array ref to return raw bound element values.  Leave $valsR
#     undefined to avoid building and returning array of bound elements.
#
# yyy document: (2011.10.16) on success, fetch returns either (a) print
# status or (b) built string (which could be ""). On error returns undef.
# yyy what's the difference now between fetch and get?
#

#our $xxx;	# commented out lines with $xxx were used to test for the
		# Apache Resolverlist Bug

sub egg_fetch { my(   $bh, $mods,   $om, $elemsR, $valsR,   $id ) =
	          ( shift, shift, shift,   shift,  shift, shift );
		my @elems = @_;		# make copy of remaining args in @_,
					# which will be elems to fetch
	defined($id) or
		addmsg($bh, "no identifier specified to fetch"),
		return undef;

	# yyy should we permit holds (ie, reserve some id)?
	# yyy this isn't ready since we don't yet bind just $id (only $id$Se...)
	#     but this may change with mkid creating an "empty" root

	# $st holds accumlated strings/statuses returns from $om calls, if any
	my $p = $om ? $om->{outhandle} : 0;  # whether 'print' status or small
	my $s = '';                     # output strings are returned to $s
	my $st = $p ? 1 : '';           # returns (stati or strings) accumulate
	my $sh = $bh->{sh};

	my $rrm = $bh->{rrm};		# yyy pretty sure $rrm not used here
	my $lcmd = $rrm ? 'resolve' : 'fetch';

	if (! $mods->{did_rawidtree}) {
		EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id, @elems) or
			addmsg($bh, "instantiate failed from fetch"),
			return undef;
	}

	! egg_authz_ok($bh, $id, OP_READ) and
		return undef;

	my $db = $bh->{db};
	$valsR and		# Now (re)initialize $valsR if supplied so
		@$valsR = ();	# that we'll be able to push values onto it.
	$elemsR and		# Now (re)initialize $elemsR if supplied so
		@$elemsR = ();	# that we'll be able to push values onto it.

	my $txnid;		# undefined until first call to tlogger

	if ($#elems < 0 and $om) {	# process and return (no fall through)
	
		# We're here because no elems were specified, so find them.
		# and don't bother if no ($om) output

		# NB: if we're here, we weren't called by get_rawidtree,
		# since it would have called us with a specific element.
# xxx so ! did_rawidtree ?

		$txnid = tlogger $sh, $txnid, "BEGIN $lcmd $id";

		if ($sh->{fetch_exdb}) {	# if EGG_DBIE is e or ei

			my $rfs = flex_enc_exdb($id, @elems);	# yyy no @elems

# xxx similar to calling get_rawidtree
			my $result;
			# yyy binder belongs in $bh, NOT to $sh!
			#     see ebopen()
			my $coll = $bh->{sh}->{exdb}->{binder};	# collection
			my $msg;
			my $ok = try {
				$result = $coll->find_one(
					{ PKEY()	=> $rfs->{id} },
				)
				// {};	# valid hash {} != undefined
			}
			catch {
				$msg = "error fetching id \"$id\" " .
					"from external database: $_";
				return undef;
				# returns from "catch", NOT from routine
			};
			! defined($ok) and # test undefined since zero is ok
				addmsg($bh, $msg),
				return undef;
			# yyy using $result how?
			#use Data::Dumper "Dumper";
			#print Dumper $result;
			#$out_id = $id ne '' ? $id : '""';
			#$out_id =~		# "flex_dec_exdb" as needed
			#	s/\^([[:xdigit:]]{2})/chr hex $1/eg;

			my ($out_elem, $out_id);	# output ready forms
			$out_id = flex_dec_for_display($id);
			# yyy maybe $id:\n or "id: $id\n"? or "# id: $id\n" ?
			$s = $om->elem('id',		# print starter comment
				" id: " . $out_id, "1#");
				# yyy use _id not id
			($p && (($st &&= $s), 1) || ($st .= $s));

			my $all = $mods->{all} // $bh->{opt}->{all} // '';
			my $skipregex = '';
			my $spat = '';
			if (! $all) {	# case 1: skip usual support elements
				$spat = SUPPORT_ELEMS_RE;
				$skipregex = qr/^$spat/o;
			}

			my $nelems = 0;
			while (my ($k, $v) = each %$result) {
				$skipregex and $k =~ $skipregex and
					next;
				$k eq '_id' and		# yyy peculiar to mongo
					next;
			#	$out_elem = $k ne '' ? $k : '""';
			#	$out_elem =~	# "flex_dec_exdb" as needed
			#		s/\^([[:xdigit:]]{2})/chr hex $1/eg;
			#	$s = $om->elem($out_elem, $v);
				$s = exdb_elem_output($om, $k, $v);
				($p && (($st &&= $s), 1) || ($st .= $s));
				$nelems++;
			}
			$s = $om->elem('elems',		# print ending comment
				" elements bound under $out_id: $nelems", "1#");
			($p && (($st &&= $s), 1) || ($st .= $s));
			# yyy $st contains return value
			# xxx unused at the moment
		}
		if ($sh->{fetch_indb}) {	# if EGG_DBIE is i or ie

			# Unlike the call from within egg_purge(), this call to
			# get_rawidtree() does our work itself by outputing as
			# a SIDE-EFFECT, instead of returning a list to process.
			# We pass in the UNencoded $id, and it takes care of
			# element handling for us.

			$st = get_rawidtree($bh, $mods, $om,	# $om defined
				$elemsR, $valsR, $id);
		}

		tlogger $sh, $txnid, "END " . ($st ? 'SUCCESS' : 'FAIL')
				. " $lcmd $id";
		return $st;
	}

#	my $key;	# xxx used?
## xxx duplicate below and test; then drop this whole if thing from here
#	if (! $mods->{did_rawidtree}) {
#		$irfs = flex_enc_indb($id, @elems);
##say "xxx naively called flex_enc_indb($id, $elems[0], ...)";
## XXX use these from $irfs -- don't overwrite original $id and elems
#		#$key = $irfs->{key};
#		#$id = $irfs->{id};		# need encoded $id
#		#@elems = @{ $irfs->{elems} };	# need encoded @elems
#	}
#	elsif ($sh->{fetch_indb}) {	# yyy exdb won't call get_ rawidtree
## xxx !! useless -- drop this clause
#		$irfs->{key} = join($Se, $id, @elems);
#		# yyy not setting id or elems because we don't use them?
#	}
#	#else {		# this does no harm or good
#	#	$key = join($Se, $id, @elems),
#	#}

	# XXX need to issue END before every error return below
	# xxx we're starting a bit late (so timing may look a little faster)
	#     but we get less noise from each recursive call
	# use UNencded $id and @elems
	$txnid = tlogger $sh, $txnid, "BEGIN $lcmd $id " . join('|', @elems);

	# If we get here, elements or element sets to fetch were specified.
	# %khash is a kludge hash to hold elements emerging from blobs.
	# yyy should this work for elem names with regexprs in them?
	# xxx need kludge hash to extract elements from XML or ERC blobs
	#     (note: xml and erc blobs are themselves kludges)
	#
	my %khash = ();		# kludge hash
	my $msg;
	my @newelems = ();
	push @newelems, EggNog::Resolver::expand_blobs
		# using UNencoded $id and @elems (don't need "rfs" args)
		($bh, $id, $msg, \%khash, @elems);
	$msg and
		addmsg($bh, $msg),
		return undef;

	scalar(@newelems) and		# btw newelems aren't encoded yet
		push @elems, @newelems;
	#
	# Any new elements were pushed on together with existing element
	# set names (eg, :brief).  New elements may include special
	# elements (eg, :id, :policy) to be processed specially.

	# if get_rawidtree() was called, our args are already "rfs"
	my $rfs;
	if (! $mods->{did_rawidtree}) {
		$rfs = $sh->{fetch_indb}
			? flex_enc_indb($id, @elems)
			: flex_enc_exdb($id, @elems)
		;
	}
	else {
		$rfs = {
			id => $id,
			elems => \@elems,
		};
	}

	# yyy make work for XML and ERC blobs

	# yyy note: returns dups mixed together with single-valued elems
	# By far most elements aren't duplicated, but we're prepared.
	#
	my (@ss, $idmapped);	# strings/statuses and rule-based mappings
	my (@dups, @kdupix);	# dups and kludge dup indices
	my $special;		# kludge for :id and :policy
	my $rrmfail = 0;

	for my $elem ( @{ $rfs->{elems} } ) {

		# xxx will this be able to use OM and get string output?
		# xxx test

		# Try to find some values, first by straightforward lookup
		# in the database and elements that emerged from blobs.
		# XXX Big kludge next for "special" elements.
		#
		$special = '';
		my $key;
		if ($elem =~ /^:/) {		# special element like :brief
			# use UNencoded args -- don't need "rfs" args since
			# all special_elems will be recognized either way
			# NB: on success, args 2 and 3 will be MODIFIED
			# yyy? but not in a way that needs re-flex_encoding
			EggNog::Resolver::special_elem(
					$id, $special, $elem, \@dups) or
				next;		# xxx error?  or what?
		}
		else {
			# NB: encoding ready-for-storage for $id and $elem(s)
			# will have been done either through get_rawidtree()
			# or through code earlier in this routine.

			@dups = $sh->{fetch_indb}
				? indb_get_dup($db, $rfs->{id} . $Se . $elem)
				: exdb_get_dup($bh, $rfs->{id}, $elem)
			;
		}

		# yyy adds values that were hidden in blobs; presumably
		#     this happens when @dups is empty, but we don't check.
		#     Make sure it doesn't accidentally pick up something
		#     on our "special" list.
		#
		@kdupix = $khash{$elem} && ! $special ?
			@{ $khash{$elem} } : ();	# index into @newelems
		scalar(@kdupix) and		# value is at index + 2
			push @dups,
				@newelems[ map {$_ + 2} @kdupix ];

		# yyy "" element value aside, this is fishy logic for
		#     outputting when you're NOT a subresolver
		#     I guess we bail here if we are a subresolver and
		#     haven't found anything yet
		#
		scalar(@dups) or	# if still no values,
			next;		# we're done with this element

		# If we get here, there's at least one element.  If the
		# first dup is undefined, it indicates an error return
		# from one of the above calls (with outmsg set).
		#
		defined($dups[0])	or return undef;

		if ($valsR) {		# if we're able to return values,
			my $kludge = $bh->{cite} && $elem =~ /^(?:what|title)$/;
			$kludge and	# xxx puts "" around a title
				($dups[0] =~ s/^/"/),
				($dups[$#dups] =~ s/$/"/);
			push(@$valsR, @dups);	# we prepare for that
		}

		$om or			# and unless we're doing output
			next;		# we're done with this element

		# If we get here, the caller wants us to output via $om.

		my $out_elem = $elem ne '' ? $elem : '""';
		$out_elem =~		# "flex_dec_indb" as needed
			s/\^([[:xdigit:]]{2})/chr hex $1/eg;

			#	$bh->{rrmlog} and $bh->{rrmlog}->out(
			#		"N: after match in $rmh on id $id");
			# we know from kludge above that there's only one

		@ss =	# save strings or status after mapping $om to @dups
			# The $elem ne '' check gets the edge case right in
			# which $elem matches /^0+$/.
			map(
				#$om->elem( ($elem ne '' ? $elem : '""'), $_),
				$om->elem( $out_elem, $_),
				@dups
			);

		# This line in the loop shows a fast and compact (if cryptic)
		# way to accumulate $om->method calls.  Used after each method
		# call, it concatenates strings or ANDs up print statuses,
		# depending on the outhandle setting.
		#
		$p && (($st &&= $_), 1) || ($st .= $_)		for (@ss);
	}
	$msg = 'END ' . ($st ? 'SUCCESS' : 'FAIL');
	$rrmfail and
		$msg = 'END FAIL';
	$msg .= ($rrm
		? " $lcmd $id to $dups[0] ("
			. $bh->{sh}->{ruu}->{http_referer}
			. ' ; '
			. $bh->{sh}->{ruu}->{http_user_agent}
			. ')'
		: " $lcmd $id " . join('|', @elems));
	tlogger $sh, $txnid, $msg;

	return $st;
}
# end of fetch routine

# Any, all, or none of $om, $elemsR, and $vals$ may be defined.
# If $om is defined, use it.  If $elemsR is defined, push element
# names onto it.  If $valsR is defined, push element values onto it.
# !! assume $elemsR and $valsR, if defined, are ready to push onto
# xxx maybe we should have a special (faster) call just to get names
#
# NB: discovered id and element names are already encoded ready-for-storage,
# (eg, | and ^), which means (a) beware not to encode them again and
# (b) you will probably want to decode before output.
#
# Note: this routine outputs via $om, as a side-effect, unless you
# arrange not to (eg, egg_purge() calls it and processes the returns).
# yyy This is perhaps strange -- maybe egg_del() should be called from
#     get_rawidtree.

# XXX this is indb-specific!

sub get_rawidtree { my(   $bh, $mods,   $om, $elemsR, $valsR,   $id )=@_;
		      #( shift, shift, shift,   shift,  shift, shift );

	my $p = $om ? $om->{outhandle} : 0; # whether 'print' status or small
	my $s = '';                     # output strings are returned to $s
	my $st = $p ? 1 : '';           # returns (stati or strings) accumulate
	my $db = $bh->{db};

	# Indicate to downstream users of this call (purge, delete, fetch)
	# that they shouldn't try to expand ids and element names, since
	# they were discovered from the database and not entered on a
	# command line.
	#
	$mods->{did_rawidtree} = 1;	# xxx kludgish; side-effects?? of
				# setting a $mods entry for downstream calls?

# xxx indb-specific!
	my $irfs = flex_enc_indb($id);
	$id = $irfs->{id};		# because we need $id ready-for-storage

	# xxx if we ever allow $id to be bound w.o. an element (ie, as
	#     $id along and not as $id$Se...), then this code will change
	#my ($first, $skip, $done) = ("$id$Se", 0, 0);

	my $elem = '';
	my ($first, $skip, $done) =
		("$id$Se$elem", 0, 0);

		# NB: we don't call flex_enc_indb here since these keys are
		# discovered FROM storage, hence they're already encoded.

	my ($key, $value) =
		($first, '');

	#print "in get_rawidtree, key starts out=$key\n";

	# Cases for modifier :all[pattern]
	# 1. No modifier means skip admin elements: $skipregex set to default.
	# 2. else do ALL elements.

	# xxx possible future cases:
	# 2. Modifier with no (empty) pattern means ALL: $skipregex = undef.
	# 3. Modifier plus pattern means skip all _but_ matching element names:
	#      $all and $skip = ! ... =~ $skipregex
	# 4. Modifier plus ??? means turn off any "--all" flag setting
	# 
	my $all = defined($mods->{all})
		? $mods->{all}		# zero ok; for overriding --all
		: $bh->{opt}->{all} || '';
	my ($spat, $skipregex);
	! $all and			# case 1: skip usual support elements
		$spat = SUPPORT_ELEMS_RE,
	1
	or
		$skipregex = undef
	;
	# yyy?
	# When we get here, $spat is undefined only for case 2, but that's
	# when we already defined $skipregex, which is what we really need.
	# We don't do the substr() version of the /^\Q.../ test since we
	# actually need a regexp match on $spat.
	# xxx evaluate impact on skipregex of flex_enc_indb format
	#
	$spat and
		$skipregex = qr/^\Q$first\E$spat/;
		# DON'T use 'o' flag because $first changes with each call
	#
	# Now if $skipregex is defined, $all says if we're to negate it.
	# If it's undefined, we never re-evaluate whether we're to skip
	# and the boolean $skip remains 0 always.

	my $cursor = $db->db_cursor();
	my $status = $cursor->c_get($key, $value, DB_SET_RANGE);

	# yyy no error check, assume non-zero == DB_NOTFOUND
	$status == 0 and
		#$skip = ($key =~ m|^\Q$first$A/|),	# skip if $id$Se:/...

		# update $skip only if $skipregex is non-null
		($skipregex and
			$skip = ($key =~ $skipregex),
			($all and		# negate match
				$skip = ! $skip),
		),

		#$skip =	# skip elements with only a support role
		#	#($key =~ m|^\Q$first\E&SUPPORT_ELEM|),
		#	($key =~ m/$skipregex/),

		#$done = ($key !~ m|^\Q$first|),
		$done = ($first ne substr($key, 0, length($first))),
	1 or
		$done = 1
	;
	#$out_id = $id ne '' ? $id : '""';
	#$out_id =~		# "flex_dec_indb" as needed
	#	s/\^([[:xdigit:]]{2})/chr hex $1/eg;

	my ($out_elem, $out_id);		# output ready forms
	$out_id = flex_dec_for_display($id);
	# yyy should it be $id:\n or "id: $id\n"? or "# id: $id\n" ?
	$om and ($s = $om->elem('id',			# print starter comment
		" id: " . $out_id, "1#"));
		#" id: " . ($id ne '' ? $id : '""'), "1#"));
	($p && (($st &&= $s), 1) || ($st .= $s));
 
	my $nelems = 0;
	# kludge for a very unlikely element ("" is too likely)
	# xxx evaluate security implications of kludge
	while (! $done) {
		unless ($skip) {
			$nelems++;

			# Here we strip "Id|" from front of $key, with 's'
			# modifier since the key might legitimately contain
			# newlines.
			#
			$elem = ($key =~ /^[^|]*\|(.*)/s ? $1 : $key);

# xxx ??? $out_id = flex_dec_for_display($id);
			$out_elem = $elem ne '' ? $elem : '""';
			$out_elem =~		# "flex_dec_indb" as needed
				s/\^([[:xdigit:]]{2})/chr hex $1/eg;

			# If $om is defined, do some output now.
			$om and ($s = $om->elem(
				$out_elem,
				#($elem ne '' ? $elem : '""'),
				#($key =~ /^[^|]*\|(.*)/ ? $1 : $key),
				$value)),
				($p && (($st &&= $s), 1) || ($st .= $s));

			# This last line is a fast and compact (if
			# cryptic) way to accumulate $om->method calls.
			# Used after each method call, it concatenates
			# strings or ANDs up print statuses, depending
			# on the outhandle setting.  It makes several
			# appearances in this routine.

			$elemsR and push(@$elemsR, $elem);
			$valsR and push(@$valsR, $value);

			#$retval .= ($verbose ?
			#	($key =~ /^[^\t]*\t(.*)/ ? $1 : $key)
			#		. ": " : "") . "$value\n";
		}
		# this picks up duplicates just fine, if any

		$status = $cursor->c_get($key, $value, DB_NEXT);

		#$status = $db->seq($key, $value, R_NEXT);
		#$status != 0 || $key !~ /^\Q$first/ and
		# yyy no error check, assume non-zero == DB_NOTFOUND
		$status != 0 || $first ne substr($key, 0, length($first)) and
			$done = 1,	# no more elements under id
		or
			#$skip = ($key =~ m|^\Q$first$A/|)
			#$skip =	# skip elems with only a support role

			# update $skip only if $skipregex is non-null
			($skipregex and
				$skip = ($key =~ $skipregex),
				#print("key=$key, all=$all, skip=$skip\n"),
				($all and
					$skip = ! $skip),
			),

			#($skipregex and $skip = # skip elems that only support
			#	#($key =~ m|^\Q$first\E&SUPPORT_ELEM|)
			#	($key =~ m/$skipregex/)),
		;
	}
	$om and ($s = $om->elem('elems',		# print ending comment
		" elements bound under $out_id: $nelems", "1#"));
		#($id ne '' ? $id : '""') . ": $nelems", "1#"));
	($p && (($st &&= $s), 1) || ($st .= $s));
	$cursor->c_close();
	undef($cursor);
	return $om ? $st : 1;		# $valsR, if set, return values
	#return $st;
}

# XXXXX feature from EZID UI redesign: list ids, eg, by user
# XXXXX feature from EZID UI redesign: sort, eg, by creation date

# Return $val constructed by mapping the element
# returns () if nothing found, or (undef) on error

sub id2elemval { my( $bh, $db, $id, $elem )=@_;

	my $first = "$A/idmap/$elem|";
	my $key = $first;
	my $value = 0;
	#my $status = $db->seq($key, $value, R_CURSOR);
	my $cursor = $db->db_cursor();
	my $status = $cursor->c_get($key, $value, DB_SET_RANGE);
	# yyy no error check, assume non-zero == DB_NOTFOUND
	$status and
		$cursor->c_close(),
		undef($cursor),
		addmsg($bh, "id2elemval: $status"),
		return (undef);
	#$key !~ /^\Q$first/ and
	$first ne substr($key, 0, length($first)) and
		$cursor->c_close(),
		undef($cursor),
		return ();

	# This loop exhaustively visits all patterns for this element.
	# Prepare eventually for dups, but for now we only do first.
	# XXX document that only the first dup works $cursor->c_get. (& fix?)
	#
	my ($pattern, $newval, @dups);
	while (1) {

		# The substitution $pattern is extracted from the part of
		# $key that follows the |.
		#
		# We don't do the substr() version of the /^\Q.../
		# test since we actually need a regexp match.
		($pattern) = ($key =~ m|\Q$first\E(.+)|);
		$newval = $id;

		# xxxxxx this next line is producing a taint error!
		# xxx optimize(?) for probable use case of shoulder
		#   forwarding (eg, btree search instead of exhaustive),
		#   which would work if the patterns are left anchored
		defined($pattern) and
			# yyy kludgy use of unlikely delimiters
		# XXX check $pattern and $value for presence of delims
		# XXX!! important to untaint because of 'eval'

			# The first successful substitution stops the
			# search, which may be at the first dup.
			#
			(eval '$newval =~ ' . qq@s$pattern$value@ and
				$cursor->c_close(),
				undef($cursor),
				return ($newval)),	# succeeded, so return
			($@ and			# unusual error failure
				$cursor->c_close(),
				undef($cursor),
				addmsg($bh, "id2elemval eval: $@"),
				return (undef))
			;
		#$db->seq($key, $value, R_NEXT) != 0 and
		# yyy no error check, assume non-zero == DB_NOTFOUND
		$cursor->c_get($key, $value, DB_NEXT) != 0 and
			$cursor->c_close(),
			undef($cursor),
			return ();
		# no match and ran out of rules
		$first ne substr($key, 0, length($first)) and
		#$key !~ /^\Q$first/ and	# no match and ran out of rules
			$cursor->c_close(),
			undef($cursor),
			return ();
	}
	$cursor->c_close();
	undef($cursor);
}

1;

__END__


=head1 NAME

Egg - routines to bind and resolve identifier data

=head1 SYNOPSIS

 use EggNog::Egg;		    # import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2013 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<dbopen(3)>, L<perl(1)>, L<http://www.cdlib.org/inside/diglib/ark/>

=head1 AUTHOR

John A. Kunze

=cut