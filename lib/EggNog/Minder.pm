package EggNog::Minder;

# XXX XXX need to add authz to noid!

use 5.010;
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
	gen_txnid
	human_num
	OP_READ OP_WRITE OP_EXTEND OP_TAKE OP_CREATE OP_DELETE
	SUPPORT_ELEMS_RE CTIME_ELEM PERMS_ELEM
	BIND_KEYVAL BIND_PLAYLOG BIND_RINDEX BIND_PAIRTREE
	prep_default_minder init_minder gen_minder mkminder rmminder
	cast mopen mclose mshow mstatus fiso_erc
	open_resolverlist
	$A $v1bdb $v1bdb_dup_warning
	get_dbversion rrminfo RRMINFOARK
	exists_in_path which_minder minder_status
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Value ":all";
use File::Copy 'mv';
use File::Path qw( make_path mkpath rmtree );
use File::Find;
use EggNog::Rlog;
use EggNog::RUU;
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;

# Perl style note:  this code often uses big boolean expressions instead
# typical if-elsif-else structures because entering a { block } is
# relatively expensive.  It looks strange if you're not used to it, but
# this is how it works.  Instead of
#
#	if ( e1 && e2 && e3 ) {
#		s1;
#		s2;
#		...;
#	}
#	elsif ( e4 || e5 && e6 ) {
#		s3;
#	}
#	else {
#		s4;
#		s5;
#	}
#
# we can write this series of conditional expressions and statements as
#
#	e1 && e2 && e3 and
#		s1,
#		s2,
#	1 or
#	e4 || e5 && e6 and
#		s3,
#	1 or
#		s4,
#		s5,
#	1;
#
# That's the rigorous form, where the "1 or" makes sure that the list
# of statements ends with a "true" and stops ("closes the brace") the
# processing of the next boolean "or" clause.  The whole mess ends at
# the ";".
# 
# Riskier to maintain but shorter is to omit the "1 or".  We can do this
# if we KNOW that the immediately preceding statements in the "," separated
# list will evaluate to "true" or if we're at the last statement before
# ";".  For example, if s2 and s3 always return "true", we can shorten the
# above to
#
#	e1 && e2 && e3 and
#		s1,
#		s2
#	or
#	e4 || e5 && e6 and
#		s3
#	or
#		s4,
#		s5
#	;
#
# For this big boolean form to work along with list processing, it's
# common to parenthsize argument lists (so Perl know where the statement
# ends) as well as an entire assignment statements (so Perl knows where the
# RHS ends). If you don't do this, the commas terminating the boolean
# statements have a tendency to get swallowed up by Perl functions
# preceding them.

my $nogbdb = 'nog.bdb';		# used a couple places

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

# Max number of re-use by mopen of an opened db before re-opening it
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

# Possible ways to do oo-interface.

# package Nog::binder
# $br = new Nog::binder;

# package Nog::minter
# $mr = new Nog::minter;

# package Nog::minder;
# $mr = new Nog::minder;	# create minder

#####
# Trying this one for now.
# package Nog;
# $mh = EggNog::Nog->new($mdrtype, $contact, $om, $minderpath, $opt);
#       # create new minder handler, where $mdrtype is one of
#           ND_MINTER, ND_BINDER, ND_NABBER, ND_COUNTER

sub new { # call with type, WeAreOnWeb, om, minderpath, optref

	my $class = shift || '';	# XXX undefined depending on how called
	my $self = {};

	$class ||= "Nog";
	bless $self, $class;

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
	# $self->{minderpath} is a Perl list; arg is colon-separated list
	# xxx confusing difference between string path and array path!
	# ** $mh->{minderpath} is an ARRAY ref ** (should it be minderpath_a?)
	#
	($self->{minderhome}, @{ $self->{minderpath} }) =
		init_minder(shift);	# arg is a minderpath STRING
	#{minder_file_name} = $mdrd, from mopen(), is the associated filename
	$self->{opt} = shift || {};	# this should not be undef
	$self->{version} = $self->{opt}->{version};
	# XXX comment out undef's for better 'new' performance?
	$self->{pfxdb} = {};		# xxx document prefix/scheme table
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

	# Start with unopened minder handler.
	$self->{open} = MDRO_CLOSED;
	$self->{open_count} = 0;
	$self->{mopenargs} = "";	# crude signature to support persistomax
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
		$self->{default_minder} = "binder1";
		$self->{evarname} = "EGG";
		$self->{cmdname} = "egg";
		$self->{objname} = "egg";	# used in making filenames
		$self->{dbname} = "egg.bdb";
		$self->{humname} = "binder";
		$self->{version} ||= $EggNog::Egg::VERSION;

		$self->{fname_pfix} = 'egg_';	# used in making filenames
		$self->{edbdir} =		# embedded db directory
			$self->{fname_pfix} . 'edb';
		$self->{edbfile} =		# embedded db filename
			catfile( $self->{edbdir}, 'edb' );
		$self->{sdbdir} =		# server db directory
			$self->{fname_pfix} . 'data';
		$self->{sdbfile} =		# server db filename
			catfile( $self->{sdbdir}, 'sdb' );
		# new: egg_README egg_lock egg_conf_default(?)
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

sub mclose { my( $mh )=@_;

	$mh->{db}			or return;	# yyy right test?
	$mh->{opt}->{verbose} and
		($mh->{om} and $mh->{om}->elem("note",
			"closing minder handler: $mh->{fiso}"));
	defined($mh->{log})		and close $mh->{log};	# XXX delete
	undef $mh->{rlog};		# calls rlog's DESTROY method
	undef $mh->{db};
	undef $mh->{ruu};
	my $hash = $mh->{tied_hash_ref};
	untie %$hash;			# untie correctly follows undef
	$mh->{open} = MDRO_CLOSED;
	$mh->{open_count} = 0;
	# XXXXX test MINDLOCK!!
	defined($mh->{MINDLOCK})	and close($mh->{MINDLOCK});
	return;
}

# xxx document changes that object interface brings:
#     cleaner error, locking, and options handling
sub DESTROY {
	my $self = shift;
	#$self = "xxx";

	mclose($self);

# xxx former mclose($self) section
#	$self->{db}			or return;	# yyy right test?
#	# XXX $self->{opt}->{verbose} and log fact of closing
#	defined($self->{log})		and close $self->{log};
#	undef $self->{db};
#	my $hash = $self->{tied_hash_ref};
#	untie %$hash;			# untie correctly follows undef
#	# XXXXX test MINDLOCK!!
#	defined($self->{MINDLOCK})	and close($self->{MINDLOCK});
# xxx done mclose section

	$self->{opt}->{verbose} and
		# XXX ?
		#$om->elem("destroying minder handler: $self");
		print "destroying minder handler: $self\n";
	undef $self;
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

# xxx temporily look for two patterns until EZID database is all converted
use constant SUPPORT_ELEMS_RE	=> '(?:__m|_\.e)[cp]';
#use constant SUPPORT_ELEMS_RE	=> '__m[cp]';
#use constant PERMS_ELEM		=> '|__mp';
#use constant CTIME_ELEM		=> '|__mc';

use constant SUBELEM_SC		=> '|';
use constant RSRVD_PFIX		=> '_,e';
use constant PERMS_ELEM		=> '|_,ep';
use constant CTIME_ELEM		=> '|_,ec';

use Data::UUID;
sub gen_txnid { my( $mh )=@_;

	! $mh->{ug} and				# if this is the first use,
		$mh->{ug} = new Data::UUID,	# initialize the generator
	;		# xxx document this ug param in of $mh

	my $id = $mh->{ug}->create_b64();
	$id =~ tr|+/=|_~|d;			# mimic nog nab
	return $id;
}

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
sub authz { my(  $ruu, $WeNeed,   $mh,   $id,  $opd ) =
	      ( shift,   shift, shift, shift, shift );

	my $dbh = $mh->{tied_hash_ref};

# p:&P/2|public|60
# p:&P/1|admin|77
#$opd and
#	$dbh->{$opd . PERMS_ELEM} = "p:&P/897839|joe|60";
#$id and
#	$dbh->{$id . PERMS_ELEM} = "p:&P/2|public|00";

	# NOTE: this routine assumes the $mh->{conf_permissions} string was
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
		($mh->{conf_permissions}	# finally, global perms
			|| undef
		),
	);
	my $permstring =		# stringify it for regex matching
		join("\n", @bigperms) || '';
	
##	print("yyy ruu_agentid=$ruu->{agentid}\notherids=",
##			join(", " => @{$ruu->{otherids}}), "\n");
##	print("zzz $_\n")

$mh->{rlog}->out("D: WeNeed=$WeNeed, id=$id, opd=$opd, ruu_agentid=" .
	"$ruu->{agentid}, otherids=" . join(", " => @{$ruu->{otherids}}));

	$permstring =~
		/^p:\Q$_\E\|.*?(\d+)$/m 	# isolate perms per agent and
		&&
#! $mh->{rlog}->out("D: xxx _=$_, 1=$1, opn=$WeNeed, 1&opn=" .
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
# Adds an authn http error message to a minder handler for output.
## If $msg arg is an array reference, add all array elements to msg_a.
#
sub unauthmsg { my( $mh, $vmsg )=@_;

#xxx think this realm stuff can be tossed -- apache handles it all??
	my $realm = 'egg';
	$mh->{realm} and
		$realm .= " $mh->{realm}";
	my $http_msg_name = 'Status';
	my $http_msg = '401 unauthorized';
	$vmsg and			# xxx a hack for debugging
		$http_msg .= ' - ' . $vmsg;

	addmsg($mh, $http_msg, "error");	# why call it $http_msg?
	# XXX! cgih must be defined iff $ruu->{webtype} !!!
	$mh->{om}->{cgih} and
		push(@{ $mh->{http_msg_a} },
			$http_msg_name, $http_msg);
# xxx needed?		'WWW-Authenticate', "Basic realm=\"$realm\"");
	return 1;
}

# Adds an authn http error message to a minder handler for output.
#
sub badauthmsg { my( $mh )=@_;

	my $http_msg_name = 'Status';
	my $http_msg = '403 forbidden';

	addmsg($mh, $http_msg, "error");	# why call it $http_msg?
	# XXX! cgih must be defined iff $ruu->{webtype} !!!
	$mh->{om}->{cgih} and
		push(@{ $mh->{http_msg_a} },
			$http_msg_name, $http_msg);
	return 1;
}

sub initmsg { my( $mh )=@_;
	$mh->{msg_a} = [];		# regular message array
	$mh->{http_msg_a} = [];		# http message array
}

sub getmsg { my( $mh )=@_;
	return $mh->{msg_a};
}

sub hasmsg { my( $mh )=@_;		# suitable for test wheter the first
	return ($mh->{msg_a})[1];	# element's message text is non-empty
}

# Adds an error message to a minder handler message array, msg_a.
# The message array is ordered in pairs, with even elements (0, 2, ...)
# being message name (eg, error, warning) and odd elements being the text
# of the message (going with the previous element's name).
# If $msg arg is an array
# reference, add all array elements to msg_a; this is how to transfer
# messages from one minder handler to another.
# Arg $msg_type is optional.
#
sub addmsg { my( $mh, $msg, $msg_name )=@_;

	$msg ||= '';
	$msg_name ||= 'error';

	ref($msg) eq '' and		# treat a scalar as a simple string
		push(@{ $mh->{msg_a} }, $msg_name, $msg),
		return 1;
	ref($msg) ne 'ARRAY' and	# we'll consider a reference to an
		return 0;		# array, but nothing else
	#print("xxx m=$_\n"), push @{ $mh->{msg_a} }, $_	# $msg must be an array reference,
	push @{ $mh->{msg_a} }, $_	# $msg must be an array reference,
		for (@$msg);		# so add all its elements
	return 1;
}

# XXX need OM way to temporarily capture outputs to a string, independent of
#     user setting of outhandle (so we can insert notes in ...README files)

# Outputs accumulated messages for a minder object using OM.  First arg
# should be a minder handler $mh.  Optional second and third args ($msg
# and $msg_name), if present, are to be used instead of the $mh->{msg_a}
# array.  If the first arg is a scalar (not a ref), assume it's a message
# string and just print it to stdout (ie, without OM) with a newline.
# See addmsg() for how to set an HTTP response status.
#
# Since this would often be used for debugging, we're very forgiving if
# you supply the wrong args, or haven't initialized $mh.  We try to do
# what you'd like to get information "out there".  Completeness wins over
# efficiency.
#
# Messages are assumed to be exceptional and more likely to be
# structured, so we use om_formal for output.
#
sub outmsg { my( $mh, $msg, $msg_name )=@_;

	unless ($mh) {				# no minder degenerates
		my $m = $msg_name || '';	# into simple case of name,
		$m	and $m .= ': ';		# colon, and
		$m .= $msg || '';		# value
		return				# print and leave
			print($m, "\n");
	}
	ref($mh) or				# if not a ref, assume $mh is
		return print($mh, "\n");	# a string -- print and leave

	# If we get here, assume valid $mh and process arrays of
	# messages, although typically there's just one message.
	#
	my $msg_a;			# every odd array element is a message
	if (defined($msg)) {		# set some defaults
		$msg_name ||= 'error';	# default message type
		$msg_a = [ $msg_name, $msg ];
	}
	else {
		$msg_a = $mh->{msg_a};
	}

	my $om = $mh->{om_formal};
	my $p = $om->{outhandle};		# 'print' status or string
	my $st = $p ? 1 : '';		# returns (stati or strings) accumulate
	my ($i, $max, $s, $n, $d);

	my $http_msg_a = $mh->{http_msg_a};
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
sub logmsg{ my( $mh, $message )=@_;

	my $logfhandle = $mh->{log};
	defined($logfhandle) and
		print($logfhandle $message, "\n");
	# yyy file was opened for append -- hopefully that means always
	#     append even if others have appended to it since our last append;
	#     possible sync problems...
	return 1;
}

=cut

our $minders = ".minders";

use Fcntl qw(:DEFAULT :flock);
use DB_File;
use File::Spec::Functions;
use Config;

# Global $v1bdb will be true if we're built with or running with pre V2 BDB.
# Returns an array of 4 elements:
#   $v1bdb                 (boolean with value of global)
#   $DB_File::VERSION      (BDB Perl module that we are running with)
#   $DB_File::db_ver       (BDB C library version we were built with)
#   $DB_File::db_version   (BDB C library version we are running with)
#
sub get_dbversion {

	my $v1bdb;			# global that's true for pre-V2 BDB
					# xxx this is a per object global
	$v1bdb = $DB_File::db_ver =~ /^1\b/ or
		$DB_File::db_version =~ /^1\b/;
	return (
		$v1bdb,
		$DB_File::VERSION,	# Perl module version
		$DB_File::db_ver,	# libdb version built with
		$DB_File::db_version,	# libdb version running with
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
	my $server_proc = "$ENV{EGNAPA_SRVREF_ROOT}/logs/httpd.pid";
	my $server_dvcsid = "$ENV{EGNAPA_SRVREF_ROOT}/logs/dvcsid";
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

# Set $minderhome and @minderpath.
sub init_minder { my( $mpath )=@_;

	# The minderpath (@minderpath) is a colon-separated sequence of
	# directories that determines the set of known minders.  A minder
	# in a directory occurring earlier in @minderpath hides a minder
	# of the same name occurring later in @minderpath.
	
	# If neither is set, the default minderpath is <~/.minders:.>.
	# If we need to create a minder (eg, $default_minder_nab), we'll
	# attempt to create it in the first directory of @minderpath.
	#
	# Set default minderpath if caller didn't supply one.
	$mpath ||= catfile(($ENV{HOME} || ""),	# ~/.minders or /.minders,
		$minders) . $Config{path_sep} . ".";	# then current dir

	my @minderpath = split($Config{path_sep}, $mpath);
	my $minderhome = $minderpath[0];
	return ($minderhome, @minderpath);
}

# xxx Takes a minder handler and a colon-separated-list as args,
# Takes a minder handler, an array ref and a minderpath array ref as args,
# calls mopen on each minder, and returns an array of open minder handlers.
# This is useful when the minders are binders to be opened O_RDONLY as
# resolvers.  The $mh arg is used to store results and as input for
# inheritance for other params that "Minder->new" needs.
# yyy right now works only for resolvers (assumes ND_BINDER) and readonly
# 
# Call: $status = open_resolverlist($mh, $mh->{resolverlist},
#
sub open_resolverlist { my( $mh, $list )=@_;

# xxx $list likely includes the same minder that is already opened
#     with $mh, in which case we'll just open it again -- should be ok as
#     we want the handler in $list to have different attributes, eg, to
#     stop recursion rather than to start it

	# Use map to create and open a minder handler for each item in
	# $resolverlist.  Unlike $mh, for these minder handlers we will
	# turn off {opt}->{resolverlist} so that recursion stops with them.
	#
	$list ||= $mh->{opt}->{resolverlist} || "";
	#print "list=$list, mpath_a=@$minderpath_a\n";

	my $rmh;
	my $me = 'open_resolverlist';
# xxx is the next test needed?
	$mh->{resolverlist_a} and
		addmsg($mh, "$me: resolver array already built"),
		return ();

	my @mharray = map {			# for each resolver in list
	    					# IF ...
		$rmh = EggNog::Minder->new(	# we get a new minder handler
						# xxx don't want to do
						#    this every time
			EggNog::Minder::ND_BINDER,
			$mh->{WeAreOnWeb},
			$mh->{om},
			undef,			# normally a STRING minderpath
			$mh->{opt},
		)
		or	addmsg($mh, "$me: couldn't create minder handler"),
			return ()
		;
		$rmh->{resolverlist} = undef;	# stop recursion 1
		$rmh->{subresolver} = 1;	# stop recursion 2
		$rmh->{rrm} = 1;	# xxx better if inherited?
					#     big assumption about caller here
		mopen(				# and IF
			$rmh,			# we can mopen it
# XXXXX check if it's already open?
			$_,			# using the map list item
			O_RDONLY,		# read-only (for a resolver)
			$mh->{minderpath},	# supplied minderpath ARRAY ref
			#'xxxmindergen',
		)
		or	addmsg($mh, getmsg $rmh),
			addmsg($mh, "$me: couldn't open minder $_"),
			return ()
		;

		$rmh;				# eval to $rmh on success

	} split
		$Config{path_sep}, $list;
	#
	# If we get here, @mharray has an array of open minders.

	#outmsg($mh, "xxx mharray=" . join(", ", @mharray) .
	#	" sep=$Config{path_sep}, list=$list");

	@{ $mh->{resolverlist_a} } = @mharray;	# save the result in $mh
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
# mopen($mh, $name, $flags, [$minderpath], [$mdrgenerator])
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
#   mopen($mh, $uname_or_dname, $flags) with other params given by
# 	$mh->{minderpath}, $mh->{}
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
# $flags can be O_CREAT, O_RDWR, or O_RDONLY (the default)
# $flags can also be O_CREAT, O_RDWR, or O_RDONLY (the default)
#
# xxx probably should change minderpath to minderpath_a to indicate an
# array not a string
sub mopen { my( $mh, $mdr, $flags, $minderpath, $mindergen )=@_;

	$mh			or return undef;	# bail
	defined($flags)		or $flags = 0;
	my $mopenargs = $mh . $mdr . $flags .	# crude argument signature
		($minderpath ? join(",", @$minderpath) : "");
	my $hname = $mh->{humname};		# name as humans know it
	my $om = $mh->{om};

	if ($mh->{open}) {

		# XXX should probably send a signal when we want to force
		#     all processes to re-open and check the .conf file
		# If already opened in the same mode with same minder args
		# as requested before save lots of work by only re-opening
		# every $mh->persistomax attempts to call mopen.  A crude
		# test is to save previous mopen args in a literal string
		# $mh->{mopenargs}, which may be wrong in some cases. XXXX
		#
		my $use_old_open = $mh->{mopenargs} eq $mopenargs &&
			$mh->{open_count}++ <= $mh->{persistomax};
		$use_old_open and
			($mh->{opt}->{verbose} and $om and $om->elem("note",
				"using previously opened $hname $mdr")),
			return 1;		# already open, don't re-open
		# Else call mclose and fall through to re-open.
		mclose($mh);
	}
	# If we get here, $mh is not open.

	# XXX easy?: have $om turn off verbose (removes extra test for output)
	#     or make it log instead?
	$mh->{opt}->{verbose} and $om and $om->elem("note",
		"opening $hname '$mdr' in path: " .
		($minderpath ? join(", ", @$minderpath) : "(undefined)"));
	$mh->{mopenargs} = $mopenargs;		# record argument signature

	#NB: $mh->{opt}->{minderpath} is STRING, $mh->{minderpath} is ARRAY ref
	#NB: $mh->{opt}->{resolverlist} STRING, $mh->{resolverlist_a} ARRAY ref
	#NB: this next resolverlist test is irrelevant for noid yyy

	# xxx if we were to create a "resolve" command, would we still
	# need to indicate that we're in a long-running process that
	# takes only "resolve" commands?, eg, could we do without "rrm"?

	if ($mh->{rrm} and $mh->{resolverlist}) {
		my $rcount =
			open_resolverlist($mh, $mh->{opt}->{resolverlist});
		#outmsg($mh, "xxx rc=$rcount, rl_a=" .
		#	join(", ", @{$mh->{resolverlist_a}}));
		$rcount or
			addmsg($mh, "problem opening resolverlist: " .
				$mh->{opt}->{resolverlist}),
			return undef;

	# XXX log errors from here with apache logs and verbose output as
	#  (a) they won't otherwise be seen and (b) they're not associated
	#   with a binder

		$mh->{opt}->{verbose} and $om and
			$om->elem("note", "resolver list count: $rcount");
	}

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
What if no server running when client starts:  startup server on demand?
  Run a per-client server writing to a filesystem path similar to Embedded
  case?  

=cut

	# This next call to prep_default_minder() may call mopen() again
	# via gen_minder().
	#
 	$mdr ||= prep_default_minder($mh, $flags, $minderpath, $mindergen);
 	$mdr or
		addmsg($mh, "mopen: no $hname specified and default failed"),
		return undef;

	# Find path to minder file.  First we need to make sure that we
	# have both the minder filename and its enclosing directory.
	#
# xxx make sure fiso_uname is only called on an arg that has been
#     extended already by fiso_dname, else successive calls could keep
#     chopping it back; better: make fiso_uname idempotent somehow.
	my $mdrd = fiso_dname($mdr, $mh->{dbname});

	# Use first minder instance [0], if any, or the empty string.
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";

	# xxx what if it exists but not in minderhome and you want
	#     to create it in minderhome?
	my $creating = $flags & O_CREAT;
	if ($creating) {	# if planning to create, it shouldn't exist
		#scalar(@mdrs) > 1 and ! $mh->{opt}->{force} and
		#	addmsg($mh, "than one instance of ($mdr) in path: " .
		#		join(", ", @$minderpath)),
		#	return undef;
		$mdrfile and
			addmsg($mh, "$mdrfile: already exists" .
				($mdrfile ne $mdr ? " (from $mdr)" : "")),
			return undef;
			# yyy this complaint only holds if dname exists,
			#     don't complain if only the uname exists
	}
	else {			# else it _should_ exist
		$mdrfile or
			# xxx would be helpful to say if it exists or not
			addmsg($mh, "cannot find $hname: $mdr"),
			# "mopen: ($mdrd|$mdrfile)" .
			#	join(":", @$minderpath) .
			return undef;
		$mdrd = $mdrfile;
	}
	my $mdru = fiso_uname($mdrd);

	# xxx should probably be called mdrhome? since database will
	# actually be in a subdirectory of this dir
	my $dbhome = fiso_uname($mdrd);
	! -d $dbhome and
		addmsg($mh, "$dbhome not a directory"),
		return undef;

	my $basename = catfile( $mdru, $mh->{fname_pfix} );
	#my $basename = catfile( $dbhome, $mh->{fname_pfix} );
	#my $basename = catfile( $dbhome, $mh->{objname} );

	#
	# Authn/Authz and binder configuration.
	#

	# note: there are config flags that have nothing to do with the
	#   definition of user identities that is in the same config file
	#   for efficiency (since only one file has to be read)
	#   It seems like a Minder::set_conf and a Minder::get_conf should
	#   call some RUU::conf (sub)routines
	my ($msg, $cfh);
	$creating and			# create a default configuration file
		$msg = EggNog::RUU::set_conf($basename, $mh->{opt}),
		($msg and		# can't write? that's a problem
			addmsg($mh, $msg),
			return undef);
	#
	# Just because we're creating a new minder doesn't mean the directory
	# was empty and didn't already have a .conf file the user wants to
	# re-use.  Therefore, don't assume if we're $creating that the
	# default config we will read next is one that we just created.

	# The config file is (re-)read every time the minder is (re-)opened,
	# which is every time mopen() is called _and_ the existing $mh is
	# determined to need re-opening.
	# xxx document this as a feature; think about efficiencies,
	#     such as only re-reading the file if it changes
	#     yyy add --nice option for not re-opening between mode changes?
	#
	$msg = EggNog::RUU::get_conf($basename, $cfh);	# get config file info
	$msg and $mh->{opt}->{verbose} and $om and	# no config isn't fatal
		$om->elem("note", $msg);		# but is interesting
	#
	# Config info should now be in $cfh, in 3 parts.
	# XXX architectural bug: ruu config is split between $mh struct
	#     and $ruu struct (below).

	$mh->{conf_flags} = $cfh->{flags} || '';	# 1/3 kinds of config

	$mh->{conf_ruu} = $cfh->{ruu} || '';		# 2/3 kinds
	# yyy this defuser option should be repeatable
	# yyy remove this command line option?  currently unused!
	$mh->{opt}->{defuser} and
		$mh->{conf_ruu} .= "\ndefuser: $mh->{opt}->{defuser}";

# AAAstart yyy replace this section too after we recreate it from defagent
	my $perms = $cfh->{permissions} || '';		# not done with 3/3
	#
	# Because we want permissions checks to go quickly without need for
	# regular expressions to tolerate optional whitespace and comments,
	# we do one-time data normalization to reduce such variability.
	#
# xxxx this seems like the wrong place to do this
# xxxx RUU and u2phash stuff should be in a separate module
	$perms and			# special optimization to remove
		$perms =~ s/^#.*\n//mg,			# comment lines,
		$perms =~ s/[ \t]+//g,			# all whitespace,
		$perms =~ s/^\n//mg,			# and blank lines
	;
	$mh->{conf_permissions} = $perms;
	#my %u2phash =			# create user-to-upid mapping
	#	( $x =~ /^p:([^\|]+)\|([^\|]+)/gm );
	#$mh->{u2phash} = \%u2phash;
	#while (my ($k, $v) = each %xxx) { print "xxx k=$k, v=$v\n"; }
# AAAend

	# Record as much as we can find out about the person or agent
	# who is calling us.
	# Note: this is the only time that $mh->{ruu} is defined or redefined.
	#
	# XXXX add config file name and last read time to $ruu
	# xxx let every_user come from config file.
	# xxx maybe combine auth() method with new()
	#
	my $ruu = EggNog::RUU->new(
		$mh->{WeAreOnWeb},
		$mh->{conf_ruu},
		$mh->{u2phash},
	);
	my $authok;
	#my $ruu = $mh->{ruu};
	($authok, $msg) = $ruu->auth();		# potentially expensive
	$authok or
		addmsg($mh, $msg),
		return undef;
	# yyy is this next necessary, or does it get garbage collected?
	$mh->{ruu} and			# in case it's defined already (not
		undef $mh->{ruu};	# sure why it would be), free up space
	$mh->{ruu} = $ruu;

# yyy now overwriting what we did in section AAA above (later remove it)
#	my ($k, $v);
#	my $perms = '';
#	while (($k, $v) = each %{ ruu->{perms} }) {
#		$perms .=;
#	}

	#$mh->{om}->{cgih}->add( { 'Acting-For' => $msg } );
	$mh->{opt}->{verbose} and $om and
	    $om->elem("note",
		"remote user: " . ($ruu->{remote_user} || '') .
		($ruu->{http_acting_for} ?
			" acting for $ruu->{http_acting_for} " : '')),
	    $om->elem("note",
		'config file section lengths: ' .
		'permissions '. length($mh->{conf_permissions}) . ", " .
		'flags '. length($mh->{conf_flags}) . ", " .
		'ruu '. length($mh->{conf_ruu}));

	#
	# Log file set up.
	# 
	# yyy do we need to open the rlog so early?? how about after tie()??

#print "xxXX: b=$basename, c=$mh->{cmdname}, who=$ruu->{who}, where=$ruu->{where}, v=$mh->{version}\n";
#$mh->{version} ||= 'foo';
	$mh->{rlog} = EggNog::Rlog->new(
		$basename, {
			preamble => "$ruu->{who} $ruu->{where}",
			header => "H: $mh->{cmdname} $mh->{version}",
		}
	);

	# Optional unified, per-server (as opposed to per-minder)
	# transaction log ("txnlog") to record both the start and end
	# times of each operation, as well as request and response info.
	# xxx this should replace the older rlog, probably with log4perl
	#
	if ($mh->{opt}->{txnlog}) {
		$mh->{txnlog} = EggNog::Rlog->new(
			$mh->{opt}->{txnlog}, {
				preamble => "$ruu->{who} $ruu->{where}",
				extra_func => \&EggNog::Temper::uetemper,
				header => "H: $mh->{cmdname} $mh->{version} "
					. localtime(),
				# xxx localtime() call only really necessary
				# on log creation -- this is not optimal
			}
		);
		$mh->{txnlog} or addmsg($mh,
			    "failed to open txnlog for $mh->{opt}->{txnlog}"),
			return undef;
	}

	use EggNog::Log qw(init_tlogger);
	$msg = init_tlogger($mh) and
		# yyy should really call on a $sh (session handler) -- oh well
		addmsg($mh, $msg),
		return undef;

	#
	# Other
	#

	my $duplicate_keys = ($mh->{type} eq ND_BINDER);	#xxx for config?
	#defined($duplicate_keys)	or $duplicate_keys = 0;
	defined($v1bdb) or
		($v1bdb) = get_dbversion();
	$mh->{'v1bdb'} = $v1bdb;

	$flags ||= O_RDONLY;
	my $rdwr = $flags & O_RDWR;	# read from flags if we're open RDWR

	# Don't lock if we're RDONLY unless we're told to.  This prevents
	# users being shut out by broad database scans, at the risk of a
	# little database inconsistency for those scans.  Use --lock when
	# consistent reads are important. xxx document
	#
	$rdwr || $mh->{opt}->{lock} and
		#print("xxx locking\n"),
		(minder_lock($mh, $flags, $dbhome) or
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
			addmsg($mh, $v1bdb_dup_warning, "warning");
		$v1bdb || ($creating) and
			$DB_BTREE->{flags} = R_DUP;
	}
	#$duplicate_keys and $v1bdb || ($flags & O_CREAT) and
	#	$DB_BTREE->{flags} = R_DUP;

	#my @dbhome_parts = grep { $_ } File::Spec->splitdir( $dbhome );
	#$mh->{realm} =		# for HTTP auth, get last part of path
	#	$dbhome_parts[ $#dbhome_parts ];

	# This is the real moment of truth, when the database is opened
	# and/or created.  First, record the filename -- even if we fail
	# to open it, we worked hard to nail it down.
	#
	$mh->{minder_file_name} = $mdrd;
	my $href = {};
	my $db = tie(%$href, "DB_File", $mdrd, $flags, 0666, $DB_BTREE) or
		addmsg($mh, "tie failed on $mdrd: $!" .
	": (" . (-r $mdrd ? "" : "not ") . "readable)" .
			($mh->{fiso} ? ", which is open" : "")),
			return undef;

	## XXXXXX trying to fix resolver bug with non-shared memory
	#my $btree = new DB_File::BTREEINFO;
	#use BerkeleyDB;
	#printf "XXX before flags=%b\n", $btree->{flags};
	#printf "XXX before cachesize=$btree->{cachesize}\n";
	#$btree->{flags} &= ~DB_PRIVATE;
	#printf "XXX after flags=%b\n", $btree->{flags};
	#printf "ZZZ after cachesize=$btree->{maxkeypage}\n";

	$mh->{opt}->{verbose} and $om and $om->elem("note",
		($creating ? "created" : "opened") . " $hname $mdrd"),
			# XXX this next is really a debug message
			$om->elem("note", "mopen $mh");

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
	$mh->{minder_status} = $href->{"$A/status"};	# XXX we don't respect this!!
	$mh->{tied_hash_ref} = $href;
	$mh->{db} = $db;
	$mh->{fiso} = $mdrd;	# yyy old defining moment for test of openness

	# Defining moment in test for openness.
	$mh->{open} = $rdwr ? MDRO_OPENRDWR : MDRO_OPENRDONLY;
	$mh->{open_count} = 0;
	$mh->{msg} = "";
	# $mh->{MINDLOCK} is set up by minder_lock()

	$msg = version_match($mh)		# check for mismatch, but
		unless $creating;		# only if we're not creating
	if ($msg) {				# if we get version mismatch
		# xxx should we just call DESTROY??
		$msg = "abort: $msg";
		#logmsg($mh, $msg);
		$mh->{rlog}->out("N: $msg");
		addmsg($mh, $msg);
		undef $db;
		mclose($mh);
		return undef;
	}
	my $secs;
	$secs = $mh->{opt}->{testlock} and
		$mh->{om}->elem('testlock',
			"holding lock for $secs seconds...\n"),
		sleep($secs);

	return 1;
}
# end of mopen

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

sub minder_lock { my( $mh, $flags, $dbhome )=@_;

	# We use simple database-level file locking with a timeout.
	# Unlocking is implicit when the MINDLOCK file handle is closed
	# either explicitly or upon process termination.
	#
	my $lockfile = catfile( $dbhome, "$mh->{fname_pfix}lock" );
	#my $lockfile = $dbhome . "$mh->{objname}.lock";
	#my $timeout = 5;	# max number of seconds to wait for lock
	#my $timeout = LOCK_TIMEOUT;	# max number of seconds to wait for lock
	my $timeout = $mh->{timeout};	# max number of seconds to wait for lock
	my $locktype = (($flags & O_RDONLY) ? LOCK_SH : LOCK_EX);

	#! sysopen(MINDLOCK, $lockfile, O_RDWR | O_CREAT) and
	! sysopen($mh->{MINDLOCK}, $lockfile, O_RDWR | O_CREAT) and
		addmsg($mh, "cannot open \"$lockfile\": $!"),
		return undef;
	eval {			# yyy convert to try/catch/finally carefully
		
		local $SIG{ALRM} = sub { die("lock timeout after $timeout "
			. "seconds; consider removing \"$lockfile\"\n")
		};
		alarm $timeout;		# alarm goes off in $timeout seconds
		eval {		# yyy convert to try/catch/finally carefully
			# creat a blocking lock
			#flock(MINDLOCK, $locktype) or	# warn only on creation
			flock($mh->{MINDLOCK}, $locktype) or
				# warn only on creation
		# XXX not tested # xxx add note to README file?
				1, ($noflock =
qq@database coherence cannot be guaranteed unless access is single-threaded or the database is re-created on a filesystem supporting POSIX file locking semantics (eg, neither NFS nor AFS)@)
				and ($flags & O_CREAT) and addmsg($mh,
					"cannot flock ($!): $noflock",
					"warning");
				#die("cannot flock: $!");
		};
		alarm 0;		# cancel the alarm
		die $@ if $@;		# re-raise the exception
	};
	alarm 0;			# race condition protection
	if ($@) {			# re-raise the exception
		addmsg($mh, "error: $@");
		return undef;
	}
	return 1;
}

# returns "" on successful match
sub version_match { my( $mh )=@_;

	my $dbh = $mh->{tied_hash_ref};

	my $dbver = $dbh->{"$A/version"};
	my $incompatible = "incompatible with this software ($VERSION)";

	defined($dbver)		or return
		"the database version is undefined, which is $incompatible";
	# xxx not a very good version check
	$dbver =~ /^1\.\d+/	or return
		"the database version ($dbver) is $incompatible";

	return "";		# successful match
}

# Returns actual path (relative or absolute) to uname of the created
# minder (which may have been
# generated and/or be in a $mh->{minderhome} unfamiliar to the caller),
# or "" if it already exists xxx?, or undef on error.  In all cases, addmsg()
# will have been called to set an informational message.  The $minderhome
# argument is optional.
# Set $minderhome to "." to _not_ use default minderhome (eg, when
# "bind -d ..." was used), else leave empty.

######
## xxx call this in a loop, max iterations 5, until success
##     (and log failures)
## xxx make mkbinder in script check anywhere in path and abort if
##     minder_uname is somewhere in minderpath, unless --force
########

# Protocol:  call EggNog::Egg->new to make a fresh $mh before mkminter/mkbinder,
#            which checks to make sure the input $mh isn't already open
#            returns the $mh still open (as most method calls do).  In
#            other words, don't call mkminter/mkbinder on an $mh that
#            you just finished minting or binding on.
# xxx should mclose($mh) close and destroy?  yes??
# xxx could we use a user-level mclose for bulkcmds?
#            $mh=EggNog::Egg->new(); mkminter/mkbinder($mh); mclose($mh);
# 		then $mh->DESTROY;?
#    (need way to clone parts of $mh in creating $submh )
#
sub mkminder { my( $mh, $dirname, $minderdir )=@_;

	my $hname = $mh->{humname};
	my $oname = $mh->{objname};
	# yyy isn't $dirname more a minder name than a "directory" name?
# XXX what if $dirname is empty or null?  We don't check!

	# If path is not absolute, we may need to prepend.  Don't prepend
	# if caller gave $minderdir as "." (not necessary, not portable),
	# but do prepend default if $minderdir is empty (but don't check
	# if caller's default was, eg, ".").
	# 
	#print "xxx before unless dirname=$dirname, minderdir=$minderdir\n";
	$minderdir ||= "";
#print "xxxzzz $mh/$dirname: before minderdir=$minderdir\n";
	$minderdir ||= $mh->{minderhome};
# xxx what does file_name_is_absolute do with empty $dirname?
	unless (file_name_is_absolute($dirname) or $minderdir eq ".") {
	  #print "xxx in unless minderdir=$minderdir, $mh->{minderhome}\n";
		$dirname = catfile(($minderdir || $mh->{minderhome}),
			$dirname);
	}
	# If here $dirname should be a valid absolute or relative pathname.
#print "xxxzzz $mh/$dirname: after minderdir=$minderdir\n";
	#print "xxx after unless dirname=$dirname\n";

#use EggNog::Minder ':all';
#EggNog::Minder::addmsg($mh, "xxxxxx");
#file_value();
#print "FFFF\n";

	my $ret = -1;		# hopefully harmless default
	my $err;
	# -e "" should evaluate to false
	! -e $dirname and
		try {
			$ret = mkpath($dirname)
		}
		catch {		# not sure when this happens (error?)
			addmsg($mh, "Couldn't create $dirname: $@");
			return undef;
		};
	$ret == 0 and           # normal(?) error
		addmsg($mh, "mkpath->0 for $dirname"),
		return "";
	-d $dirname or		# error very unlikely here
		addmsg($mh, "$dirname already exists and isn't a directory"),
		return undef;

	#if ($mh->{type} eq ND_MINTER) { # xxx temp support for old dbname
	#}
	#elsif ($mh->{type} eq ND_BINDER) { # xxx support for [es]db types
	#}
	# xxx use fiso_dname?
	my $dbname = catfile($dirname, $mh->{dbname});
	-e $dbname and
		addmsg($mh, "$dbname: $hname data directory already exists"),
		return undef;
	# yyy how come tie doesn't complain if it exists already?

#	unless (-e $dirname) {
##print "XXX dirname=$dirname, e=$mh->{edbdir}, s=$mh->{sdbdir}\n";
#		$ret = make_path(	# create two data subdirectories
#			catfile( $dirname, $mh->{edbdir} ),
#			catfile( $dirname, $mh->{sdbdir} ),
#			{ error => \$err } );
#	}
#	if (@$err) {
#		for my $diag (@$err) {
#			my ($file, $message) = %$diag;
#			addmsg($mh, "Couldn't create $dirname: " .
#				($file ? "$file: $message" : $message));
#		}
#		return undef;
#	 }
#	$ret == 0 and		# normal(?) error
#		addmsg($mh, "make_path->0 for $dirname subdirectories"),
#		return "";
#print "xxxzzz $mh/$dirname: dirname=$dirname\n";

	# Call mopen() without minderpath because we don't want search.
	#
	mopen($mh, $dbname, O_CREAT|O_RDWR) or
	#mopen($mh, $dbname, (O_CREAT|O_RDWR), $mh->{minderpath}) or
		addmsg($mh, "can't create database file: $!"),
		return undef;

	# Finally, declare the Namaste directory type.
	#
	my $msg = File::Namaste::nam_add($dirname, undef, '0',
		$oname . "_$VERSION", length($oname . "_$VERSION"));
		# xxx get Namaste 0.261.0 or better to permit 0 to mean
		#   "don't truncate" as final argument
		# xxx add erc-type namaste tags too
	$msg and
		#dbclose($mh),
# XXX call destroy/close !
		addmsg($mh, "Couldn't create namaste tag in $dirname: $msg"),
		return undef;

	return $dbname;
	#return 1;
}

sub rmminder { my( $mh, $mods, $lcmd, $mdr, $minderpath )=@_;

	$mh		or return undef;
	my $om = $mh->{om};
	my $hname = $mh->{humname};		# name as humans know it

	#$mh->{ruu}->{webtype} and
	$mh->{remote} and
		EggNog::Minder::unauthmsg($mh),
		return undef;
	$mdr or
		addmsg($mh, "no $hname specified"),
		return undef;
	# xxx use fiso_uname globally?
	$mdr =~ s|/$||;		# remove fiso_uname's trailing /, if any

# xxx test that input $mdr can be a dname or a uname
	my $mdrd = fiso_dname($mdr, $mh->{dbname});
	my $mdru = fiso_uname($mdrd);

	# Use first minder instance [0], if any, or the empty string.
	# xxx document --force causes silent consent to no minder
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";
	$mdrfile or
		addmsg($mh, "$mdr: no such $hname exists (mdrd=$mdrd)"),
		return ($mh->{opt}->{force} ? 1 : undef);

	# XXX add check to make sure that found minder is of the right
	#     type; don't want to remove a minter if we're 'bind'

	# If we get here, the minder to remove exists, and its containing
	# directory is $mdrdir.
	#
	my $mdrdir = fiso_uname($mdrfile);
	$mh->{rlog} = EggNog::Rlog->new(		# log this important event
		catfile($mdrdir, $mh->{objname}), {
			preamble => $mh->{opt}->{rlog_preamble},
			header => $mh->{opt}->{rlog_header},
		}
	);

	my $msg;
	$msg = $mh->{rlog}->out("M: $lcmd $mdrdir") and
		addmsg($mh, $msg),
		return undef;
	
	# We remove (rather than rename) in two cases: (a) if the minder
	# is already in the trash or (b) if caller defines (deliberately
	# one hopes) $mh->trashers to be empty.  xxx DOCUMENT!
	# xxx make this available via --notrash noid/bind option
	#
	my $trashd = catfile($mh->{minderhome}, $mh->{trashers});
	# xxx we don't really want regexp match, we want literal match
	if (! $mh->{trashers} or $mdrdir =~ m|$trashd|) {
		my $ret;
		try {
			$ret = rmtree($mdrdir)
		}
		catch {
			addmsg($mh, "Couldn't remove $mdrdir tree: $@");
			return undef;
		};
		$ret == 0 and
			addmsg($mh, ("$mdrdir " . (-e $mdrdir ?
				"not removed" : "doesn't exist")),
				"warning"),
			return undef;		# soft failure? yyy
		$om and
			$om->elem("note", "removed '$mdr' from trash");
		return 1;
	}

	$msg = $mh->{rlog}->out("N: will try to move $mdr to $trashd") and
		addmsg($mh, $msg);		# not a fatal error

	# We now want a unique name to rename it to in the trash directory.
	# But first create the trash directory if it doesn't yet exist.
	# Since the minter name itself may be a path, we have to figure out
	# what its immediate parent is.
	#
	my $fullpath = catfile($trashd, $mdru);
	my ($volume, $mdrparent, $file) = File::Spec->splitpath($fullpath);
	unless (-d $mdrparent) {
		my $ret;
		try {
			$ret = mkpath($mdrparent)
		}
		catch {
			addmsg($mh, "Couldn't create trash ($mdrparent): $@");
			return undef;
		};
		$ret == 0 and
			addmsg($mh, (-e $mdrparent ?
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
		addmsg($mh, "problem creating backup directory: " .
			$fullpath . ": $trashmdr"),
		return undef;

	# Quick and dirty: the name we snagged is what we want, but we
	# take a tiny chance by rmdir'ing it so that we can rename the
	# minder in one fell swoop rather than renaming each subfile.
	# yyy what if minder is multi-typed? does removing a minter also
	#     remove a co-located binder?
	#
	rmdir($trashmdr) or
		addmsg($mh, "problem removing (before moving) $mdrdir: $!"),
		return undef;
	mv($mdrdir, $trashmdr) or
		addmsg($mh, "problem renaming $mdrdir: $!"),
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
sub make_visitor { my( $mh, $symlinks_followed )=@_;

	$mh		or return undef;
	my $om = $mh->{om};
	$om or
		addmsg($mh, "no 'om' output defined"),
		return undef;
	my $oname = $mh->{objname};

	my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $sze);
	my $filecount = 0;		# number of files encountered xxx
	my $symlinkcount = 0;		# number of symlinks encountered xxx
	my $othercount = 0;		# number of other encountered xxx
	my ($return_summary, $pdname, $wpname, %h);

    my $visitor = sub {		# receives no args from File::Find

	$pdname = $File::Find::dir;	# current parent dir name
					# $_ is file in that dir
	$wpname = $File::Find::name;	# whole pathname to file

	# We always need lstat() info on the current node XXX why?
	# xxx tells us all, but if following symlinks the lstat is done
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
		#print "XXXX SYMLINK $_\n";
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
	m@^0=$oname\W?@o and		# yyy relies on Namaste tag
		print($pdname, "\n"),
		$h{$oname} = $wpname,	# xxx unused right now
	1
	or m@^noid.bdb$@o and		# old version of noid up to v0.424
		print($pdname, "  (classic noid $oname)\n"),
		$h{classic} = $wpname,	# xxx unused right now
	;
    };

    my $visit_over = sub { my( $ret )=@_;

	$ret ||= 0;
	$om->elem("summary", "find returned $ret, " .
		"$filecount files, $othercount other");
	return ($filecount, $othercount);	# returns two-element array

    };

    	return ({ 'wanted' => $visitor, 'follow' => $symlinks_followed },
		$visit_over);
}

# Show all minders known under $mh's minderpath.
# yyy $mods not used
#
sub mshow { my( $mh, $mods )=@_;

	$mh	or return undef;
	my $om = $mh->{om};

	defined($Win) or	# if we're on a Windows platform avoid -l
		$Win = grep(/Win32|OS2/i, @File::Spec::ISA);

	# xxx check that minderpath itself is sensible, eg, warn if its
	#     undefined or contains repeated or occluding minders
	# xxx warn if a minder is occluded by another
	# xxx multi-type minders?
	# xxx add 'long' option that checks for every important file, eg,
	#     minder.{bdb,log,lock,README} and 0=minder_...

	my ($find_opts, $visit_over) = make_visitor($mh, 1);
	$find_opts or
		addmsg($mh, "make_visitor() failed"),
		return undef;
	my $ret = find($find_opts, @{ $mh->{minderpath} });
	$visit_over and
		$ret = &$visit_over($ret);
	return $ret;
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
		delete($dbh->{"$A/status"});		# precaution if dups enabled
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
sub mstatus { my( $mh, $mods, $status )=@_;

	return minder_status($mh->{tied_hash_ref}, $status);
}

=for mining
# xxx Noid version needs work!
# Report values according to $level.  Values of $level:
# "brief" (default)	user vals and interesting admin vals
# "full"		user vals and all admin vals
# "dump"		all vals, including all identifier bindings
#
# yyy should use OM better
sub dbinfo { my( $mh, $level )=@_;

	my $noid = $mh->{tied_hash_ref};
	my $db = $mh->{db};
	my $om = $mh->{om};
	my ($key, $value) = ("$A/", 0);

	if ($level eq "dump") {		# take care of "dump" and return
		#print "$key: $value\n"
		$om->elem($key, $value)
			while ($db->seq($key, $value, R_NEXT) == 0);
		return 0;
	}
	# If we get here, $level is "brief" or "full".

	my $status = $db->seq($key, $value, R_CURSOR);
	if ($status) {
		addmsg($mh, "seq status/errno ($status/$!)");
		return 1;
	}
	if ($key =~ m|^$A/$A/|) {
		#print "User Assigned Values\n";
		$om->elem("Begin User Assigned Values", "");
		#print "  $key: $value\n";
		$om->elem($key, $value);
		while ($db->seq($key, $value, R_NEXT) == 0) {
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
	while ($db->seq($key, $value, R_NEXT) == 0) {
		last
			if ($key !~ m|^$A/|);
		#print "  $key: $value\n"
		$om->elem($key, $value)
			if ($level eq "full" or
				# $key !~ m|^$A/c\d| &&	# old circ status
				$key !~ m|^$A/saclist| &&
				$key !~ m|^$A/recycle/|);
	}
	$level eq "full" and
		#print durability(
		$om->elem("durability", durability(
			$$noid{"$A/shoulder"},
			$$noid{"$A/mask"},
			$$noid{"$A/generator_type"},
			$$noid{"$A/addcheckchar"},
			$$noid{"$A/atlast"} =~ /^wrap/		));
			#, "\n";
	$om->elem("End Admin Values", "");
	#print "\n";
	return 0;
}
=cut

# Get/create minder when none supplied.  In case 1 (! O_CREAT) select the
# defined default.  In case 2 (O_CREAT), select the defined default only
# if it doesn't already exist, otherwise generate a new minder name using
# snag or (if minder is a minter) the 'caster' minter, but create the
# caster minter first if need be.
#
# xxx doesn't this trounce on an existing $mh, which might be open?
# yyy $mindergen is unused
sub prep_default_minder { my( $mh, $flags, $minderpath, $mindergen )=@_;

	defined($flags)		or $flags = 0;
	my $om = $mh->{om};
	my $hname = $mh->{humname};		# name as humans know it

	#print "XXXX in prep_default_minder\n";

	my $mdr = $mh->{default_minder};
	$mdr or
		addmsg($mh, "no known default $hname"),
		return undef;
	my $mdrd = fiso_dname($mdr, $mh->{dbname});

	# Use first minder instance [0], if any, or the empty string..
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";

	unless ($mdrfile) {	# if the hardwired default doesn't exist

		my $mtype = $mh->{type};
		my $opt = $mtype eq ND_MINTER ?  $implicit_minter_opt : {};
		$opt->{rlog_preamble} = $mh->{opt}->{rlog_preamble};
		$opt->{om_formal} = $mh->{om_formal};
		$opt->{version} = $mh->{version};
			# XXX this probably corrupts $implicit_minter_opt
			#     should make copy instead of using directly

		# New $submh is auto-destroyed when we leave this scope.
		#
		my $submh = EggNog::Minder->new($mtype, $mh->{WeAreOnWeb}, $om,
			$mh->{minderpath}, $opt);
			# xxx {om} ?? logging?
		$submh or
			addmsg($mh, "couldn't create caster handler"),
			return undef;
		my $dbname = $mtype eq ND_MINTER ?
			EggNog::Nog::mkminter($submh, undef, $mdr,
				$mh->{default_template}, $mh->{minderhome})
			:
			EggNog::Egg::mkbinder($submh, undef, $mdr,
# xxx	$bgroup, $user,		# xxx if this code is ever run
				"default binder", $mh->{minderhome});
		$dbname or
			addmsg($mh, getmsg($submh)),
			addmsg($mh, "couldn't create default $hname ($mdr)"),
			return undef;

		# If we get here, the default minder is being created to
		# satisfy a request either to make a minder or to use one.
		# Either way, we just satisified the request.
		#
		$mh->{opt}->{verbose} and $om and
			$om->elem("note", "creating default $hname ($mdr)");
		# XXXX maybe this needs to make noise when we create
		#      a minter with no arg given
		return $mdr;
	}
#xxxx   how do we conduct mkminder calls then other calls in a
#       bulkcommand context on the same $mh?  Does it make sense?

	# If we're here, the default minder already existed.  If we weren't
	# asked to create a minder, we can just return the default minder,
	# otherwise we have to generate a minder.
	#
	$flags & O_CREAT and
		return gen_minder($mh, $minderpath);
	return $mdr;
}

sub gen_minder { my( $mh, $minderpath )=@_;

	# If we're here, we need to generate a new minder name and then
	# create the new minder.  How we generate depends on the minder
	# type.  We either "snag" a higher version of the name or, for a
	# minter, we mint (cast, as in "cast a die, which is used to
	# mint") a new shoulder.
	#
	my $mdr;
	my $om = $mh->{om};
	my $hname = $mh->{humname};		# name as humans know it
	if ($mh->{type} ne ND_MINTER) {
		my ($n, $msg) = File::Value::snag_version(
			catfile($mh->{minderhome}, $mh->{default_minder}),
				{ as_dir => 1 });
		$n < 0 and
			addmsg($mh, "problem generating new $hname name: " .
				$msg),
			return undef;
		$mdr = $mh->{default_minder};
		$mdr =~ s/\d+$/$n/;	# xxx assumes it ends in a number
		# xxx shouldn't we be using name returned in $msg?
		# XXX this _assumes_ only other type is ND_BINDER!!
		my $dbname = EggNog::Egg::mkbinder($mh, undef, $mdr,
# xxx	$bgroup, $user,		# xxx if this code is ever run
			"Auto-generated binder", $mh->{minderhome});
		$dbname or
			addmsg($mh, "couldn't create snagged name ($mdr)"),
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

	# New $cmh (caster minder handler) is auto-destroyed when we leave
	# scope of this routine.
	# We use some of the old handler's values to initialize.
	#
	my $c_opt = $implicit_caster_opt;
	$c_opt->{rlog_preamble} = $mh->{opt}->{rlog_preamble};
#$c_opt->{version} = $mh->{opt}->{version};
		# XXX this probably corrupts $implicit_caster_opt
	my $cmh = EggNog::Minder->new(ND_MINTER, 
		$mh->{WeAreOnWeb},
		File::OM->new("anvl"),	# default om has no outputs for
					# next implicit mkminter operation
		$mh->{minderpath}, $c_opt);
		# xxx {om} ?? logging?
	$cmh or
		addmsg($mh, "couldn't create caster handler"),
		return undef;

	# yyy assume this caster thing itself is of type minter
	#$mdr = $mh->{caster};
	$mdr = "caster";
	my $mdrd = fiso_dname($mdr, $nogbdb);
	#my $mdrfile = find_minder($minderpath, $mdrd);	# find the caster

	# Use first minder instance [0], if any, or the empty string.
	my $mdrfile = (exists_in_path($mdrd, $minderpath))[0] || "";

	if ($mdrfile) {			# yyy inelegant use of $mdrfile
		mopen($cmh, $mdr, O_RDWR, $minderpath) or
		return undef;
	}
	else {	# else it looks like we need to create caster first
		# Output messages from implicit mkminter and hold
		# operations are mostly suppressed.
		# 
		my $dbname = EggNog::Nog::mkminter($cmh, undef, $mdr,
				$implicit_caster_template, $mh->{minderhome});
		$dbname or
			addmsg($mh, getmsg $cmh),
			addmsg($mh, "couldn't create caster ($mdr)"),
			return undef;
		EggNog::Nog::hold($cmh, undef, "hold", "set",
				@implicit_caster_except) or
			addmsg($mh,
				"couldn't reserve caster exceptions ($mdr)"),
			return undef;
	}

	# If we get here, we have an open caster.  Now use it.
	#
	$mdr = cast($cmh, $mh->{minderpath});
	$mdr or
		addmsg($mh, getmsg($cmh)),
		return undef;
	$om and
		$om->elem("note", "creating new minter ($mdr)");

	# If we get here, we have a new unique shoulder string, and now
	# we create its corresponding minter using a new $submh (sub
	# minder handler) that is auto-destroyed when we leave the scope
	# of this routine.
	#
	my $opt = $implicit_minter_opt;
	$opt->{rlog_preamble} = $mh->{opt}->{rlog_preamble};
		# XXX this probably corrupts $implicit_minter_opt
	my $submh = EggNog::Minder->new(ND_MINTER, 
		$mh->{WeAreOnWeb},
		File::OM->new("anvl"),	# default om has no outputs for
					# next implicit mkminter operation
		$mh->{minderpath}, $opt);
		# xxx {om} ?? logging?
	$submh or
		addmsg($mh, "couldn't create handler for newly cast shoulder"),
		return undef;
	my $dbname = EggNog::Nog::mkminter($submh, undef, $mdr, $mdr . $implicit_minter_template,
	# XXXXX should handle defaults via variables?
		$mh->{minderhome});
	$dbname or
		addmsg($mh,
			"couldn't create minter for generated shoulder ($mdr)"),
		return undef;

	return $mdr;
}

# Assume $mh is open, mint a minder name that doesn't exist.
#
sub cast { my( $mh, $minderpath )=@_;

	my $mdr;		# generated minder name
	my ($max_tries, $n) = (10, 1);
	while ($n++ < $max_tries) {
		($mdr, undef, undef) = EggNog::Nog::mint($mh, undef, 'cast');
		defined($mdr) or
			addmsg($mh, "ran out of shoulders!?"),
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
		addmsg($mh, "Giving up after $n tries to make new minter name"),
		return undef;

	return $mdr;
}

# call with which_minder($cmdr, $mh->{minderpath})
# yyy this wants to use the same algorithm as mopen follows
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

 use EggNog::Minder ':all';	    # import routines into a Perl script

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
# yyy is this needed? in present form?
#
# get next value and, if no error, change the 2nd and 3rd parameters and
# return 1, else return 0.  To start at the beginning, the 2nd parameter,
# key (key), should be set to zero by caller, who might do this:
# $key = 0; while (each($noid, $key, $value)) { ... }
# The 3rd parameter will contain the corresponding value.

sub eachnoid { my( $mh, $key, $value )=@_;
	# yyy check that $db is tied?  this is assumed for now
	# yyy need to get next non-admin key/value pair
	my $db = $mh->{db};
	my $om = $mh->{om};

	#was: my $flag = ($key ? R_NEXT : R_FIRST);
	# fix from Jim Fullton:
	my $flag = ($key ? R_NEXT : R_FIRST);
	if ($db->seq($key, $value, $flag)) {
		return 0;
	}
	$_[1] = $key;
	$_[2] = $value;
	return 1;
}
=cut
