package EggNog::Binder;

=for dbnotes

	// Embedded DB (BDB or DB_File)
	Binder existence test is based on filesystem paths
	No server startup to worry about.

	// Server DB (eg, MongoDB or MySQL)
	Binder existence test is based on what:  on a test of shared server
	  database namespace?
	Does a user have a flat or hierarchical namespace per server?
	Should a server namespace be complemented by a filesystem stub minder,
	  eg, so that the filesystem can be explored to learn about databases?
	What if no server running when client starts: start server on demand?
	  Run a per-client server writing to a filesystem path similar to
	  Embedded case?  

=cut

# XXX XXX need to add authz to noid!

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	addmsg outmsg getmsg hasmsg initmsg
	authz unauthmsg badauthmsg
	human_num
	OP_READ OP_WRITE OP_EXTEND OP_TAKE OP_CREATE OP_DELETE
	SUPPORT_ELEMS_RE CTIME_ELEM CTIME_EL_EX PERMS_ELEM PERMS_EL_EX
	BIND_KEYVAL BIND_PLAYLOG BIND_RINDEX BIND_PAIRTREE
	prep_default_binder gen_minder createbinder rmbinder cast
	bopen bclose ibopen omclose
	bshow mstatus fiso_erc
	open_resolverlist
	$A $v1bdb $v1bdb_dup_warning
	get_dbversion rrminfo RRMINFOARK
	exists_in_path which_minder minder_status
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Value ":all";
use File::Copy 'mv';
use File::Path qw( make_path mkpath rmtree );
use File::Pairtree ":all";	# barely used, could drop easily yyy
use File::Namaste;
use File::Find;
use EggNog::Rlog;
use EggNog::RUU;
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;
use File::Basename;
use EggNog::Session;

# names of some filesystem artifacts
use constant FS_OBJECT_TYPE	=> 'egg';	# a Namaste object type
use constant FS_DB_NAME		=> 'egg.bdb';	# database filename

# These next three are really constants, but Perl constants are a pain.

our $EGGBRAND = EggNog::Session::EXDB_DBPREFIX . '_';
#our $EGGBRAND = 'egg_';
our $DEFAULT_BINDER    = 'binder1';	# user's binder name default
#our $DEFAULT_BINDER_RE = qr/^egg_.*\..*_s_\Q$DEFAULT_BINDER\E$/o;
our $DEFAULT_BINDER_RE = qr/^$EGGBRAND.*\..*_s_\Q$DEFAULT_BINDER\E$/o;
					# eg, egg_default.jak_s_binder1
our $EGG_DB_CREATE	= 1;

# xxx document
# Here's how our hierarchical mongodb namespaces are structured.
# A record/document corresponds to an identifier.
# A table/collection corresponds to a binder.
# Eggnog users aren't aware of binder names, but Eggnog admin users should know:
#   An admin user's binder has a short name, as in "egg mkbinder mystuff".
#   The full name of an eggnog binder, as stored in mongodb, looks like
#
#       egg_bgdflt.jak_s_mystuff
#
#   which breaks down into <database>.<collection>, where
#
#       egg_     begins mongodb databases for eggnog
#       bgdflt   is the default "binder group"
#       jak      is the admin user/owner of the binder (from Unix creds)
#       _s_      separates the user name from their binder name
#       mystuff  is user jak's chosen "binder name" (default binder1)

our %o;					# yyy global pairtree options

my $nogbdb = 'nog.bdb';		# used a couple places yyy mostly silly

#use constant LOCK_TIMEOUT	=>  5;			# seconds
use constant LOCK_TIMEOUT	=>  45;			# seconds

# minder {type} values
use constant ND_MINTER		=>  1;
use constant ND_BINDER		=>  2;
use constant ND_NABBER		=>  3;
use constant ND_COUNTER		=>  4;

# minder openness {open} values
use constant MDRO_CLOSED	=>  0;
use constant MDRO_OPENRDONLY	=>  1;
use constant MDRO_OPENRDWR	=>  2;

# XXXXXXX these top level "on_bind" actions should be in a egg.conf file?
use constant BIND_KEYVAL	=> 001;
use constant BIND_PLAYLOG	=> 002;
use constant BIND_RINDEX	=> 004;
use constant BIND_PAIRTREE	=> 010;
# yyy need top level "after_bind" actions (by daemon process)

# Max number of re-use by ibopen of an opened db before re-opening it
# - just a cautionary measure against leaks from overusing a connection
#
use constant MDR_PERSISTOMAX	=>  100;
our $PERSISTOMAX = MDR_PERSISTOMAX;

# We use a reserved "admin" prefix of $A for all administrative
# variables, so, "$A/oacounter" is ":/oacounter".
#
use constant ADMIN_PREFIX	=> ":";
our $A = ADMIN_PREFIX;

# This is sort of an "egg easter egg", a special reserved identifier that
# causes the resolver to return a fake target URL that divulges information
# about the resolver.
#
use constant RRMINFOARK		=> 'ark:/99999/__rrminfo__';

################

# yyy moving towards new new; just one arg: $sh
sub newnew { my( $sh )=@_;

	return EggNog::Binder->new (
		$sh, EggNog::Binder::ND_BINDER,
		$sh->{WeAreOnWeb}, $sh->{om}, $sh->{opt}
	);
}

# yyy get many args from $sh (eg, dbie)
sub new { # call with $sh, type, WeAreOnWeb, om, optref

	my $class = shift || '';	# XXX undefined depending on how called
	my $self = {};

	$class ||= "Nog";
	bless $self, $class;

	$self->{sh} = shift || '';	# session handler
	$self->{type} = shift || '';	# yyy ?good test for non-null to
					# determine if this object is defined
	$self->{WeAreOnWeb} = shift;
	defined( $self->{WeAreOnWeb} ) or	# yyy need a safe default, and
		$self->{WeAreOnWeb} = 1;	#     this is more restrictive
	$self->{remote} = $self->{WeAreOnWeb};	# one day from ssh also
	$self->{om} = shift || '';	# no $om means be quiet
	$self->{om_formal} = '';	# for 'fetch' (lazy init)
	$self->{timeout} = LOCK_TIMEOUT;	# max seconds to wait for lock
				# can be overridden after object creation
	$self->{opt} = shift || {};	# this should not be undef
	# yy this next line makes no sense and is overwritten later (good thing)
	#$self->{version} = $self->{opt}->{version};
	# yyy comment out undef's for better 'new' performance?

	$self->{minderpath} = $self->{sh}->{minderpath};
		# yyy temporary until we transition more fully to $sh
	$self->{minderhome} = $self->{sh}->{minderhome};
		# yyy temporary until we transition more fully to $sh

	$self->{fiso} = undef;		# yyy ?good test to see if obj open?
	initmsg($self);
	$self->{ug} = undef;		# transaction id generator
	$self->{log} = undef;
	$self->{top_p} = undef;		# top level permissions cache
	$self->{on_bind} =		# default actions to take on binding
		BIND_KEYVAL | BIND_PLAYLOG;	# xxx move to bind subsection?
	$self->{trashers} = "trash";		# eg, .minders/trash
	# xxx define caster location? now .minders/caster is hardwired
	$self->{MINDLOCK} = undef;
	$self->{side_minter} = "sd5";
	# XXXX do I need to undef each of those in DESTROY?

	# caching for performance
	$self->{last_need_authz} = 0;	# holds OP_WRITE, OP_EXTEND, etc.
	#$self->{last_id_authz} = undef;
	#$self->{last_shoulder_authz} = undef;

	# Start with unopened binder handler.
	$self->{open} = MDRO_CLOSED;
	$self->{open_count} = 0;
	$self->{ibopenargs} = "";	# crude signature to support persistomax
	$self->{persistomax} = $self->{opt}->{persistomax};	# by caller
	defined($self->{persistomax}) or
		$self->{persistomax} = MDR_PERSISTOMAX;

	$self->{dbgpr} = $self->{opt}->{dbgpr};	# defined (or not) by caller
	#$self->{om_msg} = $self->{opt}->{om_msg} || $self->{om};
	$self->{om_formal} = $self->{opt}->{om_formal} || $self->{om};

	# Some type-specific settings.  This might have been done with
	# heavier object-oriented artillery, but it didn't seem worth it.
	# xxx make all these single quoted strings for faster compilation
	#
	if ($self->{type} eq ND_MINTER) {
		$self->{default_minder} = "99999/df4";	# xxx portable?
		$self->{default_template} = "99999/df4{eedk}";	# xxx portable?
		$self->{evarname} = "NOG";
		$self->{cmdname} = "nog";
		$self->{objname} = "nog";
		$self->{dbname} = $nogbdb;
		$self->{humname} = "minter";
		$self->{version} ||= $EggNog::Nog::VERSION;

		$self->{fname_pfix} = 'nog_';	# used in making filenames
	}
	elsif ($self->{type} eq ND_BINDER) {
		#$self->{default_minder} = "binder1";
		$self->{default_minder} = $DEFAULT_BINDER;
		$self->{evarname} = "EGG";
		$self->{cmdname} = "egg";
		$self->{objname} = "egg";	# used in making filenames
		$self->{dbname} = "egg.bdb";
		$self->{humname} = "binder";
		$self->{version} ||= $EggNog::Egg::VERSION;

		# yyy should this egg_ be $EGGBRAND?
		$self->{fname_pfix} = 'egg_';	# used in making filenames
		$self->{edbdir} =		# embedded db directory
			$self->{fname_pfix} . 'edb';
		$self->{edbfile} =		# embedded db filename
			catfile( $self->{edbdir}, 'edb' );
		$self->{sdbdir} =		# server db directory
			$self->{fname_pfix} . 'data';
		$self->{sdbfile} =		# server db filename
			catfile( $self->{sdbdir}, 'sdb' );
		# to remove after replication implemented: egg.rlog 
		# no more need for: rrm.rlog egg.log

# 0=egg_1.00              egg.lock                pairtree_root/
# 0=pairtree_1.02         egg.log                 rrm.rlog
# egg.README              egg.rlog                
# egg.bdb                 egg_default.conf
	}
	elsif ($self->{type} eq ND_COUNTER) {
		$self->{default_minder} = "counter1";
		$self->{evarname} = "NOG";
		$self->{cmdname} = "nog";
		$self->{objname} = "counter";
		$self->{dbname} = "counter.anvl";
		$self->{humname} = "counter";
	}
	elsif ($self->{type} eq ND_NABBER) {
		$self->{default_minder} = "nabber1";
		$self->{evarname} = "NOG";
		$self->{cmdname} = "nog";
		$self->{objname} = "nabber";
		$self->{dbname} = "nabber.anvl";
		$self->{humname} = "nabber";
		$self->{version} ||= $EggNog::Nog::VERSION;
	}
	else {	# yyy ???
		$self->{default_minder} =
		$self->{evarname} =
		$self->{cmdname} =
		$self->{objname} =
		$self->{dbname} = "minder_unknown";
		$self->{humname} = "minder";
		$self->{version} ||= $EggNog::Nog::VERSION;
	}

	return $self;

	#my $options = shift;
	#my ($key, $value);
	#$self->{$key} = $value
	#	while ($key, $value) = each %$options;
}

sub omclose { my( $bh )=@_;

	$bh->{db}			or return;	# yyy right test?
	$bh->{opt}->{verbose} and
		($bh->{om} and $bh->{om}->elem("note",
			"closing binder handler: $bh->{fiso}"));
	defined($bh->{log})		and close $bh->{log};	# XXX delete
	undef $bh->{rlog};		# calls rlog's DESTROY method
	undef $bh->{db};
	undef $bh->{ruu};
	my $hash = $bh->{tied_hash_ref};
	untie %$hash;			# untie correctly follows undef
	$bh->{open} = MDRO_CLOSED;
	$bh->{open_count} = 0;
	# XXXXX test MINDLOCK!!
	defined($bh->{MINDLOCK})	and close($bh->{MINDLOCK});
	return;
}

# xxx document changes that object interface brings:
#     cleaner error, locking, and options handling
sub DESTROY {
	my $self = shift;
	#$self = "xxx";

	bclose($self);

# xxx former omclose($self) section
#	$self->{db}			or return;	# yyy right test?
#	# XXX $self->{opt}->{verbose} and log fact of closing
#	defined($self->{log})		and close $self->{log};
#	undef $self->{db};
#	my $hash = $self->{tied_hash_ref};
#	untie %$hash;			# untie correctly follows undef
#	# XXXXX test MINDLOCK!!
#	defined($self->{MINDLOCK})	and close($self->{MINDLOCK});
# xxx done omclose section

	$self->{opt}->{verbose} and
		# XXX ?
		#$om->elem("destroying binder handler: $self");
		print "destroying binder handler: $self\n";
	undef $self;
}

## Define binder and candidate binder
## returns ($bdr, $cbdr, $cbdr_from_d_flag, $err)
## always zeroes $cbdr_from_d_flag and always clobbers $cbdr, even on err
#sub def_bdr { my( $sh, $binder, $expected )=@_;
#
#	$expected ||= 0;	# default assumes we're making, not removing
#	# yyy check for $expected being non-negative integer?
#
#	my $err = 0;
#	# these two are returned for global side-effect (not because of this
#	#   subroutine, but by our own calling convention protocol -- dumb)
#	my $cmdr = fiso_dname($minder, $mh->{dbname});
#		# global side-effect when assigned to global upon return
#	my $cmdr_from_d_flag = 0;
#		# global side-effect when assigned to global upon return
#
## XXXXXXXXXX NOT
#	my @mdrs = EggNog::Minder::exists_in_path($cmdr, $mh->{minderpath});
#	my $n = scalar(@mdrs);
#
#	my $mdr = $n ? $mdrs[0] : "";			# global side-effect
#
#	# Generally $n will be 0 or 1.
#	$n == $expected and
#		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);	# normal
#
#	# If we get here, it must hold that $n != $expected and $n > 0.
#	# Dispense with the remove minder case ($exected > 0) by falling
#	# through and letting errors be caught by EggNog::Egg::rmminder().
#	#
#	$expected > 0 and			# remove minder case
#		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);	# normal
#
#	# If we get here, we were called from a routine creating a minder.
#	# If the minder we would create coincides exactly with one of
#	# the existing minders, refuse to proceed.
#	#
#	my $wouldcreate = catfile($mh->{minderhome}, $cmdr);
#	my ($oops) = grep(/^$wouldcreate$/, @mdrs);
#	my $hname = $mh->{humname};
#	if ($oops) {
#		$err = 1;
#		addmsg($mh, 
#		    "given $hname '$minder' already exists as $hname: $oops");
#		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);
#	}
#
#	# If we get here, $n > 0 and we're about to make a minder that
#	# doesn't clobber an existing minder; however, if $mdr is set,
#	# a minder of the same name exists in the path, and one minder
#	# might occlude the other, in which case we warn people.
#
#	if (! $mh->{opt}->{force}) {
#		addmsg($mh, ($n > 1 ?
#			"there are $n instances of '$minder' in path: " .
#				join(", ", @mdrs)
#			:
#			"there is another instance of '$minder' in path: $mdr"
#			) . "; use --force to ignore");
#		$err = 1;
#		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);
#	}
#	return ($mdr, $cmdr, $cmdr_from_d_flag, $err);	# normal return
#}

sub ebclose { my( $bh )=@_;

	my $exdb = $bh->{sh}->{exdb};
	my $msg;
	my $ok = try {
		$exdb->{client}->disconnect;
	}
	catch {
		$msg =	"problem disconnecting from external database: " . $_ .
			"; connect_string=$exdb->{connect_string}, " .
			"exdbname=$exdb->{exdbname}";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and
		addmsg($bh, $msg),
		return undef;
	return;
}

sub bclose { my( $bh )=@_;

	$bh->{sh}->{exdb} and
		ebclose($bh);
	$bh->{sh}->{indb} and
		omclose($bh);
	return;
}

################

our ($legalstring, $alphacount, $digitcount);
our $noflock = "";
our $Win;			# whether we're running on Windows

# 99% of egg requests will probably be 'r' (read)
# You don't have a permission if you haven't been granted it, either via
# 'public' or one of your other identities.
# ??? 'public' is the user with minimum rights -- no one has lower rights
# - for a bright archive, set public perms at least to 40
# - for a dim or dark archive, set public perms to 00 and adjust
#   perms at id level

# XXXXXXX this top level perms should be in a egg.conf file?
our $default_top_p =			# one or more p_string lines
'p:&P/2|public|40
p:&P/1|admin|77';		# xxx ?admin is default user for shelltype

# $opd is of the form id|e|se|...
# $opn is two octal digits
# symbolically: "rwxtcd"
use constant OP_READ	=> 040;
use constant OP_WRITE	=> 020;
use constant OP_EXTEND	=> 010;
use constant OP_TAKE	=> 004;
use constant OP_CREATE	=> 002;		# xxx?
use constant OP_DELETE	=> 001;		# xxx? 020 | 001

# yyy temporily look for several patterns until EZID database is all converted
use constant SUPPORT_ELEMS_RE	=> '(?:__m|_[.,]e)[cp]';
#use constant SUPPORT_ELEMS_RE	=> '__m[cp]';
#use constant PERMS_ELEM		=> '|__mp';
#use constant CTIME_ELEM		=> '|__mc';

use constant SUBELEM_SC		=> '|';
use constant TRGT_MAIN		=> '_t';
use constant TRGT_MAIN_SUBELEM	=> SUBELEM_SC . TRGT_MAIN;

# NB: changing from '.' to ',' because '.' is illegal in mongodb field names
#     yyy check if this is a conversion issue
use constant RSRVD_PFIX		=> '_,e';
use constant PERMS_ELEM		=> '|_,ep';
use constant CTIME_ELEM		=> '|_,ec';
use constant PERMS_EL_EX	=> '_,ep';
use constant CTIME_EL_EX	=> '_,ec';
use constant TRGT_METADATA	=> 'Tm,';
use constant TRGT_INFLECTION	=> 'Ti,';

#use constant RSRVD_PFIX	=> '_.e';
#use constant PERMS_ELEM	=> '|_.ep';
#use constant CTIME_ELEM	=> '|_.ec';
#use constant CTIME_EL_EX	=> '_.ec';

# xxx add extra arg for id-level operand (only caller really knows)
#	plus check that it's a substring of $opd
# xxx add extra arg for shoulder-level operand (does caller know this?)
#	plus check that it's a substring of $opd
#       can we assume that EZID knows this and can track it?
#       maybe, but we need a way to ask n2t about shoulders and naans
#       without going to EZID -- maybe a separate binder that's searched last

# Critical authorization testing routine.  Needs to be fast and secure.
#
# The main algorithm is simple.  The user arrives with one or more agent
# ids. Assemble a string of newline-separated permissions in this order:
#
#    $opd-specific \n $id-specifc \n ... \n top-level-specific
#
# Then do a regexp search from left to right to find the first matching
# agentid that has the desired rights.  Return the first match found;
# thus more-granular rights override less-granular rights) and use it.
# If none found, the authorization is denied.
#
# XXXXXX authz not currently called by anyone
sub authz { my(  $ruu, $WeNeed,   $bh,   $id,  $opd ) =
	      ( shift,   shift, shift, shift, shift );

	my $dbh = $bh->{tied_hash_ref};

# p:&P/2|public|60
# p:&P/1|admin|77
#$opd and
#	$dbh->{$opd . PERMS_ELEM} = "p:&P/897839|joe|60";
#$id and
#	$dbh->{$id . PERMS_ELEM} = "p:&P/2|public|00";

	# NOTE: routine assumes the $bh->{sh}->{conf_permissions} string was
	#       normalized/optimized to have all whitespace squeezed out!!
	# Also, no dupes here: psuedo-dupes are carried inside one value
	#       separated by newlines.	yyy RUU-specific format
	# What prevents others from modifying your permissions is that they
	# would first hit the code that checks permissions first.
	#
	my @bigperms; 			# assemble a big permissions list:
	@bigperms = grep { $_ } (	# keep only the non-null/non-empty
		($opd ?			# operand-specific perms first
			$dbh->{$opd . PERMS_ELEM} : undef
		),
		($id ?			# then id-specific perms
			$dbh->{$id . PERMS_ELEM} : undef
		),
					# yyy ... then one day (not yet)
					# shoulder- and naan-specific perms
		# finally, these are the global perms we started with
		($bh->{sh}->{conf_permissions}	# finally, global perms
			|| undef
		),
	);
	my $permstring =		# stringify it for regex matching
		join("\n", @bigperms) || '';
	
##	print("yyy ruu_agentid=$ruu->{agentid}\notherids=",
##			join(", " => @{$ruu->{otherids}}), "\n");
##	print("zzz $_\n")

$bh->{rlog}->out("D: WeNeed=$WeNeed, id=$id, opd=$opd, ruu_agentid=" .
	"$ruu->{agentid}, otherids=" . join(", " => @{$ruu->{otherids}}));

	$permstring =~
		/^p:\Q$_\E\|.*?(\d+)$/m 	# isolate perms per agent and
		&&
#! $bh->{rlog}->out("D: xxx _=$_, 1=$1, opn=$WeNeed, 1&opn=" .
#	(oct($1) & $WeNeed) . ", _p=" . "$permstring") &&
#	print("xxx _=$_, 1=$1, opn=$WeNeed, 1&opn=",
#	(oct($1) & $WeNeed), " _p=", "$permstring", "\n")
#		&&
			(oct($1) & $WeNeed)
		&&
			return 1		# return first match, if any
		for (				# checking across the user's
			@{ $ruu->{otherids} }, 	# group ids and the
			$ruu->{agentid} );	# agent id
		#
		# Putting the otherids first above is an optimization for
		# what will likely be by far the biggest use case, which is
		# 'read' by the public group (of which everyone is a member).
	return 0;
}

# auth required or permission denied
# 400 bad request (malformed -- usage?)
# 401 unauthorized (repeatable)
# 403 forbidden
# 404 not found
# 300 multiple choices (with content negotiation (section 12)
# 301 moved permanently
# 302 found (moved temporarily)
# 307 temporary redirect (moved temporarily)

# xxx Should probably replace unauthmsg() and badauthmsg() with a
#     routine in CGI::Head that returns an array of header name/val
#     pairs for a given error condition or relocation event
#
# Adds an authn http error message to a binder handler for output.
## If $msg arg is an array reference, add all array elements to msg_a.
#
sub unauthmsg { my( $bh, $vmsg )=@_;

#xxx think this realm stuff can be tossed -- apache handles it all??
	my $realm = 'egg';
	$bh->{realm} and
		$realm .= " $bh->{realm}";
	my $http_msg_name = 'Status';
	my $http_msg = '401 unauthorized';
	$vmsg and			# xxx a hack for debugging
		$http_msg .= ' - ' . $vmsg;

	addmsg($bh, $http_msg, "error");	# why call it $http_msg?
	# XXX! cgih must be defined iff $ruu->{webtype} !!!
	$bh->{om}->{cgih} and
		push(@{ $bh->{http_msg_a} },
			$http_msg_name, $http_msg);
# xxx needed?		'WWW-Authenticate', "Basic realm=\"$realm\"");
	return 1;
}

# Adds an authn http error message to a binder handler for output.
#
sub badauthmsg { my( $bh )=@_;

	my $http_msg_name = 'Status';
	my $http_msg = '403 forbidden';

	addmsg($bh, $http_msg, "error");	# why call it $http_msg?
	# XXX! cgih must be defined iff $ruu->{webtype} !!!
	$bh->{om}->{cgih} and
		push(@{ $bh->{http_msg_a} },
			$http_msg_name, $http_msg);
	return 1;
}

sub initmsg { my( $bh )=@_;
	$bh->{msg_a} = [];		# regular message array
	$bh->{http_msg_a} = [];		# http message array
}

sub getmsg { my( $bh )=@_;
	return $bh->{msg_a};
}

sub hasmsg { my( $bh )=@_;		# suitable for test wheter the first
	return ($bh->{msg_a})[1];	# element's message text is non-empty
}

# Adds an error message to a binder handler message array, msg_a.
# The message array is ordered in pairs, with even elements (0, 2, ...)
# being message name (eg, error, warning) and odd elements being the text
# of the message (going with the previous element's name).
# If $msg arg is an array
# reference, add all array elements to msg_a; this is how to transfer
# messages from one binder handler to another.
# Arg $msg_type is optional.
#
sub addmsg { my( $bh, $msg, $msg_name )=@_;

	$msg ||= '';
	$msg_name ||= 'error';

	ref($msg) eq '' and		# treat a scalar as a simple string
		push(@{ $bh->{msg_a} }, $msg_name, $msg),
		return 1;
	ref($msg) ne 'ARRAY' and	# we'll consider a reference to an
		return 0;		# array, but nothing else
	#print("xxx m=$_\n"), push @{ $bh->{msg_a} }, $_	# $msg must be an array reference,
	push @{ $bh->{msg_a} }, $_	# $msg must be an array reference,
		for (@$msg);		# so add all its elements
	return 1;
}

# XXX need OM way to temporarily capture outputs to a string, independent of
#     user setting of outhandle (so we can insert notes in ...README files)

# Outputs accumulated messages for a minder object using OM.  First arg
# should be a binder handler $bh.  Optional second and third args ($msg
# and $msg_name), if present, are to be used instead of the $bh->{msg_a}
# array.  If the first arg is a scalar (not a ref), assume it's a message
# string and just print it to stdout (ie, without OM) with a newline.
# See addmsg() for how to set an HTTP response status.
#
# Since this would often be used for debugging, we're very forgiving if
# you supply the wrong args, or haven't initialized $bh.  We try to do
# what you'd like to get information "out there".  Completeness wins over
# efficiency.
#
# Messages are assumed to be exceptional and more likely to be
# structured, so we use om_formal for output.
#
sub outmsg { my( $bh, $msg, $msg_name )=@_;

	unless ($bh) {				# no minder degenerates
		my $m = $msg_name || '';	# into simple case of name,
		$m	and $m .= ': ';		# colon, and
		$m .= $msg || '';		# value
		return				# print and leave
			print($m, "\n");
	}
	ref($bh) or				# if not a ref, assume $bh is
		return print($bh, "\n");	# a string -- print and leave

	# If we get here, assume valid $bh and process arrays of
	# messages, although typically there's just one message.
	#
	my $msg_a;			# every odd array element is a message
	if (defined($msg)) {		# set some defaults
		$msg_name ||= 'error';	# default message type
		$msg_a = [ $msg_name, $msg ];
	}
	else {
		$msg_a = $bh->{msg_a};
	}

	my $om = $bh->{om_formal};
	my $p = $om->{outhandle};		# 'print' status or string
	my $st = $p ? 1 : '';		# returns (stati or strings) accumulate
	my ($i, $max, $s, $n, $d);

	my $http_msg_a = $bh->{http_msg_a};
	my $cgih = $om->{cgih};		# should be null unless $WeAreOnWeb
	($i, $max) = (0, scalar(@$http_msg_a));
		$n = $http_msg_a->[$i++],	# -- its code and its
		$d = $http_msg_a->[$i++],	# message value -- and
		$cgih && $cgih->add( { $n => $d } )
			while ($i < $max);

	($i, $max, $s, $n, $d) = (0, scalar(@$msg_a), '');

		$n = $msg_a->[$i++],	# -- its name and its
		$d = $msg_a->[$i++],	# data value -- and
		$s = $om->elem(			# take each next element pair
			$n,
			$d,
		),				# collect strings or stati
		$p && (($st &&= $s), 1) || ($st .= $s)
			while ($i < $max);

	return $st;

	#$disposition or	# null disposition, so return string made from
	#	return join("\n", eachnth(2, $msg_a));	# overy other element
	#
	#ref(*$disposition{IO}) eq "IO::Handle" and
	#	return print $disposition join("\n", eachnth(2, $msg_a)), "\n";
	#
	#ref($disposition) =~ /File::OM/o or
	#	print STDERR ("outmsg: unknown message disposition " .
	#		"'$disposition': (", ref($disposition), ")\n"), 0;
}

# Return array composed of every nth element of the array
# referenced by $list_r.
#
sub eachnth { my( $n, $list_r )=@_;

	$n		or return undef;
	my ($i, $max, @new) = (0, scalar(@$list_r), ());

	$i % $n && push(@new, $list_r->[$i])
		while (++$i < $max);
	return @new;
}

=for removal

# XXXXX not very robust -- see wlog for better
sub logmsg{ my( $bh, $message )=@_;

	my $logfhandle = $bh->{log};
	defined($logfhandle) and
		print($logfhandle $message, "\n");
	# yyy file was opened for append -- hopefully that means always
	#     append even if others have appended to it since our last append;
	#     possible sync problems...
	return 1;
}

=cut

use Fcntl qw(:DEFAULT :flock);
#use DB_File;
use BerkeleyDB;
use constant DB_RDWR => 0;		# why BerkeleyDB doesn't define this?
use File::Spec::Functions;
use Config;

sub get_bdberr {
	$BerkeleyDB::Error and
		return $BerkeleyDB::Error;
	return '$!=' . $!;
}

# Global $v1bdb will be true if we're built with or running with pre V2 BDB.
# Returns an array of 4 elements:
#   $v1bdb    	             (boolean with value of global)
#   $BerkeleyDB::VERSION      (BDB Perl module that we are running with)
#   $BerkeleyDB::db_ver       (BDB C library version we were built with)
#   $BerkeleyDB::db_version   (BDB C library version we are running with)
#
use MongoDB;
sub get_dbversion {

	my $v1bdb;			# global that's true for pre-V2 BDB
					# xxx this is a per object global
	$v1bdb = $BerkeleyDB::db_ver =~ /^1\b/ or
		$BerkeleyDB::db_version =~ /^1\b/;

	#$v1bdb = $DB_File::db_ver =~ /^1\b/ or
	#	$DB_File::db_version =~ /^1\b/;
	#return (
	#	$v1bdb,
	#	$DB_File::VERSION,	# Perl module version
	#	$DB_File::db_ver,	# libdb version built with
	#	$DB_File::db_version,	# libdb version running with
	#);

	return (
	  $v1bdb,			# whether we're on pre-V2 BDB
	  $BerkeleyDB::VERSION,		# Perl module that we are running with
	  $BerkeleyDB::db_ver,		# C library version we were built with
	  $BerkeleyDB::db_version,	# C library version we are running with
	  $MongoDB::VERSION,		# Mongo version
	);
}

# Return a special "example.com" URL (non-actionable) disclosing information
# about the running resolver.  "example.com" won't resolve, but in a URL, it
# will pass through the rewrite rules and be returned, and if in a browser,
# it will show up visible/readable in the location field.
#
sub rrminfo {

	my ($v1bdb, $modv, $builtv, $runningv) = get_dbversion();

	my $infotarget =			# initialize
		'http://www.example.com/'
			. 'embrpt/';
	# EMBRPT is a mnemonic acronym to help interpret the returned path
	# elements:
	#	e = egg version
	#	m = Berkeley module version
	#	b = C libdb version we were built with
	#	r = C libdb version we are running with
	#	p = server process id
	#	t = server start time
	#
	# We also add a few key=value pairs as a pseudo query string.

	$infotarget .=				# add some elements
		"$VERSION/$modv/$builtv/$runningv";

	# This environment variable was put in place by build_server_tree
	# when it created the "rmap" script.  It lets us access to files
	# we want to consult to find information about the running server.
	# The $server_dvcsid file is also created by build_server_tree.
	#
	my $srvref_root =	# just in case we get called when not on the
		$ENV{EGNAPA_SRVREF_ROOT} ||	# web, use naive guess to
		"$ENV{HOME}/sv/cur/apache2";	# avoid an unitialized error
						# yyy rethink this kludge
	my $server_proc = "$srvref_root/logs/httpd.pid";
	my $server_dvcsid = "$srvref_root/logs/dvcsid";
	my ($msg, $pid, $dvcsid);

	my $sstart = etemper( (stat $server_proc)[9] )
		|| 'no_httpd.pid';	# will be returning as an error message

	($msg = file_value("<$server_proc", $pid)) and
		$pid = $msg;		# will be returning as an error message

	($msg = file_value("<$server_dvcsid", $dvcsid)) and
		$dvcsid = $msg;		# will be returning as an error message

	my $rmap = $ENV{EGNAPA_RMAP} || '';		# path to rmap script
	$infotarget .= "/$pid/$sstart?dvcsid=$dvcsid&rmap=$rmap";

	# NB: make sure there are no \n's, which would screw up resolution
	# for all downstream users.  This also suppresses any spaces that
	# show up in $pid because it's really an error message.
	#
	$infotarget =~ s/\s/_/g;

	return $infotarget;
}

our $implicit_minter_opt = { "atlast" => "add3", "type" => "rand" };
our $implicit_caster_opt = { "atlast" => "add1", "type" => "rand" };
#xxx change this type to gentype to be less confusing around other types
our $implicit_minter_template = "{eedk}";
our $implicit_caster_template = "{ed}";
our @implicit_caster_except = {"df4", "df5", "fk4", "fk5"};

# xxx Takes a binder handler and a colon-separated-list as args,
# Takes a binder handler, an array ref and a minderpath array ref as args,
# calls ibopen on each minder, and returns an array of open binder handlers.
# This is useful when the minders are binders to be opened O_RDONLY as
# resolvers.  The $bh arg is used to store results and as input for
# inheritance for other params that "Minder->new" needs.
# yyy right now works only for resolvers (assumes ND_BINDER) and readonly
# 
# Call: $status = open_resolverlist($bh, $bh->{resolverlist},
#
sub open_resolverlist { my( $bh, $list )=@_;

# xxx $list likely includes the same minder that is already opened
#     with $bh, in which case we'll just open it again -- should be ok as
#     we want the handler in $list to have different attributes, eg, to
#     stop recursion rather than to start it

	# Use map to create and open a binder handler for each item in
	# $resolverlist.  Unlike $bh, for these binder handlers we will
	# turn off {opt}->{resolverlist} so that recursion stops with them.
	#
	$list ||= $bh->{opt}->{resolverlist} || "";
	#print "list=$list, mpath_a=@$minderpath_a\n";

	my $rmh;
	my $me = 'open_resolverlist';
# xxx is the next test needed?
	$bh->{resolverlist_a} and
		addmsg($bh, "$me: resolver array already built"),
		return ();

	my @mharray = map {			# for each resolver in list
	    					# IF ...
		$rmh = EggNog::Binder->new(	# we get a new binder handler
						# xxx don't want to do
						#    this every time
			$bh->{sh},
			EggNog::Binder::ND_BINDER,
			$bh->{WeAreOnWeb},
			$bh->{om},
			$bh->{opt},
		)
		or	addmsg($bh, "$me: couldn't create binder handler"),
			return ()
		;
		$rmh->{resolverlist} = undef;	# stop recursion 1
		$rmh->{subresolver} = 1;	# stop recursion 2
		$rmh->{rrm} = 1;	# xxx better if inherited?
					#     big assumption about caller here
		ibopen(				# and IF
			$rmh,			# we can ibopen it
						# yyy check if already open?
			$_,			# using the map list item
			#O_RDONLY,		# read-only (for a resolver)
			DB_RDONLY,		# read-only (for a resolver)
			$bh->{minderpath},	# supplied minderpath ARRAY ref
			#'xxxmindergen',
		)
		or	addmsg($bh, getmsg $rmh),
			addmsg($bh, "$me: couldn't open minder $_"),
			return ()
		;

		$rmh;				# eval to $rmh on success

	} split
		$Config{path_sep}, $list;
	#
	# If we get here, @mharray has an array of open minders.

	#outmsg($bh, "xxx mharray=" . join(", ", @mharray) .
	#	" sep=$Config{path_sep}, list=$list");

	@{ $bh->{resolverlist_a} } = @mharray;	# save the result in $bh
	return @mharray;			# and return it too
}

our $v1bdb;			# global that's true for pre-V2 BDB
				# xxx this is a per object # global?

our $v1bdb_dup_warning =
'ordering of duplicates will not be preserved; to remedy, re-create binder' .
' after relinking Perl\'s DB_File module with libdb version 2 or higher' ;

# 'ordering of duplicates will not be preserved in this binder because ' .
# 'it was created with "libdb" version 1; you can remedy this by removing ' .
# 'the binder, relinking Perl\'s DB_File module with libdb version 2 or ' .
# 'higher, and re-creating the binder';

# zzz independent conditions:
#
# noid mint 1 or bind i n d -> if no minder, use default;
#    search for default, if no default, create default
#
# noid x.mint or bind x.set i n d -> search for x
# noid -d x mint or bind -d x set i n d -> ! search for x
#
# noid mkminter
#    if no default, create default; else generate new shoulder
# bind mkbinder
#    if no default (b1), create default; else generate ("snag next b1")
#
# ibopen($bh, $name, $flags, [$minderpath], [$mdrgenerator])
#	leave $minderpath empty to prevent search
#	leave $mdrgenerator empty to prevent autogeneration 
#
#   search || ! search for minder
#	minder exists && create -> error
#	minder ! exists && create -> ok
#		qualify: minder ! exist _in_ creation directory, eg,
#		minderpath[0], but issue warning if it exists elsewhere
#		in minderpath[1-$]
#	minder exists && open -> ok
#	minder ! exists && open -> error
#	minder ! specified && create -> error
#	minder ! specified && GENERATE -> ok
#	minder specified as "." -> ok use default
#		qualify: GENERATE implied if default ! exists
#   ibopen($bh, $uname_or_dname, $flags) with other params given by
# 	$bh->{minderpath}, $bh->{}
# zzz always require named minder to _right_ of rmminter/rmbinder,
#     BUT mkminter/mkbinder DONT need that when you want to create a
#     new one but don't want to have to think of a new name! eg
# $ noid mkminter
# created: fk2 | see "noid lsminter fk2" for details
# $ bind mkbinder
# created: b1 | see "bind lsbinder b1" for details
# Call with $minder set to "" or undef to invoke default minder.
# If CREAT and ! $minder, then make a new minder that is either
#    the default minder or from a generated minder name (may
#    require generating the minder generator).
# DB_File    $flags can be O_CREAT,   O_RDWR,  or O_RDONLY  (the default)
# BerkeleyDB $flags can be DB_CREATE, DB_RDWR, or DB_RDONLY (the default)
#
# xxx probably should change minderpath to minderpath_a to indicate an
# array not a string

# ibopen = internal binder open (legacy)

sub ibopen { my( $bh, $mdr, $flags, $minderpath, $mindergen )=@_;

	defined($flags)		or $flags = 0;
	my $ibopenargs = $bh . $mdr . $flags .	# crude argument signature
		($minderpath ? join(",", @$minderpath) : "");
	my $om = $bh->{om};
	if ($bh->{open}) {

		# XXX should probably send a signal when we want to force
		#     all processes to re-open and check the .conf file
		# If already opened in the same mode with same minder args
		# as requested before save lots of work by only re-opening
		# every $bh->persistomax attempts to call ibopen.  A crude
		# test is to save previous ibopen args in a literal string
		# $bh->{ibopenargs}, which may be wrong in some cases. XXXX
		#
		my $use_old_open = $bh->{ibopenargs} eq $ibopenargs &&
			$bh->{open_count}++ <= $bh->{persistomax};
		$use_old_open and
			($bh->{opt}->{verbose} and $om and $om->elem("note",
				"using previously opened binder $mdr")),
			return 1;		# already open, don't re-open
		# Else call omclose and fall through to re-open.
		omclose($bh);
	}
	# If we get here, $bh is not open.

	# XXX easy?: have $om turn off verbose (removes extra test for output)
	#     or make it log instead?
	$bh->{opt}->{verbose} and $om and $om->elem("note",
		"opening binder '$mdr', flags $flags" . ($minderpath
		? " (path: " . join(", ", @$minderpath) . ")" : ""));
	$bh->{ibopenargs} = $ibopenargs;	# record argument signature

	#NB: $bh->{opt}->{minderpath} is STRING, $bh->{minderpath} is ARRAY ref
	#NB: $bh->{opt}->{resolverlist} STRING, $bh->{resolverlist_a} ARRAY ref
	#NB: this next resolverlist test is irrelevant for noid yyy

	if ($bh->{rrm} and $bh->{resolverlist}) {
		my $rcount =
			open_resolverlist($bh, $bh->{opt}->{resolverlist});
		$rcount or
			addmsg($bh, "problem opening resolverlist: " .
				$bh->{opt}->{resolverlist}),
			return undef;
		$bh->{opt}->{verbose} and $om and
			$om->elem("note", "resolver list count: $rcount");
	}

	# This next call to prep_default_binder() may call ibopen() again
	# via gen_minder().
	#
 	$mdr ||= prep_default_binder($bh, 'i', $flags, $minderpath, $mindergen);
 	$mdr or
		addmsg($bh, "ibopen: no binder specified and default failed"),
		return undef;

	# Find path to minder file.  First we need to make sure that we
	# have both the minder filename and its enclosing directory.
	#
# xxx make sure fiso_uname is only called on an arg that has been
#     extended already by fiso_dname, else successive calls could keep
#     chopping it back; better: make fiso_uname idempotent somehow.
	my $mdrd = fiso_dname($mdr, FS_DB_NAME);

	# Use first minder instance [0], if any, or the empty string.
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";

	# xxx what if it exists but not in minderhome and you want
	#     to create it in minderhome?
	#my $creating = $flags & O_CREAT;
	my $creating = $flags & DB_CREATE;
	if ($creating) {	# if planning to create, it shouldn't exist
		#scalar(@mdrs) > 1 and ! $bh->{opt}->{force} and
		#	addmsg($bh, "than one instance of ($mdr) in path: " .
		#		join(", ", @$minderpath)),
		#	return undef;
		$mdrfile and
			addmsg($bh, "$mdrfile: already exists" .
				($mdrfile ne $mdr ? " (from $mdr)" : "")),
			return undef;
			# yyy this complaint only holds if dname exists,
			#     don't complain if only the uname exists
	}
	else {			# else it _should_ exist
		$mdrfile or
			# xxx would be helpful to say if it exists or not
			addmsg($bh, "cannot find binder: $mdr"),
			# "ibopen: ($mdrd|$mdrfile)" .
			#	join(":", @$minderpath) .
			return undef;
		$mdrd = $mdrfile;
	}
	my $mdru = fiso_uname($mdrd);

	# xxx should probably be called mdrhome? since database will
	# actually be in a subdirectory of this dir
	my $dbhome = fiso_uname($mdrd);
	! -d $dbhome and
		addmsg($bh, "$dbhome not a directory"),
		return undef;
	$bh->{dbhome} = $dbhome;	# yyy might double as test for openness?

	my $basename = catfile( $mdru, $bh->{fname_pfix} );

	my $ruu = $bh->{sh}->{ruu};
	#$bh->{om}->{cgih}->add( { 'Acting-For' => $msg } );
	if ($bh->{opt}->{verbose} and $om) {
	    $om->elem("note",
		"remote user: " . ($ruu->{remote_user} || '') .
		($ruu->{http_acting_for} ?
			" acting for $ruu->{http_acting_for} " : ''));
	    #$om->elem("note",
		#'config file section lengths: ' .
		#'permissions '. length($bh->{sh}->{conf_permissions}) . ", " .
		#'flags '. length($bh->{sh}->{conf_flags}) . ", " .
		#'ruu '. length($bh->{sh}->{conf_ruu}));
	}

	#
	# Log file set up.
	# 
	# yyy do we need to open the rlog so early?? how about after tie()??

	$bh->{rlog} = EggNog::Rlog->new(
		$basename, {
			preamble => "$ruu->{who} $ruu->{where}",
			header => "H: $bh->{cmdname} $bh->{version}",
		}
	);

	$bh->{txnlog} = $bh->{sh}->{txnlog};

	#
	# Other
	#

	my $duplicate_keys = ($bh->{type} eq ND_BINDER);	#xxx for config?
	#defined($duplicate_keys)	or $duplicate_keys = 0;
	defined($v1bdb) or
		($v1bdb) = get_dbversion();
	$bh->{'v1bdb'} = $v1bdb;

	#$flags ||= O_RDONLY;
	! defined($flags) and		# 0 is a legit value of $flags
		$flags = DB_RDONLY;
	#my $rdwr = $flags & O_RDWR;	# read from flags if we're open RDWR

	# NB: DB_RDWR is zero!  Therefore we cannot ask test for read/write
	# mode with
	#           $flags & DB_RDWR
	# Instead we ask for
	#           ! ($flags & DB_RDONLY)
	my $rdwr = ! ($flags & DB_RDONLY);	# check flags if we're open RDWR
	#my $rdwr = $flags & DB_RDWR;	# check flags whether we're open RDWR

	# Don't lock if we're RDONLY unless we're told to.  This prevents
	# users being shut out by broad database scans, at the risk of a
	# little database inconsistency for those scans.  Use --lock when
	# consistent reads are important. xxx document
	#
	#print ("xxx rdwr=$rdwr, flags=$flags, creating=$creating, DB_RDONLY=", DB_RDONLY, " DB_RDWR=", DB_RDWR, "\n");
	$rdwr || $bh->{opt}->{lock} and
		#print("xxx locking\n"),
		# XXX minder_lock has it's own defn of $flags!!
		(minder_lock($bh, $flags, $dbhome) or
			return undef);

	# We don't enable duplicate keys if we're minting, since we want
	# stored values to act like variable assignments.  We want dups
	# primarily for binding, but maybe not always for binding.
	# xxx to ask Paul Marquess:
	#     for some reason (on Linux and/or later versions of DB_File
	#     we can only use R_DUP with O_CREAT, but on older DB_File
	#     (on Mac at least) R_DUP _must_ be used on every dbopen
	#
	if ($duplicate_keys) {
		$v1bdb && $creating and
			addmsg($bh, $v1bdb_dup_warning, "warning");
		#$v1bdb || ($creating) and
		#	$DB_BTREE->{flags} = DB_DUP;
		#	#$DB_BTREE->{flags} = R_DUP;
	}
	#$duplicate_keys and $v1bdb || ($flags & O_CREAT) and
	#	$DB_BTREE->{flags} = R_DUP;

	#my @dbhome_parts = grep { $_ } File::Spec->splitdir( $dbhome );
	#$bh->{realm} =		# for HTTP auth, get last part of path
	#	$dbhome_parts[ $#dbhome_parts ];

	# Note that an environment consists of a number of files that
	# Berkeley DB manages behind the scenes for you. When you first use
	# an environment, it needs to be explicitly created. This is done
	# by including DB_CREATE with the Flags parameter, described below.
	#
	#my $envflags = DB_INIT_LOCK | DB_INIT_TXN | DB_INIT_MPOOL;
	#my $envflags = DB_INIT_CDB | DB_INIT_MPOOL;
	#($flags & DB_CREATE) and
	#	$envflags |= DB_CREATE;
	my $envflags = DB_CREATE | DB_INIT_TXN | DB_INIT_MPOOL;
	#my $envflags = DB_CREATE | DB_INIT_LOCK | DB_INIT_TXN | DB_INIT_MPOOL;
	#my $envflags = DB_CREATE | DB_INIT_TXN | DB_INIT_MPOOL;
	my @envargs = (
		-Home => $dbhome,
		-Flags => $envflags,
		-Verbose => 1
	);

	# If it exists and is writable, use log file to inscribe BDB errors.
	#
	my $logbdb = catfile( $dbhome, 'logbdb' );
	-w $logbdb and
		push(@envargs, ( -ErrFile => $logbdb ));
	# yyy should we complain if can't open log file?

	my $env = new BerkeleyDB::Env @envargs;
	if (! defined($env)) {
		addmsg($bh, 'cannot create "BerkeleyDB::Env" object ' .
			"($BerkeleyDB::Error) for [" .
			join(', ', @envargs) . ']');
		my ($x, $modversion, $built, $running);
		($x, $modversion, $built, $running) = get_dbversion();
		addmsg($bh, "System BerkeleyDB version $modversion, built " .
			"with C libdb $built, running with C libdb $running");
		my $fileversion = `db_dump -p $mdrd | \
				sed -n -e '/dbversion/{ n;p;q' -e '}'`;
		chop $fileversion;
		addmsg($bh, "Binder creation: $fileversion");
		return undef;
	}

	# This is the real moment of truth, when the database is opened
	# and/or created.  First, record the filename -- even if we fail
	# to open it, we worked hard to nail it down.
	#
	$bh->{minder_file_name} = $mdrd;
	my $href = {};
	#my $db = tie(%$href, "DB_File", $mdrd, $flags, 0666, $DB_BTREE) or
	my $db = tie(
		%$href,
		'BerkeleyDB::Btree',
		-Filename => FS_DB_NAME,
		-Flags => $flags,
		-Property => DB_DUP,
		-Env => $env
	);
	$db or
		addmsg($bh, "tie failed on $mdrd: $!: $BerkeleyDB::Error" .
			": (" . (-r $mdrd ? "" : "not ") . "readable)" .
			($bh->{fiso} ? ", which is open" : "")),
		return(undef),
	;

	$bh->{opt}->{verbose} and $om and $om->elem("note",
		($creating ? "created" : "opened") . " binder $mdrd"),
			# XXX this next is really a debug message
			$om->elem("note", "ibopen $bh");

	# If we get here, the minder is open.
	# 
# XXXXXX minder status!!! should this be in minder.conf?
	$creating and		# set minder status to 'enabled' (default)
		$href->{"$A/status"} = 'e';

	# yyy how to set error code or return string?
	#	or die("Can't open database file: $!\n");

	# Record stuff relevant to "open" event,
	# yyy?  which will all be taken care of by any "close" event?
	#
	$bh->{minder_status} = $href->{"$A/status"};	# XXX we don't respect this!!
	$bh->{tied_hash_ref} = $href;
	$bh->{db} = $db;
	$bh->{fiso} = $mdrd;	# yyy old defining moment for test of openness

	# Defining moment in test for openness.
	$bh->{open} = $rdwr ? MDRO_OPENRDWR : MDRO_OPENRDONLY;
	#print "xxx mhopen=$bh->{open}\n";
	$bh->{open_count} = 0;
	$bh->{msg} = "";
	# $bh->{MINDLOCK} is set up by minder_lock()

	my $msg = version_match($bh)		# check for mismatch, but
		unless $creating;		# only if we're not creating

	#if ($msg) ...		# if we get version mismatch
	# yyy we should define rlog early on or in session handler ($sh)
	#if ($msg and $bh->{rlog}) ...		# if we get version mismatch
	if ($msg) {		# if we get version mismatch
		# xxx should we just call DESTROY??
		$msg = "abort: $msg";
		#logmsg($bh, $msg);
		$bh->{om}->{cgih}->add( { Status => '500 Internal Error' } );
		$bh->{rlog}->out("N: $msg");
		addmsg($bh, $msg);
		undef $db;
		omclose($bh);
		return undef;
	}
	my $secs;
	$secs = $bh->{opt}->{testlock} and
		$bh->{om}->elem('testlock',
			"holding lock for $secs seconds...\n"),
		sleep($secs);

	return 1;
}
# end of ibopen

# yyy only using $bh and $exbrname, the latter should have been normalized
# via str2brnames()
#
# ebopen = external binder open (new)

sub ebopen { my( $bh, $exbrname, $flags )=@_;

	$EggNog::Egg::BSTATS //=		# lazy, one-time evaluation
		EggNog::Egg::flex_enc_exdb(
			"$A/binder_stats",		# _id name
			"bindings_count",		# element name
		);
	$flags //= 0;
	my $sh = $bh->{sh};
	! $exbrname and
		(undef, $exbrname) = str2brnames($sh, $DEFAULT_BINDER);

		# NB: this $DEFAULT_BINDER is created implicitly by the first
		# mongodb attempt to write a record/document, so it is not the
		# product of mkbinder and therefore has no "$A/erc" record,
		# which we special-case ignore when doing brmgroup().

		# yyy indb case might adopt something closer to this
		#     simple approach to default binder naming

	# With MongoDB, this is a very soft open, in the sense that it
	# returns without contacting the server. (For performance reasons
	# you don't really know if you have a connection until the first
	# access attempt.)  Consquently, it almost always "succeeds".

	# One feature of MongoDB that can be annoying is when it "succeeds" in
	# opening a non-existent binder, creating it as a result. Instead you
	# want it to fail so that you know if you constructed the binder name
	# incorrectly. The feature is that you save a round trip on opening,
	# but for read-only resolution by a long-running process, we do an
	# explicit existence check since resolution is such a pain to debug.

#	if ($bh->{rrm}) {		# if we're in resolver mode
#	        my ($indbexists, $exdbexists) =
# xxx this test should maybe go before DEFAULT_BINDER is used above
# xxx maybe it should go before "bopen"
# xxx need to get these next args passed in from caller
# xxx $sh->{ruu}->{who} is $user?
# xxx $sh->{bgroup} is $bgroup?
# xxx $binder comes from ancestor of $exbrname, which refines it...
#			binder_exists($sh, undef, $binder, $bgroup, $user, undef);
#
#	}
# ZZZZZZZZZZZZZZZZZZZZXXXXXX

	my $exdb = $sh->{exdb};
	my $om = $bh->{om};
	#my $open_exdb = {};
	my $msg;
	my $ok = try {
		$exdb->{binder} = $exdb->{client}->ns( $exbrname );
	}
	catch {
		$msg =	"problem opening external database: " . $_ .
			"; connect_string=$exdb->{connect_string}, " .
			"exdbname=$exbrname";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and
		addmsg($bh, $msg),
		return undef;
	#$open_exdb->{exdbname} = # xxx transition to $bh->{open_exdb}->{binder}
					# and stop with $sh->{exdb}->{binder}
	$exdb->{exdbname} = $exbrname;
	#$bh->{open_exdb} = $open_exdb;

	my $ruu = $sh->{ruu};
	#my $ruu = $bh->{sh}->{ruu};
	if ($bh->{opt}->{verbose} and $om) {
	    $om->elem("note",
		"remote user: " . ($ruu->{remote_user} || '') .
		($ruu->{http_acting_for} ?
			" acting for $ruu->{http_acting_for} " : ''));
	}

	my $creating = $flags & $EGG_DB_CREATE;
	$bh->{opt}->{verbose} and $om and $om->elem("note",
		($creating ? "created" : "opened") . " binder $exbrname"),
			# XXX this next is really a debug message
			$om->elem("note", "ibopen $bh");
	return 1;
}

# bopen = binder open (new, generic multi-db version)
sub bopen { my( $bh, $bdr, $flags, $minderpath, $mindergen )=@_;

	! $bh and		# yyy or open binder handler for the caller?
		return undef;
	my $sh = $bh->{sh} or	# yyy or open a session for the caller?
		return undef;
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($bh, $msg);	# failed to configure
		return undef;
	}
# xxx if rrm check for existence and bail if not!

# xxx move this next into ebopen, so we can pass raw $bdr arg to ebopen
	my ($inbrname, $exbrname) =
		str2brnames($sh, $bdr);
#say STDERR "xxx bopen: bdr=$bdr, exbrname=$exbrname";
	if ($sh->{exdb}) {
		($flags & DB_CREATE) and
			$flags = $EGG_DB_CREATE;	# yyy dumb kludge
		ebopen($bh, $exbrname, $flags) || return undef;
	}
	$sh->{indb} and
		ibopen(@_) || return undef;
	return 1;
}

sub fiso_erc { my( $ruu, $tagdir, $what )=@_;

	use EggNog::Temper 'etemper';

	my $cwd = file_name_is_absolute($tagdir)
		?  $tagdir : catfile(curdir(), $tagdir);
		# XXX need to canonicalize this last?

	return qq@erc:
who:       $ruu->{who}
what:      $what
when:      @ . etemper() . qq@
where:     $ruu->{where}:$cwd
@;
}

# yyy side-effect: sets global variable $noflock

sub minder_lock { my( $bh, $flags, $dbhome )=@_;

	# We use simple database-level file locking with a timeout.
	# Unlocking is implicit when the MINDLOCK file handle is closed
	# either explicitly or upon process termination.
	#
	my $lockfile = catfile( $dbhome, "$bh->{fname_pfix}lock" );
	#my $lockfile = $dbhome . "$bh->{objname}.lock";
	#my $timeout = 5;	# max number of seconds to wait for lock
	#my $timeout = LOCK_TIMEOUT;	# max number of seconds to wait for lock
	my $timeout = $bh->{timeout};	# max number of seconds to wait for lock
	#my $locktype = (($flags & O_RDONLY) ? LOCK_SH : LOCK_EX);
	my $locktype = (($flags & DB_RDONLY) ? LOCK_SH : LOCK_EX);

	#! sysopen(MINDLOCK, $lockfile, O_RDWR | O_CREAT) and
	! sysopen($bh->{MINDLOCK}, $lockfile, O_RDWR | O_CREAT) and
		addmsg($bh, "cannot open \"$lockfile\", type $locktype: $!"),
		return undef;

	eval {			# yyy convert to try/catch/finally carefully
		
		local $SIG{ALRM} = sub { die("lock timeout after $timeout "
			. "seconds; consider removing \"$lockfile\"\n")
		};
		alarm $timeout;		# alarm goes off in $timeout seconds
		eval {		# yyy convert to try/catch/finally carefully
			# creat a blocking lock
			#flock(MINDLOCK, $locktype) or	# warn only on creation
			flock($bh->{MINDLOCK}, $locktype) or
				# warn only on creation
				# XXX not tested # xxx add note to README file?
				1, ($noflock =
qq@database coherence cannot be guaranteed unless access is single-threaded or the database is re-created on a filesystem supporting POSIX file locking semantics (eg, neither NFS nor AFS)@)
				#and ($flags & O_CREAT) and addmsg($bh,
				and ($flags & DB_CREATE) and addmsg($bh,
					"cannot flock ($!): $noflock",
					"warning");
				#die("cannot flock: $!");
		};
		alarm 0;		# cancel the alarm
		die $@ if $@;		# re-raise the exception
	};
	alarm 0;			# race condition protection
	if ($@) {			# re-raise the exception
		addmsg($bh, "error: $@");
		return undef;
	}
	return 1;
}

# returns "" on successful match
sub version_match { my( $bh )=@_;

	my $dbh = $bh->{tied_hash_ref};

	my $dbver = $dbh->{"$A/version"};
	my $incompatible = "incompatible with this software ($VERSION)";

	if (! defined $dbver) {
		return
		  "the database version is undefined, which is $incompatible";
	}
	# xxx not a very good version check
	if (! $dbver =~ /^1\.\d+/) {
		return
			"the database version ($dbver) is $incompatible";
	}

	return "";		# successful match
}

# Normalize binder names
# Given a session handler and a user-oriented binder name, return an
# array of 2 name strings suitable for machine connection:
#    Elem 0: the internal database name, if session configured for it
#    Elem 1: the external database name, if session configured for it
# The corresponding string will be empty if the session wasn't configured
# for it or if there was some sort of error.
#
# Returned strings take into account the binder owner (populator) and
# internal filesystem requirements (internal database) or connection
# string (external database) requirements.
# An external database name lacks the path information that an internal
# database name uses to distinguish temporary, personal, and production
# names (eg, ./td_egnapa/..., ~/.eggnog/..., ~/sv/cur/apache2/...), so we
# prepend info from $sh->{home} for external db names.
# NB: We convert binder name '/' into the empty string in the external case
# where we don't support generating binder names (unlike the internal case).
# yyy this doesn't do the fiso_db... stuff for internal database names
# 
sub str2brnames { my( $sh, $binder, $bgroup, $user )=@_;

	my ($inbrname, $exbrname) = ('', '');
	! $binder and
		return ($inbrname, $exbrname);
	$binder =~ s/^[\W_]+//;		# drop leading and trailing non-word,
	$binder =~ s/[\W_]+$//;		# non-_ characters from requested name
	#$sh->{indb} and			# eg, BerkeleyDB
	$inbrname = $binder;		# we still need this for exdb case
		# $inbrname = ($sh->{ruu}->{WeAreOnWeb} ?
		#		$sh->{ruu}->{who} : '')
		#	. $binder;
	! $sh->{exdb} || ! $sh->{cfgd} and
		return ($inbrname, $exbrname);

	# If we get here, we're dealing with an external binder, eg, MongoDB.

	# to be safe, since fiso_uname isn't idempotent, ...
	my $mdrd = fiso_dname($binder, FS_DB_NAME);	# first extend
	my $mdru = fiso_uname($mdrd);		# then unextend (safely)
	my $bname = basename $mdru;	# user's binder name
	#my $bname = basename $binder;	# user's binder name
	$bname =~ s/^[\W_]+//;		# drop leading and trailing non-word,
	$bname =~ s/[\W_]+$//;		# and non-_ characters from item name
	my (undef, undef, $ns_root, $clean_ubname) =
		EggNog::Session::ebinder_names($sh, $bgroup, $user, $bname);
	#$exbrname = $sh->{exdb}->{ns_root_name} . $bname;
	#return ($inbrname, $exbrname);
	$exbrname = $inbrname
		? "$ns_root$clean_ubname"
		: '';
	return ($inbrname, $exbrname);
	#return ($inbrname, "$ns_root$clean_ubname");

	#my $homebase = basename($sh->{home}) || 'unknown';
	#my $who = $sh->{ruu}->{who};
	#for my $item ($bname, $homebase, $who) {
	#	$item =~ s/^[\W_]+//;	# drop leading and trailing non-word,
	#	$item =~ s/[\W_]+$//;	# non-_ characters from item name
	#}
}

# returns array ($inbrname, $exbrname) similar to str2brnames, which it
# calls, but with the empty string for any component that either
# str2brnames returned empty or that does NOT exist (or whose existence
# could not be verified, eg, because the external db wasn't available).
# NB: because MongoDB creates binders/collections simply be trying to
#     read from them, if "show collections" comes up with a default binder
#     name we'll just assume it is a binder that was NOT created by mkbinder
# yyy $mods currently unused

sub binder_exists { my( $sh, $mods, $binder, $bgroup, $user, $minderdir )=@_;
# ZZZZZZZZZZZZZZZZZZZZXXXXXX

	$binder =~ s|/$||;	# remove fiso_uname's trailing /, if any
	#$binder =~ /[\W]_/ and
	#	addmsg($sh, $binder .
	#		': binder name restricted to one or more ' .
	#		'letters, digits, and internal underscores'),
	#	return undef;
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($sh, $msg);	# failed to configure
		return undef;
	}

	my ($inbrname, $exbrname) =		# yyy not using $inbrname
		str2brnames($sh, $binder, $bgroup, $user);
		# yyy how should we contruct username-sensitive indbnames?
	if ($inbrname) {
		my $dirname = $binder;	# yyy assume it names a directory
		$minderdir ||= $sh->{minderhome};
		unless (file_name_is_absolute($dirname) or $minderdir eq ".") {
			$dirname = catfile(($minderdir || $sh->{minderhome}),
				$dirname);
		}
		# If here $dirname is a valid absolute or relative pathname.
		! -e $dirname and		# if it does NOT exist, then
			$inbrname = '';		# change to communicate that
	}

	# In the exdb case, check if collection list contains the name, for
	# if we attempt to open a non-existent mongo database, we inadvertently
	# create it.

	if ($exbrname) {
# the system.namespaces collection for {name : "dbname.analyticsCachedResult"}

my $NSNS = 'system.namespaces';	# namespace of all namespaces

		$exbrname =~ m/^([^.].*)\.(.+)/ or
			$msg = "exbrname \"$exbrname\" must be of the form " .
				"<database>.<collection>",
			return undef;
		my ($dbname, $collname) = ($1, $2);
#		my $db = $sh->{exdb}->{client}->get_database($dbname) or
#			$msg = "could not create database object from name " .
#				"\"$dbname\" (from exbrname \"$exbrname\")",
#			return undef;
		my ($db, $result, @collections);
		my $ok = try {				# exdb_get_dup
			$db = $sh->{exdb}->{client}->get_database($dbname);
			@collections = $db->collection_names;
#			my $nscoll = $sh->{exdb}->{client}->ns($NSNS);
#				# namespace namespace
#			$result = $nscoll->find_one(
#				{ name => $exbrname },	# query for binder name
#			$result = $nscoll->find(
#			)
#			// 0;		# 0 != undefined
		}
		catch {
#error: error looking up database name "egg_td_egg.jak_s_egg_td_egg"
#        (from exbrname "egg_td_egg.jak_s_egg_td_egg.jak_s_bar")
#error: brmgroup: not removing egg_td_egg.jak_s_bar
			$msg = "error looking up database name \"$dbname\" " .
				"(from exbrname \"$exbrname\")";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and 	# test for undefined since zero is ok
			addmsg($sh, $msg),
			return undef;
#say "xxx result=$result, exbrname=$exbrname";
#say "xxx collections=", join(', ', @collections);
		grep( { $_ eq $collname } @collections ) or
			$exbrname = '';	# set return name to empty string
	}
# xxx can drop $DEFAULT_BINDER_RE


#	if ($exbrname and $exbrname !~ $DEFAULT_BINDER_RE) {
#		my $bh = newnew($sh) or
#			addmsg($sh, "couldn't create binder handler"),
#			return undef;
#		if (ebopen( $bh, $exbrname )) {		# yyy other args unused
#			require EggNog::Egg;
#			my $rfs = EggNog::Egg::flex_enc_exdb("$A/", 'erc');
#			my @dups = EggNog::Egg::exdb_get_dup($bh,
#				$rfs->{id}, $rfs->{elems}->[0]);
#			#$ret = EggNog::Egg::exdb_find_one( $bh,
#			#	$sh->{exdb}->{binder}, "$A/");	# yyy no 'erc'?
#			#! $ret || ! $ret->{ "erc" } and	# not a binder
#			scalar(@dups) or
#				addmsg($sh, "$exbrname is a collection/table "
#					. "but does not appear to be a binder"),
#				$exbrname = '';		# then say so
#				# yyy maybe return set to undef ?
#			ebclose($bh);
#		}
#		else {
#			# yyy how often do we get here, given mongodb's
#			#     create-always policy?
#			$exbrname = '';		# ordinary non-existence
#		}
#	}
#	# else do nothing if $exbrname corresponds to a default binder for the
#	# binder group, which for mongodb we consider to _always_ exist

	return ($inbrname, $exbrname);
}

# Returns the fullpath uname of the created binder (which may have been
# generated and/or be in a $sh->{minderhome} unfamiliar to the caller),
# or "" if it already exists (from createbinder), or undef on error.
# In all cases, addmsg()
# will have been called to set an informational message.
#
# $tagdir must be specified: it should be a directory name (uname);
# return should be dirname picked for you xxxxxx?
# (might not be quite what you asked for if there's a conflict)

sub mkbinder { my( $sh, $mods, $binder, $bgroup, $user, $what, $minderdir )=@_;

	! $sh and
		return undef;
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($sh, $msg);	# failed to configure
		return undef;
	}
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;

	my ($inbrname, $exbrname) = str2brnames($sh, $binder, $bgroup, $user);

	# yyy ignore result for internal db, since binder_exists thinks there's
	#     a binder when the dir. was just snagged by gen_minder
	my ($indbexists, $exdbexists) =
		binder_exists($sh, $mods, $binder, $bgroup, $user, $minderdir);

	if ($sh->{exdb}) {
		$exdbexists and
			addmsg($sh, "exdb binder \"$exbrname\" already exists"),
			return undef;
		mkebinder($sh, $mods, $exbrname, $bgroup, $user,
				$what, $minderdir) or
			return undef;
	}
	if ($sh->{indb}) {
		#$indbexists and
		#	addmsg($sh, "indb binder \"$inbrname\" already exists"),
		#	return undef;
		mkibinder($sh, $mods, $inbrname, $bgroup, $user,
				$what, $minderdir) or
			return undef;
	}
	return 1;
}

sub mkebinder { my( $sh, $mods, $exbrname, $bgroup, $user, $what, $minderdir )=@_;

	# xxx should reconcile diffs between mk{e,i}binder
	! $sh and
		return undef;
	! $exbrname and
		addmsg($sh, 'external database name cannot be empty'),
		return undef;
		# yyy unlike indb case, where we generate a new binder name
		#     using prep_default_minder

	my $bh = newnew($sh) or
		addmsg($sh, "mkebinder couldn't create binder handler"),
		return undef;

#XXX; # modify the args below
# ZZZZZZZZZZZZZZZZZZZZXXXXXX
	! ebopen($bh, $exbrname, $EGG_DB_CREATE) and	# yyy some args unused
		addmsg($sh, "could not open external binder \"$exbrname\""),
		return undef;

	my $exdb = $sh->{exdb};
	! EggNog::Egg::exdb_set_dup( $bh, "$A/", "erc",
		    fiso_erc($sh->{ruu}, '', $what), { no_bcount => 1 } ) and
		addmsg($sh, "problem initializing binder \"$exbrname\""),
		return undef;

	# By setting that value, we can check a random MongoDB collection,
	# that might have been created by accident (eg, a typo). A later
	# test for this value can tell us if the collection was created
	# by mkebinder() or not.

	return 1;
}

sub mkibinder { my( $sh, $mods, $binder, $bgroup, $user, $what, $minderdir )=@_;

	#$bh->{fiso} and		# XXXXX why not? just close and re-open?
	#	addmsg($sh, "cannot make a new binder using an open handler " .
	#		"($bh->{fiso})"),
	#	return undef;

	# xxx should reconcile diffs between mk{e,i}binder
	unless ($binder) {
		#$binder = prep_default_binder($sh, 'i', (O_CREATE|O_RDWR),
		$binder = prep_default_binder($sh, 'i', (DB_CREATE | DB_RDWR),
			$sh->{minderpath});	# xxx why not just O_CREAT?
		$binder or
			addmsg($sh, "no binder specified and default failed"),
			return undef;
		return $binder;
	}

	$binder =~ s|/$||;	# remove fiso_uname's trailing /, if any

	my $om = $sh->{om};
	#my $contact = $sh->{ruu}->{contact};

	my $bh = newnew($sh) or		# newer Binder object maker
		addmsg($sh, "mkibinder couldn't create binder handler"),
		return undef;
	my $bdr = createbinder($bh, $binder, $minderdir);
	$bdr or
		addmsg($sh, getmsg($bh)),
		return undef;			# outmsg() tells reason

	$what ||= "arbitrary elements and values beneath identifiers";

	my $msg;
# XXX should record in txnlog
	#$msg = $bh->{rlog}->out("M: mkbinder $binder") and
	#	addmsg($sh, $msg),
	#	return undef;

	# iii=internal db assumed
	my $tagdir = fiso_uname($bdr);	# iii
	#my $v1bdb = $bh->{'v1bdb'};

	my $dbh = $bh->{tied_hash_ref};	# iii

	# jjj=internal file store assumed
	my $ret = pt_mktree($tagdir, "", \%o);	# jjj yyy no prefix, no options
	$ret and
		addmsg($sh,
			"couldn't create binder pairtree $tagdir: $o{msg}"
			. `ls $tagdir`
		),
		return undef;

	my ($v1bdb, $dbfile, $built, $running) =
		EggNog::Binder::get_dbversion();	# iii

	$dbh->{"$A/version"} = $VERSION;	# iii
	$dbh->{"$A/dbversion"} = "With Egg version $VERSION, " .   # iii
		#"Using DB_File version $dbfile, built with Berkeley DB " .
		"built with Berkeley DB " .
		"version $built, running with Berkeley DB version $running.";

	#my $erc = fiso_erc($sh->{ruu}, $tagdir, $what); # iii
	my $erc = fiso_erc($sh->{ruu}, $tagdir, $what); # iii
	# yyy add nfs warning to README file
	$noflock and				# global set inside dbopen
		# XXX should really get this next from msgs saved by addmsg()
		$erc .= qq@
Note:      $noflock@;
	$v1bdb and
		$erc .= "Note:  " . $EggNog::Binder::v1bdb_dup_warning;
		# XXX not proper ANVL (not ANVL line-wrapped)
	$dbh->{"$A/erc"} = $erc;	# iii

	my $readme = catfile( $tagdir, "$bh->{fname_pfix}README");	# iii
	#my $readme = catfile($tagdir, "$bh->{objname}.README");
	$msg = flvl(">$readme", $erc);	# iii
	$msg and
		addmsg($sh, "couldn't create binder README file: $msg"),
		return undef;	# not somehow as serious as a createbinder fail
	# yyy add namaste tag based on $erc
	my $report = "creating new binder ($binder)";
		#. qq@See $readme for details.\n@;

	if ($om) {
		# xxx think through what should really be reported in the
		#     normal non-verbose cases
		#$om->elem("dbreport", $report);
		#$msg = outmsg($sh)	and $om->elem("warning", $msg);
		#outmsg($sh, $om);	# if any messages, output them
		outmsg($sh);		# if any messages, output them
		# XXX fix temper string! to be even temper
	}

	return $bdr;		# return name of the new binder
}

# Returns actual path (relative or absolute) to uname of the created
# minder (which may have been
# generated and/or be in a $bh->{minderhome} unfamiliar to the caller),
# or "" if it already exists yyy?, or undef on error.  In all cases, addmsg()
# will have been called to set an informational message.  The $minderhome
# argument is optional.
# Set $minderhome to "." to _not_ use default minderhome (eg, when
# "bind -d ..." was used), else leave empty.

# Protocol:  call EggNog::Egg->new to make a fresh $bh before mkminter/mkbinder,
#            which checks to make sure the input $bh isn't already open
#            returns the $bh still open (as most method calls do).  In
#            other words, don't call mkminter/mkbinder on an $bh that
#            you just finished minting or binding on.
# yyy should omclose($bh) close and destroy?  yes??
# yyy could we use a user-level omclose for bulkcmds?
#            $bh=EggNog::Egg->new(); mkminter/mkbinder($bh); omclose($bh);
# 		then $bh->DESTROY;?
#    (need way to clone parts of $bh in creating $submh )
#
sub createbinder { my( $bh, $dirname, $minderdir )=@_;

	my $hname = 'binder';
	my $oname = FS_OBJECT_TYPE;
	# yyy isn't $dirname more a minder name than a "directory" name?
	# yyy what if $dirname is empty or null?  We don't check!

	# If path is not absolute, we may need to prepend.  Don't prepend
	# if caller gave $minderdir as "." (not necessary, not portable),
	# but do prepend default if $minderdir is empty (but don't check
	# if caller's default was, eg, ".").
	# 
	#print "xxx before unless dirname=$dirname, minderdir=$minderdir\n";
	#$minderdir ||= "";
	$minderdir ||= $bh->{minderhome};
	# xxx what does file_name_is_absolute do with empty $dirname?
	unless (file_name_is_absolute($dirname) or $minderdir eq ".") {
	  #print "xxx in unless minderdir=$minderdir, $bh->{minderhome}\n";
		$dirname = catfile(($minderdir || $bh->{minderhome}),
			$dirname);
	}
	# If here $dirname should be a valid absolute or relative pathname.
	#print "xxx after unless dirname=$dirname\n";

	my $ok = -1;		# hopefully harmless default
	my $msg;
	# -e '' should evaluate to false
	! -e $dirname and
		$ok = try {
			mkpath($dirname);
			#$ret = mkpath($dirname)
		}
		catch {			# ?not sure when this happens
			$msg = "couldn't create $dirname: $!";
			return undef;
		};
	! defined($ok) and
		addmsg($bh, $msg),
		return '';
	-d $dirname or		# error very unlikely here
		addmsg($bh, "$dirname already exists and isn't a directory"),
		return undef;

	#if ($bh->{type} eq ND_MINTER) { # yyy temp support for old dbname
	#}
	#elsif ($bh->{type} eq ND_BINDER) { # yyy support for [es]db types
	#}
	# yyy use fiso_dname?
	my $dbname = catfile($dirname, FS_DB_NAME);
	-e $dbname and
		addmsg($bh, "$dbname: $hname data directory already exists"),
		return undef;
	# yyy how come tie doesn't complain if it exists already?

	# Call ibopen() without minderpath because we don't want search.
	#
	ibopen($bh, $dbname, DB_CREATE|DB_RDWR) or
	#ibopen($bh, $dbname, O_CREAT|O_RDWR) or
	#ibopen($bh, $dbname, (O_CREAT|O_RDWR), $bh->{minderpath}) or
		addmsg($bh, "can't create database file: $!"),
		return undef;

	# Create lockfile.
	my $lockfile = catfile( $bh->{dbhome}, "$bh->{fname_pfix}lock" );
	! sysopen(MINDLOCK, $lockfile, O_RDWR | O_CREAT) and
		addmsg($bh, "cannot create \"$lockfile\": $!"),
		return undef;

	# Finally, declare the Namaste directory type.
	#
	$msg = File::Namaste::nam_add($dirname, undef, '0',
		$oname . "_$VERSION", length($oname . "_$VERSION"));
		# xxx get Namaste 0.261.0 or better to permit 0 to mean
		#   "don't truncate" as final argument
		# xxx add erc-type namaste tags too
	$msg and
		#dbclose($bh),
		# XXX call destroy/close !
		addmsg($bh, "couldn't create namaste tag in $dirname: $msg"),
		return undef;

	close(MINDLOCK);	# didn't really need lock in the first place?
	return $dbname;
	#return 1;
}

# yyy only using $sh and $binder
# yyy bails early unless we're in the exdb case

sub brmgroup { my( $sh, $mods, $bgroup, $user )=@_;

	! $sh and
		return undef;
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;
	! $bgroup and
		addmsg($sh, "no binder group specified"),
		return undef;
	# yyy should we check if $bgroup matches $sh->{bgroup} ?
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($sh, $msg);	# failed to configure
		return undef;
	}
	! $sh->{exdb} and		# yyy only works for exdb case
		return 1;
	if ($sh->{opt}->{allb} || $sh->{opt}->{allc}) {
		addmsg($sh, "--allb or --allc option not allowed");
		return undef;
	}
	my @ebinders = ebshow($sh, $mods, 0, $bgroup, $user);

	# empty return list is ok
	@ebinders and ! defined($ebinders[0]) and	# our test for error
		addmsg($sh, 'brmgroup: ebshow failed'),
		return undef,
	;
	# yyy bug: brmgroup won't remove any internal binders
	my ($inbrname, $exbrname, $rootless);	# yyy $inbrname unused

	my $errs = 0;				# don't make errors fatal
	my $binder_root_name = $sh->{exdb}->{binder_root_name};
	for my $b (@ebinders) { 
		# yyy should we call rmebinder($sh, $mods, $exbrname,
		# $bgroup, $user)?
		#     we don't because that would fail on internal dbs at
		#     the moment
		# yyy ignore result for internal db, since binder_exists doesn't
		#     look in @$minderpath yyy this is too complicated
		# Need this next test because a collection that's listed
		# might not actually be an eggnog binder.

		# Take fully qualified binder name and convert to simple name
		# name as user knows it, eg, egg_td_egg.sam_s_foo -> foo
		# Use $rootless to hold that simple binder name.

		($rootless = $b) =~ s/^[^.]+.\Q$binder_root_name//;
		my ($indbexists, $exdbexists) =
# ZZZZZZZZZZZZZZZZZZZZXXXXXX
			binder_exists($sh, $mods, $rootless, $bgroup,
				$user, undef);
#error: error looking up database name "egg_td_egg.jak_s_egg_td_egg"
#        (from exbrname "egg_td_egg.jak_s_egg_td_egg.jak_s_bar")
#error: brmgroup: not removing egg_td_egg.jak_s_bar
		($inbrname, $exbrname) =
			str2brnames($sh, $rootless, $bgroup, $user);
		! $exdbexists and ! $sh->{opt}->{force} and
			addmsg($sh, "brmgroup: not removing $rootless"),
			$errs++,
			next,
		;
		rmebinder($sh, $mods, $exbrname, $bgroup, $user) or
			addmsg($sh, "brmgroup: error removing binder $rootless "
				. "($exbrname)"),
			$errs++,
		;
	}
	$errs and
		return undef;
	return 1;
}

# called by remove_td() and remake_td() in test scripts with no active session
# return message on error, or '' on success

sub brmgroup_standalone { my( $bgroup )=@_;

# xxx require instead of use?
# yyy test database instead of egg_eggnog? eg, egg_td_egnapa
	use EggNog::Session;
	my $sh = EggNog::Session->new(0) or
		return "couldn't create session handler";
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;
	my $msg;
	$msg = EggNog::Session::config($sh) and
		return $msg;
	brmgroup($sh, undef, $bgroup) or
		return outmsg($sh);
	return '';
	# $sh session object destroyed on return
}

sub rmbinder { my( $sh, $mods, $binder, $bgroup, $user, $minderpath )=@_;

	! $sh and
		return undef;
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($sh, $msg);	# failed to configure
		return undef;
	}
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;

	my ($inbrname, $exbrname) = str2brnames($sh, $binder, $bgroup, $user);

	# yyy ignore result for internal db, since binder_exists doesn't
	#     look in @$minderpath yyy this is too complicated
	my ($indbexists, $exdbexists) =
		binder_exists($sh, $mods, $binder, $bgroup, $user, undef);

	if ($sh->{exdb}) {
		$binder =~ s|/$||;	# remove fiso_uname's trailing /, if any
		! $binder and
			addmsg($sh, "no binder specified"),
			return undef;
		my $dflt_binder = ($exbrname and
			$exbrname =~ $DEFAULT_BINDER_RE);
		! $exdbexists and ! $sh->{opt}->{force} and ! $dflt_binder and
			addmsg($sh,
				"external binder \"$exbrname\" doesn't exist"),
			return undef;
		rmebinder($sh, $mods, $exbrname, $bgroup, $user) or
			return undef;
	}
	if ($sh->{indb}) {
		# yyy this test won't work: ! $indbexists and ...
		rmibinder($sh, $mods, $binder, $bgroup, $user, $minderpath) or
			return undef;
	}
	return 1;
}

# assume existence check and call to str2brnames were already done by caller
sub rmebinder { my( $sh, $mods, $exbrname, $bgroup, $user )=@_;

	! $exbrname and
		addmsg($sh, "no binder specified"),
		return undef;
	my $exdb = $sh->{exdb};
	my $msg;
	my $ok = try {
		# yyy not an error if it doesn't exist?
		$exdb->{client}->ns($exbrname)->drop;
		return 1;		# since drop doesn't return "ok"
	}
	catch {
		$msg =	"problem removing external binder: " . $_ .
			"; connect_string=$exdb->{connect_string}, " .
			"exdbname=$exbrname";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and
		addmsg($sh, $msg),
		return undef;
	return 1;
}

sub rmibinder { my( $sh, $mods, $mdr, $bgroup, $user, $minderpath )=@_;

	! $sh and
		return undef;
	my $om = $sh->{om};

	! $mdr and
		addmsg($sh, "no binder specified"),
		return undef;
	# xxx use fiso_uname globally?
	$mdr =~ s|/$||;		# remove fiso_uname's trailing /, if any

	# xxx test that input $mdr can be a dname or a uname
	my $mdrd = fiso_dname($mdr, FS_DB_NAME);
	my $mdru = fiso_uname($mdrd);

	# Use first minder instance [0], if any, or the empty string.
	# xxx document --force causes silent consent to no minder
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";
	$mdrfile or
		addmsg($sh, "$mdr: no such binder exists (mdrd=$mdrd)"),
		return ($sh->{opt}->{force} ? 1 : undef);

	# XXX add check to make sure that found minder is of the right
	#     type; don't want to remove a minter if we're 'bind'

	# If we get here, the minder to remove exists, and its containing
	# directory is $mdrdir.
	#
	my $mdrdir = fiso_uname($mdrfile);
# xxx txnlog
	#$bh->{rlog} = EggNog::Rlog->new(		# log this important event
	#	catfile($mdrdir, FS_OBJECT_TYPE), {
	#		preamble => $sh->{opt}->{rlog_preamble},
	#		header => $sh->{opt}->{rlog_header},
	#	}
	#);

	#$msg = $bh->{rlog}->out("M: $lcmd $mdrdir") and
	#	addmsg($sh, $msg),
	#	return undef;
	
	# We remove (rather than rename) in two cases: (a) if the minder
	# is already in the trash or (b) if caller defines (deliberately
	# one hopes) $sh->trashers to be empty.  xxx DOCUMENT!
	# xxx make this available via --notrash noid/bind option
	#
	my $msg;
	my $trashd = catfile($sh->{minderhome}, $sh->{trashers});
	# xxx we don't really want regexp match, we want literal match
	if (! $sh->{trashers} or $mdrdir =~ m|$trashd|) {
		my $ret;
		my $ok = try {
			$ret = rmtree($mdrdir)
		}
		catch {
			$msg = "couldn't remove $mdrdir tree: $_";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and
			addmsg($sh, $msg),
			return undef;
		$ret == 0 and
			addmsg($sh, ("$mdrdir " . (-e $mdrdir ?
				"not removed" : "doesn't exist")),
				"warning"),
			return undef;		# soft failure? yyy
		$om and
			$om->elem("note", "removed '$mdr' from trash");
		return 1;
	}

# xxx txnlog
	#$msg = $bh->{rlog}->out("N: will try to move $mdr to $trashd") and
	#	addmsg($sh, $msg);		# not a fatal error

	# We now want a unique name to rename it to in the trash directory.
	# But first create the trash directory if it doesn't yet exist.
	# Since the minter name itself may be a path, we have to figure out
	# what its immediate parent is.
	#
	my $fullpath = catfile($trashd, $mdru);
	my ($volume, $mdrparent, $file) = File::Spec->splitpath($fullpath);
	unless (-d $mdrparent) {
		my ($ret, $msg);
		my $ok = try {
			$ret = mkpath($mdrparent)
		}
		catch {
			$msg = "couldn't create trash ($mdrparent): $_";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and
			addmsg($sh, $msg),
			return undef;
		$ret == 0 and
			addmsg($sh, (-e $mdrparent ?
			    "$mdrparent already exists but isn't a directory"
			    : "mkpath returned '0' for $mdrparent")),
			return undef;
	}

# xxx make snag_dir do versions automatically
# xxx change test to not look for foo1 the first time, just foo
# XXXXXX add? mkpath functionality to snag???
	my ($n, $trashmdr) = File::Value::snag_version(
		$fullpath, { as_dir => 1 });
	$n < 0 and			# on error, $trashmdr holds a message
		addmsg($sh, "problem creating backup directory: " .
			$fullpath . ": $trashmdr"),
		return undef;

	# Quick and dirty: the name we snagged is what we want, but we
	# take a tiny chance by rmdir'ing it so that we can rename the
	# minder in one fell swoop rather than renaming each subfile.
	# yyy what if minder is multi-typed? does removing a minter also
	#     remove a co-located binder?
	#
	rmdir($trashmdr) or
		addmsg($sh, "problem removing (before moving) $mdrdir: $!"),
		return undef;
	mv($mdrdir, $trashmdr) or
		addmsg($sh, "problem renaming $mdrdir: $!"),
		return undef;

	$om and
		$om->elem("note", "moved '$mdr' to trash ($trashmdr)");
	return 1;
	# XXX should log this event!
	# xxx need to tell $caster to unhold (??) the shoulder
}

# Create a closure to hold a stateful node-visiting subroutine and other
# options suitable to be passed as the options parameter to File::Find.
# Returns the small hash { 'wanted' => $visitor, 'follow' => 1 } and a
# subroutine $visit_over that can be called to summarize the visit.
#
sub make_visitor { my( $sh, $symlinks_followed, $om )=@_;

# xxx add ability to return array instead of output
	$sh		or return undef;
	$om //= $sh->{om};
	#$om or
	#	addmsg($sh, "no 'om' output defined"),
	#	return undef;
	my $hname = 'binder';
	my $oname = FS_OBJECT_TYPE;
	#my $oname = $sh->{objname};

	my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $sze);
	my $filecount = 0;		# number of files encountered yyy
	my $symlinkcount = 0;		# number of symlinks encountered yyy
	my $othercount = 0;		# number of other encountered yyy
	my ($return_summary, $pdname, $wpname, %h);

    my $visitor = sub {		# receives no args from File::Find

	$pdname = $File::Find::dir;	# current parent dir name
					# $_ is file in that dir
	$wpname = $File::Find::name;	# whole pathname to file

	# We always need lstat() info on the current node XXX why?
	# yyy tells us all, but if following symlinks the lstat is done
	# ... by find:  use (-X _), but of the nifty facts below we
	# still need to harvest the size ($sze) by hand.
	#
	($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $sze) = lstat($_)
		unless ($symlinks_followed and ($sze = -s _));

	# If we follow symlinks (usual), we have to expect the -l type,
	# which hides the type of the link target (what we really want).
	#
	if (! $Win and -l _) {
		$symlinkcount++;
		# yyy presumably this branch never happens when
		#     _not_ following links?
		($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $sze)
			= stat($_);		# get the real thing
	}
	# After this, tests of the form (-X _) give almost everything.

	-f $_ or			# we're only interested in files
		$othercount++,
		return;

	$filecount++;
	#m@^0=([^_]+)(_[\d._]*)?$@o and
	m|^0=$oname\W?|o and		# yyy relies on Namaste tag
		#print($pdname, "\n"),	# yyy why not use $om?
		($om && $om->elem('b', $pdname)),
		$h{$oname} = $wpname,	# yyy unused right now
	1
	or m|^noid.bdb$|o and		# old version of noid up to v0.424
		($om && $om->elem('b', "$pdname (classic noid $hname)")),
		$h{classic} = $wpname,	# yyy unused right now
	;
    };

    my $visit_over = sub { my( $ret )=@_;

	$ret ||= 0;
	$om and $om->elem("summary",
		" (processed $filecount files, $othercount other)", '1#');
	#$om->elem("summary", " (processed $ret, " .
	#	"$filecount files, $othercount other)", '1#');
	return ($filecount, $othercount);	# returns two-element array

    };

    	return ({ 'wanted' => $visitor, 'follow' => $symlinks_followed },
		$visit_over);
}

# NB: unlike ebshow, this does NOT return a list of binders (print only)
# yyy convert to use $om
# yyy doesn't yet use or honor $bgroup or $user

sub ibshow { my( $sh, $mods, $om )=@_;	# internal db version of bshow

	defined($Win) or	# if we're on a Windows platform avoid -l
		$Win = grep(/Win32|OS2/i, @File::Spec::ISA);

	# yyy check that minderpath itself is sensible, eg, warn if its
	#     undefined or contains repeated or occluding minders
	# yyy warn if a minder is occluded by another
	# yyy multi-type minders?
	# yyy add 'long' option that checks for every important file, eg,
	#     minder.{bdb,log,lock,README} and 0=minder_...

	$om //= $sh->{om};
	my ($find_opts, $visit_over) = make_visitor($sh, 1, $om);
	$find_opts or
		addmsg($sh, "make_visitor() failed"),
		return undef;
	$om and $om->elem('note',
		' Internal binders found via minderpath ('
			. join(':', @{$sh->{minderpath}}) . ')', '1#');
	my $ret = find($find_opts, @{ $sh->{minderpath} });
	$visit_over and
		$ret = &$visit_over($ret);
	return $ret;
}

# external db bshow
# returns a list of fully qualified binder names on success, (undef) on error
# NB: the returned list is used directly by td_remove()
# $om == 0 (zero) means just return list and don't do output
# first get list of collections, later filter by $bgroup and $user
# yyy ?add 'long' option that checks for every important file, eg,
#     minder.{bdb,log,lock,README} and 0=minder_...

sub ebshow { my( $sh, $mods, $om, $bgroup, $user, $ubname )=@_;

	my $exdb = $sh->{exdb};
	my ($edatabase_name, $ebinder_root_name, $ns_root_name, $clean_ubname) =
		EggNog::Session::ebinder_names($sh, $bgroup, $user, $ubname);
	my ($msg, $db, @cns);
	my $ok = try {
		# get all database names
		for my $dbname ( $exdb->{client}->database_names ) {
			$db = $exdb->{client}->db( $dbname );
			# for each dbname, get all collection names
			#push @cns, $db->collection_names;
			push @cns, map "$dbname.$_", $db->collection_names;
		}
		#$db = $exdb->{client}->db( $edatabase_name );
		#@cns = $db->collection_names;
		1;		# else empty list would look like an error
	}
	catch {
		$msg = "list external binders failed: $_";
		return undef;	# returns from "catch", NOT from routine
	};
	! defined($ok) and
		addmsg($sh, $msg),
		return (undef);
	$om //= $sh->{om};

	#my $root_re = $sh->{opt}->{all} ? qr// :	# pass everything
	#	qr/^\Q$exdb->{binder_root_name}/;	# or just mine

	# xxx document these --allb and --allc options
	my $root_re =
		$sh->{opt}->{allc} ? qr// :	# do all collections if --allc,
		($sh->{opt}->{allb} ?		# else if --allb just do what
			qr/^\Q$EGGBRAND/ :	# looks like a binder
						# else just do my binders
			qr/^\Q$edatabase_name.$ebinder_root_name$clean_ubname/)
	;

	my @ret_binders = sort			# return sorted results of
			grep m/$root_re/,	# filtering binder names
		@cns;				# from collection names
	! $om and			# if $om == 0, suppress output
		return @ret_binders;		# yyy is there a better way?

	# if we get here we're doing output
	$om->elem('note', ' ' . scalar(@ret_binders) . ' ' .
		($sh->{opt}->{allc} ? "external collections" :
		($sh->{opt}->{allb} ? "external binders under $EGGBRAND" :
			"external binders under $edatabase_name." .
				"$ebinder_root_name$clean_ubname")),
		'1#'
	);
	map $om->elem('b', $_), @ret_binders;
	#map $om->elem('b', "$edatabase_name.$_"), @ret_binders;
	return @ret_binders;
}

# Show binders, in particular, show
#  - internal binders found under $sh's minderpath.
#  - external binders found under the given (or default) bindergroup
# yyy $mods not used
# yyy to rename, make these synonyms: bmake = mkbinder, brm = rmbinder,
#     in later release, remove old names

sub bshow { my( $sh, $mods, $om, $bgroup, $user, $ubname )=@_;

	! $sh and
		return undef;
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($sh, $msg);	# failed to configure
		return undef;
	}
	my @ret;
	$sh->{exdb} and
		# ebshow indicates error by returning 1-element list: (undef)
		(@ret = ebshow($sh, $mods, $om, $bgroup, $user, $ubname)),
		(@ret and ! defined($ret[0]) and return undef),
	;
	$sh->{indb} and
		# doesn't use $bgroup or $user
		ibshow($sh, $mods, $om) || return undef,
	;
	return 1;
}

# XXXXX rethink this in light of doing a .conf file
#       A .conf file is slower, but much easier to manipulate, and we need
#          it anyway for permissions and authz users and on_bind settings
#          which are dumb to put into the bdb file
#
# return human readable word representing minder status
# first arg is pointer to tied hash ref
# optional second argument sets status

sub minder_status { my( $dbh, $status )=@_;

	my $cur_status;
	if ($status) {		# if a proposed new status was specified
		$status !~ m/^[edrs]$/	and return
			("'$status' is not a valid status; use one of <edrs>");
	# XXXX!!! check $dbh->{authz} to see if authorized!
		$dbh->{"$A/status"} eq 's'	and return
			("cannot change status of a 'shoulderonly' minter");
		delete($dbh->{"$A/status"});	# precaution if dups enabled
		$dbh->{"$A/status"} = $status;
	}
	$cur_status = $dbh->{"$A/status"};
	return
		# yyy use numeric constants?
		($cur_status eq 'e' ?	'enabled' :
		($cur_status eq 'd' ?	'disabled' :
		($cur_status eq 'r' ?	'readonly' :
		($cur_status eq 's' ?	'shoulderonly' :
					'unknown' ))));
}

# yyy not currently using $mods
# yyy rename bstat(us)
sub mstatus { my( $bh, $mods, $status )=@_;

	! $bh and
		return undef;
	my $sh = $bh->{sh} or
		return undef;
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;
	#my $msg;
	#if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
	#	addmsg($bh, $msg);	# failed to configure
	#	return undef;
	#}

	return minder_status($bh->{tied_hash_ref}, $status);
}

=for mining

# # xxx Noid version needs work!
# # Report values according to $level.  Values of $level:
# # "brief" (default)	user vals and interesting admin vals
# # "full"		user vals and all admin vals
# # "dump"		all vals, including all identifier bindings
# #
# # yyy should use OM better
# sub dbinfo { my( $bh, $level )=@_;
# 
# 	my $noid = $bh->{tied_hash_ref};
# 	my $db = $bh->{db};
# 	my $om = $bh->{om};
# 	my ($key, $value) = ("$A/", 0);
# 
# 	if ($level eq "dump") {		# take care of "dump" and return
# 		#print "$key: $value\n"
# 		$om->elem($key, $value)
# 			while ($cursor->c_get($key, $value, DB_NEXT) == 0);
# 			#while ($db->seq($key, $value, R_NEXT) == 0);
# 		return 0;
# 	}
# 	# If we get here, $level is "brief" or "full".
# 
# 	#my $status = $db->seq($key, $value, R_CURSOR);
# 	my $cursor = $db->db_cursor();
# 	my $status = $cursor->c_get($key, $value, DB_SET_RANGE);
# # don't forget to close cursor!
# #$cursor->c_close();
# #undef($cursor);
# 	if ($status) {
# 		addmsg($bh, "seq status/errno ($status/$!)");
# 		return 1;
# 	}
# 	if ($key =~ m|^$A/$A/|) {
# 		#print "User Assigned Values\n";
# 		$om->elem("Begin User Assigned Values", "");
# 		#print "  $key: $value\n";
# 		$om->elem($key, $value);
# 		#while ($db->seq($key, $value, R_NEXT) == 0) {
# 		while ($cursor->c_get($key, $value, DB_NEXT) == 0) {
# 			last
# 				if ($key !~ m|^$A/$A/|);
# 			#print "  $key: $value\n";
# 			$om->elem($key, $value);
# 		}
# 		#print "\n";
# 		$om->elem("End User Assigned Values", "");
# 	}
# 	#print "Admin Values\n";
# 	$om->elem("Begin Admin Values", "");
# 	#print "  $key: $value\n";
# 	$om->elem($key, $value);	# one-off from last test
# 	#while ($db->seq($key, $value, R_NEXT) == 0) {
# 	while ($cursor->c_get($key, $value, DB_NEXT) == 0) {
# 		last
# 			if ($key !~ m|^$A/|);
# 		#print "  $key: $value\n"
# 		$om->elem($key, $value)
# 			if ($level eq "full" or
# 				# $key !~ m|^$A/c\d| &&	# old circ status
# 				$key !~ m|^$A/saclist| &&
# 				$key !~ m|^$A/recycle/|);
# 	}
# 	$level eq "full" and
# 		#print durability(
# 		$om->elem("durability", durability(
# 			$$noid{"$A/shoulder"},
# 			$$noid{"$A/mask"},
# 			$$noid{"$A/generator_type"},
# 			$$noid{"$A/addcheckchar"},
# 			$$noid{"$A/atlast"} =~ /^wrap/		));
# 			#, "\n";
# 	$om->elem("End Admin Values", "");
# 	#print "\n";
# 	return 0;
# }

=cut

# Get/create minder when none supplied.  In case 1 (! O_CREAT) select the
# defined default.  In case 2 (O_CREAT), select the defined default only
# if it doesn't already exist, otherwise generate a new minder name using
# snag or (if minder is a minter) the 'caster' minter, but create the
# caster minter first if need be.
#
# yyy $mindergen is unused

sub prep_default_binder { my( $sh, $ie, $flags, $minderpath, $mindergen )=@_;
	# xxx not yet using $ie (one of 'i' or 'e')!

	defined($flags)		or $flags = 0;
	my $om = $sh->{om};

	my $mdr = $DEFAULT_BINDER;
	$mdr or
		addmsg($sh, "no known default binder"),
		return undef;
	my $mdrd = fiso_dname($mdr, FS_DB_NAME);

	# Use first minder instance [0], if any, or the empty string..
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";

	unless ($mdrfile) {	# if the hardwired default doesn't exist

		my $mtype = $sh->{type} || ND_BINDER;	# yyy drop?
		my $opt = $mtype eq ND_MINTER ?  $implicit_minter_opt : {};
		$opt->{rlog_preamble} = $sh->{opt}->{rlog_preamble};
		$opt->{om_formal} = $sh->{om_formal};
		$opt->{version} = $sh->{version};
			# XXX this probably corrupts $implicit_minter_opt
			#     should make copy instead of using directly

		# New $submh is auto-destroyed when we leave this scope.
		#
		#my $submh = EggNog::Binder->new($bh->{sh}, $mtype,
# xxx change $bh to $sh in this routine, eg, next line!
		my $submh = EggNog::Binder->new($sh, $mtype,
			$sh->{WeAreOnWeb}, $om, $opt);
			# xxx {om} ?? logging?
		$submh or
			addmsg($sh, "couldn't create caster handler"),
			return undef;
		my $dbname = $mtype eq ND_MINTER ?
			EggNog::Nog::mkminter($submh, undef, $mdr,
				$sh->{default_template}, $sh->{minderhome})
			:
# XXX NO:should there be an exdb case for this?
			mkibinder($submh, undef, $mdr, undef, undef,
				"default binder", $sh->{minderhome});
		$dbname or
			addmsg($sh, getmsg($submh)),
			addmsg($sh, "couldn't create default binder ($mdr)"),
			return undef;

		# If we get here, the default minder is being created to
		# satisfy a request either to make a minder or to use one.
		# Either way, we just satisified the request.
		#
		$sh->{opt}->{verbose} and $om and
			$om->elem("note", "creating default binder ($mdr)");
		# XXXX maybe this needs to make noise when we create
		#      a minter with no arg given
		return $mdr;
	}
	#xxxx   how do we conduct createbinder calls then other calls in a
	#       bulkcommand context on the same $sh?  Does it make sense?

	# If we're here, the default minder already existed.  If we weren't
	# asked to create a minder, we can just return the default minder,
	# otherwise we have to generate a minder.
	#
	#$flags & O_CREAT and
	$flags & DB_CREATE and
		return gen_minder($sh, $minderpath);
	return $mdr;
}

sub gen_minder { my( $sh, $minderpath )=@_;

	# If we're here, we need to generate a new minder name and then
	# create the new minder.  How we generate depends on the minder
	# type.  We either "snag" a higher version of the name or, for a
	# minter, we mint (cast, as in "cast a die, which is used to
	# mint") a new shoulder.
	#
	my $mdr;
	my $om = $sh->{om};
	my $mtype = $sh->{type} || ND_BINDER;
	if ($mtype ne ND_MINTER) {
	#if ($bh->{type} ne ND_MINTER) {
		my ($n, $msg) = File::Value::snag_version(
			#catfile($bh->{minderhome}, $bh->{default_minder}),
			catfile($sh->{minderhome}, $DEFAULT_BINDER),
				{ as_dir => 1 });
		$n < 0 and
			addmsg($sh, "problem generating new binder name: " .
				$msg),
			return undef;
		$mdr = $DEFAULT_BINDER;
		# yyy drop default_minder attribute?
		#$mdr = $bh->{default_minder};
		$mdr =~ s/\d+$/$n/;	# xxx assumes it ends in a number
		# xxx shouldn't we be using name returned in $msg?
		# XXX this _assumes_ only other type is ND_BINDER!!
		my $dbname = mkibinder($sh, undef, $mdr, undef, undef,
			"Auto-generated binder", $sh->{minderhome});
		$dbname or
			addmsg($sh, "couldn't create snagged name ($mdr)"),
			return undef;
		return $mdr;
	}

# xxx reserve df5 for the minter co-located with a binder (df4 as normal
#     default)
	# If we're here, the unnamed minder we're to create is a minter
	# and we need to generate its name.  To create a minter we must
	# mint a die ("cast a die") using a special minter we call a
	# "caster".  The caster creates a unique shoulder that we can use
	# as the name of the minder we're to create.  If the caster doesn't
	# exist yet, we must first create it.
	# 

	# New $cmh (caster binder handler) is auto-destroyed when we leave
	# scope of this routine.
	# We use some of the old handler's values to initialize.
	#
	my $c_opt = $implicit_caster_opt;
	$c_opt->{rlog_preamble} = $sh->{opt}->{rlog_preamble};
	#$c_opt->{version} = $bh->{opt}->{version};
		# XXX this probably corrupts $implicit_caster_opt
	#my $cmh = EggNog::Binder->new($bh->{sh}, ND_MINTER, 
	my $cmh = EggNog::Binder->new($sh, ND_MINTER, 
		$sh->{WeAreOnWeb},
		File::OM->new("anvl"),	# default om has no outputs for
					# next implicit mkminter operation
		$sh->{minderpath}, $c_opt);
		# xxx {om} ?? logging?
	$cmh or
		addmsg($sh, "couldn't create caster handler"),
		return undef;

	# yyy assume this caster thing itself is of type minter
	#$mdr = $bh->{caster};
	$mdr = "caster";
	my $mdrd = fiso_dname($mdr, $nogbdb);
	#my $mdrfile = find_minder($minderpath, $mdrd);	# find the caster

	# Use first minder instance [0], if any, or the empty string.
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";

	if ($mdrfile) {			# yyy inelegant use of $mdrfile
		#ibopen($cmh, $mdr, O_RDWR, $minderpath) or
		ibopen($cmh, $mdr, DB_RDWR, $minderpath) or
		return undef;
	}
	else {	# else it looks like we need to create caster first
		# Output messages from implicit mkminter and hold
		# operations are mostly suppressed.
		# 
		my $dbname = EggNog::Nog::mkminter($cmh, undef, $mdr,
				$implicit_caster_template, $sh->{minderhome});
		$dbname or
			addmsg($sh, getmsg $cmh),
			addmsg($sh, "couldn't create caster ($mdr)"),
			return undef;
		EggNog::Nog::hold($cmh, undef, "hold", "set",
				@implicit_caster_except) or
			addmsg($sh,
				"couldn't reserve caster exceptions ($mdr)"),
			return undef;
	}

	# If we get here, we have an open caster.  Now use it.
	#
	$mdr = cast($cmh, $sh->{minderpath});
	$mdr or
		addmsg($sh, getmsg($cmh)),
		return undef;
	$om and
		$om->elem("note", "creating new minter ($mdr)");

	# If we get here, we have a new unique shoulder string, and now
	# we create its corresponding minter using a new $submh (sub
	# binder handler) that is auto-destroyed when we leave the scope
	# of this routine.
	#
	my $opt = $implicit_minter_opt;
	$opt->{rlog_preamble} = $sh->{opt}->{rlog_preamble};
		# XXX this probably corrupts $implicit_minter_opt
	#my $submh = EggNog::Binder->new($bh->{sh}, ND_MINTER, 
	my $submh = EggNog::Binder->new($sh, ND_MINTER, 
		$sh->{WeAreOnWeb},
		File::OM->new("anvl"),	# default om has no outputs for
					# next implicit mkminter operation
		$sh->{minderpath}, $opt);
		# xxx {om} ?? logging?
	$submh or
		addmsg($sh, "couldn't create handler for newly cast shoulder"),
		return undef;
	my $dbname = EggNog::Nog::mkminter($submh, undef, $mdr, $mdr . $implicit_minter_template,
	# XXXXX should handle defaults via variables?
		$sh->{minderhome});
	$dbname or
		addmsg($sh,
			"couldn't create minter for generated shoulder ($mdr)"),
		return undef;

	return $mdr;
}

# Assume $bh is open, mint a minder name that doesn't exist.
#
sub cast { my( $bh, $minderpath )=@_;

	my $mdr;		# generated minder name
	my ($max_tries, $n) = (10, 1);
	while ($n++ < $max_tries) {
		($mdr, undef, undef) = EggNog::Nog::mint($bh, undef, 'cast');
		defined($mdr) or
			addmsg($bh, "ran out of shoulders!?"),
			return undef;
		# Normally we're done after one minting attempt.
		my $mdrd = fiso_dname($mdr, $nogbdb);
		# Use first minder instance [0], if any, or the empty string.
		my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";
		$mdrfile or
			last;

		#find_minder($minderpath, fiso_dname($mdr, $nogbdb)) or
		#	last;
		# If we get here, we minted something that exists already,
		# so try again.
	}
	$n >= $max_tries and
		addmsg($bh, "Giving up after $n tries to make new minter name"),
		return undef;

	return $mdr;
}

# call with which_minder($cmdr, $bh->{minderpath})
# yyy this wants to use the same algorithm as ibopen follows
sub which_minder { my( $cmdr, $path )=@_;

	my $mdrfile = fiso_uname(	# use the minder's enclosing directory
		(exists_in_path(	# where minder file was found in path
			fiso_dname($cmdr), $path ))	# file is dname
			[0]		# 0 means take just the first found
	);
	chop $mdrfile;			# chop off separator ('/' or '\')
	return $mdrfile;
}

# xxx move this to File::Value
# xxx maybe call this: exists_or_is_in_path()
# Return a list, possibly empty, of all instances where the file or
# directory argument $fd exists in array argument @$path.  If $fd is
# absolute or if $path is empty, just return ($fd) if $fd passes a
# simple -e test.
#
sub exists_in_path { my( $fd, $path )=@_;

	$fd		or return ();		# an empty $fd doesn't exist
	file_name_is_absolute($fd) ||		# if $fd is absolute name
			! $path and		# or $path is empty, answer
		return (-e $fd ? ($fd) : ());	# quickly without searching

	my $an;		# grep and return absolute names found in $path
	return (grep {-e $_} map(catfile($_, $fd), @$path));

	#return (grep {$an = catfile($_, $fd) and -e $an and $an} @$path);
	#return (grep {$an = catfile($_, $fd) and -e $an and $an} $path);
}

# Return printable form of an integer after adding commas to separate
# groups of 3 digits.
# XXXXXXXXX isn't there a cpan module that does this?
#
sub human_num { my( $num )=@_;

	$num ||= 0;
	my $numstr = sprintf("%u", $num);
	if ($numstr =~ /^\d\d\d\d+$/) {		# if num is 4 or more digits
		$numstr .= ",";			# prepare to add commas
		while ($numstr =~ s/(\d)(\d\d\d,)/$1,$2/) {};
		chop($numstr);
	}
	return $numstr;
}

1;

=head1 NAME

Minder - routines to support minders on behalf of Nog.pm and Egg.pm

=head1 SYNOPSIS

 use EggNog::Binder ':all';	    # import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut

=for removal?

# # yyy is this needed? in present form?
# #
# # get next value and, if no error, change the 2nd and 3rd parameters and
# # return 1, else return 0.  To start at the beginning, the 2nd parameter,
# # key (key), should be set to zero by caller, who might do this:
# # $key = 0; while (each($noid, $key, $value)) { ... }
# # The 3rd parameter will contain the corresponding value.
# 
# sub eachnoid { my( $bh, $key, $value )=@_;
# 	# yyy check that $db is tied?  this is assumed for now
# 	# yyy need to get next non-admin key/value pair
# 	my $db = $bh->{db};
# 	my $om = $bh->{om};
# 
# 	#was: my $flag = ($key ? R_NEXT : R_FIRST);
# 	# fix from Jim Fullton:
# 	#my $flag = ($key ? R_NEXT : R_FIRST);
# 	my $flag = ($key ? DB_NEXT : DB_FIRST);
# 	my $cursor = $db->db_cursor();
# # don't forget go close cursor!
# #$cursor->c_close();
# #undef($cursor);
# 
# 	#if ($db->seq($key, $value, $flag)) {
# 	if ($cursor->d_get($key, $value, $flag)) {
# 		return 0;
# 	}
# 	$_[1] = $key;
# 	$_[2] = $value;
# 	return 1;
# }

=cut
