package EggNog::RUU;

# how to make this secure for web but permissive for non-web?
# if we're not on the web, whoever runs me and has read/write
# permission on the database is effectively "root"
#   if that's how it has to be, how to reflect that in
#   the $ruu struct?  special "user" named "admin"?

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	set_conf get_conf
	$adminpass $testpass $admin_id
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

######	Configuration file support  #####

# Well-known users:
#        oca ark:/99166/n2t/1c9  (admin)
#       ezid ark:/99166/n2t/3z1  (admin)
#   n2tadmin ark:/99166/n2t  (admin)
#      admin ark:/99166/1
#     public ark:/99166/2
#   testuser ark:/99166/8
#  testgroup ark:/99166/9
#
# XXX should those arks be abbreviated (eg, p7b) to save space in the db?

our $adminpass		= 'xyzzy';
our $testpass		= 'testpass';
our $admin_id		= '&P/1';
our $public_id		= '&P/2';
our $testuser_id	= '&P/8';
our $testgroup_id	= '&P/9';

# xxx put default_cfc in set_conf so it doesn't have to be eval'd unless run
# The default configuration file contents, if there's no config file.
#
# xxx should use $mh->{version} instead of $VERSION

# Needed in short term: return unauth for any mod in resolver mode
# Medium term: who is admin, and what perms public and admin have

######################### Default Configuration ##################
our $default_cfc =	# zero-config requires default config file contents
qq@
# This is the default configuration file for "egg" (v$VERSION).
# It is in ANVL format and has 3 sections.

:: flags
# Top-level binder flags section
# status is one of enabled, disabled, or readonly
status: enabled
on_bind: keyval | playlog
alias: &P | http://n2t.net/ark:/99166

:: permissions
# Top-level permissions section.
# XXXX doubles currently also to establish upids for common users. xxx
#      better to define that mapping separately, and express everything
#      in this file in human-readable-string form instead of upids
#   ** see new defagent addition to ruu section
p: &P/2 | public | 40
p: &P/1 | admin | 77

:: ruu
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
# These are really like user classes, defining high-level perms
defagent: admin | &P/1 | 77 | proxy
defagent: public | &P/2 | 40 | every

# ca = condition | agent_group
# proxyall = agent_login
# where the agent and login are human readable, eg, login name

# Everyone is a member of group "public" (xxx has at least agentid public).
#ca: all | public
#ca: ipaddr ^127\\.0\\.0\\.\\d+ | testgroup

@;

# Scan Configuration File Contents xxx actually, just "ruu" section.
# Called by user_cred, which is called by auth/shell_auth/web_auth
# Returns a list of effective agentid and otherids, with error
# indicated by a null agentid (elem 0) and a message in the elem 1.
# yyy modified now to skip any check of ppa lines, since all auth
#     is handled by Apache module
sub scan_cfc { my(  $ruu,  $cfc, $user, $pass, $proxy2 ) =
		 ( shift, shift, shift, shift,  shift );

	my ($s, $tag, @vals);
	my ($agentid, @gids, @proxyfrom) = ('', (), ());
	my ($agent, $upid, $perms, $flag);
	my (%agents, %perms, %proxyagents);
	for $s (split("\n", $cfc)) {		# XXXX no ANVL continue lines

	# XXX this is likely obsolete
		# Exhaustive scan, potentially long.  Skip anything that
		# doesn't look like an ANVL element, including comments and
		# blank lines.  Do simple match against plain text user and
		# password for ppa: lines, leaving loop at the first match.

		$s =~ /^#/ || $s =~ /^\s*$/s and	# skip blanks/comments
			next;
		$s !~ s/^\s*([^:]*):\s*// and
			next;	# skip anything not having a ":" as mal-formed
		($tag = $1) =~ s/\s+$//;	# trim trailing whitespace

		$tag ne 'defagent' and
			next;			# optimize away for now

		#@vals = split(/\s*\|\s*/, $s);
		#print "sjoin=", join("!", $tag, @vals), "\n";

		($agent, $upid, $perms, $flag) = split(/\s*\|\s*/, $s);

		#             0             1          2       3
		# defagent = agent_login | user_pid | perms | {proxy,every,<>}
		# defagent: admin | &P/1 | 77 | proxy
		$agent or
			return (undef, 'no agent on defagent line');
		$agents{ $agent } = $upid or
			return (undef, 'no user_pid on defagent line');
		$perms{ $agent } = $perms or
			return (undef, 'no perms on defagent line');
		$flag and
			($flag eq 'proxy' and
				$proxyagents{ $agent } = 1)
		or
			($flag eq 'every' and
				$ruu->{every_user} = $agent)
		;
	}
	$ruu->{proxy2} = $proxy2 || '';	# XXX counting on its being defined
	$ruu->{proxyfrom} = '';		# default

	$ruu->{agents} = \%agents;			# key is an agent
	$ruu->{perms} = \%perms;			# key is an agent
	$ruu->{proxyagents} = \%proxyagents;		# key is an agent
	$ruu->{every_user} ||= '';
# xxx track down and change proxyfrom to new hash above
	return ($agentid, [ $ruu->{every_user} ] );
}

sub auth { my $self = shift;

	$self->{WeAreOnWeb} and
		return $self->web_auth( @_ )
	or
		return $self->shell_auth( @_ )
	;
	# yyy may need a third case based on $self->{remote}
}

use MIME::Base64;

# Typically shell_auth returns admin privileges.  But you may simulate
# a designated user's privileges with something like
#    shell_auth( $self, $user, $pass, $proxy );
#
sub shell_auth { my( $self, $user, $pass ) =
		   ( shift, shift, shift ) ;

	# An undefined value for $user will grant admin privileges.
	#
	my ($authok, $msg) = $self->user_cred(
		$self->{remote},
		$user,
	);
	$self->{authok} = $authok;
	return ($authok, $msg);
}

# yyy upon return $self->{user} is set by user_cred
#
sub web_auth { my( $self, $user, $pass, $proxy,  $opt ) =
		 ( shift, shift, shift,  shift, shift );

	$self->{remote_user} =
		$opt->{remote_user} || $ENV{REMOTE_USER} || '?';
	$self->{remote_addr} =		# best guess as to remote IP address
		$opt->{remote_addr}
		|| $ENV{REMOTE_ADDR} || '';
	$self->{remote_port} =
		$opt->{remote_port} || $ENV{REMOTE_PORT} || '';
	$self->{http_host} =		# name of host requested by client
		$opt->{http_host} || $ENV{HTTP_HOST} || '';
	$self->{http_cookie} =		# if any
		$opt->{http_cookie} || $ENV{HTTP_COOKIE} || '';
		# XXX no cookies yet, for which see perldoc CGI::Cookie
	$self->{http_referer} =		# if any
		$opt->{http_referer} || $ENV{HTTP_REFERER} || '';
	$self->{http_user_agent} =		# if any
		$opt->{http_user_agent} || $ENV{HTTP_USER_AGENT} || '';
	$self->{http_acting_for} =		# if any
		$opt->{http_acting_for} || $ENV{HTTP_ACTING_FOR} || '';
	$self->{http_acting_for} =~	# yyy put this regex in a CONSTANT
		s|^https?://+n2t\.net/+ark:/+99166/+|&P/|i;	# &P-compress
					# and recognize multiple /s as one /

	# xxx this next needed?
	$self->{https} =		# XXXX this is ON iff https://...  ?
		$opt->{https} || $ENV{HTTPS} || '';

	my $prxy = $self->{http_acting_for};	# yyy do this prxy thing better

	# yyy nice trick:
	# $self->{msg} = join "\n", map "X-E-$_: $ENV{$_}", sort keys %ENV;

	my $pwd ||= $pass || '';
	$prxy ||= $proxy || '';

	# It is important that $usr and $pwd be defined, even if empty.
	# Undefined values for both will grant admin privileges.
	#
	my ($authok, $msg) = $self->user_cred(
		$self->{remote},
		$self->{remote_user},
		$pwd,
		$self->{https},
		$prxy,
	);

	$self->{authok} = $authok;
	return ($authok, $msg);
}

#my @elems;	# yuck -- why is this interface so off-putting?
#($m = anvl_recarray($rec, \@elems)) and
#	# XXX log this msg! (not returned to the user)
#	return 0;
#for ($i = 4; $i < $#elems; $i += 3)
#                { print "[$elems[$i] <- $elems[$i+1]]  "; }

# Updates $ruu object as a side-effect and returns tuple ($authok, $msg),
# ($ruu->{authok} also records it).
# where authok is 0 or 1, and $msg is an error message if authok is 0.

=for consideration

  if addAuthenticateHeader: r["WWW-Authenticate"] = "Basic realm=\"EZID\""

def _statusMapping (content, createRequest):
  if content.startswith("success:"):
    return 201 if createRequest else 200
  elif content.startswith("error: bad request"):
    return 400
  elif content.startswith("error: unauthorized"):
    return 401
  elif content.startswith("error: method not allowed"):
    return 405
  else:
    return 500

=cut

####### hypothesis:  groupids is really otherids, and agentid is a pid
####### most associated with a login, and otherids are pids too, typically
####### associated with a 'group' concept

#===== 1. Keep ruu associated with a user, across minder handlers?
#=====    + more efficient, more user-identity-centered, indep of minder
#=====    - where to tether authinfo: abstract "binder" realm?
#===== or
#===== 2. Make ruu associated with one minder handler?
#=====    + one-stop shop for config, more directly driven by minder reality,
#=====        sharply defined HTTP authz realm: "binder_n2t" or "binder_oca"
#=====    - requires on each mopen: re-scan of user/pwd info, re-eval of
#=====        ENV vars, and re-read of config
#=====
#===== What if we try 2, and record config file name and mtime in $mh, so we
#=====    can reduce inefficiency and only re-scan/eval/read on change?
#=====    - still has drawback of tying user identity to a given minder
#=====
#===== We can avoid requiring Egg.pm users who always run in "shell admin"
#=====    mode from ever having to know about RUU: mopen can call it on their
#=====    behalf if it's found to be undefined, and selectively redefine it
#=====    on mopen if it's found to have changed since last get_conf
#=====

# xxx add? rights for creating or deleting binders?
# Given user and optional password, read config file and return
# userid and groupids applicable to this user.  Return 3-tuple
#    $ok, $msg, $id..??
#
# ruu(login, pw, vouched4by, ipaddr, user_agt_software)
#     -> pers.uid,   pers.groupid(s)
# 
use Sys::Hostname;

# checks if the credentials passed in are ok and
# initializes ruu variables to be used to log operations and
# record and check permissions later on
#
# So far the $user is a human-friendly string, eg, kris, public, admin.
# But we will need to translate these into the user-pids (upids) that we
# compute with and record.  We want the proxied user to come in via HTTP
# Basic authN as a upid.  We need to look up users in scan_cfc via upid.
# Uniquely, $proxy2 should be a &P-compressed URL.
#
sub user_cred { my( $self, $remote, $user, $pass, $https, $proxy2 ) =
		  ( shift,   shift, shift, shift,  shift,   shift );
	
	my $cfc = $self->{conf_ruu};

	my ($agentid, $otherids);
	# xxx should have the ability to set user in ! $remote mode
	#if (! defined($user) and ! defined($pass) and ! $remote) {

	$proxy2 ||= '';
	#$user = 'testuser'; $pass = 'testbadpass';
	$self->{user} = $user;
	if (! $remote) {
		# jackpot -- you have permission to do anything
		$self->{user} ||= "+$self->{sysuser}";
		$self->{proxyfrom} =	# if no password, don't test it; this
			defined($pass) ? $admin_id : '';	# means proxy
	# yyy (or not?) replace hardwired admin (&P/1) name with configured name
	}
	else {
		$user ||= ''; 
		$pass ||= '';
	}

	($agentid, $otherids) =
		$remote || defined($user) ?
			scan_cfc($self, $cfc, $user, $pass, $proxy2) :
			($admin_id, []) ;
			# xxx this admin_id should be set by config

	# from scan_cfc, we should have definitions for:
	#     $self->{proxy2}    (directly from scan_cfc) and
	#     $self->{user}      (via web_auth)

	my ($host, $message, $authok);
	$authok = defined($agentid) or		# or $otherids is a message
		$message = $otherids;		# (overloaded array ref)

	# xxx need to have a better default agentid?

	my @light_otherids = grep		# yyy? needed remove redundant
		{$_ ne $agentid} @$otherids;	# agentids from otherids
	$self->{agentid} = $agentid || '';
	$self->{otherids} = \@light_otherids;
	#$self->{otherids} = $otherids;		# a pointer to an array
	#print "xxx otherids=$otherids, ref(otherids)=", ref($otherids), "\n";

	# The who and where elements help with user reports, logs, etc.
	# It's usually *<proxy2>, or <remote_user> if no proxy2
	#  (yyy think analogy with real/effective uids)
	#
	$self->{who} = $proxy2 ?
		"*$proxy2" : $self->{user};
#		($proxy2 ?	"*$proxy2" : $self->{user}) :
#		"+$self->{sysuser}" ;

	#print "XXXyyy $self->{remote}| $self->{who}, $self->{user},
	#		$self->{sysuser}\n";
	$self->{where} = $self->{remote_addr};	# initialize for remote case
	$remote or				# if not remote case, no need
# zzz xxx don't call hostname again -- we did it on session creation
		($host = hostname()) =~ s/\..*//,	# for FQDN since local
		$self->{where} = $host;

	return ($authok, $message);
}

# xxxx messed up?
# return matching $grp id if string implied by condition matches the $re
#     or return ()
#
sub ca_match { my( $self, $otherid, $cond, $agentid ) =
		  ( shift,    shift, shift,   shift );
# xxx $agentid unused here, and needs better name

	$cond ||= '';
	$cond eq 'all' and
		return $otherid;

	my ($test, $regexp);
	($test, $regexp) = $cond =~ /^(\S+)\s*(.*)$/ or
		return ();
	$regexp ||= '';

	# Leave now if we're in a web context, since only web checks remain.
	#
	$self->{remote} or
		return ();

	$test eq 'ipaddr' and
		return ($regexp ?
#XXXXXX replace m/$regexp/ with just ... =~ $regexp !!
			$self->{remote_addr} =~ m/$regexp/ : ());
	$test eq 'user_agent' and
#XXXXXX replace m/$regexp/ with just ... =~ $regexp !!
		return ($self->{http_user_agent} =~ m/$regexp/ ?
			$otherid : ());
	return ();
}

=for removal

# Call with split_http_user_agent($ENV{HTTP_USER_AGENT);
# Return ($client_software, $proxy2), or () on error.
# In addition to being a URL, we will also translate the initial string,
# http://n2t.net/ark:/99166 -> &P before computing or storing with it.
# This is to save space, esp. as we scale up.
#
sub split_http_user_agent { my( $huagent ) = shift;

	$huagent	or return ();
		# verbose and "no HTTP_USER_AGENT header"
	$huagent =~ s/\s*OnBehalfOf\s*\(([^)]+)\)//i or
		return ($huagent, '');		# no proxy2 found
	my $ua = $1;				# must start &P/ or http://
	$ua !~ m,^&P/, && $ua !~ m,http://, and # if not &P/... or URL
		return ($huagent, $ua);		# yyy maybe disallow?

	#$ua =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg;	# %-decode yyy??
	$ua =~ s|^https?://n2t\.net/ark:/99166/|&P/|i;	# &P-compress
	return ($huagent, $ua);			# good proxy2 value
}

# Return decoded user name and password form of HTTP Basic authentication,
# eg, "Basic <encode_base64('Aladdin:open sesame')>"
# As a special extension, returns a 3rd "proxy2" field preceding the others,
# eg, "Basic <encode_base64(':::r2d2:Aladdin:open sesame')>" to make
#   r2d2 the user on whose behalf Aladdin acts (still his password).

# "Proxy2" means, although authenticated with Aladdin, we switch "to", or
# act as if, we are the proxy2 user; we "proxy _to_ the named user" (using
# "proxy" as a verb).  That field should be a URL that is
# url-(percent)-encoded so that
# any internal ':' (highly likely) won't screw up the other ':' separators.
# We want proxy2 to be given as a URL because we (n2t) have no way to
# translate between login names and upids.  We don't want the admin user
# Aladdin to be a URL because (a) that's unfriendly to general users and
# (b) we have the means to turn it into a URL.
#
# In addition to being a URL, we will also translate the initial string,
# http://n2t.net/ark:/99166 -> &P before computing or storing with it.
# This is to save space, esp. as we scale up.
#
sub split_http_auth { my( $hauthz )= shift;

	$hauthz				or return ();
		# verbose and "no HTTP_AUTHORIZATION header"
exit;
	$hauthz =~ s/^\s*Basic\s+//	or return ();
		# verbose and "HTTP_AUTHORIZATION must be of type Basic"

	my ($proxy2, $authz) = (undef, encode_base64($hauthz));
	$authz =~ s/^:::([^:]*):// and		# non-standard $proxy field
		$proxy2 = $1;

# XXX untested
	$proxy2 and				# decode and compress
		$proxy2 =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg ,
		$proxy2 =~ s|^https?://n2t\.net/ark:/99166/|&P/|i ,
	;

	# Restrict split() to 2 since the password may itself contain a ":".
	#
	return (
		split(":",	decode_base64( $authz ),	2),
		$proxy2
	);
}

=cut

use File::Value 'flvl';
use File::ANVL 'anvl_recarray';	# xxx?

=for removal

# Returns a string with contents of config file found in the directory
# given by $conf_dir.  Returns default contents if no $conf_dir defined.
# If $conf_dir defined, it is an error for no file to be present.
# On error, the string begins with "error:".

sub oget_conf { my( $conf_dir ) = (shift);

	$conf_dir or		# no config? return hardcoded default
		return $odefault_cfc;

	my ($m, $cfc);			# try safely non-archived config
	$m = flvl('< ' . catfile($conf_dir, 'ruu_norepo.conf', $cfc));
	$m or
		return $cfc;		# quit with good return on first try

	my $msg = $m;			# now try the default config file
	$m = flvl('< ' . catfile($conf_dir, 'ruu_default.conf', $cfc));
	$m or
		return $cfc;		# quit with good return on second try

	return				# out of options, so we now fail
		"error: no RUU config file: $msg: $m";
}

=cut

# Creates a default configuration file using $cfc as contents.
# Returns the empty string on success, or a message upon error.
#
sub set_conf { my( $basename, $opt ) = ( shift, shift );

	$basename or		# no config? return hardcoded default
		return 'no config file basename';
	my $cfc = $default_cfc;
# xxx use $opt->{admin}   (ezid, &P/xxx to alter .conf file)

	return	flvl("> ${basename}conf_default", $cfc);
	#return	flvl("> ${basename}_default.conf", $cfc);
}

# Call with get_conf($basename, $cfh), where the second argument will be
# updated with a 3-value hash of the 3 major sections (3 ANVL "records")
# of the configuration file contents.
#
sub get_conf { my( $basename ) = ( shift );
	# remaining arg $_[0] is config hash ref to be defined as a side-effect

	my ($m, $cfc, $cfh, $header);
	$m = read_conf( $basename, $cfc ) and
		return $m;		# error return
	#$cfh = {};			# initialize
	($header,			# header gets tossed
		%{ $_[0] }) =		# remaining arg ($cfh) gets section
			split /\s*\n::\s*(.*)/,	# names and contents from
				$cfc;		# file content string
	return '';

	#$_[0] = $cfh;
	# xxx how about shortcut
	#my ($header, %$_[0]) = split /^:: *(\S*)/, $cfc;
}

# Call with read_conf($basename, $cfc), where the second argument will
# be updated with the contents of the configuration file read.
# Returns the empty string on success, or a message upon error.
#
sub read_conf { my $basename = shift;	# remaining arg $_[0] to be updated

	$basename or		# no config? return hardcoded default
		return 'no config file basename';

	my ($m, $cfc);			# try safely non-archived config
	# XXX maybe we don't need _norepo.conf if we already have _default
	#$m = flvl("< $basename_norepo.conf", $cfc);
	#$m or
	#	return $cfc;		# quit with good return on first try

	# NOTE: For security reasons, do NOT ever put your .conf file into
	# your open source repository.  Even if you take it back out, early
	# versions can remain forever in your repo (eg, mercurial).
	#
	#$m = flvl("< $basename.conf", $cfc);	# now try usual config
	$m = flvl("< ${basename}conf", $cfc);	# now try usual config
	! $m and
		$_[0] = $cfc,
		return '';		# quit with good return on second try

	my $msg = $m;
	$m = flvl("< ${basename}conf_default", $cfc);	# try default
	#$m = flvl("< ${basename}_default.conf", $cfc);	# try default
	! $m and
		$_[0] = $cfc,
		return '';		# quit with good return on third try

	return				# out of options, so now we fail
		"no config info: $msg: $m";
}

# Call to create new RUU object as
#    $ruu = EggNog::RUU->new($WeAreOnWeb, $conf_ruu, $mh->{u2phash}, [ $opt ]);
# maybe one day yyy old:
#    $ruu = EggNog::RUU->new($OnWeb, $conf_dir, $userid, $proxy, $opt);

# Some authorization depends on whether you are
#   remote  (eg, talking via http or ssh)
#	eg, able to do rmbinder, or change admin values
# One user can be a proxy for other users
#   proxy joe other users are listed here
# Some users can proxy for any users
#   proxyall ezid
# CGI headers are produced if
#   WeAreOnWeb

# Returns an object that collects lots of information about a potential user
# If $WeAreOnWeb is set, check for HTTP environment variables for user auth(z)n.
#   (if none, use $userid as default, eg, 'public')
#   (no default for $proxy)
#   
# if no $conf_dir, use CONF_RUU env var to set config
#
sub new { my $class = shift;

	my $self = {};
	bless $self, $class;

	$self->{WeAreOnWeb} = shift;
	defined( $self->{WeAreOnWeb} ) or	# unlikely to be undefined
		$self->{WeAreOnWeb} = 1;	# yyy more cautious assumption
	$self->{remote} = $self->{WeAreOnWeb};	# might one day be from ssh
						# xxx document remote

	# First, configuration file location and default user info.
	#
	#$self->{conf_dir} =		# directory with RUU config file
	#	$opt->{conf_dir} || $ENV{RUU_CONF} || '';
	$self->{conf_ruu} =		# RUU config file (section) contents
		shift || $ENV{CONF_RUU} || '';
	$self->{u2phash} = shift;		# pointer to user-to-upid hash
	my $opt = shift;
	$opt and		# XXXX should be defined in config file??
		$self->{every_user} =		# if none supplied
			$opt->{every_user} || '';

	# Second, get the Unix-type REAL_USER_ID and EFFECTIVE_USER_ID.
	#
	my ($name, $gid, $ugid, $sysuser);
	($name, undef, undef, $gid) =
		getpwuid($<);		# $REAL_USER_ID is in $<
	$sysuser = getlogin() || $name;
	$ugid = $sysuser . '/' .
		((getgrgid($gid))[0] || '');

	if ($> ne $<) {			# $EFFECTIVE_USER_ID is in $>
		($name, undef, undef, $gid) = getpwuid($>);
		$ugid .= " ($name/" . ((getgrgid($gid))[0] || "") . ")";
		$sysuser .= "/$name";
	}
	$self->{sysuser} = $sysuser;
	$self->{sysugid} = $ugid;	# internal system uid/gid, usually of
					# little use in identifying a web user

	#$self->{remote} = undef;	# 1 or 0 or undef
	#$self->{authok} = undef;	# 1 or 0 or undef
	#$self->{agentid} = undef;	# eg, an EZID login name
	#$self->{gids} = undef;		# normally a list
	#$self->{contact} = undef;	# a display name XXX

	return $self;
}

sub DESTROY {
	my $self = shift;

	$self->{opt}->{verbose} and
		# XXX ?
		#$om->elem("destroying minder object: $self");
		print "destroying RUU object: $self\n";
	undef $self;
}


1;

__END__

=head1 NAME

RUU - are you you?

=head1 SYNOPSIS

 use EggNog::RUU;		# import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
