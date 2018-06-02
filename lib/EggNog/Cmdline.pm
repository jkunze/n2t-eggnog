package EggNog::Cmdline;

# XXX to do to fix the $line_count problem and tidy up this sprawling mess:
#     change package name to EggNog::Cmdstream,
#     add 'new(...) that replaces "get_execution_context"
#     replace globals in noid and egg with class vars,
#     add $line_count to the object
#     put pointer to cmdstream object in $mh
#     updated pointer from instantiate

use 5.010;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	def_cmdr def_mdr
	pod2use mkdbgpr init_om_formal 
	get_execution_context launch_commands
	expand_token extract_modifiers instantiate
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

##====================## start noid/bind beginning block of notes

# bind = Bind Identifier to Named Data (args: bind i n d)
# bind i n d   same as   bind i n = d
#    interpolate var with '&x', eg, bind id x = &y + &z
#    generate id with    bind &- n = d
#    generate n with     bind i &- = d
# 

# bind id.fetch :brief	-> temporary promotion to anvl
# bind id.get :brief

# ZZZ changes since 0.424 -- many incompatible changes
##untrue: no longer uses BerkeleyDB.pm, just DB_File
##   greatly simplifying installation, stabilizing the code,
##   and eliminating PERL5LIB untainting problems
# File name changes: log->minter.log, README->minter.README, lock->minter.lock
# Env variable changes: NOG now contains command line options, not a filename
# Many option changes: -f dbdir -> -d dbdir, ...
# New concept of minder = minter/binder
# Implicit minder creation, ~/.minders directory, minder path
# portability improvements
# zero-config
# non-locking if rdonly unless --lock
# + no longer separates args in query string (used for other purposes)
# ?? disable interrupts in dblock/dbunlock windows

# Now uses File::OM to produce output in a variety of formats.

# Completely removed are:
# 1. circulation records
# 2. any concept of short/medium/long, which are irrelevant after all
#    for minters, and relevant but unenforceable in binders

# zzz lower level changes
#   default dbopen mode is O_RDONLY
#   portability improvements, eg, File::Spec->curdir() instead of env(PWD)

# zzz keep decent-sized history of minted ids (eg, 2000) to support 'unmint'
# zzzxxx --> no can do 'unmint' in multi-user environment since I might
#    unmint your identifier.
# zzz ideas: (Aug 09)
# $ noid cast -- outputs minter name
# $ noid -d foo mint
# $ noid -d foo.bar/zaf mint -- mints over net
# $ pt mknode `noid mint 3` | xargs
# $ pt mknode `noid mint 3` -- pt and noid could work on same pairtree in
#    current dir  -- how?  noid bind's use of pairtree shouldn't conflict
#    with pt's use of it

# bind set i n d -> bind i.el n d    or bind i.set n d
# bind get i n -> bind i.get n     or bind i.fetch n
# bind get i -> bind i.get     or bind i.fetch
# bind del i n -> bind i.del n
#  (not yet)  -> bind mkid i j k
#  (not yet)  -> bind rmid i j k
# therefore bind i.get n m o     requests 3 elems at once
# therefore bind i.set n d m e o f    sets 3 elems at once
# bind getfi f1 f2 f3		# get files
# bind getbl b1 b2 b3		# get blobs

# where does the '--user=U' concept fit?
# what does U own?
#   an entire id?
#   an entire element of an id?
#   an entire file of an id?
# how is ownership expressed?
#   special file at toplevel of pairtree leaf?
#     0=n2tleaf
#     1=Smith, J.
#     owner
#       eg, erc-owner: Smith, J. | objid | when | ark-of-owner
#       [ this works for whole-id ownership ]
#       [ possibility of local override at elem level with anvl sub-elems?]
#     allowable_actions
#       who(class)|what(RWUD)|when(future?)|where??
#     file/
#     elem/
#     playlog | pastlog
#       
# what are the ops on id ownership?
#   'set' implies owner setting
#   chown jak id ?
#   chown jak id elem?
#   chown jak id elem instance?  (eg, just one of the redirect targets)
#   stored as erc-owner: who|whatclassofownership|when|where??
# what identifier string to use for user?
#   ark:/99.../???

# om_anvl(OPEN|CLOSE|MORE, label, value
# om("(label" ...

#=== April 2010 ideas
# xxx bind:
#     --nofiles = index only, don't save this binding in non-volatile
#     storage
#     --noindex = don't index, just save this binding in non-volatile
#     storage
#     default is to do both, returning after saving in non-volatile
#     storage
#          and before backgrounding indexing step (except if --wait)
#===

#noid mkminter [ shoulder [ template ] ]
#noid forge 
#noid proof 
#noid mkminter foo rb2 eeddeek
#noid rmminter foo

#To solve: "noid" is to "mint" as "??" is to "bind"?
#To solve: "noid" is to "mkminter" as "??" is to "mkbinder"?
#To solve: "noid" is to "mkminter" as "bind" is to "mkbinder"?  ok, I guess
#To solve: "noid" is to "mkminter" as "bind" is to "mkminder"?
#bind mkbinder foo
#bind rmbinder foo

#mint gen ?
#mint nab ?
#mint deal ?
#mint hold ?
#mint queue ?
#mint validate ?
#mint mkminter ?
#mint mkminter -s fk2 eedek ?    -> sequential (-r random)
#mint mkminter -r fk2<eedek>  ?  -> of form "fk2<eedek>"
#mint mkminter -r fk2<eedek>bcd<dd>  ?  -> of form "fk2<eedek>bcd<dd>"
#mint mkminter --type rX|sX fk2<eedek>  ?
#   -> r=random(def)|s=sequential,  X=seed (def 0) or X=start (def 0)
#   --last cN|w,    c=continue(def)  N=top N(def 1) digits to propagate
#                   w=wrap to beginning
#   --atlast action, where action (default "add1") is one of
#	add[N]   (prepend copy of N (1) high-order blade chars and continue)
#	stop[N]   (exit, returning shell status N (3))
#
# bind command [options] id elem val
# command: set get del prepend append
#   command modes:
#	--record
#	  eg, get recno [field ...]
#            or maybe "bind record|remove|return ..." ???
#	--id  (default)
#	  eg, get id [elem]
# options:
#    --ifx     (succeed only if it exists, where "it" is any and all
#               values of the hierarchy:  id [elem [val]])
#    --ifnox   (succeed only if it doesn't exist)
#    --xonox  (default -- succeed whether it exists or not)
#    --file   (default -- bind in filesystem with pairtree)
#    --nofile   (don't bind in filesystem)
#    --index   (default -- inverse index bound value)
#    --noindex   (don't inverse index bound value)
# Binder models:
#    hierarchical model: id element value <needs binder.btree>
#	inverted index maps elem to id, values to elems, values to ...?
#		format: val \t elemno -> id
#    record model: id element value <needs binder.recno and binder.btree>
#           in record model what is id?  element? value?
#	inverted index maps val to recno, and val-fieldno to recno
#		format: val \t fieldno -> recno
#
# Strong parallels between pt and bind.
# Weak or intentionally different verbs for noid, given strong difference?

# Command forms across pt, bind, noid for ids and elems and values
# bind mkid id1 id2 ...
#   pt mkid id1 id2 ...
# bind rmid id1 id2 ...
#   pt rmid id1 id2 ...
# bind mkel id elem1 elem2 ...     #? same as "set id elem1 ''" ... ?
# ??pt mkel id elem1 elem2 ...     #? same as "set id elem1 ''" ... ?
# bind rmel id elem1 elem2 ...
# ??pt rmel id elem1 elem2 ...
# Q: are these ops undoable?

# bind = Bind Identifier to Named Data (args: bind i n d)
# bind i n d   same as   bind i n = d
#    interpolate var with '&x', eg, bind id x = &y + &z
#    generate id with    bind &- n = d
#    generate n with     bind i &- = d
# 


## bind rmelem id elem1 elem2 ...
## bind rmeleminst id elem 3 5 -1
##?bind purge id ... that purges all trace of ids

# Listings
#   pt ls            "pairtree list your tree"
# bind ls            "egg list your bindings"
#   pt lsid id ...   "pairtree list files under id ..."
# bind lsid id ...   "egg list elements under id ..."

# Context and Stats (show minders, minder stats, minder ping)
#   pt mshow       "pairtree show known minders"
# bind mshow       "egg show known minders"
# noid mshow       "minder show known minders"
#   pt mstat mdr   "pairtree show stats for minder 'mdr'"
# bind mstat mdr   "egg show stats for minder 'mdr'"
# noid mstat mdr   "minder show stats for minder 'mdr'"
#   pt mping mdr   "pairtree ping minder 'mdr'"
# bind mping mdr   "egg ping minder 'mdr'"
# noid mping mdr   "minder ping minder 'mdr'"

# pt mktree vs pt mk, lstree vs ls
# noid ls   # applies to id?
# noid rm   # applies to id?
# noid del   # applies to elem?
# noid lstree   # applies to all <what>? ids?
# pt lstree   # applies to all ids?
# bind lstree   # applies to all ids?

# Interesting:  noid mkid,  noid rmid,  noid lsid, noid ls
#
# Binder I<How>
# B<set>, B<add>, B<insert>, and B<purge> kinds "don't care"
# if there is no current binding.

# bind find query
# 
# = new Only if Element does not exist, create a new binding.
# = replace Only if Element exists, undo any old bindings and create a new binding.  
# = set Means B<new> or, failing that, B<replace>.  
# = append Only if Element exists, place Value at the end of the old binding.  
# = add Means B<new> or, failing that, B<append>.  
# = prepend Only if Element exists, place Value at the beginning of the old binding.  
# = insert Means B<new> or, failing that, B<prepend>.  
# = delete Remove any trace of Element, returning an error if it did not exist to begin with.
# 
# = purge Remove any trace of Element, returning success whether or not it existed to begin with.
# = mint Means B<new>, but ignore the Id argument (actually, confirm that it was given as B<new>) and mint a new Id first.
# = peppermint [This kind of binding is not implemented yet.] Means B<new>, but ignore the Id argument (B<new>) and peppermint a new Id first.

# yyy make a noidmail (email robot interface?)
# yyy location field for redirect should include a discriminant
#     eg, ^c for client choice, ^i for ipaddr, ^f format, ^l language
#     and ^b for browser type, ^xyz for any http header??
# yyy add "file" command, like bind, but stores a file, either as file or
#     in a big concatenation stream (binding offset, length, checksum)?
# yyy figure out whether validate needs to open the database, and if not,
#     what that means

##====================## end noid/bind beginning block of notes

use File::Value ":all";
use File::Copy 'mv';
use File::Path;
use File::Find;
use EggNog::Minder ':all';
use CGI::Head;

sub xinit_om_formal { my( $mh )=@_;

	my $om = File::OM->new('anvl',
		{ outhandle => $mh->{om}->{outhandle},
		  wrap => $mh->{om}->{wrap} });
	$om and
		return $om;
	addmsg($mh, "couldn't create formal output formatter");
	return undef;
}

## Should make a "debug printer" by creating a closure around caller's static
## view of $om and an optional $outfile (eg, for debugging web server).
##
#sub mkdbg { my( $om, $outfile )=@_;

# xxx combine this somehow with Minder::outmsg?
# yyy currently ignoring $debug_level
sub mkdbgpr { my( $debug_level )=@_;

    return sub { my( $msg, $outfile )=@_;

	my $ret = print($msg);
	my $err;
	$outfile and		# this doesn't need to be efficient
		$err = flvl(">>$outfile", $msg)
			and print($err, "\n");
	return $ret;
    }
}

=for dumb?
# second arg optional
sub debug_toggle { my( $mh, $dbgpr )=@_;

	$mh			or return 0;	# error
	$mh->{opt}->{debug} = ! $mh->{opt}->{debug};
	$mh->{opt}->{debug}	or return 1;	# if debug off -- done

	# if here, then debug was just toggled on
	$dbgpr and				# if user-supplied a routine
		$mh->{opt}->{dbgpr} = $dbgpr;	# use it
	$mh->{opt}->{dbgpr} ||= \&dbgpr;	# else use our own
	return 1;
}
=cut

=for consideration

% telnet noid.cdlib.org 80
Trying 128.48.120.77...
Connected to noid-s10.cdlib.org.
Escape character is '^]'.
GET /nd/noidu_fk4?mint+1 HTTP/1.1
host: noid.cdlib.org

HTTP/1.1 200 OK
Date: Wed, 05 Sep 2012 22:57:20 GMT
Server: Apache/2.2.22 (Unix)
Transfer-Encoding: chunked
Content-Type: text/plain

id: 99999/fk4bg370v

=cut

# returns ($error_message, $debug_message, @query_string_words)
# success if ! $error_message
#
sub massage_web_args { my( $err2out, $query_string, @ARGV )=@_;

	! $err2out and
		return ("couldn't combine stderr and stdout: $!");
	! defined($query_string) and
		return ("No QUERY_STRING (hence no command) defined.");

		#
		# If QUERY_STRING isn't given we bail.  Considered
		# the trick of testing for tty and asking user but
		# that can be annoying and can cause tests to stall,
		# which gets code blacklisted by CPAN testers.

	# Add query string arguments _after_ (late binding) any
	# other args.  We don't remove the original query string
	# because it does no harm sitting inert in the hash.
	# First, %-decode any %HH sequences.
	#
	my $line;
	($line = $query_string) =~
		s/%([[:xdigit:]]{2})/chr hex $1/eg;
	#$omx->elem("xxxxxy", "qs=$query_string, line=$line");

	# Now begins a check for naughty attempts by a web user
	# to break out of the minderpath and minder that they're
	# supposed to use, which will normally be configured upon
	# httpd startup via env variables and/or rewrite rules.
	#
	# Bottom line is (a) we REQUIRE --ua to introduce any user
	# arguments arriving in the query string and (b) we abort if
	# those user args contain things like -p or -d.
	# 
	my @qstring_words =		# yyy? ok to use shellwords
		shellwords($line);	# since $line will be short?
	my @naughty = qw(-d -p --directory --minderpath --minder);
		# xxx deprecate --minder flag?? used?
		# XXXXXXX bug! user could specify just --direc and
		#      we wouldn't spot it
	my $start_user_args = 0;	# whether --ua has been seen
	for my $arg (@qstring_words) {
		#$omx->elem("xxxdiag", "a=$arg");
		if (! $start_user_args) {
			$arg eq '--ua' and
				$start_user_args = 1;
			next;
		}
		grep {
			$_ eq $arg
			or
			$arg =~ /^--/ && $_ =~ /^\Q$arg/
		} @naughty and return ('-d or -p not allowed in query string');
	}
	! $start_user_args and			# if no --ua and
		scalar(@qstring_words) and	# there were user args
			return ('no --ua was found in front of user arguments');

	return ('', "QUERY_STRING line=$line", @qstring_words);	# success
}

use Pod::Usage;

# side effects: alters ARGV
sub get_execution_context { my( $m_cmd, $version, $getoptlistR, $optR )=@_;

	# First find out about ourselves, such as whether we're called
	# as 'bind' or 'noid' (stored in the global $WeAreBinder variable).
	#
	# The name of the executable file (typically a filesystem link)
	# for the present script is a way of hard-coding some command
	# line options.  By the principle of "latest binding", any
	# actual options override executable file name options.
	#
	my $xfn = $0;				# executable's file name
	my $WeAreBinder = ($xfn =~ m|\begg[^/]*$|);

	# Test executable file name to see if it names a minder. XXX deprecate?
	# yyy or generalize to encode option string in executable?
	#
	my $pname_mdr;
	($pname_mdr) = ($xfn =~ m|_([^/]+)$|);	# name tells which minder?

	# If certain environment variables are set we will add them as
	# synthetic command options (options usually) that, processed
	# left to right, will be correctly over-ridden by any user-supplied
	# options.  This makes a new command line that can then be written
	# to the playback log to capture both command line and environment.
	#
	my $line = "";
	my $m_evar = $WeAreBinder ? "EGG" : "NOG";
	$WeAreBinder and $ENV{RESOLVERLIST} and
		$line .= " --resolverlist $ENV{RESOLVERLIST} ";
	$ENV{MINDERPATH}	and $line .= " -p $ENV{MINDERPATH} ";
# XXXXX does this binder-as-first-arg or minter-as-first-arg work the
#       same way between egg and noid?
	$ENV{$m_evar}		and $line .= " $ENV{$m_evar} ";


#	# If we think we're on the web and we don't have systemmatic
#	# output (eg, OM) in place yet, we'll want a preamble on our very
#	# first message so that our output will be visible to caller.
#	# Our best initial guess is yes if REMOTE_ADDR is non-empty.
#	#
# XXX are $preamble and $webpreamble needed?
#	my $web_preamble = "Content-Type: text/plain\n\n";
#	my $preamble = $ENV{REMOTE_ADDR} ? $web_preamble : '';


	# Add --noop to tell playback log that synthetic options are done.
	#
	my @pre_argv = ();
	$line and	# ok to use shellwords since $line will be short
		unshift @pre_argv, shellwords($line . " --noop");

	# By the principle of latest binding, command line flags override
	# the form of the $xfn.

	# There are several ambiguous tests for whether we were called
	# from behind a server, and whether we're simulating that for
	# testing purposes.  Among them is a test for whether we're
	# behind a CGI interface, in which case we need to remove any
	# argument list that it supplied -- it's duplicative with what
	# we'll pull from the QUERY_STRING environment variable and we
	# don't want its deprecated '+'-to-space decoding.
	#
	$ENV{GATEWAY_INTERFACE} and	# a typical value is "CGI/1.1"
		@ARGV = ();

	# This next unorthodox option check precedes formal options
	# processing because it may require scooping up extra arguments
	# from $ENV{QUERY_STRING}.
	# yyy document "latest binding" rationale, eg, aliases with later
	#    options overriding earlier ones
	# yyy change $query_string name to less confusing $qs_string, as
	#     it only comes from --qs arg and not from env var
	#
	my ($WeAreOnWeb, $debug, $query_string, $http_accept);
	($WeAreOnWeb, $debug, $query_string) = (0, 0, "");
	for my $arg (@pre_argv, @ARGV) {
		defined($query_string) or	# trick to capture next arg
			($query_string = $arg), next;
		$arg eq "--debug" and
			$debug = 1
		or
		# XXX why doesn't this work?  (lots of test fail)
		#$arg eq "--rrm" and
		#	$WeAreOnWeb = 1
		#or
		$arg eq "--api" and
			$WeAreOnWeb = 1
		or
		$arg eq "--qs" and
			undef($query_string),
			$WeAreOnWeb = 1
		;
	}
	$query_string ||= "";		# don't leave it undefined

	# xxx set debug level! xxx rethink this, esp. in re. verbose
	# xxx combine this somehow with Minder::outmsg?
	#     eg, $debug and dbugpr(...)
	#     eg, $verbose and verbpr(...)
	#     with dbugpr_set_opt() and verbpr_set_opt() for initializing, etc.
	my $dbgpr = ($debug ? mkdbgpr() : undef);

	$ENV{REMOTE_ADDR} and		# one more test of remote-ness
		$WeAreOnWeb ||= 1;	# xxx but this might be non-web (ssh)
	$WeAreOnWeb ||=			# yyy one last kludgy test
		$xfn =~ m{(noid|egg)u[^/]*$};
	#
	# If we reach here, the boolean $WeAreOnWeb contains our best guide
	# to behaving as if we are on the web, whether it's for real or for
	# testing (an important use).


# XXX are $preamble and $webpreamble needed?
#	$WeAreOnWeb and ! $preamble and		# now that we know for sure,
#		$preamble = $web_preamble;	# correct $preamble if empty

	# As soon as we are able, create an OM object so that we can
	# do systematic outputting of error and diagnostic messages.
	# Once we know whether we're on the web, that's enough to
	# output the initial http header block (if need be) so that
	# output messages won't be scramble the headers and prevent
	# all other outputs from reaching anyone.
	#
	# We don't yet know what the requested format is, but if we
	# make an ANVL OM object now, we'll likely get to re-use it for
	# om_formal, web operations, or both.  We may have to update
	# it based on what we learn from find_options.
	#
	my $default_labeled_format = 'anvl';

	# This CGI header object is created if $WeAreOnWeb.  If it is
	# created, it needs to be shared among all OM objects that might
	# perform output, so that HTTP headers are output only once.
	# We may later alter the Status header, eg, with
	#    $om->{cgih}->add( { Status => '401 unauthorized' } );
	#    $om->{cgih}->add( { Status => '500 Internal Server Error' } );
	#
	# This is Head stuff is defined in lib/CGI under anvl/src/lib
	my $cgih = $WeAreOnWeb ?
		CGI::Head->new( {
			#'Status'  => '200 OK',		# optimistic
			'Content-Type'  => 'text/plain',
			"$m_cmd-version" => $version, } )
		: undef;
	my $om_optR = {
		outhandle	=> *STDOUT,
		cgih		=> $cgih,
	};

	my $err2out;		# chicken and egg problem:  can't check this
	$WeAreOnWeb and		# return until we've created an output stream
		$err2out = open(STDERR, ">&STDOUT");

	my ($emsg, $dmsg, @qstring_words);
	unshift @ARGV, @pre_argv;
	if ($WeAreOnWeb) {
		$http_accept = $ENV{HTTP_ACCEPT};
		$query_string ||= $ENV{QUERY_STRING};

		($emsg, $dmsg, @qstring_words) =
			massage_web_args($err2out, $query_string, @ARGV);

		if (! $emsg) {			# unless error
			push @ARGV, @qstring_words;
			$dbgpr and $dmsg and		# if diagnostic
				&$dbgpr("$dmsg\n");
		}
		# Sit on $emsg if any and report when we get an output channel.
	}
	$dbgpr and	# yyy fix this $dbgpr crap
		&$dbgpr("ARGV=@ARGV\n"),
		&$dbgpr("line=$line\n"),
		&$dbgpr("before find_options ARGV=" . join(", ", @ARGV) . "\n");

	# Formal options processing now occurs.
	#
	find_options($getoptlistR, $optR) or
		pod2usage(-exitstatus => 2, -verbose => 1);

	# If we get here, %opt (via $optR) contains all option settings.
	# xxx all communication with this module is an embarrassing kludge

	# Test options and executable name to see if we should be
	# operating as a resolver (as if behind Apache RewriteMap).
	#
	my $WeAreResolver = $optR->{rrm} || $xfn =~ m{binderr[^/]*$};

	# xxx need to stop creating $om for resolvers, since $om 
	#     outputs a newline, on close-rec, called by destroy;
	#     OR maybe we should just create a new OM format
	#
	my $omx = File::OM->new(		# our interim OM object
		$default_labeled_format, $om_optR,
	);
	# $WeAreResolver ? 'plain' : $default_labeled_format, $om_optR,

	# If there's no OM for output, we take a drastic step, which
	# reports to stderr, and for the web case we have to hope we
	# were able to combine stderr and stdout.
	#
	$omx or	
		die($cgih->take() . "couldn't create an OM output multiplexer" .
			" for format '$default_labeled_format'");
	#
	# If we get here, we have labeled error outputs at our disposal.

	$emsg and
		$omx->elem('error', $emsg),
		exit 1;

	my ($bulkcmdmode, $textwrap);
		# yyy make textwrap a settable command line option?
	# XXX isn't this code way too special/important to leave in
	#       this generic module?
	if ($WeAreResolver) {
		$| = 1;		# very important to unbuffer the output
		$bulkcmdmode = 1;
		$textwrap = 0;

		# 0 is signal to not use Text::Wrap at all
		# XXX isn't this really GRANVL?
		#$textwrap = 32766;	# xxx largest quantifier for Text::Wrap
	}
	else {
		$bulkcmdmode = 0;
		$textwrap = $optR->{wrap};	# xxx no wrap option yet
		defined($textwrap) or		# recall that 0 is valid value
			$textwrap = 0;		# wrapping usually a bad idea
		# xxx use window width instead of 72? if so then
		# xxx use Term::ReadKey (unauthorized release 2.30?)
		#($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
	}
	$omx->{wrap} = $om_optR->{wrap} =	# to what we did and will do,
		$textwrap;			# add a {wrap} attribute

	$dbgpr and	# xxx this $dbgpr is nonsense
		&$dbgpr("after find_options ARGV=" . join(", ", @ARGV) . "\n");

	my $format = $optR->{format} ||		# if user chose a format name,
		($WeAreOnWeb ?				# else if on the web
			$default_labeled_format :	# use labels, else use
			'plain' );			# usual Unix default
	#$WeAreResolver and			# force plain for our resolver
	#	$format = 'plain';

	$format = lc $format;			# normalize to lower case
	#
	# When we get here, $format is the main selected format.  If it
	# is 'plain', we need a labeled format for "formal" output, for
	# which we might as well use the $omx that we've already created.

	# yyy should OM pre-lowercase its format names?
	my $om = $format eq lc( $omx->{format} ) ?
		$omx :			# re-use what we already made
		File::OM->new($format, $om_optR) ;
	$om or		# yyy oddly it only fails for this one reason now
		pod2usage("$xfn: unknown format: $format");

	# For $om_formal we need a labeled format.
	#
	my $om_formal = $format eq 'plain' ?
		$omx :		# already labeled
		$om ;		# since all other formats are labeled

	return ($pname_mdr, $WeAreOnWeb, $WeAreResolver,
		$om, $om_formal, $bulkcmdmode, $cgih);
}

=for consideration

cases:
0. ?show+:brief -> html with embedded
0. 
0. ?showas+erc+:brief -> html with embedded
1. ? inflection only -> html
2. http_accept == html -> html
 XXX for "content negotiation"

Requirements for output:

  - support multiple user-selectable output formats: plain, anvl, json,
    xml, etc. (note all of these are "labeled formats" except 'plain')
  - support plain text format by default as the defacto Unix norm, unless
    behind an http server, in which case default to a labeled format
    [ $default_labeled_format = 'anvl' ]
  - support unwrapped text and text wrapped to a certain number of chars
    [ $default_text_wrap = 72 ]
  - if 'plain' selected, support an additional labeled format to alert
    users to important conditions eg, "error:..." or "warning:..."
    [ {om_formal?} ] [ $default_labeled_format = 'anvl' ]
  - if 'plain' selected, support a labeled format for occasional
    subcommands that call for it (eg, fetch vs get, delete vs rm)
    [ {om_formal} ] [ $default_labeled_format = 'anvl' ]
  - regardless of chosen format, support a labeled output for the early
    part of execution (eg, errors) before we even know what format has
    been chosen (because a number of conditions must be checked first)
    [ $omx ] [ $default_labeled_format = 'anvl' ]
  - if behind an http server, esp. apache, regardless of format, support
    initial http headers that _must_ precede all output to avoid output
    getting lost and/or ruining the entire http response by causing an
    apache internal server error (due to bad headers)
  - optional: routines that integrate debug and verbose printing

=cut

# wrapper around pod2usage to output preamble (eg, HTTP headers), if any
#
sub pod2use { my( $cgih ) = ( shift );
	$cgih and
		print $cgih->take;
	pod2usage @_;
}

# XXXX remove
#	call with, eg, usage($om, 'unknown command', $usage_text)
sub xusage { my( $om, $errmsg, $usage )=@_;

	# XXXXX not using $om??
	$errmsg		and outmsg($errmsg);
	print $usage;
	return 1;
}

use Text::ParseWords;

# The $first_token argument is empty or a regexp and if it matches a
# command line it turns off tokenizing and collecting of continuation lines;
# currently it is used to get almost raw inputs in bulk command mode.
# 
sub launch_commands { my( $mh, $bulkcmdmode, $EmitStatus,
	$m_cmd, $optR, $cmd_line, $max_cmds )=@_;

	my $dbgpr = $optR->{dbgpr};
	$dbgpr and
		&$dbgpr("opt{minderpath}=$optR->{minderpath}\n"),
		&$dbgpr("minderpath=" . join(", ", $mh->{minderpath}) . "\n");
	# XXX do we need $optR any more? at all?

	#
	# xxx how to capture minderpath and reflect in playback log?
	#     -- or for that matter, how to capture and reflect all
	#        command line args in playback log?

	# Normally we do one command per invocation, but in bulk command
	# mode, signified by a single final argument of "-", we accept a
	# stream of commands.
	#
	$bulkcmdmode ||= ($#ARGV == 0 && $ARGV[0] eq "-");
	
	# Normally we're not in bulk command mode, in which case expect a
	# single command represented by the remaining arguments, so return
	# the exit code from performing it.
	#
	# If there's a command count limit (for testing or to deal with
	# memory leaks), exit if we've surpassed it.  For an exit not to
	# be disruptive, the caller should detect the exit and re-start
	# the process if need be.
	#
	my $cmd_count = 0;

	my ($st, $om) = (0, $mh->{om});
	if (! $bulkcmdmode) {			# normal, non-bulk mode case
		$st = &$cmd_line($bulkcmdmode, @ARGV);
		$EmitStatus and
			$om->elem("$m_cmd-status", $st);
		return $st;
			#$om->elem("$m_cmd-status", $ret ? "NOTOK" : "OK")),
			# XXXX crec isn't calling cgih method -- bug??
			# XXXX doc:  only ostream/orec does it 
			# yyy don't call crec because it won't call cgih->take
			#     bug???
			#$om->crec(),
			#$om->elem("$m_cmd-status", $ret ? "NOTOK" : "OK")),
	}

	# If we get here, we're in bulk command mode.  Read, tokenize,
	# and execute commands from the standard input.  Test with
	#   curl --data-binary @cmd_file http://dot.ucop.edu/nd/noidu_kt5\?-
	# where cmd_file contains newline-separated commands.
	#
	my ($cmd, $line, $partial, $lineno) = ('', '', '', 0);

	my $rrm = $mh->{rrm};
	my $line_count = 0;
	my $ret = 0;		# overall return from set of bulk commands
	while (defined($line = <STDIN>)) {
		$lineno++;
# xxx $lineno needs to be updated by expand_token
# XXXXXX ... and we an error in a given bulk command MUST skip over
#         input tokens and _not_ try to read them as commands
#         (untold damage could happen as this is user-supplied data)
		$line =~ /^\s*-?\s*$/	and next;	# skip blank lines or
				# just "-", since we're in bulk mode already,
				# ie, no bulk commands within bulk commands
		$line =~ /^#/		and next;	# skip comment lines

		# If we get here, we tokenize and collect continuation lines.
		#
		$line =~ s/\\\n$// and
			$partial .= $line,
			next;
		# If we get here, we have a complete command, possibly ...
		$partial and            # preceded by continuation lines
			$line = $partial . $line,
			$partial = "";          # reset continuation buffer
		#($st, $line_count) =
		$st = &$cmd_line(
			$bulkcmdmode,
			($line =~ /['"\\]/	# shellwords has a token size
				? shellwords($line)	# of 32767 octets, so
				: split(' ', $line)	# use split if we can
			)
		);
			# check $st in continue block
		#$lineno += $line_count;
	}
	continue {
		$st and
			$ret ||= 1,	# record problem just once
			($rrm or $om->elem('note', "non-zero status ($st) " .
				"returned by command on line $lineno")),
			$st = 0,	# turn it off or subsequent comment
				# and blank lines will report as errors too
		;
		if (defined($max_cmds) and ++$cmd_count >= $max_cmds) {
			$ret = 0;	# yyy distinctive return code
					# yyy txn log message?
			last;
		}
	}
	$EmitStatus and
		#$om->crec(),
		#$om->elem("$m_cmd-status", $ret ? "NOTOK" : "OK");
		$om->elem("$m_cmd-status", $ret);

	return $ret;
}

our $default_regexp = qr/\^([0-9a-fA-F]{2})/o;

# Modifies arguments 2, 3, etc, returning 1 on success, undef on error.
# DON'T call this routine with identifiers and element names that are
# output by get_rawidtree(). xxx document
# $hexchar arg can be undef ?
# 
sub instantiate { my( $mh, $hexchar ) = ( shift, shift );

	# NOTE: remaining args in @_ are all MODIFIED in place.

	my ($regexp, $indirect, $line_count);

	$hexchar and
		$regexp = $hexchar eq '^' ?	# optimize for the usual case
			$default_regexp :	# with a pre-compiled regexp
			qr/\Q$hexchar\E([0-9a-fA-F]{2})/;	# DON'T use 'o'
			# flag or you get only one value of $hexchar forever

	# Here begins an indented and comma-separated list of commands
	# representing the body of a foreach (not indented) that processes
	# and modifies the caller's arguments "in place".
	#
		$indirect = /^[@&]/,
		($hexchar and
			s{    $regexp     }
			 { chr hex "0x$1" }xeg
		),
		($indirect and
			($line_count, $_) = expand_token($mh, $_),
			(defined($line_count) or
				return undef)
		),				# end of loop command list
	foreach (@_);				# loop control

	return 1;
}

# Remove command modifiers from an argument list and return them via a
# pointer to a separate modifiers hash.  Modifies the input array as a
# side-effect.  In the presence of redundant modifiers, keeps only the
# last one.  Called with something like
#   $modlist = extract_modifiers( \@_ );
#
sub extract_modifiers { my( $alist ) = ( shift );

	# XXX is there a more memory efficient way than creating new modifier
	#     hash on each bulk command?
# XXXXXX probably should clean and recycle before each use
	my %modifiers = ();
	my $arg;
	while ( scalar(@$alist) ) {	# while at least one argument left
		$arg = shift @$alist;	# remove arg

		$arg =~ /^:hx(.?)$/i and
			$modifiers{hx} = $1 || '^',
			next;
# xxx to implement next for rlogging very large tokens
		$arg =~ /^:slzok$/i and		# caller says args are already
			$modifiers{slzok} = 1,	# serializable (means we don't
			next;			# slow down to quote them)
		$arg =~ /^:all$/i and	# get/fetch 'all' or matching
			$modifiers{all} = 1,	# elems yyy better as a list?
			next;			# xxx pattern unimplemented yet
		$arg =~ /^:allnot$/i and	# get/fetch 'all' or matching
			$modifiers{all} = 0,	# elems yyy better as a list?
			next;			# xxx pattern unimplemented yet
		$arg =~ /^:pif(.)$/i and	# xxx formerly sifx/sifn
			$modifiers{pif} = $1,	# 'x' (exists) or 'n' (not)
			next;			# xxx not implemented yet
		#$arg =~ /^:on_bind=(\d+)$/i and #XXX only admin can change!!
		#$arg !~ /^:/ and		# no more modifier args
		#	unshift(@$alist, $arg),	# restore this argument
		#	last;			# and leave the loop

		# If we get here, it's not a modifier we recognize, so we
		# throw it back and decide there are no more modifiers.
		#
		unshift(@$alist, $arg);		# restore this argument
		last;				# and leave the loop
	}
	return \%modifiers;
}

# XXXXXXXXX this breaks $lineno!! since we're not updating it based on
#    lines read from tokens.

# Expands a token into memory as a variable value.  If you just need to
# copy token content onto a log file, more efficient (especially for large
# file content) to use (xxx?) copy_token().  If the token is read from
# stdin, count newlines to permit accurate bulk file error reporting.
#
# Returns line count and token.
# If token is not from stdin, that line count is 0.
# On error, that line count is undef and token is an error message.
# XXXX hard to distinguish undef and 0?
#
use constant NLNL	=> "\n\n";
use constant NL		=> "\n";
use constant EOT	=> "\n#eot\n";		# xxx \012 for platform-indep?
use constant EOTLEN	=> length( EOT );	# platform-dependent

sub expand_token { my( $mh, $tk, $strip ) = ( shift, shift, shift );

	defined($strip) or	# default is to strip the end-of-token marker
		$strip = 1;

	local $/;		# $/ === $INPUT_RECORD_SEPARATOR
	my ($n, $msg, $token);
	my $token_ends_after_N_octets = 0;

	$tk ||= '';
	$tk =~ s/^\@// or	# xxx we don't yet support &tokens
		addmsg($mh, "unknown token type: $tk"),
		return (undef, '');
	#
	# @	up to end of line
	# @-	up to end of paragraph
	# @--	up to end of file
	# @-N	up to N octets plus 6 (\012#eot\012)
	# @-XYZ	up to \nXYZ\n
	# @foo	whole file named foo  (need admin rights)
	# @zaf	whole response body at URL zaf		# yyy not yet
	# &bar	db value bar  (need read rights to bar)
	#
	$tk eq '' and		# normal line-at-a-time mode from stdin
		$/ = NL,
	1
	or $tk =~ /^-(\d+)$/ and	# if a number, read that many octets
		$n = $1,		# data octets we plan to read
		(! $strip and		# if not stripping end-of-token marker,
			$n += EOTLEN),	# increase number of octets to read
		$token_ends_after_N_octets = 1,
		$/ = \$n,
	1
	or $tk =~ /^-$/ and	# strict "paragraph" mode (exactly 2 \n's ends
		$/ = NLNL,	# input record, not 2+ \n's implied by $/ = ''),
	1
	or $tk =~ /^--$/ and	# whole file mode (slurp mode)
		$/ = undef,	# chomp (below) understands nothing to strip
	1
	or $tk =~ /^-(.+)$/ and		# like <<$tk (a "here" document)
		$/ = NL . $1 . NL,
	1
	or $tk =~ m|^(https?://.*)|i and	# value is GET response body
		addmsg($mh, "unsupported token expansion: $tk"),
		return (undef, ''),
	1
	or $tk =~ /^([^-].*)/ and	# expect value to be contents of file
		# Note: we do not fall through this branch.
		($mh->{remote} and		# you don't have admin rights
			unauthmsg($mh),		# so you don't get access to
			return (undef, '')	# local server files
		),
		(($msg = File::Value::flvl("< $1", $token)) and
			addmsg($mh, $msg),
			return (undef, '')
		),
		return (0, $token),	# read and return, 0 lines from stdin
	1
	or
		addmsg($mh, "unknown token expansion: $tk"),
		return (undef, ''),
	;
	#
	# If we get here, we can assume we're reading only from STDIN.

	$token = <STDIN> || '';		# the actual read is here

	my $line_count =	# so we can continue accurate input reporting
		$token =~ tr/\n//;	# this tr COUNTS but does NOT replace

	$token_ends_after_N_octets and $strip and	# passively strip...
		$/ = \EOTLEN,		# by reading eot marker separately
		<STDIN>,		# read the eot marker and toss it
		$line_count += 2,	# let's count that as two lines
			# yyy what about platform independence?
		# XXX or should we have read N + EOTLEN in one read and
		#     then chomped that last bit off (or s/EOT$//)?
		#     which is better or more efficient?
	1
	or $strip and
		chomp($token),
	;

	return ($line_count, $token);
}

=for removal

# xxx dump this
sub get_stdin_token { my( $tkarg, $strip ) = ( shift, shift );

	local $/;		# $/ === $INPUT_RECORD_SEPARATOR

	defined($strip) or	# default is to strip record separator
		$strip = 1;

	my $token_ends_after_N_octets = 0;
	$tkarg ||= '';
	! $tkarg and		# if $tkarg is '' or 0 (zero length) then use
		$/ = NLNL,	# strict "paragraph" mode (exactly 2 \n's ends
				# input record, not 2+ \n's implied by $/ = '')
	1
	or $tkarg =~ /^\d+$/ and	# if a number, read that many octets
		$strip = 0,
		$token_ends_after_N_octets = 1,
		$/ = \$tkarg,
	1
	or			# else it's like <<$tkarg (a "here" document)
		$/ = NL . $tkarg . NL,
	1;

	my $token = <STDIN> || '';	# the actual read is here

	my $eot_comment;
	my $line_count =	# so we can continue accurate input reporting
		$token =~ tr/\n//;	# this tr counts but does NOT replace
	$token_ends_after_N_octets and
		$line_count += 2,
		$/ = \EOTLEN,
		$eot_comment = <STDIN>;	# read and toss token end comment

	$strip and
		$token =~ s|$/$||;

	return ($line_count, $token);
}

# Use "^" for encodings because it's rarer than "%" in our expected inputs.
#
sub nlencode { my $s = shift;

	$s =~ s{
		([\x0a\x0d^])			# replace NL, CR, and ^
	}{
		sprintf("^%02x", ord($1))	# with "^" and hex code
	}xeg;
	return $s;
}

sub nldecode { my $s = shift;

	$s =~ s{
		\^([0-9a-fA-F]{2})
	}{
		chr(hex("0x"."$1"))
	}xeg;
	return $s;
}

=cut

# this :config allows -h24w80 for '‐h 24 ‐w 80', -vax for --vax or --Vax
use Getopt::Long qw(:config bundling_override);

# This function may be called to parse options specified (a) on the
# command line and/or (b) in an environment variable.  We don't look
# for options in bulk commands.
# xxx is this good? (see GetOptionsFromString)

# XXX implement verbose/quiet as opposites?
#   1. my $verbose = ''; # option variable with default value (false)
#   2. GetOptions ('verbose' => \$verbose,
#   3. 'quiet' => sub { $verbose = 0 });
#
sub find_options { my( $getoptlistR, $optR, $no_reset )=@_;

	# To prevent GetOptions from seeing numbers with - (or +) in
	# front as option arguments, we preprocess to hide any [+-]N by
	# putting 3 Ctl-E's in front, eg, "^E^E^E-2".  After calling
	# GetOptions, we strip back out the initial Ctl-E's.  yyy kludge
	#
	for my $a (@ARGV) {
		$a =~ s/^([+-]\d)/$1/;
	}

	# xxx don't trust this code (remove?) when run with $no_reset -- bug
	$no_reset ||= 0;	# if no arg, reset global options by default
	$no_reset or %$optR = ();

	my $retval = GetOptions ($optR, @$getoptlistR);
	# Stripping out any initial Ctl-E, hopefully, one's we added.
	# yyy kludge
	#
	for my $a (@ARGV) {
		$a =~ s/^//;
	}
	return $retval;
}

# Now try to determine the minter/binder ("minder") database to use.
# In order of precedence, $mdr is defined by
#   0. noid xyz mkminter mdr ... (mdr findable in path)
#   1. noid mdr command ... (mdr findable in path)
#      noid -n mdr command ... (show which minder you'd use xxx)
#   2. noid mdr.command ... (mdr findable in path)
#   3. -d mdr     (mdr can be absolute or relative)
#   4. else -d as given in $ENV{NOG} or $ENV{EGG}
#   5. else use any --minder mdr (searchable)
#   6. else program name extension of form progname_mdr
#    xxx or should 3 trump and error out in presence of 2 or 1?
#    xxx purpose of MINDERPATH is what? is to permit easy creation
#        and visibility of minters... not so important for binders?
#    _named_ with the -d option
#
# xxx How about one minter namespace per machine (by default) to
#      reduce confusion?
#     xt1 above xtk4 above xtkr8
#
# XXX wouldn't it be way easier to specify
#       progname_mdr arg1 arg2... as progname mdr_arg1? eg, no
# symlinks needed...; also, http://.../nd/noid?_d%20mdr ... ?
#   xxx what about "noid .mint" as an abbreviation for noid -d . mint ?
#
#   If any of the above were specified, we will look for it
#   in the MINDERPATH dirs; even if we don't find it, we're
#   committed to that name (eg, for mkminter).
#
#   If none of the above were specified, we look further.
#   6. check "." to see if there's a minder in the current dir
#   7. else see if $default_minder exists in $minderhome
#   8. else prepare to create $default_minder in $minderhome
#      (eg, for mkminter)
# 
# Two independent parts: (a) name of minder and (b) path _to_ minder
# But not independent if minder _found_ be defaulting???
#

# the return value from cmd_line becomes process' exit code!

sub def_cmdr { my( $pname_mdr, $smdr, $m_dbbase, $optR )=@_;

	#
	# Now we start looking for the specified minder.  A minder that
	# is specified need not already exist.
	#
	# We'd kind of like to deprecate this pname_mdr thing because it
	# requires creating a link per binder to a noid executable, but
	# because Apache RewriteMap only lets you name a program without
	# parameters, it's the only way to do resolver mode without a
	# wrapper script.
	#
	$pname_mdr && ! $optR->{directory} and	# if no -d but progname gives
		$smdr = $pname_mdr;	# minder, treat it as if searchable

	my $mdr = "";	# xxx drop entirely!
	my ($cmdr, $cmdr_from_d_flag);
	$cmdr_from_d_flag = 0;
	if ($smdr) {			# searchable minder occludes -d
		$cmdr = fiso_dname($smdr, "$m_dbbase.bdb");
	}
	elsif ($optR->{directory}) {	# else if -d minder specified
		# don't search for -d minder in minderpath
		$cmdr_from_d_flag = 1;
		$cmdr = fiso_dname($optR->{directory}, "$m_dbbase.bdb");
	}
	elsif ($optR->{minder}) {	# else if --minder minder specified
		$cmdr = fiso_dname($optR->{minder}, "$m_dbbase.bdb");
	}
	else {		# don't know; may yet default depending on command
		$cmdr = "";
	}

	# If we get here, we will have detected every user attempt to
	# specify a minder that comes before (to the left of) a command
	# name.  (some commands, eg, 'mkminter foo', allow a minter to
	# be given as command args).  $cmdr should contain the extended
	# name (with filename extension).
	### XXXXXXXXXXX
	### $cmdr is candidate minder on _left_, ie,
	###        "backup" minder -> $mfon_choice2
	###          (minder filesystem object name, 2nd choice)
	###          select default minder, 3rd choice, if appropriate)
	### 
	# xxx want to delay setting of $mdr until later, esp. to share this code
	#      in the module
	# $mdr should be empty unless $cmdr exists
	# Unlike $smdr, which potentially floats as a relative name
	# within a searchable minderpath, $cmdr and $mdr do not float,
	# but are relative to the current or to the root directory.
	# $cmdr and $mdr, if non-null, are full (fiso_dname) names.

	#if ($optR->{debug}) {
	my $dbgpr = $optR->{dbgpr};
	if ($dbgpr) {
		$cmdr and
			&$dbgpr("candidate minder '$cmdr'" . ($mdr ?
				($mdr ne $cmdr ? " (found $mdr)" :
				" (found)") : " (not found)") . "\n")
		or
			&$dbgpr("no candidate minder\n")
		;

		#$cmdr and
		#	print("candidate minder '$cmdr'", ($mdr ?
		#		($mdr ne $cmdr ? " (found $mdr)" :
		#		" (found)") : " (not found)"), "\n")
		#or	print "no candidate minder\n"
		##or	print "no candidate minder ($cmdr, $mdr)\n"
		#;
	}
	return ($cmdr, $cmdr_from_d_flag);
}

# yyy? add flags: NOSEARCH|NODEFAULT??

# Called by commands that make and remove minders.
# Finally define the global $mdr and $cmdr variables (kludge).
# This is the routine that once and for all causes an explicitly
# specified minder (eg, shoulder) to override any candidate minder
# ($cmdr).  It sets the global $mdr variable. (kludge) xxx
#
# Third arg $count is the number of instances expected to be found.
# It may be an error if the number found is different.
#
# A minder is considered to exist if its named directory _and_
# enclosed file "dname" exists.  This way a caller can create
# (reserve) the enclosing directory ("shoulder") name ahead of
# time and we can create the dname without complaining that
# the minder exists.
#
# If $minder is set, it names a minder that hides any
# $cmdr candidate or found $mdr, which we now overwrite.
# $expected is the number of minders expected, usually 0 for
# making a minder and 1 for removing a minder. (yyy kludge?)
#

use File::Spec::Functions;

# returns ($mdr, $cmdr, $cmdr_from_d_flag, $err)
# always zeroes $cmdr_from_d_flag and always clobbers $cmdr, even on err
sub def_mdr { my( $mh, $minder, $expected )=@_;

	$expected ||= 0;	# default assumes we're making, not removing
	# yyy check for $expected being non-negative integer?

	my $err = 0;
	# these two are returned for global side-effect (not because of this
	#   subroutine, but by our own calling convention protocol -- dumb)
	my $cmdr = fiso_dname($minder, $mh->{dbname});	# global side-effect
	my $cmdr_from_d_flag = 0;			# global side-effect

	my @mdrs = EggNog::Minder::exists_in_path($cmdr, $mh->{minderpath});
	my $n = scalar(@mdrs);

	my $mdr = $n ? $mdrs[0] : "";			# global side-effect

	# Generally $n will be 0 or 1.
	$n == $expected and
		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);	# normal

	# If we get here, it must hold that $n != $expected and $n > 0.
	# Dispense with the remove minder case ($exected > 0) by falling
	# through and letting errors be caught by EggNog::Egg::rmminder().
	#
	$expected > 0 and			# remove minder case
		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);	# normal

	# If we get here, we were called from a routine creating a minder.
	# If the minder we would create coincides exactly with one of
	# the existing minders, refuse to proceed.
	#
	my $wouldcreate = catfile($mh->{minderhome}, $cmdr);
	my ($oops) = grep(/^$wouldcreate$/, @mdrs);
	my $hname = $mh->{humname};
	$oops and
		$err = 1,
		addmsg($mh, 
		"given $hname '$minder' would clobber existing $hname: $oops"),
		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);

	# If we get here, $n > 0 and we're about to make a minder that
	# doesn't clobber an existing minder; however, if $mdr is set,
	# a minder of the same name exists in the path, and one minder
	# might occlude the other, in which case we warn people.
	#
	$mh->{opt}->{force} or
		addmsg($mh, ($n > 1 ?
			"there are $n instances of '$minder' in path: " .
				join(", ", @mdrs)
			:
			"there is another instance of '$minder' in path: $mdr"
			) . "; use --force to ignore"),
		$err = 1,
		return ($mdr, $cmdr, $cmdr_from_d_flag, $err);
=for later
	    return ($mdr, $cmdr, $cmdr_from_d_flag, (($n > 1 ?
	
		"there are $n instances of '$minder' in path: " .
			join(", ", @mdrs)
		:
		"there is another instance of '$minder' in path: $mdr"
		) . "; use --force to ignore"));
=cut

	return ($mdr, $cmdr, $cmdr_from_d_flag, $err);	# normal return
}

=for later

sub dx_rmminder { my( $mh, $name )=@_;	# yyy works for noid and bind

	$name ||= "";
	my $retval = def_mdr($mh, $name, 1);	# 0 or '' is a normal return
	# yyy that should have returned our candidate minder, right?
	$retval	and				# bail if non-null
		return $retval;

	my $minderpath = $cmdr_from_d_flag ?	# if user specified -d
		"" :			# ignore minderpath setting
		$mh->{minderpath};	# else use $mh->{minderpath}
# xxx these EggNog::Egg::* routines should take a name that is either a
#     fiso_dname or fiso_uname (which is easier on the caller/user)
	EggNog::Minder::rmminder($mh, fiso_uname($cmdr), $minderpath) or
		return err1 outmsg($mh);
	return 0;
}

# Context and Stats (show minders, minder stats, minder ping)
#   pt mshow       "pairtree show known minders"
# bind mshow       "egg show known minders"
# noid mshow       "minder show known minders"
#   pt mstat mdr   "pairtree show stats for minder 'mdr'"
# bind mstat mdr   "egg show stats for minder 'mdr'"
# noid mstat mdr   "minder show stats for minder 'mdr'"
#   pt mping mdr   "pairtree ping minder 'mdr'"
# bind mping mdr   "egg ping minder 'mdr'"
# noid mping mdr   "minder ping minder 'mdr'"
# XXX implement!!

# show known binders
sub dx_mshow { my( $mh )=@_;

	EggNog::Minder::mshow($mh)	or return 1;
	return 0;
}

## show stats of minder
#sub ndx_mstat { my( $x )=@_; }
## return pulse check
#sub ndx_mping { }
## show stats of minder
#sub bdx_mstat { my( $x )=@_; }
## return pulse check
#sub bdx_mping { }

=cut

1;

__END__


=head1 NAME

Cmdline - routines to support command line scripts

=head1 SYNOPSIS

 use EggNog::Cmdline ':all';	    # import routines into a Perl script

This module provides general support for scripts that want a consistent
way (across a set of scripts) to add features to options processing,
filesystem entities, query strings submitted via the web.  In the first
use cases it supports the "noid" and "egg" scripts.

To service these top-level scripts, some routines are politically
incorrect in occasionally doing such things as calling "die" or
"pod2usage".

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut
