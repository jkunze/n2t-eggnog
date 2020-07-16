package EggNog::Egg;

# Author:  John A. Kunze, jak@ucop.edu, California Digital Library
#		Originally created, UCSF/CKM, November 2002
# 
# Copyright 2008-2020 UC Regents.  Open source BSD license.
#
# XXX add low-level check for binder opened RDONLY since BDB silently fails
#     with no messag

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	exdb_get_dup indb_get_dup exdb_get_id egg_inflect
	flex_enc_exdb flex_enc_indb
	iddump idload
	PERMS_ELEM OP_READ
	EXsc PKEY
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Path;
use File::OM;
use File::Value ":all";
use File::Copy;
use File::Find;
use EggNog::Temper ':all';
use EggNog::Binder ':all';	# xxx be more restrictive?
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

our $PKEY =  '_id';	# exdb primary key, which
	# happens to be a MongoDB reserved key that enforces uniqueness

our %md_kernel_map;
our %md_type_map;
our $unav = '(:unav)';
our $reserved = 'reserved';		# yyy ezid; yyy global
our $separator = '; ';			# yyy anvl separator
our $SL = length $separator;

our $BSTATS;	# flex_encoded exdb record id/elem hash for binder stats

# yyy test bulk commands at scale -- 2011.04.24 Greg sez it bombed
#     out with a 1000 commands at a time; maybe lock timed out?

# yyy The database must hold nearly arbitrary user-level identifiers
#    alongside various admin variables.  In order not to conflict, we
#    require all admin variables to start with ":/", eg, ":/oacounter".
#    We use "$A/" frequently as our "reserved root" prefix.

# We use a reserved "admin" prefix of $A for all administrative
# variables, so, "$A/oacounter" is ":/oacounter".
#
my $A = EggNog::Binder::ADMIN_PREFIX;
my $Se = EggNog::Binder::SUBELEM_SC;	# indb case
my $So = '|';				# sub-element separator on OUTPUT
our $EXsc = qr/(^\$|[.^])/;		# exdb special chars, mongo-specific

use Fcntl qw(:DEFAULT :flock);
use File::Spec::Functions;

#use DB_File;
use BerkeleyDB;
use constant DB_RDWR => 0;		# why BerkeleyDB doesn't define this?

our $noflock = "";
our $Win;			# whether we're running on Windows

# Legal values of $how for the bind function.
# yyy document that we removed: purge replace mint peppermint new
# yyy but put "mint" back in!
# yyy implement append and prepend or remove!
# yyy document mkid rmid
# yyy valid_hows is unused -- remove here and in Nog.pm?
my @valid_hows = qw(
	set let add another append prepend insert delete mkid rm
);

#
# --- begin alphabetic listing (with a few exceptions) of functions ---
#

# yyy genonly seems to be there to relax validation,
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

# Increment or decrement bindings_count by $amount, return non-zero on error.
# Instantiates with $amount if field doesn't yet exist.
# NB: this routine ASSUMES exdb

sub bcount { my( $bh, $amount )=@_;

# xxx when exactly should we NOT update bindings count?
	# XXX binder belongs in $bh, NOT to $sh!
	my $coll = $bh->{sh}->{exdb}->{binder};	# collection
	my ($result, $msg);
	my $ok = try {
		$result = $coll->update_one(
			{ $PKEY	  => $BSTATS->{id} },
			{ '$inc'  => { $BSTATS->{elem} => $amount } },
			{ upsert  => 1 },	# create if it doesn't exist
		)
		// 0;		# 0 != undefined
	}
	catch {
		# xxx these should be displaying UNencoded $id and $elem
		$msg = "error updating bindings_count elem under " .
			"id \"$BSTATS->{id}\" from external database: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and 	# test undefined since zero is ok
		addmsg($bh, $msg),
		return undef;
#say "xxx query={ $PKEY => $BSTATS->{id} }, { \$inc => { $BSTATS->{elem} => $amount } } ===> result=$result";

#say "xxx matched_count=$result->{matched_count}, modified_count=$result->{modified_count}, upserted_id=$result->{upserted_id}";

	return $result;
}

my $cfq_usage_text = << "EOF";

SUBCOMMAND
   cfq - eggnog configuration query

SYNOPSIS
   egg cfq [ Tword ]

where Tword is a trigger word for various kinds of plain text output
showing configuration information. Except for the reserved forms

   _list
   _list_all
   _help
   *_today
   *_N
   _host_where Key Value

the Tword is normally taken as a verbatim key whose value is returned.
If the key doesn't identify a host-specific setting, it will be looked up
as general service setting. If the key identifies a value of "false", the
return status to the shell will be non-zero, and otherwise zero (success).

The cfq subcommand supports cron. Extra processing occurs when the Tword
word contains the string "_today". Before lookup, this string is transformed
into the current day of the week (monday, ..., sunday) or, failing a match,
day of the month (1, 2, ..., 31). The resulting keys are looked up and the
first match is returned. For example, these keys

   patch_tuesday	# for OS patching on Tuesdays
   rotate_1		# rotate logs at the start of the month

will cause "egg cfq patch_today" to print the value for patch_tuesday only
on Tuesdays, and "egg -q cfq rotate_today" to print nothing, but return a
non-zero exit status only on the first of the month and if the value for
rotate_1 is non-empty or non-zero. The _host_where trigger prints those
configured hostnames for which Key equals Value, eg, "class" equals "prd".

EOF

our @wdays =
	qw( sunday monday tuesday wednesday thursday friday saturday );

# output 1 if set 0 if not
# first try hash given as first arg, and if no keys found,
# try hash given as second arg; usually these args are given as
# 1. a host-specific hash
# 2. a service-specific hash

sub outkey { my( $om, $h1cf, $h2cf, $key, $quiet )=@_;

	! exists $h1cf->{$key} && ! exists $h2cf->{$key} and
		$quiet || $om->elem($key, 'UNDEFINED'),
		return 0;
	my $value = $h1cf->{$key} // $h2cf->{$key};	# defined but 0 is ok
	$quiet || $om->elem($key, $value);
	return ($value ? 1 : 0);
}

# various configuration queries, used by cron
# reserved queries: _help, _list, _list_all

sub egg_cfq { my( $bh, $mods, $om, $subcmd, $hwkey, $hwval )=@_;

	my $sh = $bh->{sh};
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;

# return EggNog::Conf::cfq($tword);
# generic cfq doesn't use $sh, $bh, $mods, $om
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		outmsg($sh, $msg);	# failed to configure
		return undef;
	}

	$subcmd ||= '_help';
	my $servicecf = $sh->{service_config};
	my $hcf = $sh->{host_config};

# dependencies: $sh->{service_config}; $sh->{host_config};
# Data::Dumper, YAML
# outkey()

	use Data::Dumper 'Dumper';
	if ($subcmd eq '_help') {
		say "$cfq_usage_text";
		return 1;
	}
	elsif ($subcmd eq '_list') {
		say Dumper $hcf;
		return 1;
	}
	elsif ($subcmd eq '_list_all') {
		say Dumper $servicecf;
		return 1;
	}
	elsif ($subcmd eq '_host_where') {
		! $hwkey || ! $hwval and
			return outkey($om, $hcf, $servicecf,
			 '_host_where needs both key and value args non-empty');
		my ($host, $attribs);
		while (($host, $attribs) = each $servicecf->{hosts}) {
			$attribs->{$hwkey} eq $hwval and
				say "$host";	# yyy not using $om
		}
		return 1;
	}
	# All above cases will have returned, so the rest is an "else" case.

	my $key = $subcmd;
	$key !~ /_today(?:_|$)/ and		# ordinary case
		return outkey($om, $hcf, $servicecf, $key);

	# Special processing case. Greedy match extracts only the last
	# instance of "_today".

	my ($before, $after) = $key =~ /^(.*_)today(_.*|$)/;
	defined($before) or			# yyy unknown error
		return outkey($om, $hcf, $servicecf, "bad query");
	$after //= '';
	my @date = localtime();
	my $mday = $date[3];
	my $wday = $date[6];	# day of week, 0 = Sunday

	my $keywday = $before .
		$wdays[ $date[6] ] . $after;		# day of week, 0=sunday
	my $keymday = $before . $date[3] . $after;	# day of month
	my $quiet = 1;
	outkey($om, $hcf, $servicecf, $keywday, $quiet) and
		# quietly check if true and if so, output and return
		return outkey($om, $hcf, $servicecf, $keywday);
	# if it wasn't a day-of-week key, try day-of-month key
	outkey($om, $hcf, $servicecf, $keymday, $quiet) and
		# quietly check if true and if so, output and return
		return outkey($om, $hcf, $servicecf, $keymday);
	# NB: if weekday check succeeds, it occludes any monthday match
	return 0;

# Used in boolean testing, Class is one of these attributes:
# 
#     dev | stg | prd | loc	- overall class returned by "get" (loc=local)
#      (default is 'loc' if cannot be devined from string embedded in hostname)
#     pfxpull			- prefixes pulled in and tested
#     backup			- backups performed (eg, live data)
#     fulltest			- full testing performed (eg, live data)
#     rslvrcheck			- regular resolver check performed
#     patch_{mon,tue,wed,thu,fri} - day on which OS patching occurs
}

# yyy want mkid to be soft if exists, like open WRITE|CREAT
#  yyy and rlog it

sub mkid { }

# MUCH FASTER way to query mongo for existence
# https://blog.serverdensity.com/checking-if-a-document-exists-mongodb-slow-findone-vs-find/

sub egg_exists { my( $bh, $mods, $id, $elem )=@_;

	my $db = $bh->{db};
	my $opt = $bh->{opt};
	my $om = $bh->{om};
	my $sh = $bh->{sh};

	defined($id) or
		addmsg($bh, "no identifier name given"),
		return undef;

	my $defelem = defined $elem;		# since it might match /^0+/
	my ($erfs, $irfs);	# ready-for-storage versions of id, elem, ...
	$sh->{exdb} and
		$erfs = $defelem ? flex_enc_exdb($id, $elem)
			: flex_enc_exdb($id);
	$sh->{indb} and
		$irfs = $defelem ? flex_enc_indb($id, $elem)
			: flex_enc_indb($id);

	my ($exists, $key, @dups);
	if ($defelem) {		# does element exist?
		# xxx are there situations (eg, from_rawidtree that
		#     should prevent us calling this?
		EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id, $elem) or
			addmsg($bh, "instantiate failed from exists"),
			return undef;
		if ($sh->{exdb}) {
			@dups = exdb_get_dup($bh, $erfs->{id},
					$erfs->{elem});
			$exists = scalar(@dups);
		}
		if ($sh->{indb}) {		# yyy if ie, i answer wins
			$key = $irfs->{key};		# only need encoded key
			$exists = defined( $bh->{tied_hash_ref}->{$key} )
					? 1 : 0;
		}
	}
	else {			# does id exist?
		# xxx are there situations (eg, from_rawidtree that
		#     should prevent us calling this?
		EggNog::Cmdline::instantiate($bh, $mods->{hx}, $id) or
			addmsg($bh, "instantiate failed from exists no elem"),
			return undef;
		if ($sh->{exdb}) {
			my $rech = exdb_get_id($bh, $erfs->{id});
			$exists = scalar(%$rech) ? 1 : 0;
		}
		if ($sh->{indb}) {		# yyy if ie, i answer wins
			$key = $irfs->{key};		# only need encoded key
			$exists = defined( $bh->{tied_hash_ref}->{$key
					. PERMS_ELEM} )
				? 1 : 0;
		}
	# xxxx need policy on protocol-breaking deletions, eg, to permkey
	}

	my $st = $om->elem("exists", $exists);
	# XXX this om return status is being ignored

	return 1;
}

# yyy purge bug? why does the @- arg get ignored (eg, doesn't eat up the
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
# yyy bring this in line with other authz sections! (or delete)
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

	# Set "all" flag so we act even on admin elements, eg, get_rawidtree().
	#
	$mods->{all} = 1;			# xxx downstream side-effects?

	my $num_elems;
	my $retval = 1;
	if ($sh->{exdb}) {

		my $erfs = flex_enc_exdb($id);		# ready-for-storage id
		my $msg;
		my $ok = try {
			my $coll = $bh->{sh}->{exdb}->{binder};	# collection

			# In delete_many, "many" refers to records/docs,
			# but with our uniqueness constraint, delete_one
			# should be sufficient yyy right?
			# yyy deleting everything as if $mods->{all} = 1;

			my $rech = $coll->find_one(
				{ $PKEY => $erfs->{id} },	# query clause
			)
			// {};

			# Count elements and dupes except the $PKEY element,
			# which we never count. If we found a record for it
			# (non-empty hash), we know it's there, so we can
			# pre-subtact 1 instead of bothering to test for it.

			$num_elems = %$rech ? -1 : 0;
			my $elval;			# element's value
			while ((undef, $elval) = each %$rech) {
				$num_elems += ref($elval) eq 'ARRAY' ?
					scalar(@$elval)	# number of dupes
					: 1;		# just one element
			}
			# Could do delete_many, but we assume uniqueness
			# constraint on $PKEY is enforced already.

			$retval = $coll->delete_one(
				{ $PKEY => $erfs->{id} },	# query clause
			)
			// 0;		# 0 != undefined
		}
		catch {
			$msg = "error deleting id \"$id\" from "
				. "external database: $_";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and 	# test undefined since zero is ok
			addmsg($bh, $msg);	# just report, don't abort
			#return undef;
		bcount($bh, -$num_elems);	# updates bindings_count
	}

	if ($sh->{indb}) {

		# NB: arg3 undef means don't output results; instead we're
		# generating a list of elements that we'll later delete
		# individually.  We're calling this with UNencoded $id.

		get_rawidtree($bh, $mods, undef, \@elems, undef, $id) or
			addmsg($bh, "rawidtree returned undef"),
			return undef;
		$num_elems = scalar(@elems);

		my $msg;	# NB: no rlog for exdb case
		$msg = $bh->{rlog}->out("C: $id.$lcmd") and
			addmsg($bh, $msg),
			return undef;

		# Give '' instead of $lcmd so that egg_del won't create multiple
		# log events (for each element), as we just logged one 'purge'.

		my $delst;			# delete status
		my $prev_elem = "";	# init to something unlikely
		for my $elem (@elems) {
			# previous element dupes deleted by egg_del already
			$elem eq $prev_elem and
				next;	# so skip another call to avoid error
			$retval &&= (
				# calling with UNencoded $id and $elem
				$delst = egg_del($bh, $mods, '', $formal,
					$id, $elem), 
				($delst or outmsg($bh)),
			$delst ? 1 : 0);
		}
	}

	my $out_id;			# output ready form
	$out_id = flex_dec_for_display($id);
	$om and ($retval = $om->elem('elems',		# print comment
		" admin + user elements found to purge under $out_id: "
			. $num_elems, "1#"));

	tlogger $sh, $txnid, "END SUCCESS $id.$lcmd";

	#return $retval;	# yyy should we check $retval for return?
	return 1;		# what the heck do we return, from which case?
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
#					{ $PKEY	=> $id },
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
			{ $PKEY => $id },	# query
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
#say(STDERR "xxx notok result=$result, id=$id, elem=$elem"),
		return ();
#say STDERR "xxx ok result=$result, id=$id, elem=$elem";
	my $ref = ref $result->{$elem};
	$ref eq 'ARRAY' and		# already is array ref, so return array
		return @{ $result->{$elem} };
	$ref ne '' and
		addmsg($bh, "unexpected element reference type: $ref"),
		return undef;
	return ( $result->{$elem} );	# make array from scalar and return it
}

sub exdb_get_id { my( $bh, $id )=@_;
	# yyy shares much code with previous sub -- collapse to one sub?

	# yyy not error checking the args
	my ($result, $msg);
	my $ok = try {				# exdb_get_dup
		my $coll = $bh->{sh}->{exdb}->{binder};	# collection
		$result = $coll->find_one(
			{ $PKEY => $id },	# query
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
	$result or		# if nothing found, return empty hash
		return {};
# xxx should just return scalar
		#return ();
	return $result;
	#return ( $result );	# make array from scalar and return it
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
##				{ $PKEY => $id },	# query
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
# Return array of dupes for $key in list context
#     in scalar context return the number of dupes
# Assumes $key is ready for storage

# XXXXXXXXXXXXXXXX CHANGE this signature to match exdb_get_dup
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

# Assumes $id and $elem are already encoded "rfs"

sub indb_del_dup { my( $bh, $id, $elem )=@_;

	my $instatus = 0;	# indb status; default is success
	my $db = $bh->{db};

	# xxx check that $elem is non-empty?
	my $key = "$id$Se$elem";
	$instatus = $db->db_del($key);
	$instatus != 0 and addmsg($bh,
		# xxx these should be displaying UNencoded $id and $elem
		"problem deleting elem \"$elem\" under id \"$id\" " .
			"from internal database: $@");
		#return undef;
	$instatus != 0 and
		return -1;
	return 0;
}

# yyy currently returns 0 on success (mimicking BDB-school return)
# xxx this is called only once, so we can easily split it into two;
#     {ex,in}db_del_dup and pass in appropriatedly flex_encoded args

# yyy NB: inconsistency: unlike exdb_set_dup, we don't call bcount()
#     from within exdb_del_dup; instead it's the caller's responsibility.
#     -> consider making these two routines more consistent

# Assumes $id and $elem are already encoded "rfs"
# An empty $id or $elem should generate exdb exception.
# yyy Caller is responsible for updating bindings_count

sub exdb_del_dup { my( $bh, $id, $elem )=@_;

	my $result = 1;		# default is success

	# XXX binder belongs in $bh, NOT to $sh!
	my $coll = $bh->{sh}->{exdb}->{binder};	# collection
	my $msg;
	my $ok = try {
		$result = $coll->update_one(
			{ $PKEY		=> $id },
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
	! $result and
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
			: exdb_get_dup($bh, $erfs->{id}, $erfs->{elem})
			#: exdb_get_dup($bh, $erfs->{id}, $erfs->{elems}->[0])
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
# xxx exdb fix next line?
			: -1		# xxx always delete?
		;
	}
	# xxx dropping this for now
	# XXXX is this the right message/behavior?
	#sif($bh, $elem, $oldvalcnt) or		# check "succeed if" option
	#	addmsg($bh, "proceed test failed"),
	#	return undef;

	dblock();	# no-op

	# Somehow we decided that rm/delete operations should succeed
	# after this point even if there's nothing to delete. Maybe
	# that's because our indb doesn't throw an exception in that case.
	# But with support of exdb, we no longer try to delete a non-existent
	# value because our exdb _would_ throw an exception. (true? yyy)

	my $status = 0;		# default is success
	my ($emsg, $imsg);

	#$oldvalcnt and		# if there's at least one (even -1) value
	#	$status = egg_del_dup($bh, $id, $elem);		# then delete

	# if there's at least one (even -1) value, then delete
	if ($oldvalcnt and $erfs) { 
		#$status = exdb_del_dup($bh, $erfs->{id}, $erfs->{elems}->[0]);
		$status = exdb_del_dup($bh, $erfs->{id}, $erfs->{elem});
		$emsg = ($status != 0				# error
			? "couldn't remove key ($erfs->{key}) ($status)"
			: '');
		$emsg and 
			addmsg($bh, $emsg);
	}
	if ($oldvalcnt and $irfs) { 
		#$status = indb_del_dup($bh, $irfs->{id}, $irfs->{elems}->[0]);
		$status = indb_del_dup($bh, $irfs->{id}, $irfs->{elem});
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
		# Note that if a problem shows up and you fix it, you won't
		# likely enjoy the results until you recreate the binder
		# to re-initialise the bindings_count.

		$irfs and
			arith_with_dups($dbh, "$A/bindings_count", -$oldvalcnt),
			($dbh->{"$A/bindings_count"} < 0 and addmsg($bh,
				"bindings count went negative on $irfs->{key}"),
				return undef);
		$erfs and
			bcount($bh, -$oldvalcnt) || (addmsg($bh,
				"bindings count update failed on $erfs->{key}"),
				return undef);
	}
#{ my @dups = exdb_get_dup($bh, $BSTATS->{id}, $BSTATS->{elem});
#say "xxx del bindings=", $dups[0]; }

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

	my $omstatus = $om->elem("ok", ($oldvalcnt == 1 ?
		# XXX need way to DISPLAY id + elem, and this next looks like a
		#     mistake but it's not
		#"element removed: $key" :
		"element removed: $id$So$elem" :
		($status == 1 ? "element doesn't exist" :
			"$oldvalcnt elements removed: $id$So$elem")));
			#"$oldvalcnt elements removed: $key")));
	return 1;
}

# Check user-specified existence criteria.
# yyy hold back releasing this:
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

# yyy need flex_get() routine that 

# Circumflex-encode, internal db (indb) version.
# Return hash with ready-for-storage (efs) versions of
#   key		# for storage
#   id		# identifier
#   elems	# array: elem, subelem, subsubelem, ...
# For our use of BerkeleyDB, the characters to watch out for during
# storage are $Se (sub-element separator char, eg, | or \t) and ^ (circumflex)

sub flex_enc_indb { my ( $id, @elems )=@_;

	my $irfs = {};	# hash that we'll return with ready-for-storage stuff
	if ($id =~ m|^:idmap/(.+)|) {
		my $pattern = $1;	# note: we don't encode $pattern
# xxx wait, why not encode $pattern, then later decode?
#     xxx test
					# xxx document
		my $elem = $elems[0];
		$elem =~ s{ ([$Se^]) }{ sprintf("^%02x", ord($1)) }xeg;
		$irfs->{key} = "$A/idmap/$elem$Se$pattern";
		$irfs->{id} = $id;		# unprocessed
		$irfs->{elems} = [ $elem ];	# subelems not supported
		$irfs->{elem} = $elem;		# shortcut to first element
		return $irfs;
	}
	# if we get here we don't have an :idmap case

	$irfs->{key} =
		join $Se, grep
		s{ ([$Se^]) }{ sprintf("^%02x", ord($1)) }xoeg || 1,
		$id, @elems;
	$irfs->{id} = $id;		# modified
	$irfs->{elems} = \@elems;	# modified
	$irfs->{elem} = $elems[0];	# shortcut to first element
	return $irfs;
}

# Circumflex-encode, external db (exdb) version.
# Return hash with ready-for-storage (rfs) versions of
#   key		# for :idmap	xxx untested
#   id		# identifier
#   elems	# array: elem, subelem, subsubelem, ...
# For our use of MongoDB, the characters to watch out for during
# storage are $EXsc (special chars: '.', '^' and initial '$')

sub flex_enc_exdb { my ( $id, @elems )=@_;

	my $erfs = {};	# hash that we'll return with ready-for-storage stuff
	if ($id =~ m|^:idmap/(.+)|) {
		# form: :idmap/pattern, where pattern becomes element name
		my $pattern = $1;	# note: we don't encode $pattern
					# xxx document
		$pattern =~ s{ $EXsc }{ sprintf("^%02x", ord($1)) }xeg;
		$erfs->{id} = "$A/idmap/$elems[0]";
		$erfs->{id} =~ s{ $EXsc }{ sprintf("^%02x", ord($1)) }xeg;

		#$erfs->{key} = "$A/idmap/$elem$Se$pattern";
		$erfs->{key} = '';		# yyy undefined really
		#$erfs->{id} = $id;		# unprocessed
		$erfs->{elems} = [ $pattern ];	# subelems not supported
		$erfs->{elem} = $pattern;	# shortcut to first element
		return $erfs;
	}
	# if we get here we don't have an :idmap case

	$erfs->{key} =
		join $Se, grep
		s{ $EXsc }{ sprintf("^%02x", ord($1)) }xoeg || 1,
		$id, @elems;
	$erfs->{id} = $id;		# modified by grep
	$erfs->{elems} = \@elems;	# modified by grep
	$erfs->{elem} = $elems[0];	# shortcut to first element
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
# a circumflex-decoded string suitable for human display _and_ for
# doing handing to scripts (eg, to support inflections) that expect
# un-encoded inputs (eg, 10.5072 encodes to 10^2e5072, but the scripts
# need to be given it in decoded form).
# Does not modify its argument.
#
sub flex_dec_for_display { my( $s )=@_;

	# yyy do a version that takes multiple args and inserts '|' between
	#     them suitable for calling with $id, $elem --> foo|bar
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
# yyy this is similar to how we'll put in :- and : element support!
# yyy transform other ids beginning with ":"?

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
# yyy temporary
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
# yyy how to distinguish shoulders: "__mtype: shoulder?
#        (__mtype: naan?) if #matches > 1, weird error
#
# NB: shoulder() not currently called by anyone

sub shoulder { my( $bh, $WeNeed, $id, $opd ) = ( shift, shift, shift, shift );

	# XXX yuck -- what a mess -- clean this up
	#	my $agid = $bh->{ruu}->{agentid};
	$bh->{rlog}->out(
		"D: shoulder WeNeed=$WeNeed, id=$id, opd=$opd, remote=" .
		  "$bh->{remote}, ruu_agentid=$bh->{ruu}->{agentid}, otherids="
		  . join(", " => @{$bh->{sh}->{ruu}->{otherids}}));

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

#use MongoDB;

# Called by egg_set.
# First arg example:  $bh->{sh}->{exdb}->{binder}, eg, egg.ezid_s_ezid

# This routine assumes $id and $elem args have been flex_encoded
# The goal of this routine is to construct a set of hashes to submit
# to $collection->update_one(). Here's an annotated example.
#
# {		# filter_doc to select what doc to update
#	$PKEY => $id,			# primary key
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
	my $no_bcount = $flags->{no_bcount} || 0;	# update bindings_count?
	my $optime = $flags->{optime} || time();	# for setting modtime
	my $delete = $flags->{delete} || 0;		# delete old val first?
	my $polite = $flags->{polite} || 0;		# noclobber?
	my $init = 0;

	# NB: if this test is true, we assume a special case of init_id
	$elem eq PERMS_EL_EX and		# to force binding_count update
		($init, $delete) = (1, 1);	# and to delete old val
				
	#my ($result, $presult);		# current op and prior value
	my $result;
	#my ($oldvalR, $oldval);		# yyy unused
	my $fetch_oldval = 1;		# usually we find old val count first
	my $oldvalcnt = 0;
	my $coll = $bh->{sh}->{exdb}->{binder};		# collection

# xxx to do:
# rename $sh->{exdb} to $sh->{exdb_session}
#   move ebopen artifacts to $bh->{exdb}
# add: consider sorting on fetch to mimic indb behavior with btree
# yyy big opportunity to optimize assignment of a bunch of elements in
#     one batch (eg, from ezid).

	my $filter_doc = { $PKEY => $id };		# initialize
	my $upsert = 1;					# default
	if ($polite) {
		$filter_doc->{$elem} = { '$exists' => 0 };
		$upsert = 0;	# causes update to fail if $elem exists
	}

	my $update_doc = {};
	my $to_set = { CTIME_EL_EX() => $optime };	# initialize
	if ($delete) {				# eg, "set" overwrites
		$no_bcount and		# if we're not updating bindings_count,
			$fetch_oldval = 0;	# no need to first fetch oldval
#{ my @dups = exdb_get_dup($bh, $BSTATS->{id}, $BSTATS->{elem});
#say "xxx after init bindings=", $dups[0]; }
		$to_set->{$elem} = [ $val ];		# to be set
	}
	else {					# eg, "add" not "set"
		$fetch_oldval = 0;	# adding, so no need to fetch oldval
		$update_doc->{'$push'} = { $elem => $val };
	}
	$update_doc->{'$set'} = $to_set;
	my $msg;
	my $ok = try {
#say "xxx ELEM=$elem, fetch_oldval=$fetch_oldval, no_bcount=$no_bcount";
		if ($fetch_oldval) {	# so we can update bindings_count
			my $presult;
			$presult = $coll->find_one(
				{ $PKEY => $id },	# query
				{ $elem => 1 },		# projection
			)
			// 0;		# 0 != undefined
			#my $ref = $presult ? ref($presult->{$elem}) : undef;
			my $ref = $presult && defined($presult->{$elem})
				? ref($presult->{$elem})
				: undef;
			$ref && $ref eq 'ARRAY' and	# if there was an array
				#$oldvalR = $presult->{$elem},
				#$oldvalcnt = @$oldvalR,  # old bindings_count
				$oldvalcnt =		# old bindings_count
					scalar(@{ $presult->{$elem} }),
			1 or		# else if there was still some result
			#$presult and $ref and
			defined($ref) and
				#$oldval = $presult->{$elem},
#say("xxx presult->{$elem}=$presult->{$elem}, exists{$elem}=", exists($presult->{$elem}), ", defined=", defined($presult->{$elem})),
				$oldvalcnt = 1,		# old bindings_count=1
			;
			# yyy we're not currently using $oldval or $oldvalR
#say "xxx ref=$ref, elem=$elem, oldvalcnt=$oldvalcnt";
		}
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
	# if we get here, an update occurred

	$init and	# on init_id we set PERMS_EL_EX, plus CTIME_EL_EX
		bcount($bh, +2),	# as a side-effect, hence +2
	1 or
	! $no_bcount and	# if we're updating the bindings_count and not
		$oldvalcnt != 1 and	# swapping one-for-one (optimization)
			bcount($bh, 1 - $oldvalcnt),
#say("xxx bcount ELEM, oldvalcnt=$oldvalcnt"),
			;	# call to update
	return $result;		# yyy is this a good return status?

#use Data::Dumper "Dumper"; print Dumper $result;
#use Data::Dumper "Dumper"; print Dumper $bh;
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
			arith_with_dups($dbh, "$A/bindings_count", +2);
		$bh->{sh}->{exdb} and
			bcount($bh, +2);

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
#{ my @dups = exdb_get_dup($bh, $BSTATS->{id}, $BSTATS->{elem});
#say "xxx set bindings=", $dups[0]; }
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
	my $rfs = flex_enc_indb($id, $elem);
	my $key;
	#($key, $id, $elem) = ($rfs->{key}, $rfs->{id}, $rfs->{elems}->[0]);
	($key, $id, $elem) = ($rfs->{key}, $rfs->{id}, $rfs->{elem});

	! egg_authz_ok($bh, $id, OP_WRITE) and
		return undef;

	my $optime = time();

	# an id is "created" if need be
	#if (! egg_init_id($bh, $id, $optime))
	if (! egg_init_id($bh, $rfs->{id}, $optime)) {
		addmsg($bh, "error: could not initialize $id");
		return undef;
	}

	my $slvalue = $value;		# single-line log encoding of $value
	$slvalue =~ s/\n/%0a/g;		# xxxxx nasty, incomplete kludge
					# xxx note NOT encoding $elem

	# Not yet a real transaction in the usual sense, but
	# more of something that has a start and an end time.

	my $txnid;		# undefined until first call to tlogger
	$txnid = tlogger $sh, $txnid, "BEGIN $id$Se$elem.$lcmd $slvalue";

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

sub exdb_set { my( $bh, $mods, $lcmd, $delete, $polite,  $how,
						$incr_decr,
						$id, $elem, $value )=@_;

	# yyy consider merging this routine back into egg_set and leaving early
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
	if (! egg_init_id($bh, $rfs->{id}, $optime)) {
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

	# The main event.

	dblock();	# no-op

	# permit 'set' to overwrite dups, but don't permit 'let' unless
	#    there is no value set

	# NB: exdb_set_dup updates bindings_count by default

	if (! exdb_set_dup($bh, $rfs->{id}, $rfs->{elem}, $value, {
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
		#    $msg = $bh->{rlog}->out("C: $id$Se$elem.$lcmd $slvalue");
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

# This routine assumes it's been called with ready-for-storage $id.
# It creates/initializes an id. In the indb case (but NOT in the exdb case),
# it won't create an id if it already appears to have an $id_permkey.

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
#{ my @dups = exdb_get_dup($bh, $BSTATS->{id}, $BSTATS->{elem});
#say "xxx before init bindings=", $dups[0]; }
		@pkey = exdb_get_dup($bh, $id, PERMS_EL_EX);
		# bindings_count updated by exdb_get_dup
		scalar(@pkey) and		# it exists,
			return 1;		# so nothing to do
		# yyy do I need to flex_encode elem name & value?
		! exdb_set_dup($bh, $id, PERMS_EL_EX, $id_value, {
				optime => $optime, delete => 1 }) and
			return undef;
#{ my @dups = exdb_get_dup($bh, $BSTATS->{id}, $BSTATS->{elem});
#say "xxx after init bindings=", $dups[0]; }
	}
	return 1;
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

sub exdb_count { my( $bh )=@_;
	my ($count, $coll, $msg);
	my $ok = try {
		$coll = $bh->{sh}->{exdb}->{binder};	# collection
		$count = $coll->count();
	}
	catch {
		$count = "error in estimated_document_count for \"$coll\: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and 	# test undefined since zero is ok
		addmsg($bh, $count);
	return $count;
}

sub mstat { my( $bh, $mods, $om, $cmdr, $level )=@_;

	$om ||= $bh->{om};
	my $hname = $bh->{humname};		# name as humans know it
	$level ||= "brief";

	my $sh = $bh->{sh};
	if ($sh->{exdb}) {

		my ($mtime, $size, @dups);
		if ($level eq "brief") {

			#$om->elem("External binder", $sh->{exdb}->{exdbname});
			$om->elem("External binder", $bh->{exdbname});
			my $count = exdb_count($bh);
			$count //= "error in fetching document count";
			$om->elem("record count", $count);
			my @dups = exdb_get_dup($bh,
				$BSTATS->{id}, $BSTATS->{elem});
			$om->elem("bindings", $dups[0]);
		}
		return 1;
	}
	my $db = $bh->{db};
	my $dbh = $bh->{tied_hash_ref};
	my ($mtime, $size);

	if ($level eq "brief") {
		$om->elem("binder", $bh->{minder_file_name});
		(undef,undef,undef,undef,undef,undef,undef,
			$size, undef, $mtime, undef,undef,undef) =
					stat($bh->{minder_file_name});
		$om->elem("modified", etemper($mtime));
		$om->elem("size in octets", $size);
		# xxx next ok?
		#$om->elem("binder", which_minder($cmdr, $bh->{minderpath}));
		#$om->elem("status", minder_status($dbh));
		$om->elem("bindings", $dbh->{"$A/bindings_count"});
	}
	return 1;
}

# yyy bind list [pattern]
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

# Read ids one per line from STDIN. For each id, fetch all elements and print
# a block dump in hex format. If no elements, indicate with special block.

sub iddump { my( $bh, $mods )=@_;

	my $om = $bh->{om_formal};
	my ($id, $rfs, $elemsR, $valsR);
	my $errcnt = 0;
	while (<STDIN>) {
		chop;
		if (! $bh->{sh}->{fetch_exdb}) { # yyy no exdb, only indb case
			! dumphexid($bh, $mods, $_) and
				outmsg($bh),	# XXX use stderr
				initmsg($bh),
				$errcnt++,
				return 1;
		}
	}
	$errcnt > 0 and
		return 0;
	return 1;
}

sub dumphexid { my( $bh, $mods, $id )=@_;

	my ($elemsR, $valsR) = ([], []);
	my $hexid;
	($hexid = $id) =~ s{(.)}{sprintf("%02x", ord($1))}eg;

	say("# id: $id");	# yyy ignoring print/say error status throughout
	say("# hexid: $hexid");

	my $rfs = flex_enc_indb($id);	# for get_rawidtree fetch of
	$mods->{all} = 1;		# all, including admin elements
	! get_rawidtree($bh, $mods,
		undef,		# here OM arg undefined because
		$elemsR,	# here want elem names returned
		$valsR,		# and here want values returned
			$rfs->{id}) and
		return 0;

	my ($elem, $val, $hexelem, $hexval);
	my $ecnt = 0;		# element count
	foreach (@$elemsR) {	# for each element name ($_)
		$ecnt++;

		# some found raw element name encodings need to be decoded
		$hexelem = flex_dec_for_display($_);	# initialize elem name
		$hexval = shift @$valsR;		# corresponding value
		$hexelem =~ s{(.)}{sprintf("%02x", ord($1))}eg;	# hexify
		$hexval =~ s{(.)}{sprintf("%02x", ord($1))}eg;	# hexify

		say("$hexelem: $hexval");
	}
	say("# elements bound under $id: $ecnt");
	say("");		# block/paragraph separator
}

# Read id dump blocks from STDIN. For each id, purge it, and if there are
# accompanying elements, add them. If there are no such elements, the id is
# considered to have been purged. This kind of input is deemed sufficient to
# bring this binder, wrt to this input, into alignment with another binder.
#
# Even though id creation date will be initialized as of moment of calling,
# loading a complete dump will overwrite creation/mod date with old time.
# To get duplicates correct, we insert elements with "add", not "set".

sub idload { my( $bh, $mods )=@_;

	# Read input one "paragraph" block at a time.
	# Process blocks that look like this example (from i.set a b)
	#
	#   # id: i
	#   # hexid: 69
	#   5f2e6563: 31343931373533323037
	#   5f2e6570: 703a7c7c3736
	#   61: 62
	#   # elements bound under i: 3
	#
	# A block starts with \n# id: <id>
	# A block ends with \n# elements bound under <id>: <numelems>
	# When <numelems> is zero, that means simple purge, else
	# it means we purge and then set all elements given.
	# The hexid line gives the hex version of the id to set.
	# The remaining lines give the hex elements and values to set.
	# 
	# XXX ? All ids, element names, and values are raw? and ready for
	# storage encoding?  VERIFY rationale

	my $formal = 1;			# ? needed?
	my ($lcnt, $ecnt) = (0, 0);	# line count and element count
	my ($displayid, $hexid);	# encoded in one way or another
	my ($id, $elem, $val);		# unencoded
	my $numelems;			# number of elements expected
	my $errcnt = 0;
	local $/ = '';			# read input in paragraph mode
	while (<STDIN>) {		# read each line from input
		$lcnt++;
		if (! s/^# id: (.*)\n# hexid: (.*)\n//) {
			say STDERR "ERROR: malformed preamble in " .
				"record starting on line $lcnt";
			$lcnt += (tr/\n// - 1);
			$_ = '';
			next;
		}
		($displayid, $hexid) = ($1, $2);
		$lcnt += 2;		# because we removed 2 lines

		if (! s/# elements bound under.*: (\d+)\n\n$//) {
			say STDERR "ERROR: malformed footer in " .
				"record starting on line $lcnt";
			$lcnt += (tr/\n// - 1);
			$_ = '';
			next;
		}
		$numelems = $1;		# number of elements expected
		$lcnt += 2;		# because we removed 2 lines

		if ($numelems == 0 and m/./) {	# if purge but elems given
			say STDERR "ERROR: elem count 0 but elements exist " .
				"in record starting on line $lcnt";
			$lcnt += (tr/\n// - 1);
			$_ = '';
			next;
		}

		say "XXX displayid=$displayid; hexid=$hexid, numelems expected=$numelems";
		($id = $hexid) =~ s/([[:xdigit:]]{2})/chr hex $1/eg;

# XXX create tests that reflect changes in binder1 to binder2
# XXX back to iddump: re-implement it by calling get_rawidtree directly,
#          and as module-level code
		! egg_purge($bh, $mods, "purge", $formal, $id) and
			outmsg($bh),
			initmsg($bh),		#  clear error messages
			$errcnt++;

#
# XXX can I turn a linux1 binder readonly during DNS transition
#     when some clients will still have old ip addr?
# XXX what about Linux1 OCA minter? can I make it readonly? should I
#     artificially advance that minter (since can't pause it)?

		# For dupes, use "add" not "set"; ok since we did purge first.
		# If we were doing bulk commands, we might encode like this
		#      @.add @ @
		#      $id
		#      $elem
		#      $val

		$ecnt = 0;
		while ($ecnt < $numelems) {	# process one line at a time
			if (! s/^([[:xdigit:]]*): ([[:xdigit:]]*)\n//) {
				say STDERR "ERROR: malformed element in " .
					"record starting on line $lcnt";
				$lcnt += (tr/\n// - 1);
				$_ = '';
			}
			($elem, $val) = ($1, $2);
			$elem =~ s/([[:xdigit:]]{2})/chr hex $1/eg;
			$val  =~ s/([[:xdigit:]]{2})/chr hex $1/eg;
			! egg_set($bh, $mods, 'add', 0, 0,
					EggNog::Egg::HOW_ADD,
					$id, $elem, $val) and
				outmsg($bh),
				initmsg($bh),		#  clear error messages
				$errcnt++;
			$ecnt++;
			$lcnt++;
		}
		if ($ecnt != $numelems) {
			say STDERR "ERROR: elem count expected ($numelems) " .
				"different from number of elements found in " .
				"record starting on line $lcnt";
			$lcnt += (tr/\n// - 1);
			$_ = '';
			next;
		}
	}
	$errcnt > 0 and
		outmsg($bh, "Error count is $errcnt"),
		return 1;

	return 0;
}

# yyy dbsave and dbload built for the old DB_File.pm environment
# yyy should probably be updated for BerkeleyDB.pm and MongoDB.pm

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

# yyy dbsave and dbload built for the old DB_File.pm environment
# yyy should probably be updated for BerkeleyDB.pm and MongoDB.pm

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
# yyy maybe delete these?

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

# marks txnlog, eg, just before converting a live database, so that
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

sub egg_pr { my( $bh, $mods )=( shift, shift );
	# remaining args are concatenated

	# yyy before processing $() and ${}, must warn Greg!
	my $om = $bh->{om};
	return $om->elem('', join( ' ' => @_ ));
}

# yyy deprecated
#
# Strict protocol for id modification.
# yyy protocol: before setting _anything_ extending id, check id|__mp
#   if you don't find it (even as ! remote), set it now!
#     -- but how do you know you have permission on that shoulder?
#     yyy to do: lookup shoulder permissions:  find a proper substring
#   if you do find it, see if you have permission
#   if changing permissions, remember to delete dupes first!
# 
# yyy retrieve top_level __mp just once and cache in $bh, right?
#
# yyy add this protocol to egg_del
# yyy need a better way than WeAreOnWeb to mean "non-admin mode"
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
# XXX authy not currently called by anyone

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
	my $xerc = EggNog::Egg::egg_fetch($bh,
		undef, $som, undef, \@vals, $id, @elems);
	$bh->{cite} = undef;	# total kludge to get title quotes
	# XXX need one of these for HTML?
	my $citation = join(", ", @vals);
	# see, eg, http://datashare.ucsf.edu/dvn/dv/CIND/faces/study/StudyPage.xhtml?globalId=hdl:TEST/10011&studyListingIndex=6_b75aa0d196115a2b53fa22df13c6

	# xxx kludgy to call print directly instead of OM?
	print "# Please cite as\n#  $citation\n\n";
	my $erc = EggNog::Egg::egg_fetch($bh,
		undef, $bh->{om}, undef, undef, $id, @elems);
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

sub pop_meta { my ( $h )=( shift );	# remaining args are keys
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

sub format_metablob { my( $rawblob, $h, $om, $profile, $target )=@_;

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
# Assumes $id ($rid actually) is NOT already encoded ready for storage.

sub egg_inflect { my ( $bh, $mods, $om, $id )=@_;

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

	my $rfs;
	if ($bh->{sh}->{fetch_exdb}) {
		$rfs = flex_enc_exdb($id);	# flex_encode for exdb_get_id
		my $rech = exdb_get_id($bh, $id);	# record hash
		scalar(%$rech) or
			return ('', '');	# nothing found

		# Go through all elements in $rech, creating parallel lists
		# of element names and values, and otherwise no output.

		my $all = $mods->{all} // $bh->{opt}->{all} // '';
		my $skipregex = '';
		my $spat = '';
		if (! $all) {	# case 1: skip usual support elements
			$spat = SUPPORT_ELEMS_RE;
			$skipregex = qr/^$spat/o;
		}
		while (my ($k, $v) = each %$rech) {
			$skipregex and $k =~ $skipregex and
				next;
			$k eq $PKEY and		# yyy peculiar to mongo
				next;
			push @$elemsR, $k;
			push @$valsR, $v;
		}
	}
	else {
		#my $rawblob = get_rawidtree($bh, $mods,...)
		$rfs = flex_enc_indb($id);	# flex_encode for get_rawidtree
		get_rawidtree($bh, $mods,
			undef,		# here OM arg undefined because
			$elemsR,	# here we want element names returned
			$valsR,		# and here we want values returned
				$rfs->{id}) or
				#$id) or
			return '';
	}

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
# once  my $parser = XML::LibXML->new();
#
# once  my $style_doc = $parser->parse_file('bar.xsl');
# once  my $xslt = XML::LibXSLT->new();
# once  my $stylesheet = $xslt->parse_stylesheet($style_doc);

# MANY  my $source = $parser->parse_file('foo.xml');
# MANY  my $results = $stylesheet->transform($source);
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

# returns triple: number of elements, accumulated status, and string (if any)

sub elems_output { my( $om, $key, $val )=@_;

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
	#return $st;
	return (scalar(@vals), $st, $s);
}

# ? get/fetch [-r] ... gets values?
# ? getm/fetchm [-r] ... gets names minus values?
# ? getm/fetchm [-r] ... gets metadata elements (not files)?

# --format (-m) tells whether we want labels
# -r tells whether we recurse
# yyy do we need to be able to "get/fetch" with a discriminant,
#     eg, for smart multiple resolution??

#our @suffixable = ('_t');		# elems for which we call suffix_pass

# yyy can we use suffix chopback to support titles that partially match?
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

	# we may have been called by user from egg, with or w.o. an element,
	# or been called by get_rawidtree() with a specific element

	if ($#elems < 0 and $om) {	# process and return (no fall through)
	
		# We're here because no elems were specified, so find them.
		# and don't bother if no ($om) output

		# NB: if we're here, we weren't called by get_rawidtree,
		# since it would have called us with a specific element.

		$txnid = tlogger $sh, $txnid, "BEGIN $lcmd $id";

		if ($sh->{fetch_exdb}) {	# if EGG_DBIE is e or ei

			my $rfs = flex_enc_exdb($id, @elems);	# yyy no @elems

			# yyy similar to calling get_rawidtree
			my $result;
			# yyy binder belongs in $bh, NOT to $sh!
			#     see ebopen()
			my $coll = $bh->{sh}->{exdb}->{binder};	# collection
			my $msg;
			my $ok = try {
				$result = $coll->find_one(
					{ $PKEY	=> $rfs->{id} },
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

			my $ast;	# accumulated status from elems_output
			my $ndups;		# number of dupes in an element
			my $nelems = 0;
			while (my ($k, $v) = each %$result) {
				$skipregex and $k =~ $skipregex and
					next;
				$k eq $PKEY and		# yyy peculiar to mongo
					next;
			#	$out_elem = $k ne '' ? $k : '""';
			#	$out_elem =~	# "flex_dec_exdb" as needed
			#		s/\^([[:xdigit:]]{2})/chr hex $1/eg;
			#	$s = $om->elem($out_elem, $v);
				#$s = elems_output($om, $k, $v);
				#($p && (($st &&= $s), 1) || ($st .= $s));
				# yyy GETHEX not implemented for exdb
				($ndups, $ast, $s) = elems_output($om, $k, $v);
				($p && (($st &&= $ast), 1) || ($st .= $s));
				$nelems += $ndups;
				#$nelems++;
			}

			$s = $om->elem('elems',		# print ending comment
				" elements bound under $out_id: $nelems", "1#");
			($p && (($st &&= $s), 1) || ($st .= $s));
			# yyy $st contains return value
			# xxx unused at the moment
		}
		# yyy isn't this an "else"?
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

	# If we get here, elements or element sets to fetch were specified.
	# yyy or $om was not defined -- what case is that good for?

	# XXX need to issue END before every error return below
	# xxx we're starting a bit late (so timing may look a little faster)
	#     but we get less noise from each recursive call
	# use UNencded $id and @elems
	$txnid = tlogger $sh, $txnid, "BEGIN $lcmd $id " . join('|', @elems);

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
#say STDERR "XXXXXXXXXX inside egg_fetch, dups0=$dups[0]";
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
#say STDERR "xxx om=$om, dups0=$dups[0]";
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
# yyy maybe we should have a special (faster) call just to get names
#
# NB: input id and element names are already encoded ready-for-storage,
# (eg, | and ^), which means (a) beware not to encode them again and
# (b) you will probably want to decode before output.
#
# Note: this routine outputs via $om, as a side-effect, unless you
# arrange not to (eg, egg_purge() calls it and processes the returns).
# yyy This is perhaps strange -- maybe egg_del() should be called from
#     get_rawidtree.

# NB: this routine is very indb-specific, which may be ok given that we may
#     never need it for exdb-specific work (eg, for mongodb we fetch or
#     purge all elements with mongodb calls).

sub get_rawidtree { my(   $bh, $mods,   $om, $elemsR, $valsR,   $id )=@_;

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

	my $gethex = $bh->{GETHEX};	# yyy big kludge, set by "egg gethex"

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
	defined($gethex) and		# overridden by gethex, meaning a
		$all = 1;		# hex dump of the whole record
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
	if ($gethex and $om) {
		my $hexid = $id;
		$hexid =~ s{(.)}{sprintf("%02x", ord($1))}seg;
		($s = $om->elem('hexid', " hexid: " . $hexid, "2#")),
		($p && (($st &&= $s), 1) || ($st .= $s));
	}
 
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

			$out_elem = flex_dec_for_display($elem);
			#$out_elem = $elem ne '' ? $elem : '""';
			#$out_elem =~		# "flex_dec_indb" as needed
			#	s/\^([[:xdigit:]]{2})/chr hex $1/eg;

			# If $om is defined, do some output now.
			if ($gethex and $om) {
				my $hexelem = $out_elem;
				my $hexval = $value;
				$hexelem =~ s{(.)}{sprintf("%02x", ord($1))}seg;
				$hexval =~ s{(.)}{sprintf("%02x", ord($1))}seg;
				($s = $om->elem($hexelem, $hexval)),
				($p && (($st &&= $s), 1) || ($st .= $s));
			}
			elsif ($om) {
				($s = $om->elem(
				$out_elem,
				#($elem ne '' ? $elem : '""'),
				#($key =~ /^[^|]*\|(.*)/ ? $1 : $key),
				$value)),
				($p && (($st &&= $s), 1) || ($st .= $s));
			}

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

1;

__END__

=head1 NAME

Egg - routines to bind and resolve identifier data

=head1 SYNOPSIS

 use EggNog::Egg;		    # import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2020 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<dbopen(3)>, L<perl(1)>, L<http://www.cdlib.org/inside/diglib/ark/>

=head1 AUTHOR

John A. Kunze

=cut
