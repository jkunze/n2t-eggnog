package EggNog::Session;

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	config tlogger read_conf_file
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Spec::Functions;
use File::Path 'mkpath';
use File::Basename;
use EggNog::RUU;
use File::Value 'flvl';
use EggNog::Log qw(init_tlogger);
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;
use YAML::Tiny 'LoadFile';
use Config;

use constant TIMEZONE		=> 'US/Pacific';

#xxxuse constant EXDB_CONNECT	=> 'mongodb://localhost';  # xxx replicasets?
use constant SMODE_MAIN		=> 'real';	# storage mode
use constant SMODE_ALT		=> 'test';	# storage mode
use constant SMODE_DEFAULT	=> 'real';	# storage mode
use constant TESTING_DATA	=> 'td_';

# External database record attributes.
use constant EXDB_CTGT	 	=> '_t';	# content target element
use constant EXDB_ITGT_PX 	=> '_,eTi,';	# inflection target prefix
use constant EXDB_MTGT_PX 	=> '_,eTm,';	# metadata tgt. prefix (conneg)

use constant EGGNOG_DIR_DEFAULT		=> '.eggnog';
use constant SERVICE_DEFAULT		=> 's';		# default service name
use constant HOST_CLASS_DEFAULT		=> 'loc';

use constant CONFIG_FILE_DEFAULT	=> 'eggnog_conf_default';
use constant CONFIG_FILE		=> 'eggnog_conf';
use constant PFX_FILE_DEFAULT		=> 'prefixes_default.yaml';
use constant PFX_FILE			=> 'prefixes.yaml';
use constant TXNLOG_DEFAULT		=> catfile 'logs', 'transaction_log';

use constant MG_CSTRING_HOSTS_DEFAULT	=> 'localhost';
use constant MG_REPSETOPTS_DEFAULT	=> '';
use constant MG_REPSETNAME_DEFAULT	=> 'live';

######################### Default Configuration ##################
our $default_cfc =	# zero-config requires default config file contents
qq@
# XXX this file should be more generic, leaving real conf file to be
# custom built, eg, via build_server_tree

# This is the configuration file for "egg" (v$VERSION).
# It is in YAML format and has separate sections (associative arrays)
# introduced by unindented top-level keys.

# Top-level binder flags section
# status is one of enabled, disabled, or readonly

service: s
role_account: eggnog_role	# else defaults to service name
contact_email: info_at_example.org

hosts:				# all sample values, just so there's something
  localhost:			# used if EGNAPA_HOST env var value isn't a key
    shell_name: localhost	# must be unique
    class: loc			# may default to what's found in the hostname
    client_name: loc		# one instance of this class as known to wegn
    patch_18: 1			# patch on the 18th
    one_check: 1		# one = true
    zero_check: 0		# zero value (false)
    false_check: false		# false = true
    empty_check:		# empty value (false)

flags:
  status: enabled
  on_bind: "keyval | playlog"
  alias: "&P | http://n2t.net/ark:/99166"
  resolver_ignore_redirect_host: n2t

# Top-level permissions section.
# XXXX doubles currently also to establish upids for common users. xxx
#      better to define that mapping separately, and express everything
#      in this file in human-readable-string form instead of upids
#   ** see new defagent addition to ruu section

permissions:
  - "&P/2 | public | 40"
  - "&P/1 | admin | 77"

# Authentication section.  This should really be in its own file where
# it could be shared among many minders and maintained independently.
# You get the given pid with you if you pass the test, eg, "all" (no test),
# password challenge, or ipaddress test.
#
# Some users might proxy for (to) any user.
# !xxx merge :: permissions section into :: ruu section
# !xxx Call egg with --defagent 'ezid|&P/mm|NN|proxy'  (NO?!)
# defagent = agent_login | user_pid | permissions | {proxy,every,<empty>}
#    where proxy means the user can proxy for others (eg, ezid) and
#    where 'every' means (a) the default, non-authn'd user (eg, public) 
#          and (b) that every user possesses at least these rights
#    and the 'admin' sample below won't work unless --defadmin is given?
# xxx make sure defagent admin isn't standard, or everyone's default setup
#    is wide open and public write
#
# These are like user classes (admin, public), defining high-level perms.

#ruu:
uinfo:
  - "admin | &P/1 | 77 | proxy"
  - "public | &P/2 | 40 | every"

# ca = condition | agent_group
# proxyall = agent_login
# where the agent and login are human readable, eg, login name
# Everyone is a member of group "public" (xxx has at least agentid public).
#ca: all | public
#ca: ipaddr ^127\\.0\\.0\\.\\d+ | testgroup

# Software used for internal and external databases.
# Set dbie to 'i', 'e', or both ('ie').
db:
  indb_class: berkeleydb
  exdb_class: mongodb
  exdb_connect_string: "mongodb://localhost"
  dbie: i

# Redirects section, with pre-binder-lookup and post-binder-lookup subsections.
# Similar to Apache server redirects, lines in each subsection have the form
#
#  - Mode Pattern [Status_code] TargetURL
#
# where Mode is one of r=regex, s=string literal, or t=tree,
# and Pattern is the incoming URL path, Status_code is an option 3-digit
# HTTP code (usually of the form 3NN), and TargetURL is the URL to send
# matching patterns to.
# NB: the only Mode currently working is "s" (literal).
# NB: only pre_lookup redirects are currently working.

redirects:
  pre_lookup:
    - "s e/ezid https://ezid.cdlib.org"
  post_lookup:
    - "s e/NAAN_request https://goo.gl/forms/bmckLSPpbzpZ5dix1"

@;

sub connect_string { my( $hostlist, $repsetopts, $setname )=@_;

	defined($hostlist) && defined($repsetopts) && defined($setname) or
		return undef;		# all args must be defined
	return 'mongodb://' .
			$hostlist . "/?$repsetopts" . "&replicaSet=$setname";
}

# Create a new, configured session so we can use its attributes.
# Returns a pair ($sh, $msg), where $sh is defined on success.
# On error, $sh is undefined and $msg contains an error message.
# Called from ApacheTester::test_binders() without the benefit of
# egg arg processing, but we need a way to pass in equivalent of
# --home Dir, so we do it with $egnhome (a bit of a kludge).

sub make_session { my( $egnhome )=@_;

	use EggNog::Session;
	my ($sh, $msg);

	my $opt = $egnhome ? { home => $egnhome } : {};
	$sh = EggNog::Session->new(0, '', '', $opt) or
		return ($sh, "couldn't create session handler");
	$msg = EggNog::Session::config($sh) and
		return ($sh, $msg);
	return ($sh, $msg);
}

# Load YAML file and return pointer to YAML struct on success.
# Return undef on error and sets second arg to an error message.
# This routine protects egg by catching exceptions thrown by YAML.

sub LoadYAML { my( $file, $errmsgR )=@_;

	my $yaml;
	my $ok = try {
		$yaml = YAML::Tiny::LoadFile($file);
	}
	catch {		# NB: catch this exception or process aborts
		$$errmsgR = $YAML::Tiny::errstr;
		return undef;	# returns from "catch", NOT from routine
	};
	#! defined($ok) and
	#	return...
	return $yaml;
}

# Creates default conf file from global $default_cfc contents.

sub init_conf_file { my( $conf_file )=@_;

	my $dir = dirname $conf_file;
	my $msg;
	my $ok = try {
		$msg = mkpath( $dir );
	}
	catch {
		$msg = "Couldn't create config directory \"$dir\": $@";
		return undef;
	};
	$ok // return $msg;	# test for undefined since zero is ok

	return
		flvl("> $conf_file", $default_cfc);
}

# read_conf_file($sh, [$hostname] )
# init default if not there
# modify $sh->{host_config} based on $hostname or envvar or options
# modify $sh->{cfh} on return
# return '' on success, or error message on error

# zzz is this needed as a separate routine (could be inline)?
sub read_conf_file { my( $sh )=@_;

	my $msg;
	if (! -e $sh->{conf_file_default}) {	# create default config file
		($msg = init_conf_file( $sh->{conf_file_default} )) and
			return $msg;	# if there's a message, error out
	}
	my $conf_file =
		(-e $sh->{conf_file} ? $sh->{conf_file} :
			$sh->{conf_file_default});	# which should exist
	$sh->{conf_file_actual} = $conf_file;	# save actual conf file chosen
				# yyy document key; record event in txnlog

	# Now read the config file. Any conflicting
	# settings from the latter will override those from the former.
	# NB: either call to LoadFile may throw a fatal (uncaught) exception,
	# which is ok (yyy right?) because something would be very wrong.

	my $errmsg;		# reference to string
	my $cfh = LoadYAML($conf_file, \$errmsg) or	# config hash of hashes
		return "$conf_file: config file load failed: $errmsg";
	$sh->{service_config} = $cfh;		# config hash
	my $key = $cfh->{hosts}->{ $sh->{hostname} } ?
		$sh->{hostname} : 'localhost';
	$sh->{host_config} = $cfh->{hosts}->{ $key } and
		$sh->{host_config}->{ _key } = $key;	# add key to id entry
		# added key '_key' distinguished by initial underscore

	return '';		# success
}

# Eggnog session configuration. Defines $sh->{cfgd} when done.
# Returns empty string on success, or an error message on failure.

sub config { my( $sh )=@_;

	# yyy {home} should be where binders and minters go too
	# yyy drop this and drop per-binder config (for now) soon

	my $msg;
	$msg = read_conf_file($sh) and
		return $msg;
	my $cfh = $sh->{service_config};

	$sh->{smode} ||=
		$sh->{opt}->{smode} || SMODE_DEFAULT;
	$sh->{smode} eq SMODE_MAIN		# enforce "test" or "real"
			|| $sh->{smode} eq SMODE_ALT or	# if messed up
		$sh->{smode} = SMODE_ALT;	# assume caller meant "test"

	# Need service and yyy? host_class to form unique database names.

	$sh->{service} =			# service name, eg, n2t, web
		$sh->{opt}->{service}
		|| $ENV{EGNAPA_SERVICE}		# yyy ? zzz
		|| SERVICE_DEFAULT;		# eg, "s"

	$sh->{host_class} = $ENV{HOST_CLASS}	# eg, dev, stg, prd
		|| HOST_CLASS_DEFAULT;

#	$sh->{conf_file_actual} = $conf_file;	# save actual conf file used

	# Config info should now be in $cfh, in 4 parts.  yyy probably unused
	$sh->{conf_flags} = $cfh->{flags} || '';	# 1/4 kinds of config

	# Need to turn array into strings.
	my $defagents = $cfh->{uinfo} || [];		# defined agents
	#my $defagents = $cfh->{ruu} || [];		# defined agents

	# kludge for scan_cfc to make blob look like list of lines of the form
	#    defagent: admin | &P/1 | 77 | proxy
	#$sh->{conf_ruu} = "defagent: " .		# 2/4 kinds of config
	$sh->{conf_uinfo} = "defagent: " .		# 2/4 kinds of config
		join "\ndefagent: ",
			@$defagents;

	# Need to turn array into strings.
	my $perms = $cfh->{permissions} || [];

	# Because we want permissions checks to go quickly without need for
	# regular expressions to tolerate optional whitespace and comments,
	# we do one-time data normalization to reduce such variability.
	#
	$sh->{conf_permissions} = "p:" .		# 3/4 kinds of config
		join "\np:",			# as optimization, squeeze out
			map { s/[ \t]+//g; $_ }			# whitespace
				@$perms;
	# kludge for scan_cfc to make blob look like list of lines of the form
	#    p: &P/2 | public | 40

	$sh->{conf_db} = $cfh->{db} || '';	# 4/4 kinds of config

	my $redirs = $cfh->{redirects} || '';	# 5/4 kinds of config
	if ($redirs) {
		$sh->{conf_pre_redirs} = redir_recs($redirs->{pre_lookup});
		$sh->{conf_post_redirs} = redir_recs($redirs->{post_lookup});
	}
	else {
		$sh->{conf_pre_redirs} = '';
		$sh->{conf_post_redirs} = '';
	}

	##### Done retrieving information from the config file.

	my $rignore_redirect_host =
			$sh->{conf_flags}->{resolver_ignore_redirect_host} or
		return "xxx temporary check: unset resolver_ignore_redirect_host in config file";


# xxx can we move this into "new" ??
#     depends on opts and (currently) conf_db dbie setting
#     depends on ENV var
	# $dbie: whether to use internal or external database, or both
	# precedence: in order, check
	# 1. command line ops (in $sh->{opt})
	# 2. EGG_DBIE env var setting
	# 3. EGG env var setting (in $sh->{opt}) (yyy should consult
	#       in module, eg, even if NOT called by egg)
	# 4. config file

	# xxx these DBIE setting look like a mess
	my $dbie =
		$sh->{opt}->{dbie} || $ENV{EGG_DBIE} || $sh->{conf_db}->{dbie};
	$ENV{EGG_DBIE} and ! $sh->{opt}->{dbie} and
		$sh->{EGG_DBIE} = $ENV{EGG_DBIE};
	! defined($dbie) and
		$dbie = 'i';		# default is internal only
	# if dbie is 'ie', read internal only
	# if dbie is 'ei', read external only
	$sh->{ietest} =		# test for equality on fetch if option
		$dbie =~ s/=$//;	# ends in '=', and remove from option
	if ($dbie ne 'e' && $dbie ne 'ie' && $dbie ne 'ei' && $dbie ne 'i') {
		return "unknown dbie option value ($dbie): should be " .
			"i (internal), e (external), ie (set both, fetch " .
			"internal), ei (set both, fetch external); 'ie=' " .
			"means fetch both and test for equality (not yet)";
			# xxx for now we always fetch internal if "both"
	}
	my $pos;
	if (($pos = index($dbie, 'i')) > -1) {
		$sh->{indb} = 1;		# xxx document these keys
		$sh->{fetch_indb} =		# read indb on fetch if 0
			$pos == 0 || $sh->{ietest};
	}
	if (($pos = index($dbie, 'e')) > -1) {
		$sh->{exdb} = {};		# yyy document these keys

		# We're doing exdb connections, so finalize our environment.
		$ENV{MG_CSTRING_HOSTS} ||= MG_CSTRING_HOSTS_DEFAULT;
		$ENV{MG_REPSETOPTS} ||= MG_REPSETOPTS_DEFAULT;
		$ENV{MG_REPSETNAME} ||= MG_REPSETNAME_DEFAULT;

		$sh->{exdb}->{connect_string} =
			connect_string( $ENV{MG_CSTRING_HOSTS},
				$ENV{MG_REPSETOPTS}, $ENV{MG_REPSETNAME} )
			|| $sh->{conf_db}->{exdb_connect_string};
		$sh->{fetch_exdb} =		# read exdb on fetch if 0
			$pos == 0 || $sh->{ietest};
	}

	# Record as much as we can find out about the person or agent
	# who is calling us.
	# Note: this is the only time that $sh->{uinfo} is defined or redefined.
	# yyy add to $sh config file name used and last time it was read?
	#
	my $ruu = EggNog::RUU->new(	# XXX stop calling from $mh config
		$sh->{WeAreOnWeb},
		$sh->{conf_uinfo},
		$sh->{u2phash},
	);

	my $authok;
	($authok, $msg) = $ruu->auth(		# potentially expensive; sets
		$sh->{opt}->{user} );		# $ruu->{who}, $ruu->{where}
				
	! $authok and
		return $msg;
	$sh->{ruu} = $ruu;

	# with $ruu set we have enough to define default_bname_parts
	$sh->{default_bname_parts} = EggNog::Binder::init_bname_parts($sh);

	#use Data::Dumper "Dumper"; print Dumper $sh->{default_bname_parts};

	if ($sh->{exdb}) {
		# yyy a tiny stab at generic external db support;
		#     you'd better say mongodb or you won't get through
		lc( $sh->{conf_db}->{exdb_class} ) ne 'mongodb' and
			return 'Unknown external database class: ' .
				$sh->{conf_db}->{exdb_class};
		my $ok = try {
			$sh->{exdb}->{client} =		# "soft connect"
				MongoDB->connect($sh->{exdb}->{connect_string});
		}
		catch {
			$msg = "mongodb connect error: $_->{message}";
			return undef;	# returns from "catch", NOT from routine
		};
		$ok // return $msg;	# test for undefined since zero is ok
	}

	# aim to be able to test using $mh->{sh}->{indb} and $mh->{sh}->{exdb}
	# xxx test scripts should use $buildout_root for dbpath/log files

	$msg = init_tlogger($sh) and
		return $msg;

	$sh->{cfgd} = 1;	# boolean to see if session is "configured"
	return '';
}

# Take a redirect array reference and a return hash reference.

sub redir_recs { my( $rarrayR )=@_;

	my $hashR = {};
	my ($i, @line);
	foreach my $i ( @$rarrayR ) {
		@line = split ' ', $i, 3;
		$line[0] ne 's' and		# only 's' supported right now
			next;			# so skip all others
		$hashR->{ $line[1] } = $line[2];
	}
	return $hashR;
	#  pre_lookup:
	#    - "s /e/naan_request https://goo.gl/forms/bmckLSPpbzpZ5dix1"
	#    - "s /e/NAAN_request https://goo.gl/forms/bmckLSPpbzpZ5dix1"
}

# Set $minderhome and @minderpath.
sub init_minder { my( $home, $mpath )=@_;

	# The minderpath (@minderpath) is a colon-separated sequence of
	# directories that determines the set of known minders.  A minder
	# in a directory occurring earlier in @minderpath hides a minder
	# of the same name occurring later in @minderpath.

	# If neither is set, the default minderpath (for egg at least)
	# is <~/.eggnog/binders:.>.
	# If we need to create a minder (eg, $default_minder_nab), we'll
	# attempt to create it in the first directory of @minderpath.
	#
	# Set default minderpath if caller didn't supply one.
	#$mpath ||= $home . $Config{path_sep} . ".";	# add current dir

	$mpath ||= catfile($home, 'binders') .	# yyy 'binders' literal -1
		$Config{path_sep} . ".";	# add current dir

	my @minderpath = split($Config{path_sep}, $mpath);
	my $minderhome = $minderpath[0];
	return ($minderhome, @minderpath);
}

# When done, this object should be initialized with these attributes:
#  {WeAreOnWeb} {om} {opt} {home}
#  {conf_file} {conf_file_default}
#  {txnlog_file_default}
#  {pfx_file} {pfx_file_default}
#  {trashers}
#  {db_isolator}

sub new {		# call with WeAreOnWeb, om, om_formal, optref

	my $class = shift || '';	# XXX undefined depending on how called
	my $self = {};
	$class ||= "Session";
	bless $self, $class;

	$self->{WeAreOnWeb} = shift;
	defined( $self->{WeAreOnWeb} ) or	# yyy need a safe default, and
		$self->{WeAreOnWeb} = 1;	#     this is more restrictive
	$self->{remote} = $self->{WeAreOnWeb};	# one day from ssh also
	$self->{om} = shift || '';		# empty $om means be quiet
	$self->{om_formal} = shift || '';
	#$self->{om_formal} = $self->{opt}->{om_formal} || $self->{om};

	use Sys::Hostname;
	$self->{hostname} = $ENV{EGNAPA_HOST} ||
		hostname() || '';	# defined even if empty

	$self->{dbhome} = '';		# dir of the open internal database
					# yyy don't really need to initialize

	$self->{opt} = shift || {};	# this should not be undef
	if (! $self->{om}) {
		use File::OM;
		$self->{om} ||= File::OM->new('anvl');
		$self->{om}->{outhandle} = '';		# return strings
	}
	$self->{om_formal} ||= $self->{om};

	#$self->{version} = $self->{opt}->{version};	# yyy what?
	$self->{version} = $VERSION;
	# yyy comment out undef's for better 'new' performance?

	# yyy all of the above can be dropped from $mh? except $om maybe?

	# eggnog session home dir, for config, binders, minters, prefixes, etc.
	$self->{home} = $self->{opt}->{home}		# eg, .../apache2
		|| catfile( $ENV{HOME} || '',	# on web $ENV{HOME} can be null
			EGGNOG_DIR_DEFAULT )		# eg, ~/.eggnog
		|| '';

	# NB: binder/database connection settings done at configuration time.

	# $self->{minderpath} is a Perl list; arg is colon-separated list
	# xxx confusing difference between string path and array path!
	# ** $mh->{minderpath} is an ARRAY ref ** (should it be minderpath_a?)
	#
	($self->{minderhome}, @{ $self->{minderpath} }) =
		init_minder($self->{home}, $self->{opt}->{minderpath});
					# option arg is a STRING
	#{minder_file_name} = $mdrd, from ibopen(), is the associated filename

	$self->{conf_file} = catfile( $self->{home}, CONFIG_FILE );
	$self->{conf_file_default} =
		catfile( $self->{home}, CONFIG_FILE_DEFAULT );
	# we open config file only if we need it, eg, NOT for help command

	$self->{txnlog_file_default} =
		catfile( $self->{home}, TXNLOG_DEFAULT );
	# we open txnlog file only if we need it, eg, NOT for help command

	$self->{pfx_file} = catfile( $self->{home}, PFX_FILE );
	$self->{pfx_file_default} =
		catfile( $self->{home}, PFX_FILE_DEFAULT );
	# we open pfx_file only if we need it, eg, NOT for help command
	# to force use of hardwired prefixes, specify --pfx_file=''

	$self->{fiso} = undef;
	initmsg($self);		# xxx use this for message not requiring $mh
	$self->{ug} = undef;		# transaction id generator xxx needed?
	# xxx transition to using this log, not log in $mh
	$self->{log} = undef;
	$self->{top_p} = undef;		# top level permissions cache yyy?
	$self->{trashers} = 'trash';	# eg, .minders/trash (yyy configurable)
	# xxx define caster location? now .minders/caster is hardwired

	# caching for performance xxx keep?
	$self->{last_need_authz} = 0;	# holds OP_WRITE, OP_EXTEND, etc.

	return $self;
}

sub session_close { my( $sh )=@_;

	$sh->{db}			or return;	# yyy right test?
	$sh->{opt}->{verbose} and
		($sh->{om} and $sh->{om}->elem("note",
			"closing minder handler: $sh->{fiso}"));
	defined($sh->{log})
		and close $sh->{log};	# XXX delete
#	undef $sh->{rlog};		# calls rlog's DESTROY method
	undef $sh->{db};	# yyy?
	undef $sh->{ruu};
	# yyy should and array minder handlers live under a session handler?
	#     ... and get closed when the session is closed?
	# XXXXX test MINDLOCK!!
	defined($sh->{MINDLOCK})	and close($sh->{MINDLOCK});
	return;
}

# xxx document changes that object interface brings:
#     cleaner error, locking, and options handling
sub DESTROY {
	my $self = shift;
	session_close($self);
	undef $self;
}

# xxx Should probably replace unauthmsg() and badauthmsg() with a
#     routine in CGI::Head that returns an array of header name/val
#     pairs for a given error condition or relocation event
#
# Adds an authn http error message to a minder handler for output.
## If $msg arg is an array reference, add all array elements to msg_a.
#
sub unauthmsg { my( $mh, $vmsg )=@_;

	#xxx can this realm stuff can be tossed -- apache handles it all??
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

Session - routines to support eggnog sessions

=head1 SYNOPSIS

 use EggNog::Session;	   

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2017 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
