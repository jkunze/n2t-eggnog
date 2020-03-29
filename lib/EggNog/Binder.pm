package EggNog::Binder;

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

# XXXXXX need to add authz to nog!

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	addmsg outmsg getmsg hasmsg initmsg
	authz unauthmsg badauthmsg
	bname_parse gbip human_num
	init_bname_parts 
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

# Database naming components.
use constant DBPREFIX		=> 'egg';	# "app", for dbname building
use constant EXDB_UBDELIM	=> '_s_';	# populator's binder delimiter
						# mnemonic: possessive "s"
use constant INDB_FILENAME	=> 'egg.bdb';

# These next three are really constants, but Perl constants are a pain.

our $EGGBRAND = DBPREFIX . '_';
#our $EGGBRAND = 'egg_';
our $DEFAULT_BINDER    = 'binder1';	# user's binder name default
#our $DEFAULT_BINDER_RE = qr/^egg_.*\..*_s_\Q$DEFAULT_BINDER\E$/o;
our $DEFAULT_BINDER_RE = qr/^$EGGBRAND.*\..*_s_\Q$DEFAULT_BINDER\E$/o;
					# eg, egg_default.jak_s_binder1
our $EGG_DB_CREATE	= 1;

# zzz xxx;
our $CAREFUL = 'public';

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
		# yyy deprecating this use of $DEFAULT_BINDER
		#$self->{default_minder} = $DEFAULT_BINDER;
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

use File::Spec::Functions;

# gbip routine
# Get (find) binder in path (gbip)
# args: $sh, $name, $is_existence_expected
# returns: undef on error with message via $sh, plus $err contains
# sometimes finds multiple binders
# this is supposed to be an improved version of def_bdr (deleted)
# xxx not called for exdb case

# Define binder and candidate binder, given short binder name as arg
#    to mkbinder, rmbinder, or renamebinder
# returns ($bdr, $cmdr, $cmdr_from_d_flag, $err), where
#    $bdr = the expanded...?  (currently unused by caller)
#    $cmdr = the full pathname (user, not system binder name) FOUND in the minderpath array
# always zeroes $cmdr_from_d_flag and always clobbers $cmdr, even on err
# Again, this is only called in the indb case, so we don't test for exdb.
#  zzz but should it apply to exdb too? should it apply to all commands
#     (except maybe help)

# This is called by commands that make and remove binders.
# yyy why not by all commands?
# Finally define the global $mdr and $cmdr variables (kludge).
# This is the routine that once and for all causes an explicitly
# specified high-level (eg egg user arg)binder to override any candidate
# binder ($cmdr).  It sets the global $mdr variable. (kludge) xxx
#
# A binder is considered to exist if its named directory _and_
# enclosed file "dname" exists.  This way a caller can create
# (reserve) the enclosing directory ("shoulder") name ahead of
# time and we can create the dname without complaining that
# the binder exists.
#
# If $binder is set, it names a binder that hides any
# $cmdr candidate or found $mdr, which we now overwrite.
# $expected is the number of binders expected, usually 0 for
# making a binder and 1 for removing a binder. (yyy kludge?)

# Get Binder In Path
sub gbip { my( $sh, $binder, $is_existence_expected )=@_;

	$is_existence_expected ||= 0;	# assumes we're making, not removing
	# yyy check for $is_existence_expected being non-negative integer?

	my $err = 0;
	# these two ($err and $cmdr_from_d_flag) are returned for global
	#   side-effect (not because of this
	#   subroutine, but by our own calling convention protocol -- dumb)

	my $cmdr_from_d_flag = 0;
		# global side-effect when assigned to global upon return

	my $exists_flag = 0;
	# NB: bname_parse will make sure $sh is configured for us
	my ($isbname, $esbname, $bn) =
		bname_parse($sh, $binder, $exists_flag, $sh->{smode});

	my $scmdr = fiso_dname($isbname, INDB_FILENAME);
		# global side-effect when assigned to global upon return

	#use Data::Dumper "Dumper"; print Dumper $sh->{minderpath};
	# yyy we assume only indb case
	my @bdrs = exists_in_path($scmdr, $sh->{minderpath});
	my $n = scalar(@bdrs);

	my $bdr = $n ? $bdrs[0] : "";			# global side-effect

	my $ucmdr = $binder
		? fiso_dname($bn->{user_binder_name}, INDB_FILENAME)
		: '';
	$bn->{front_path} and
		$ucmdr = catfile $bn->{front_path}, $ucmdr;

	$is_existence_expected ||			# remove binder case
			$n == $is_existence_expected and	# $n 0 or > 0
		return ($bdr, $ucmdr, $cmdr_from_d_flag, $err);	# normal

	# If we get here, we were called from a routine creating a binder,
	# which will always (indb case) be located in $sh->{minderhome}.
	# If the binder we would create coincides exactly with one of
	# the existing binders, refuse to proceed.
	#
	my $wouldcreate = catfile($sh->{minderhome}, $scmdr);
	my ($oops) = grep(/^$wouldcreate$/, @bdrs);
	#my ($oops) = grep(/^\Q$bdr\E$/, @bdrs);
	#my ($oops) = grep(/^\Q$cmdr\E$/, @bdrs);
	if ($oops) {
		$err = 1;
		addmsg($sh, 
		    "given binder '$binder' already exists: $oops");
		return ($bdr, $ucmdr, $cmdr_from_d_flag, $err);
	}

	# If we get here, $n > 0 and we're about to make a binder that
	# doesn't clobber an existing binder; however, if $bdr is set,
	# a binder of the same name exists in the path, and one binder
	# might occlude the other, in which case we warn people.

	if (! $sh->{opt}->{force}) {
		addmsg($sh, ($n > 1 ?
			"there are $n instances of '$binder' in path: " .
				join(", ", @bdrs)
			:
			"there is another instance of '$binder' in path: $bdr"
			) . "; use --force to ignore");
		$err = 1;
		return ($bdr, $ucmdr, $cmdr_from_d_flag, $err);
	}
	return ($bdr, $ucmdr, $cmdr_from_d_flag, $err);	# normal return
}

sub ebclose { my( $bh )=@_;

	my $exdb = $bh->{sh}->{exdb};
	my $msg;
	my $ok = try {
		$exdb->{client}->disconnect;
	}
	catch {
		$msg =	"problem disconnecting from external database: " . $_ .
			"; connect_string=$exdb->{connect_string}, " .
			"exdbname=$bh->{exdbname}";
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
	
	$bh->{rlog}->out("D: WeNeed=$WeNeed, id=$id, opd=$opd,
		ruu_agentid=" . "$ruu->{agentid},
		otherids=" . join(", " => @{$ruu->{otherids}}));

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
		bopen(				# and IF
			$rmh,			# we can bopen it
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

# yyy independent conditions:
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
# yyy always require named minder to _right_ of rmminter/rmbinder,
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

# ibopen = internal binder open

sub ibopen { my( $bh, $mdr, $flags, $minderpath, $mindergen )=@_;
#    if (ibopen( $bh, $isbname, 0, $minderpath )) {

	$mdr //= '';
	# an empty $minderpath means DON'T use any minderpath
	#$minderpath ||= $bh->{sh}->{minderpath};
	defined($flags) or
		$flags = 0;

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
	# via gen_minder(). This call may have a side-effect of creating the
	# default binder.

# XXX zzz unify prep_default_binder to work for indb and exdb cases
# XXX zzz redo this to clearer: if ! $mdr then prep_default_binder()
 	$mdr ||= prep_default_binder($bh->{sh},
		'i', $flags, $minderpath, $mindergen);

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
	#print ("xxx rdwr=$rdwr, flags=$flags, creating=$creating,
	#		DB_RDONLY=", DB_RDONLY, " DB_RDWR=", DB_RDWR, "\n");
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

	$bh->{indbname} = $mdrd;	# the full name of the open binder

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

# ebopen = external binder open (new)

sub ebopen { my( $bh, $exbrname, $flags )=@_;

	$EggNog::Egg::BSTATS //=		# lazy, one-time evaluation
		EggNog::Egg::flex_enc_exdb(
			"$A/binder_stats",		# _id name
			"bindings_count",		# element name
		);
	$flags //= 0;
	my $sh = $bh->{sh};

		# NB: $DEFAULT_BINDER is created implicitly by the first
		# mongodb attempt to write a record/document, so it is not the
		# product of mkbinder and therefore has no "$A/erc" record,
		# which we special-case ignore when doing brmgroup().

		# yyy indb case might adopt something closer to this
		#     simple approach to default binder naming

	# With MongoDB, this is a very soft open, in the sense that it
	# returns without contacting the server. (For performance reasons
	# you don't really know if you have a connection until the first
	# access attempt.)  Consquently, it almost always "succeeds".
	# One annoying consequence is when it "succeeds" in opening a
	# non-existent binder, creating it as a result, when instead you
	# want it to fail so that you know if you constructed the binder name
	# incorrectly. The plus side of this MongoDB behavior is that you
	# save a round trip on opening. But we don't need that savings for
	# read-only resolution by a long-running process, when we do an
	# explicit existence check since resolution is such a pain to debug.

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
	$exdb->{exdbname} = $exbrname;	# xxx do we need this?
	$bh->{exdbname} = $exbrname;	# the name of the open binder
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
			$om->elem("note", "ebopen $bh");
	return 1;
}

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

	my $exists_flag = 0;
	my ($isbname, $esbname) =		# default binder if ! $bdr
		bname_parse($sh, $bdr, $exists_flag, $sh->{smode});

	if ($sh->{exdb}) {
# xxx this code needs re-testing
		($flags & DB_CREATE) and
			$flags = $EGG_DB_CREATE;	# yyy dumb kludge

		if (! ebopen($bh, $esbname, $flags)) {
			! $bdr and addmsg($bh,
				"error opening default binder \"$esbname\"");
			return undef;
		}

	}
	if ($sh->{indb}) {

		my $ibdr = $bdr ? $isbname : '';	# zzz needed?

		if (! ibopen($bh, $ibdr, $flags, $minderpath, $mindergen)) {
			! $bdr and addmsg($bh,
				"error opening default binder \"$isbname\"");
			return undef;
		}
	}
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

# Binder Naming Conventions

=head1 NAME

Binder - routines to support Eggnog binders

=head1 SYNOPSIS

 use EggNog::Binder ':all';	    # import routines into a Perl script

In mongodb, a record/document corresponds to an identifier and a
table/collection corresponds to a binder.

=head1 BINDER NAMES

# xxx document
bname_parse() is the main routine defining names
Eggnog users aren't aware of binder names, but Eggnog admin users sometimes
need to know how databases are named in the filesytem (indb) or on a remote
server (exdb). For simplicity there's one naming convention for both cases.
The indb case can easily use the filesytem hierarchy to easily isolate
databases from each other, but it is harder to implement the exdb case,
where the space of database names may be

(a) shared by applications other than "egg",
(b) shared by more than one host,
(c) shared by code testing suites that want to use production names, and
(d) shared by production code using production names in test mode ("smode"),

For simplicity, database names are kept the same in both the indb and exdb
cases.

Here's how our hierarchical mongodb (and BDB) namespaces are structured.

User binder name to system binder name conversion, with optional existence
check. On success, returns exdb and indb names (according to whether the
session is configured for it or not, as found in $sh). If $exists_flag is

   0, don't check for existence
   1, do shallow existence check
   2, do hard existence check (for --rrm case)

Returned system names can be used for indb or exdb cases. They look like

zzz
      App_Svc_Clas_Isoltr.Smod_Who_s_Bname

      egg_n2t_prd_public.real_ezid_s_ezid
      egg_td_loc_idsn2tprd2b.real_ezid_s_ezid

zzz the _td_ below is VERY important for shielding prod databases from accidental deletion
zzz Isoltr CANNOT be set to public except via a special option XXX called...?

      egg_n2t_loc_Isoltr.real_ezid_s_ezid           or
      egg_n2t_loc_Isoltr.test_ezid_s_ezid (rare)    or
      egg_s_loc_Isoltr.real_jak_s_mybinder          or
      egg_n2t_public.real_foo_s_foo (for public-facing binders)
      egg_td_prd_idsn2tprd2b.real_foo_s_foo (for test scripts)

where a service name matching .*_pub is always rejected by mkbinder, 
rmbinder, and rmbindergroup. It can only be matched by using --public
together with --service (minus the '_pub'), forcing the manipulation
of public binders to be done as a very deliberate act. So service names
have two parts:

      Base + '_' + Isolator

where Base is often one of

      s (default)
      td (generic eggnog test scripts)
      n2t (N2T related test and public binders)


when does it NOT include hostname?  for 'public' case


XXX where does 'n2t' come from in a generic eggnog test script?
    from scripts: build_server_tree, n2t, ademegn, pfx, in_ezid
    
    shouldn't we use just 's' by default, and maybe 'td_idsn2t...' for testing?
    the 'n2t' should come from all scripts that build web-facing stuff,
       taken from ENV? from env.sh? 

Test scripts NEED to be able to safely create and remove binders without any
effect on other binders (eg, especially production binders). In the indb case,
binders are safely isolated by filesystem hierarchy. In the exdb case, the
xxx wrong below
convention is to take the Service name, append "_x" plus the top-level domain
name with problem characters squeezed out; for example, if the host is

	ids-n2t-prd-2b.n2t.net

the "n2t" Service name becomes

	n2t_xidsn2tprd2b

In general, system names are of the form

	App_Service_Smode.User_s_Ubname

which consists of underscore-delimited fragments:

	App is "egg" or "nog"
	Service is "s" (none, the default), a service like "n2t" or "web"
	    defined via the eggnog source directory (eg, t/n2t or t/web),
	    or "n2t_x" and a compressed hostname (no punctuation)
	Smode (service mode) is "real" or "test"
	User is a Populator (eg, "ezid", "oca", local system login)
	Ubname is the lightly normalized caller-supplied binder name, usually
	    the name by which external API users know it

An Smode of "test" is meant for users, not developers. So, for example, it
is rarely used even by developer test scripts.

The system name looks like databasename.tablename, typical of server-based
DBMSs, and suitable for both the exdb (eg, mongo) and indb (eg, BDB) cases.

The names are constrained in such a way that they can be decomposed and the
individual fragments identified. Even though the Service and Ubname strings
may themselves contain underscores, they are identifiable because they must
be next to fragments that cannot contain underscores.

The system binder name is used for both the indb (eg, filesystem-based
embedded Berkeley DB) and exdb (eg, namespace shared among multiple client
hosts by a remote database server like mongodb) cases. The exdb case needs
system names unlikely to accidentally conflict across multiple hosts, so we
add a client hostname to support administrative test suites (would be better
if we used a FQDN that didn't make it overly long).

how does t/... test invoke admin test flag? (via a "keep it local" flag?)
is it a global ENV var, since cwd is irrelevant for exdb case?
  (yes, same indb name can exist without conflict in more than one dir)

ZZZ
and to egg --rrm for test binders and t-... resolution
   --smode [real|test]
ZZZ
  !!! we do not do same for nog yet!

EGN_SERVICE=n2t    (set in service.cfg, overridable from test suites
		with eg, --service n2txidsn2tprd2b
		with eg, --smode real
EGN_SERVICE=n2txidsn2tprd2b
EGN_SERVICE_MODE=     default: test,real
EGN_SERVICE_MODE=n2t,test
EGN_SERVICE_MODE=xidsn2tprd2b,real

=head1 DB NOTES

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

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2019 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut

# how should binder_names react to command line args and options?
# should ebshow list binder names restricted by args for service, class,
# isolator, service_mode, user, and user_binder_name?
# what's the relationship to bname_parse()? (recall bname_parse takes
# name as input, does (a) uname to sname and hash or (b) sname to hash)
# --> for binder_names() we need to construct a kind of template to match
#     against, so that hash filled up with defaults and args could be
#     very useful

# zzz
# Returns hash of binder name parts, generally for storage in a session hash.
# Called during session config to set up a bunch of per-session defaults.
# Final adjustments to defaults are made by, eg, bopen() and mkbinder().

#       App_Svc_Clas_Isoltr_Smod.Who_s_Bname

sub init_bname_parts { my( $sh )=@_;

	return {
		app		   => DBPREFIX,
		service		   => ($sh->{opt}->{service} || 's'),
		class		   => ($sh->{host_class} || 'loc'),
		isolator	   => ($sh->{hostname} || 'NoHostName'),
		service_mode	   => ($sh->{opt}->{smode} || 'real'),
		who		   => $sh->{ruu}->{who},
		user_binder_name   => $DEFAULT_BINDER,
	};
}

# Take a binder name, in user or system format, analyze it, return triple,
#
#     $isbname, $esbname, $bn
#
# where $bn is a hash of binder name components, which includes the short
# form user-oriented name {user_binder_name}.
#
# The $exists return is undefined, unless $bname begins with a path
# component, in which case it will be 0 or 1 depending on whether the
# binder was found to exist.
# Probably kludge(?):
# If $bname begins with a path component, after parsing an existence
# check will be made. This will be true for either the exdb or indb case.
# In both cases, an initial path of "./" will disappear after signaling
# intent to do the existence check. 
#
# If it's in system format, fill hash and return.
# If it's in "user format", compute the corresponding system format,
# using args $sh and $smode for missing hash components, and return.
# 
# Consider the received name to be of either full-blown "system binder"
# type or single-part name as known to users. Anything else returns
# undef to indicate an error. Names of either type may have filepath
# components we'll strip from the front and/or back, before we know
# what the received type is. Drop initial and final whitespace, and
# tolerate multiple '/'s (instead of just one '/') in filepaths.

# NB: unlike old ub2sb, always return non-empty values for $isbname and $esbname
# NB: $minderpath is an array

sub bname_parse { my( $sh, $bname, $exists_flag, $service_mode, $who, $minderpath )=@_;
	# yyy $who used, but $service_mode unused?

	if (! $sh->{cfgd}) {		# configure a session to set defaults
		my $msg = EggNog::Session::config($sh);
		if ($msg) {
			addmsg($sh, $msg);	# failed to configure
			return undef;
		}
	}
	$sh->{opt}->{verbose} and
		$sh->{om}->elem("note", "parsing $bname, testdata=" .
			($sh->{opt}->{testdata} || '')
		);

	#$bname ||= $DEFAULT_BINDER;	# user binder defaults if not given
	my $dbnparts = $sh->{default_bname_parts};	# see init_bname_parts()
	$bname ||= $dbnparts->{user_binder_name};

	my $bn = {};		# actual binder name hash to be returned
	$bn->{iexists} = $bn->{eexists} = undef;
	# xxx use const FS_DB_NAME egg.bdb
	$bname =~ s|/+egg\.bdb\s*$|| and	# strip off any descender
		$bn->{back_path} = 'egg.bdb';
	if ($bname =~ s|^\s*(.+)/||) {		# strip and save up to last '/'
		$bn->{front_path} = $1;
		$bn->{front_path} =~ s|/+$||;	# drop multiple '/'s
		$bn->{front_path} eq '.' and	# but treat '.' as if absent
			delete $bn->{front_path};
	}
	# xxx assign and compile this just once (per session, per forever?)
	#my $sbparser = qr|^([^._]+)_([^.]+)_([^._]+)\.(.+)_s_(.+)$|o;
# zzz make docs match this code
	my $sbparser = qr|^
		([^._]+)_	# 1. app name, no internal _
		([^.]+)_	# 2. service name, internal _ ok
		([^._]+)_	# 3. class name, no internal _
		([^._]+)	# 4. isolator, no internal _
		\.
		([^._]+)_	# 5. service mode, no internal _
		(.+)_		# 6. user name, internal _ ok
		s_
		(.+)		# 7. user binder name, internal _ ok
	$|xo;

	# ==== Case 1: long binder name ====

	# If the given name matches $sbparser, it's already in system format,
	# in which case fill hash with component parts and return.
	#
	# If $exists_flag < 0, use only components from the caller's string,
	# otherwise use standard parts found from caller's environment and
	# options (found in the session).

#say "XXX exf: $exists_flag, bname: $bname, sbparser: $sbparser";
	if ($bname =~ $sbparser) {	# start with pure string parse
		$bn->{got_sbtype} = 1;
		$bn->{app} = $1;
		$bn->{service} = $2;
		$bn->{class} = $3;
		#$bn->{isolator} = $4;
		$bn->{isolator} = normalize_isolator( $4 );
		$bn->{service_mode} = $5;
		$bn->{who} = $6;
		$bn->{user_binder_name} = $7;
		cat_bname_parts($bn);		# NB: alters $bn hash

		$exists_flag < 0 and		# if no existence check
			return ($bn->{isbname}, $bn->{esbname}, $bn);

		# similar to rmbinder, since $isbname is to be removed
		my ($isbexists, $esbexists, $isbpathname) =
			binder_exists($sh,
				$bn->{isbname}, $bn->{esbname},
				$exists_flag, $minderpath);
		if ($sh->{indb}) {
			$bn->{iexists} = $isbexists;
			$bn->{isbpathname} = $isbpathname;
		}
		$sh->{exdb} and
			$bn->{eexists} = $esbexists;	# yyy
		##use Data::Dumper "Dumper"; print Dumper $bn;
		return ($bn->{isbname}, $bn->{esbname}, $bn);
	}
	elsif ($bname =~ /\./) {	# yyy dumb check for malformed binder
		addmsg($sh, "bname_parser: malformed binder name: $bname");
		return undef;		# abort in this case
	}

	# ==== Case 2: short binder name ====

	# If we get here, the name is NOT in system format. To fill out
	# the hash, we will rely very heavily on session defaults.

	$bname =~ s|^\s+||;		# strip initial whitespace
	$bname =~ s|\s+$||;		# strip final whitespace
	$bn->{user_binder_name} //= $bname;	# may have been set above
	$bn->{got_sbtype} //= 0;		# may have been set above

	# If we're on the web, we go with a kludge that the "user" of a
	# binder is the same as the binder name, except if it ends in
	# "_test", in which case (second kludge) chop that end off.
	# This keeps URLs looking simpler.

	$who ||= $sh->{ruu}->{WeAreOnWeb}
		? $bname		# eg, first ezid in ezid_s_ezid
		: $sh->{ruu}->{who};	# eg, jak in jak_s_foo
		# NB: yyy can't yet specify other than eponymous web binders
	$sh->{ruu}->{WeAreOnWeb} and $who eq $bname and
		$who =~ s/_test\s*$//;	# eg, assume ezid owns ezid_test
			# zzz this is temporary; should use --smode

	$bn->{app} = $dbnparts->{app};
	$bn->{service} =
		$sh->{service_config}->{service} || $dbnparts->{service};
	my $tdata = $sh->{opt}->{testdata} || $ENV{EGG_TESTDATA};
	$tdata and
		$bn->{service} .= '_' . $tdata;
		# NB: helps protect permanent binders from testing activity

	$bn->{class} = $sh->{opt}->{class} ||
		$sh->{host_config}->{class} || $dbnparts->{class};

	my $isolator = $sh->{opt}->{isolator} || $dbnparts->{isolator};
	$bn->{isolator} = normalize_isolator( $isolator );
	#$bn->{isolator} = normalize_isolator( $dbnparts->{isolator} );
	$bn->{service_mode} = $dbnparts->{service_mode};
	$bn->{who} = $who;
	$bn->{user_binder_name} = $bname;

	# Now clean up (normalize) name fragments that might need it.
	# Crudely, we just silently drop chars we don't like. We start
	# by dropping all leading and trailing chars in each name
	# fragment that are an underscore or a non-word char. Also drop
	# any internal hyphens.
	# yyy seems like these normalizations are haphazard, occurring in
	#     different spots -- should make more consistent

# zzz shouldn't we be cleaning up names received in system format (above)?
	(s/^[\W_]+//, s/[\W_]+$//, s/-//g)
		foreach (
			$bn->{app}, $bn->{service}, $bn->{class},
			$bn->{isolator}, $bn->{service_mode},
			$bn->{who}, $bn->{user_binder_name}
		);

	# To be able to isolate fragments reversably, no internal underscores.

	(s/_//g)		# to meet decomposition requirements
		foreach ( $bn->{who}, $bn->{service_mode} );


# zzz document that we DO permit underscores in (a) service name and
#              (b) binder name
#     AND DISALLOW it in the prefix "egg" -- this permits us to parse
#      things deterministically

	cat_bname_parts($bn);		# NB: alters $bn hash

	if ($exists_flag > 0) {
		# similar to rmbinder, since $isbname is to be removed
		my ($isbexists, $esbexists, $isbpathname) =
			binder_exists($sh, $bn->{isbname}, $bn->{esbname},
				$exists_flag, $minderpath);
		if ($sh->{indb}) {
			$bn->{iexists} = $isbexists;
			$bn->{isbpathname} = $isbpathname;
		}
		$sh->{exdb} and
			$bn->{eexists} = $esbexists;	# yyy
	}
	return ($bn->{isbname}, $bn->{esbname}, $bn);
# zzz drop distinction between isbname and esbname?
}

# Return an isolator string with naught but alphanumerics.

sub normalize_isolator { my( $s )=@_;		# input string

	$s =~ s/[\W_]//g;
	return $s;
}

sub cat_bname_parts { my( $bn )=@_;		# $bn is hash of bname_parts

	# Build the two halves of the name, then join them with a '.'.
	# Works for both indb and exdb cases.

	my $sdatabasename =	# eg, system database (mongo "database") name
		$bn->{app} . '_' .
		$bn->{service} . '_' .
		$bn->{class} . '_' .
		$bn->{isolator};
		#$bn->{service_mode};
		#DBPREFIX . '_' . $service . '_' . $service_mode;
	my $stablename =	# eg, system table (mongo "collection") name
		$bn->{service_mode} . '_' .
		$bn->{who} . '_s_' .
		$bn->{user_binder_name};
	(s/\.//g)			# drop any and all '.'s in each half
		foreach ($sdatabasename, $stablename);
	my $sbname =			# system binder name
		$sdatabasename . '.' . $stablename;

	$bn->{isbname} = exists $bn->{front_path}
		? catfile($bn->{front_path}, $sbname)
		: $sbname;
	$bn->{esbname} = $sbname;
	$bn->{sdatabasename} = $sdatabasename;
	$bn->{stablename} = $stablename;
	$bn->{system_binder_name} = $sbname;
}

# returns array ($isbname, $esbname) similar to old str2brnames, which it
# calls, but with the empty string for any component that either
# str2brnames returned empty or that does NOT exist (or whose existence
# could not be verified, eg, because the external db wasn't available).
# NB: because MongoDB creates binders/collections simply by trying to
#     read from them, if "show collections" comes up with a default binder
#     name we'll just assume it is a binder that was NOT created by mkbinder
# yyy $mods currently unused

# zzz fix doc block above
# ARGS:
# zzz $exists_flag = 1 (soft check) or 2 (hard check)
# zzz $exists_flag = -1 (pure parse, using string only and not the calling env)
# zzz $isbname non empty to check indb case
# zzz $esbname non empty to check exdb case
# RETURNS:
# ($isbname, $esbname, $isbpathname)

sub binder_exists { my( $sh, $isbname, $esbname, $exists_flag, $minderpath )=@_;

	! $sh and
		return undef;
	$isbname && $sh->{indb} or
		$isbname = '';			# simplify test and return vals
	$esbname && $sh->{exdb} or
		$esbname = '';			# simplify test and return vals
	$exists_flag ||= 1;			# default is softcheck
	my $softcheck =
		$exists_flag == 1;		# ie, hardcheck if not 1

# ZZZ this is NOT checking path!! why not? does it need to?
# zzz why does gbip do a better job searching for a binder?

	my $minderdir;
	$minderpath and
		$minderdir = $minderpath->[0];	# zzz why just take first elem?
	$minderdir ||= $sh->{minderhome};

	my $isbpathname = '';
	if ($isbname) {			# $isbname may be altered below
		my $dirname = $isbname;		# assume it names a directory

# zzz wait! whose job is it to do the defaulting? should bopen and # b{make,rm,...}?

		unless (file_name_is_absolute($dirname) or $minderdir eq ".") {
			$dirname = catfile(($minderdir || $sh->{minderhome}),
				$dirname);
		}
		$isbpathname = $dirname;
		# If here $dirname is a valid absolute or relative pathname.
		! -e $dirname and		# if it does NOT exist, then
			$isbname = $isbpathname = '';	# change to say that
	}

	# In the exdb case, check if collection list contains the name, for
	# if we attempt to open a non-existent mongo database, we inadvertently
	# create it.

	if ($esbname) {			# $esbname may be altered below
		# xxx deprecated since 3.0
		#my $NSNS = 'system.namespaces'; # namespace of all namespaces
		#		# mongodb system.namespaces collection for
		#		#    {name : "dbname.analyticsCachedResult"}

		my ($dbname, $collname) = split /\./, $esbname;
		my ($db, $result, @collections, $msg);
		my $ok = try {				# exdb_get_dup
			$db = $sh->{exdb}->{client}->get_database($dbname);
			@collections = $db->collection_names;
		}
		catch {
			$msg = "error looking up database name \"$dbname\" " .
				"(from esbname \"$esbname\")";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and 	# test for undefined since zero is ok
			addmsg($sh, $msg),
			return undef;
		grep( { $_ eq $collname } @collections ) or
			$esbname = '';	# set return name to empty string
		# yyy this grep could permit anyone to see if a collection
		#     exists, even if it doesn't belong to them
	}
	$softcheck and
		return ($isbname, $esbname, $isbpathname);

	# If we get here, do a more thorough existence check (eg, for --rrm).

	if ($isbname) {			# $isbname may be altered below
		my $bh = newnew($sh) or
			addmsg($sh, "couldn't create binder handler"),
			return undef;
		if (ibopen( $bh, $isbname, 0, $minderpath )) {
			require EggNog::Egg;
			# ready-for-storage versions of key
# XXXZZZ the inconsistencies in flex_enc_indb and indb_get_dup signatures
#    waste huge amounts of debugging time!!
			my $rfs = EggNog::Egg::flex_enc_indb("$A/erc");
			my @dups = EggNog::Egg::indb_get_dup($bh->{db},
				$rfs->{key});

			#use Data::Dumper "Dumper"; print Dumper $bh;
			# yyy could probably use a generic "binder_find_one"
			$isbpathname = $bh->{dbhome};
			scalar(@dups) or
				addmsg($sh, "$isbname is a collection/table "
					. "but does not appear to be a binder"),
				$isbname = $isbpathname = '';	# then say so
				# yyy maybe return set to undef ?
			bclose($bh);	# yyy why is there no ibclose?
		}
		else {
			$isbname = '';		# ordinary non-existence
		}
	}

	# we wouldn't attempt to look for an erc record unless we already
	#    found a collection of this name, so this ebopen won't be
	#    creating it accidentally (which is what mongodb does)
	if ($esbname) {			# $esbname may be altered below
		my $bh = newnew($sh) or
			addmsg($sh, "couldn't create binder handler"),
			return undef;
		if (ebopen( $bh, $esbname )) {		# yyy other args unused
			require EggNog::Egg;
			# ready-for-storage versions of key
			my $rfs = EggNog::Egg::flex_enc_exdb("$A/", 'erc');
			my @dups = EggNog::Egg::exdb_get_dup($bh,
				$rfs->{id}, $rfs->{elems}->[0]);
			#$ret = EggNog::Egg::exdb_find_one( $bh,
			#	$sh->{exdb}->{binder}, "$A/");	# yyy no 'erc'?
			#! $ret || ! $ret->{ "erc" } and	# not a binder
			scalar(@dups) or
				addmsg($sh, "$esbname is a collection/table "
					. "but does not appear to be a binder"),
				$esbname = '';		# then say so
				# yyy maybe return set to undef ?
			ebclose($bh);
		}
		else {
			# yyy how often do we get here, given mongodb's
			#     create-always policy?
			$esbname = '';		# ordinary non-existence
		}
	}
#	# ?else do nothing if $esbname corresponds to a default binder for the
#	# binder group, which for mongodb we consider to _always_ exist

	return ($isbname, $esbname, $isbpathname);
}

# Move (rename) binder

# zzz should other binder commands act on fsb (full system binder names)?
# NB: $cmdr1 is short name, $b2fullsysname is pathname of full system name

sub renamebinder { my( $sh, $mods, $cmdr1, $minderpath, $b2fullsysname, $user )=@_;

	! $sh and
		return undef;
	my $om = $sh->{om};		# if $om we might use it for messages
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($sh, $msg);	# failed to configure
		return undef;
	}
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;

	if (! $cmdr1) {
		addmsg($sh, "current binder name must not be empty");
		return undef;
	}

	my $exists_flag = 2; 		# thorough check
	my ($isbname, $esbname, $bn) =
		bname_parse($sh, $cmdr1, $exists_flag, $sh->{smode}, undef,
			$minderpath);
		# similar to rmbinder, since $isbname is to be removed

	# Check that old exists, that new doesn't exist

	if ($bn->{isolator} eq $CAREFUL and ! $sh->{opt}->{ikwid}) {
		addmsg($sh, "cannot remove binder with \"$CAREFUL\" as isolator"
			. " unless the \"--ikwid\" option is also specified");
		return undef;
	}

	if ($sh->{exdb} and ! $bn->{eexists}) {
		addmsg($sh, "source binder \"$bn->{esbname}\" doesn't exist"),
		return undef;
	}
	my $isbpathname = $bn->{isbpathname};
	if ($sh->{indb} and ! $bn->{iexists}) {
		addmsg($sh, "source binder \"$bn->{isbname}\" doesn't exist"),
		return undef;
	}

	if ($sh->{indb}) {
		-e $b2fullsysname and
			addmsg($sh, "destination binder \"$b2fullsysname\"" .
				" must not yet exist"),
			return undef;

		# NB: To rename dev binder foo to become n2t's production
		# public binder, where
		#   dev binders live in td_egnapa_public/binders and
		#   production binders live in ~/sv/cur/apache2/binders,
		# do something like (unverified) this:
		#   prdpath=$HOME/sv/cur/apache2/binders
		#   new=$( perl -Mblib egg --service n2t --class prd
		#     --isolator public bname foo )
		#   perl -Mblib egg brename foo $prdpath/$new

		use File::Copy;
		move($bn->{isbpathname}, $b2fullsysname) or
			addmsg($sh, "error in 'move' of $bn->{isbname} " .
				"to $b2fullsysname: $!"),
			return undef;;
	}
	return 1;
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

sub mkbinder { my( $sh, $mods, $binder, $user, $what, $minderdir )=@_;

	! $sh and
		return undef;
	my $om = $sh->{om};		# if $om we might use it for messages
	my $msg;
	if (! $sh->{cfgd} and $msg = EggNog::Session::config($sh)) {
		addmsg($sh, $msg);	# failed to configure
		return undef;
	}
	$sh->{remote} and		# yyy why have this and {WeAreOnWeb}?
		unauthmsg($sh),
		return undef;

	my $exists_flag = 2; 		# thorough check
	my ($isbname, $esbname, $bn) =	# default binder if ! $binder
		bname_parse($sh, $binder, $exists_flag, $sh->{smode}, undef,
			 [ $minderdir ]);
		#bname_parse($sh, $binder, $exists_flag, $sh->{smode});
	#my ($isbexists, $esbexists) = binder_exists($sh,
	#	$isbname, $esbname, $exists_flag, [ $minderdir ]);

	if ($sh->{exdb}) {
		#$esbexists and
		#my $esbname = $bn->{esbname};
		$bn->{esbexists} and
			addmsg($sh, ($binder ? '' : 'default ') .
				"binder \"$esbname\" already exists"),
			return undef;
		mkebinder($sh, $mods, $esbname, $user,
				$what, $minderdir) or
			return undef;
		! $binder and $om and $om->elem("note",
			"default binder \"$esbname\" created");
	}
	if ($sh->{indb}) {
		#if ($isbexists) {
		#my $isbname = $bn->{isbname};
		if ($bn->{isbexists}) {
			addmsg($sh, ($binder ? '' : 'default ') .
				"binder \"$isbname\" already exists"),
			return undef;
		}
		mkibinder($sh, $mods, $isbname, $user,
				$what, $minderdir) or
			return undef;
		! $binder and $om and $om->elem("note",
			"default binder \"$isbname\" created");
	}
	return 1;
}

sub mkebinder { my( $sh, $mods, $esbname, $user, $what, $minderdir )=@_;

	# xxx should reconcile diffs between mk{e,i}binder
	! $sh and
		return undef;
	! $esbname and
		addmsg($sh, 'external database name cannot be empty'),
		return undef;
		# yyy unlike indb case, where we generate a new binder name
		#     using prep_default_minder

	my $bh = newnew($sh) or
		addmsg($sh, "mkebinder couldn't create binder handler"),
		return undef;

	! ebopen($bh, $esbname, $EGG_DB_CREATE) and	# yyy some args unused
		addmsg($sh, "could not open external binder \"$esbname\""),
		return undef;

	my $exdb = $sh->{exdb};
	! EggNog::Egg::exdb_set_dup( $bh, "$A/", "erc",
		    fiso_erc($sh->{ruu}, '', $what), { no_bcount => 1 } ) and
		addmsg($sh, "problem initializing binder \"$esbname\""),
		return undef;

	# By setting that value, we can check a random MongoDB collection,
	# that might have been created by accident (eg, a typo). A later
	# test for this value can tell us if the collection was created
	# by mkebinder() or not.

	return 1;
}

sub mkibinder { my( $sh, $mods, $binder, $user, $what, $minderdir )=@_;

# xxxzzz $binder comes in with $isbname -- change arg name?

	#$bh->{fiso} and		# XXXXX why not? just close and re-open?
	#	addmsg($sh, "cannot make a new binder using an open handler " .
	#		"($bh->{fiso})"),
	#	return undef;

	# xxx should reconcile diffs between mk{e,i}binder
# xxxzzz can this clause be dropped?
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
# zzz !!! check this. looks like createbinder calls ibopen!
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

# zzz XXXXXXXXX not doing indb case at all here? and what would it mean?

# zzz drop binder_exists, check via bname_parse; ADD minderpath arg! zzz
# replace isbname/esbname with $bn->{isbname}/$bn->{isbname}...
sub brmgroup { my( $sh, $mods, $user )=@_;

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
	! $sh->{exdb} and		# yyy only works for exdb case
		return 1;
	if ($sh->{opt}->{allb} || $sh->{opt}->{allc}) {
		addmsg($sh, "--allb or --allc option not allowed");
		return undef;
	}
	my @ebinders = ebshow($sh, $mods, 0, $user);

	# empty return list is ok
	@ebinders and ! defined($ebinders[0]) and	# our test for error
		addmsg($sh, 'brmgroup: ebshow failed'),
		return undef,
	;
	# yyy bug: brmgroup won't remove any internal binders
	my ($inbrname, $exbrname, $rootless);	# yyy $inbrname unused

	my $errs = 0;				# don't make errors fatal
	for my $b (@ebinders) { 
# zzz drop this nuance. if it starts with "egg_..." assume it's ours to do with
# what we want
		# yyy ignore result for internal db, since xxxbinder_exists
		#     doesn't look in @$minderpath yyy this is too complicated
		# Need this next test because a collection that's listed
		# might not actually be an eggnog binder.

		# Take fully qualified binder name and convert to simple name
		# name as user knows it, eg, egg_td_egg.sam_s_foo -> foo
		# Use $rootless to hold that simple binder name.

		#($rootless = $b) =~ s/^[^.]+.\Q$binder_root_name//;

# zzz should we store $bn hash in $bh?
		my $exists_flag = 1;		# soft check
		my ($isbname, $esbname, $bn) =
			bname_parse($sh, $b, $exists_flag, $sh->{smode});
			# bname_parse($sh, $rootless, $sh->{smode});
		my ($isbexists, $esbexists) = binder_exists($sh,
			$isbname, $esbname, $exists_flag, undef);

# slug
#	my $exists_flag = 2; 		# thorough check
#	my ($isbname, $esbname, $bn) =
#		bname_parse($sh, $binder, $exists_flag, $sh->{smode}, undef,
#			$minderpath);
#		# similar to rmbinder, since $isbname is to be removed

# slug
#	my $isbpathname = $bn->{isbpathname};
#	if ($sh->{indb} and ! $bn->{iexists}) {
#		addmsg($sh, "source binder \"$bn->{isbname}\" doesn't exist"),
#		return undef;
#	}
		if ($bn->{isolator} eq $CAREFUL and ! $sh->{opt}->{ikwid}) {
			addmsg($sh, "cannot remove binder with \"$CAREFUL\" "
				. "as isolator unless the \"--ikwid\" option "
				. "is also specified");
			$errs++;
			next;
		}
		! $esbexists and ! $sh->{opt}->{force} and
			addmsg($sh, "brmgroup: not removing $rootless"),
			$errs++,
			next,
		;
		rmebinder($sh, $mods, $esbname, $user) or
			addmsg($sh, "brmgroup: error removing binder $rootless "
				. "($esbname)"),
			$errs++,
		;
	}
	$errs and
		return undef;
	return 1;
}

sub rmbinder { my( $sh, $mods, $binder, $user, $minderpath )=@_;

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
	if (! $binder) {
		addmsg($sh, "missing binder name; use \"$DEFAULT_BINDER\" "
			. "to remove the default binder");
		return undef;
	}

	# yyy ignore result for internal db, since xxxbinder_exists doesn't
	#     look in @$minderpath yyy this is too complicated

	my $exists_flag = 1; 		# soft check
	my ($isbname, $esbname, $bn) =
		bname_parse($sh, $binder, $exists_flag, $sh->{smode}, undef,
			$minderpath);
		#bname_parse($sh, $binder, $exists_flag, $sh->{smode});
	if ($bn->{isolator} eq $CAREFUL and ! $sh->{opt}->{ikwid}) {
		addmsg($sh, "cannot remove binder with \"$CAREFUL\" as isolator"
			. " unless the \"--ikwid\" option is also specified");
		return undef;
	}

#	my ($isbexists, $esbexists) = binder_exists($sh,
#		$isbname, $esbname, $exists_flag, $minderpath);
#		#$isbname, $esbname, $exists_flag, undef);

	if ($sh->{exdb}) {
		# xxx untested code
		$binder =~ s|/$||;	# remove fiso_uname's trailing /, if any
		! $binder and		# yyy is this test needed?
			addmsg($sh, "no binder specified"),
			return undef;
		my $dflt_binder = ($esbname and
			$esbname =~ $DEFAULT_BINDER_RE);
			# ? default binder for the binder group,
			# ? which for mongodb we consider to _always_ exist
			# yyy why do we check if if looks like default binder?
			#     do we need this check?
		! $bn->{esbexists} and ! $sh->{opt}->{force} and
				! $dflt_binder and
			addmsg($sh,
				"external binder \"$esbname\" doesn't exist"),
			return undef;
		rmebinder($sh, $mods, $esbname, $user) or
			return undef;
	}
	if ($sh->{indb}) {
		# yyy this test won't work: ! $indbexists and ...
		# yyy why not test ! $isbexists and ...?
		rmibinder($sh, $mods, $isbname, $user, $minderpath) or
			return undef;
	}
	return 1;
}

# assume existence check and call to str2brnames were already done by caller
sub rmebinder { my( $sh, $mods, $exbrname, $user )=@_;

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

sub rmibinder { my( $sh, $mods, $mdr, $user, $minderpath )=@_;

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

# zzz adapt for internal db bshow?
# external db bshow
# returns a list of fully qualified binder names on success, (undef) on error
# NB: the returned list is used directly by td_remove()
# $om == 0 (zero) means just return list and don't do output
# first get list of collections, later filter by $user
# yyy ?add 'long' option that checks for every important file, eg,
#     minder.{bdb,log,lock,README} and 0=minder_...

sub ebshow { my( $sh, $mods, $om, $user, $ubname )=@_;

# zzz xxx make bshow arg1 be binder name, and test
	my $exists_flag = 0;
	my ($ibn, $ebn, $bn) =
		bname_parse($sh, $ubname, $exists_flag, undef, $user);
# zzz bname_parse($sh, $ubname, $sh->{smode}, $user);

	my $exdb = $sh->{exdb};
	my ($msg, $db, @cns);
	my $ok = try {
		# Build a complete list of collection names in @cns by
		# stepping through a list of database names, and for each
		# dbname, adding its list of collection names to @cns.
		for my $dbname ( $exdb->{client}->database_names ) {
			$db = $exdb->{client}->db( $dbname );
			#push @cns, $db->collection_names;
			push @cns,
				map "$dbname.$_",
					$db->collection_names;
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

	# Now we will filter the fully-qualified collection names in @cns by
	# various criteria and return a subset of those as binder names.
	# The main filtering criteria is for binders/collections belonging
	# to the current user, based on default binder components from
	# $sh->{default_bname_parts}.

	my ($sysdb, $who, $ubdr) = (
		$bn->{sdatabasename},
		$bn->{who},
		($ubname
			? $bn->{user_binder_name} : ''),
	);

	my $root_re =
		$sh->{opt}->{allc} ? qr// :	# do all collections if --allc,
		($sh->{opt}->{allb} ?		# else if --allb just do what
			qr/^\Q$bn->{app}/ :	# looks like a binder
						# else just do my binders
			qr/^\Q$sysdb.\E[^_]+_\Q${who}_s_\Q$ubdr\E/)
			#qr/^\Q$edatabase_name.$ebinder_root_name$clean_ubname/)
			#qr/^\Q$EGGBRAND/ :	# looks like a binder
			#			# else just do my binders
			#qr/^\Q$edatabase_name.$ebinder_root_name$clean_ubname/)
	;

	my @ret_binders = sort			# return sorted results of
		grep m/$root_re/,		# filtering binder names
			@cns;			# from collection names
	! $om and			# if $om == 0, suppress output, which
		return @ret_binders;		# is how brmgroup calls us

	# if we get here we're doing output
	$om->elem('note', ' ' . scalar(@ret_binders) . ' ' .
		($sh->{opt}->{allc} ? "external collections" :
		($sh->{opt}->{allb} ? "external binders under $bn->{app}" :
			"external binders under $bn->{sdatabasename}.")),
#		($sh->{opt}->{allb} ? "external binders under $EGGBRAND" :
#			"external binders under $edatabase_name." .
#				"$ebinder_root_name$clean_ubname")),
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

sub bshow { my( $sh, $mods, $om, $user, $ubname )=@_;

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
		(@ret = ebshow($sh, $mods, $om, $user, $ubname)),
		(@ret and ! defined($ret[0]) and return undef),
	;
	$sh->{indb} and
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

# zzz remove gen_minder stuff
# xxx this creation of binders when none specified -- is it worth the code
# complexity? ibopen calls prep_default_binder, but ebopen does NOT
#    --> so drop in the ibopen case too?

# Get/create minder when none supplied.  In case 1 (! O_CREAT) select the
# defined default.  In case 2 (O_CREAT), select the defined default only
# if it doesn't already exist, otherwise generate a new minder name using
# snag or (if minder is a minter) the 'caster' minter, but create the
# caster minter first if need be.
#
# yyy $mindergen is unused

# xxxzzz can we stop calling this routine yet?

sub prep_default_binder { my( $sh, $ie, $flags, $minderpath, $mindergen )=@_;
	# xxx not yet using $ie (one of 'i' or 'e')!

	defined($flags)		or $flags = 0;
	my $om = $sh->{om};

	my $exists_flag = 0; 	# don't check, caller already decided to open it
	my ($def_isbname, $esbname) =
		bname_parse($sh, $DEFAULT_BINDER, $exists_flag, $sh->{smode});

	my $mdr = $def_isbname;
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
			mkibinder($submh->{sh}, undef, $mdr, undef,
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

# xxxzzz can we stop calling this routine yet?

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

		my $exists_flag = 0; 	# don't check, caller decided to open
		my ($def_isbname, $esbname) =
			bname_parse($sh, $DEFAULT_BINDER, $exists_flag, $sh->{smode});

		my ($n, $msg) = File::Value::snag_version(
			catfile($sh->{minderhome}, $def_isbname),
				{ as_dir => 1 });
		$n < 0 and
			addmsg($sh, "problem generating new binder name: " .
				$msg),
			return undef;
		$mdr = $def_isbname;
		# yyy drop default_minder attribute?
		#$mdr = $bh->{default_minder};
		$mdr =~ s/\d+$/$n/;	# xxx assumes it ends in a number
		# xxx shouldn't we be using name returned in $msg?
		# XXX this _assumes_ only other type is ND_BINDER!!
		my $dbname = mkibinder($sh, undef, $mdr, undef,
			"Auto-generated binder", $sh->{minderhome});
		$dbname or
			addmsg($sh, "couldn't create snagged name ($mdr)"),
			return undef;
		return $mdr;
	}

	# If we get here, the unnamed minder we're to create is a MINTER
	# and we need to generate its name.  To create a minter we must
	# mint a die ("cast a die") using a special minter we call a
	# "caster".  The caster creates a unique shoulder that we can use
	# as the name of the minder we're to create.  If the caster doesn't
	# exist yet, we must first create it.
	# 

# xxx reserve df5 for the minter co-located with a binder (df4 as normal
#     default)
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
	# this is MINTER, so don't do bname_parse
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

# xxx does anyone call this?
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

