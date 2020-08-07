package EggNog::Resolver;

# xxx new feature:
#     for n2t, add rule for 12345 naan that describes example nature of
#       the NAAN along with the 404 error
#     similarly for 99999 ids that don't work (instead of simple 404)

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	expand_blobs id2shadow
	resolve
	special_elem suffix_pass
	id_decompose id_normalize uuid_normalize
	print_hash empty_hash
	PFX_DB PFX_TABLE PFX_CONNECT
	PFX_RRULE PFX_XFORM PFX_LOOK PFX_REDIR PFX_REDIRNOQ 
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

use File::Value ":all";
use EggNog::Binder ':all';	# xxx be more restricitve
use EggNog::Egg ':all';
use EggNog::Log qw(tlogger);
#use EggNog::Session qw(tlogger);

use constant TSUBEL	=> EggNog::Binder::TRGT_MAIN_SUBELEM;	# shorthand

my $ANCESTOR_MATCH_ELEM = '_am';  # "ancestor match" elem name (pseudo-constant)
my $SCHEMELESS = ':unkn';	# xxx -> :unkn
my $EXsc = $EggNog::Egg::EXsc;
my $PKEY = $EggNog::Egg::PKEY;
#my $fdfd = \&EggNog::Egg::flex_dec_for_display;			# shorthand

# elems for which we call suffix_pass
our @suffixable = ( EggNog::Binder::TRGT_MAIN );

# Resolver - resolver functions (Perl module)
# 
# Author:  John A. Kunze, jak@ucop.edu, California Digital Library
#		Originally created, UCSF/CKM, November 2002
# 
# Copyright 2008-2017 UC Regents.  Open source BSD license.

######################### Default Prefixes File Content ##################
our $default_pfc =	# zero-config requires default prefixes file contents
qq@
# This is the default prefixes file for "eggnog" (v$VERSION).
# It is in YAML format.
# xxx add pmid, pdb, ec, taxon
# yyy move test shoulders to alternate test config file
# xxx convert from using \$id to \${ac}

# Begin -- default prefixes file

ark:
  type: "scheme"
  name: "Archival Resource Key"
  alias: 
  provider: "n2t"
  primary: "true"
  redirect: "n2t.net/ark:\$id"
  test: "/88435/hq37vq534"
  probe: "http://n2t.net/ark:/88435/hq37vq534"
  more: "https://wiki.ucop.edu/display/Curation/ARK"

doi:
  type: "scheme"
  name: "Digital Object Identifier"
  alias:
  primary: "true"
  redirect: "http://doi.org/\$id"
  test: "10.1038/nbt1156"
  probe: "http://doi.org/10.1038/nbt1156"
  more: "http://www.doi.org/"

hdl:
  type: "scheme"
  name: "Handle System Identifier"
  alias: handle
  primary: "true"
  redirect: "http://hdl.handle.net/\$id"
  test: "4263537/4000"
  probe: "http://hdl.handle.net/4263537/4000"
  more: "http://www.handle.net"

purl:
  type: "scheme"
  name: "Persistent URL"
  alias: 
  primary: "true"
  redirect: "http://purl.org/\$id"
  test: "dc/terms/creator"
  probe: "http://purl.org/dc/terms/creator"
  more: "http://purl.org/"

zzztestprefix:
  type: "scheme"
  name: "Test Prefix"
  alias: 
  primary: "true"
  redirect: "id.example.org/\$id"
  test: "0123456789"
  probe: "id.example.org/0123456789"
  more: "https://id.example.org/"

a/b/ark:
  type: "scheme"
  name: "Test Multi-Layer Prefix"
  alias: 
  primary: "true"
  redirect: "id.example.org/\$id"
  test: "0123456789"
  probe: "id.example.org/0123456789"
  more: "https://id.example.org/"

ark:/99997/6:
  type: "shoulder"
  manager: "ezid"
  name: "Test ARK Shoulder -- Minimal, Mixed case"
  redirect: "id.example.org/nothing_to_subst"
  norm: "mc"
  date: "2017.02.17"
  minter:

ark:/99998/pfx8:
  type: "shoulder"
  manager: "ezid"
  name: "Test ARK Shoulder -- Lowercasing"
  redirect: "id.example.org/\${blade}&null"
  norm: "lc"
  date: "2017.02.14"
  minter:

# End -- default prefixes file

@;

# We use a reserved "admin" prefix of $A for all administrative
# variables, so, "$A/oacounter" is ":/oacounter".
#
my $A = EggNog::Binder::ADMIN_PREFIX;
my $Se = EggNog::Binder::SUBELEM_SC;

#use Fcntl qw(:DEFAULT :flock);
#use File::Spec::Functions;
#use DB_File;
use BerkeleyDB;

our $noflock = "";
our $Win;			# whether we're running on Windows

#our $def_pfx_file = 'prefixes.yaml';	# supports prefix hash
our $empty_hash = {};		# yyy want a constant so we don't keep
	# allocating memory just to create an empty hash that won't throw
	# an exception when we reference it.

# Special code :id puts the id as the final "where".  Kludge.
# Special code :policy creates a fixed policy statement.  Kludge.
#
sub eset_brief {
	return qw(who what when where :id);
}

sub eset_support {
	#return (eset_brief(), ':policy');
	return (eset_brief(),
		':s-who', ':s-what', ':s-when', ':s-where', ':s-how');
}

#### Blob support

# If any of the elements or sets were requested and blobs are bound to the
# id, we'll first open up the blobs to make their elements accessible.
#
our %deblobify = (
	':brief' => \&eset_brief, ':support' => \&eset_support,
	'who' => 1, 'what' => 1, 'when' => 1, 'where' => 1,
);

# Returns list of any new elements to add and updates $khashR
#
sub expand_blobs { my( $bh, $id, $msg, $khashR )=
		(shift,shift,shift,shift);	# rest of arg list is elements

	$msg = '';
	my $db = $bh->{db};
	#my @triggers = grep $deblobify{$_}, @_;
	my @triggers = ();
	map { $deblobify{$_} and push @triggers, $deblobify{$_} }
		@_;		# remaining args are elements
	scalar(@triggers) or	# if no trigger elements, return empty list
		return ();

	# If we get here, @triggers contains those elements requested
	# that trigger blob expansion.  Some of those "elements" actually
	# name sets of elements that the user requests, and we also need
	# to add those elements to the array of elements requested.  To
	# expand them, constitute a hash from blobs we find in $id.
	# XXX currently only look for erc blobs; don't do xml blobs yet
	#
	#my @dups = indb_get_dup($db, "$id${Se}erc");
	my ($erfs, $irfs);
	my @dups;
	if ($bh->{sh}->{fetch_indb}) {
		$irfs = flex_enc_indb($id, 'erc');
		@dups = indb_get_dup($db, $irfs->{key});
	}
	else {
		$erfs = flex_enc_exdb($id, 'erc');
		@dups = exdb_get_dup($bh, $erfs->{id}, 'erc');
	}

	my @elems;
	for my $erc (@dups) {
					# xxx why? what about flex-ecoding?
		$erc =~ s{		# undo (decode) any %-encoding
			%([0-9a-fA-F]{2})
		}{
			chr(hex("0x"."$1"))
		}xeg;
		# yyy this pass ref for $msg doesn't work, does it?
		$msg = anvl_recarray("erc:\n" . $erc, \@elems) and
			return ();
		$msg = anvl_arrayhash(\@elems, $khashR) and
			return ();
	}

	# Now to add new elements from any named element sets, for which
	# the trigger is actually a reference to code.
	#
	return map { ref($_) eq "CODE" and &$_ } @triggers;
}

# NB: on success MODIFIES args $special and $elem
# process elem requests specially if they begin with :
# returns 1 on success, 0 for elem requests that require no further
# processing (eg, an element set name like :brief) or are unrecognized
#
sub special_elem { my( $id, $special, $elem, $dupsR )=@_;

	$elem eq ':id' and	# special kind of "where"
		(($_[1], $_[2]) = ($elem, 'where/id')),
		# XXX 'where/id'? where/main? where/at?
		#     where/it?  where/this?
		(@$dupsR = ($id)),
		#
		# Perl makes this kind of assignment safe
		# this says: use $elem as label, but use
		#    the identifier string as the value
		return 1;

	$elem eq ':s-who' and	# org name
		(($_[1], $_[2]) = ($elem, 'support-who')),
		(@$dupsR = ('California Digital Library')),
		return 1;

	$elem eq ':s-what' and	# permanence rating
	# yyy should check if element is actually in the record, or if
	#     there's a "support class", and supply default unknowns if none
	# yyy rating or inflection for presence of version chain?

	# yyy must add (:codes) for values missing from a record
		(($_[1], $_[2]) = ($elem, 'support-what')),
		(@$dupsR = ('(:permcode NVR) id not re-assigned | ' .
			'versionable -- version data fixed | data replicated')),
		# N=ot re-assigned, T=emporary, U=nsupported id;
		#    V=ersionable, D=ynamic; R=eplicated,
		#    S=ingleton (not officially replicated
		#    by the org.)
		return 1;

	$elem eq ':s-when' and	# date range of support
		(($_[1], $_[2]) = ($elem, 'support-when')),
		(@$dupsR = ('2010-')),
		return 1;

	$elem eq ':s-where' and	# org id or web URL
		(($_[1], $_[2]) = ($elem, 'support-where')),
		(@$dupsR = ('http://www.cdlib.org/uc3/permcodes.html')),
		return 1;

	$elem eq ':s-how' and	# as non-profit, govt, etc
		(($_[1], $_[2]) = ($elem, 'support-how')),
		(@$dupsR = ('(:mission LNE) library | ' .
			'non-profit | higher education')),
		# L=ibrary, A=rchive, M=useum, G=overnment,
		# N=on-profit, P=rofit
		return 1;

	# if we get here it's unknown or it's a harmless element set name
	# whose elements we added alrady (eg, :brief).
	#
	return 0;
}

# yyy delete these PFX_* constants?
# Prefix database constants.
use constant PFX_DB		=> 'n2t';
use constant PFX_TABLE		=> PFX_DB . '.prefix';
use constant PFX_CONNECT	=> 'mongodb://localhost';

# Prefix record attributes read from the database.
use constant PFX_RRULE		=> 'redirect_rule';
use constant PFX_XFORM	 	=> 'normalize';
use constant PFX_LOOK 		=> 'lookup';

# Prefix record attributes computed and returned upon resolution request.
use constant PFX_REDIR 		=> 'redirect';
use constant PFX_REDIRNOQ 	=> 'redirect_noquery';

our ($scheme_test, $scheme_target) = (
	'xyzzytestertesty', 'http://example.org/foo?gene=$id.zaf'
);

# yyy ? add 'lookup' to make_naanders?

# Effectively a safety net (backup plan) hash in case real database fails.
# If no lookup key, lookup => 1 is assumed default.
# xxx right now it contains no backup info, eg, for ark, doi, etc.
# There are two separate transformations:
#  1. that we do before Lookup in our OWN database: PFX_LXFORM
#      eg, we _must_ do this before looking up doi's
#  2. that we do before Redirecting externally:     PFX_RXFORM
#      eg, we need not necessarily do this before redirecting doi's
my $n2thash = {
	ark => {
		PFX_XFORM => 'NH',
	},
	doi => {
		PFX_XFORM => '2U',
	},
#	cangem => {
#		PFX_RRULE => 'http://www.cangem.org/index.php?gene=$id',
#		PFX_XFORM => '2U',
#	},
#	rrid => {
#		PFX_RRULE => 'https://scicrunch.org/resolver/$id',
#		PFX_XFORM => '2U',
#	},
	$scheme_test => {
		PFX_RRULE => $scheme_target,
		PFX_XFORM => '2U,NH',
		PFX_LOOK => 0,
	},
};
# From Oct 19, 2016 (Nick J?)
# Yep - we picked up your hints at non-word characters ;p
# But then you mentioned that you allow spaces in your 'prefix:id', which
# is odd! But anyway....
# 
# The non-word characters we allow in our namespaces (kegg.drug,
# kegg.pathway as examples) won't disappear. We need to support those for
# certain. However, I can see various ways around this. For kegg.xyz we
# create a 'upper' namespace called 'kegg', and thats what we align with.
# For others I will need to look into them, but where needed we can create
# an alias to the non-word-character-containing namespace which we work
# with (but still support the original assigned by ourselves). The only
# namespace I recall with a dash is ec-code, but we will alias 'ec' and
# work with that for our alignment.
# 
# That all make sense?
# 
# For the initial set of namespace prefixes, we are working on:
# 
# pmid (alias for pubmed)
# go
# ec (ec-code)
# kegg
# ncbigene
# pdb
# uniprot
# chebi
# pmc
# taxonomy (debating whether we should alias 'taxon' for you, or whether
# you can switch to 'taxonomy'?)
# 
# For example, you can try http://identifiers.org/kegg:E00032
# Note: the aliases above are in progress (ec and pmid)
# 
# The provider prefixes we need for those namespaces above are:
# ncbi
# ebi
# epmc (for pmc)
# amigo (for go)
# quickgo (for go)
# bptl (==bioportal prefix)
# ols (==ontology lookup service at ebi)
# expasy (for ec)
# intenz (for ec)
# rcsb (for pdb)
# pdbe (for pdb)
# pdbj (for pdb)

#use MongoDB;

#=for removal
#
#use Data::UUID;
#sub gen_txnid { my( $bh )=@_;
#
#	! $bh->{ug} and				# if this is the first use,
#		$bh->{ug} = new Data::UUID,	# initialize the generator
#	;		# xxx document this ug param in of $bh
#
#	my $id = $bh->{ug}->create_b64();
#	$id =~ tr|+/=|_~|d;			# mimic nog nab
#	return $id;
#}
#
## xxx this should eventually obsolete gen_txnid
#sub get_txnid { my( $bh )=@_;
#
#	$bh->{txnlog} or	# speeding by $bh arg check, if not logging
#		return '';	# transactions, return defined but false value
#	use Data::UUID;
#	! $bh->{ug} and				# if this is the first use,
#		$bh->{ug} = new Data::UUID;	# initialize the generator
#	# xxx document this ug param in of $bh
#	my $txnid = $bh->{ug}->create_b64();
#	$txnid =~ tr|+/=|_~|d;			# mimic nog nab
#	$txnid and
#		return $txnid;			# normal return
#	addmsg($bh, "couldn't generate transaction id");
#	return undef;
#}
#
#=cut

# dummy (for now) authorization check
sub authz_ok { my( $bh, $id, $op ) =@_;

# XXXXX convert away from pure indb!

	my $dbh = $bh->{tied_hash_ref};		# speed by $bh arg check
	my $WeNeed = $op;			# operation requested
	#my $id_permkey = $id . PERMS_ELEM;
	my $id_permkey = $id . EggNog::Egg::PERMS_ELEM();

	! $bh->{remote} and		# ok if not from web, as we only
		return 1;		# need to do authz if on web
	return 1;	# xxx temporary, as this check is really disabled
	# xxxx this !$bh->{remote} is really an are you admin check
	if (defined $dbh->{$id_permkey}) {	# if there's top-level permkey
#ZXXX disable	# xxx faster if we pass in permstring $id_p here?
#ZXXX disable	#! authz($bh->{ruu}, $WeNeed, $bh, $id, $key) and
#ZXXX disable	! authz($bh->{ruu}, $WeNeed, $bh, $id) and
#ZXXX disable		unauthmsg($bh),
#ZXXX disable		return undef;
#ZXXX disable	# If we get here, we're authorized.
	}
	else {	# else permkey doesn't exist -- panic
		# xxx temporarily disable this message until EZID db updated
		#$bh->{rlog}->out($bh,
		#	"D: $id: id permissions string absent");
#ZXXX disable	addmsg($bh, "$id: id permissions string absent"),
#ZXXX disable	return undef;
	}
}

# There should only be one header arg, but there might be
# more than one arg if internal spaces/tabs didn't get
# encoded properly.  Caller should assume that and call us
# after joining (with ' ') everything into one $hdrinfo blob.
# Returns an array of 3 elements: hdrinfo, $accept, $proto.
#
sub get_headers { my( $hdrinfo )=@_;

	! $hdrinfo and
		return ('', '', '');

	# strip first layer of encoding
	$hdrinfo =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	# Extract incoming protocol info, which we'd like to preserve if
	# when a redirect rule doesn't specify (ie, supports both).
	# yyy based on private format shared with build_server_tree

	my $proto;
	$hdrinfo =~ /!!!pr=(.*?)!!!/;	# non-greedy
	$proto = $1 || '';
	$proto =~ /^https?$/ or		# must be either 'http' or 'https'
		$proto = '';

	# Extract the "Accept:" header, as it may affect resolution.
	# yyy based on private format shared with build_server_tree

	my $accept;
	$hdrinfo =~ /!!!ac=(.*?)!!!/;		# non-greedy
	$accept = $1 || '';

	# NB: In the past, browsers would put nothing or just '*/*' in
	# the Accept: header, which we would take to mean "no special
	# format requested", ie, no content negotiation or "request".
	# Modern browsers, however, seem to put lots into that header,
	# which we don't really want to parse. To make life simple for
	# ourselves, we will take the presence of '*/*' inside it to
	# mean "no content negotiation".

	#$accept eq '*/*' and	# if anything accepted then
	$accept =~ m|\*/\*| and		# if anything is accepted, it's the
		$accept = '';		# same as no content negotiation

	# xxx why was the whitelist below ever in effect?
	#$accept eq '*/*' and	# if anything accepted then
	#	$accept = '';		# no content negotiation
	#1 or			# else if we don't know it, then ignore
	#$accept ne 'application/rdf+xml' &&
	#		$accept ne 'text/turtle' &&
	#		$accept ne 'application/atom+xml' and
	#	$accept = '',		# as if no content negotiation
	#;

	return ($hdrinfo, $accept, $proto);
}
# xxx adjust resolver protocol to get command and args in return
# eg, "Command FileOrURL", where <command> is one of
#    redir302 URL		# redirect status 302
#    redir303 URL		# redirect status 303
#    inflect args		# eg, to do multiple resolution
#    file filename

# XXXX awaiting shoulder prefix normalize rules ??  these?
#3.7.  Element: normalize
#
#   A rule specified as a coded string with instructions for normalizing
#   LUIs before forwarding.  An example string with three codes is "2U,
#   NH,NS", which instructs a meta-resolver to convert to upper case and
#   remove all hyphens and whitespace.  The defined codes are
#
#           2U    convert to upper case
#           2L    convert to lower case
#           NH    remove hyphens
#           NS    remove whitespace
#           TR    trim just external whitespace
#           SS    squeeze multiple whitespace chars into one space
#           4E    hex-encode (every 4 bits)
#           6E    base64-encode (every 6 bits)>
#
#$scheme eq 'ark' and	
#	$id = lc $id,

# debug: print hash info for reference to hash (eg, prefix info)
sub print_hash { my( $msg, $hashR )=@_;
	print($msg, "\n");
	$hashR or
		print("null hash arg\n"),
		return 0;
	print("  $_: ",
		(defined($hashR->{$_}) ? $hashR->{$_} : '<undef>'),
		"\n")
			for (sort keys %$hashR);
	return 1;
}

# initialize $idx hash/struct

use constant PARTIAL_SO => 1;	# scheme only
use constant PARTIAL_SC => 2;	# scheme + colon only
use constant PARTIAL_SN => 3;	# scheme + naan or prefix only
use constant PARTIAL_SP => 4;	# scheme + naan or prefix + /
use constant PARTIAL_SS => 5;	# scheme + naan or prefix + / non-empty shlder
use constant PARTIAL_US => 6;	# unspecified: scheme + optional naan
use constant PARTIAL_ST => 7;	# scheme contains *, id may be non-empty

sub idx_init { my( $idx )=@_; 

	#   ur_origid   => '',  # original original
	#   origid	=> '',  # original identifier string
	#   full_id	=> '',	# whole id after normalization
	#   base_id	=> '',	# id up to first / or . between NAAN and query
	#   extension	=> '',	# remainder of id after base_id
	#   checkstring	=> '',	# string that a check digit might protect
	#   scheme	=> '',	# scheme name, eg, doi, ark, pmid
	#   partial	=> '',	# flag indicating probably partial identifier
	#                  values are PARTIAL_*

	#xxx field for what we do with prefix:
	#    m = mint
	#    b = bind
	#    r = redirect
	# yyy don't wait up for this (validate)
	#    v = validate (how/what?) Noid check digit algorithm
	#        eg, v=1, or v= 13030/qt$blade  ?
	# ezid == manager then usually mb, unless no minter (then b)
	# xxx ... if ezid != manager and type=naan then r

	#    naan	=> '',	# name issuer, if any, eg, NAAN, DOI Prefix
	#    fqnaan	=> '',	# fully qualified naan (scheme + naan)
	#    naan_sep	=> '/',	# separator char after naan, if any

	#    shoulder	=> '',	# shoulder eg, b2345/s3
	#    fqshoulder	=> '',	# fully qualified shoulder eg, ark:/b2345/s3
	#    shoshoblade	=> '',	# short shoulder plus blade, eg, s398765
	#    blade	=> '',	# after end of shoulder, eg, 98765

	#    slid	=> '',	# scheme-local id (id minus scheme)
	#    query	=> '',	# URL query string, if any
	#    pinfo	=> '',	# prefix (matching initial substring) info
	#    # xxx drop pinfo?

	#    origid	=> $id,		# original identifier string
	#    errmsg	=> undef,	# non-empty means error
	#    fail	=> undef,	# failure or success
	#    suffix	=> undef,	# defined after id_decompose
	#    rid	=> '',		# root id (id minus suffix)

	$idx->{origid} =	# original identifier string
		$idx->{ur_origid} =
		$idx->{full_id} =
		$idx->{slid} =
		$idx->{naan} =
		$idx->{scheme} =
		$idx->{fqnaan} =
		$idx->{shoulder} =
		$idx->{fqshoulder} =
		$idx->{shoshoblade} =
		$idx->{blade} =
		$idx->{query} =
		$idx->{pinfo} =
		$idx->{rid} = '';
	$idx->{naan_sep} = '/';
	$idx->{base_id} =
		$idx->{extension} =
		$idx->{partial} =
		$idx->{checkstring} = '';
	$idx->{shdr_i} =
		$idx->{naan_i} =
		$idx->{scheme_i} = {};
	$idx->{errmsg} =
		$idx->{fail} =
		$idx->{suffix} = undef;		# important state info
	return $idx;
}

# return an array of normalized elements, as follows:
#    normalized id
#    scheme type (ark, doi, urn, uuid, etc.)
#    naan (eg, ARK NAAN or "DOI Prefix")
#    naan/shoulder (fully qualified shoulder (within scheme namespace))
#    [ Note that for many rule-based redirected schemes, there's no concept
#      of naan or shoulder, so what we store in $naan may be a SLID. ]
#    shoulder+blade (no naan preceding it)
#    query string (beginning with the first '?')
#    scheme-local id
#    prefix info, specifically: $pinfo->{PFX_REDIR}, $pinfo->{PFX_REDIRNOQ}
#    Not yet: fragment (maybe)

# id_decompose tries to classify an id, and returns an idx structure
# that breaks it down into constituent parts
# Note: this routine contains custom code that "knows" about some current
# global identifier schemes.  This has pros and cons.

sub id_decompose { my( $pfxs, $id )=@_;

	defined($id) or
		return undef;

	my $idx = {};
	$idx->{ origid	} = $id;	# original identifier string

	###### "Shallow n11n" (normalization).

	## 1. remove whitespace

	# we've saved original in $origid, so we can now modify it safely
	$id =~ s/\s+$//;	# drop terminal whitespace
	$id =~ s|^\s+||;	# drop initial whitespace

	# This supports "ark 12345/67" -> ark:/12345/67 and similar, eg,
	#   "DOI 10.1234/56" -> DOI:10.1234/56

	# yyy what might it mean if id begins with a colon (:) ?
	my $has_colon =		# does this id contain a colon?
		(index($id, ':') >= 0);
	! $has_colon and	# if no colon, convert the first run of spaces,
		$id =~ s/\s+/:/g;	# if there is one, to a colon
	$id =~ s/\s*\n\s*//g;	# drop internal newlines and surrounding spaces

# ZZZZZZZZZZZZZZZZZZZZZZZZXXXXXX

	## 2. try to infer a scheme if it's not obvious

	# Shorthand for parts that we will return.  All have names
	# corresponding to the $idx hash keys.
	#
	my ($scheme_raw, $scheme, $rid);

	# yyy ?add crutch to make grid:x.y become grid:grid.x.y
	#        (when x ne "grid")
	# yyy add url: as scheme?

	#if ($id =~ /^urn:([^:]+):(.*)/i) {	# yyy kludgy special case
	if ($id =~ /^urn:([^:]+):((([^:]+):)?(.*))/i) {	# kludgy special case
		my $nid_raw = $1;
		my $nid = lc $1;
		my $subnid = $4 ? lc($4) : '';	# look one level deeper
		if ($nid eq 'nbn' && $subnid eq 'nl') {
			$scheme = 'nbn_nl';
			$scheme_raw = "$nid_raw:$4";
			$id = $5 || '';
		}
		elsif ($nid eq 'nbn' || $nid eq 'issn' || $nid eq 'isbn' ||
				$nid eq 'lsid') {
			$scheme = $nid;
			$scheme_raw = $nid_raw;
			$id = $2 || '';
		}
		else {
			$scheme = $scheme_raw = 'urn';
			$id = $1 . ':' . ($2 || '');
		}
	}
	# NB: the FIRST colon is taken to be the separator, which is a reason
	# that urn:...:...:... has to be handled specially above
	elsif ($id =~ m|^([^:]+):/*\s*(.*)|) {	# grab scheme name and id,
		$scheme_raw = $1;		# ignoring spaces after scheme
		$scheme = lc $1;	# $scheme is now defined and lowercase
		$id = $2 || '';		# $id now w.o. scheme or initial spaces
	}
	#elsif ($id !~ /:/) {		# if no colon-y bit, infer scheme
	elsif (! $has_colon) {		# if no colon-y bit, infer scheme
		if ($id =~ /^10\.\d+/o) {			# DOI Prefix
			$scheme = 'doi';
		}
		elsif ($id =~ /^[-\da-fA-F]{32}/o) {		# UUID
			$id = 'uuid:' . $id;
			$scheme = 'urn';
		}
		elsif ($id =~ /^[\dbcdfghjkmnpqrstvwxz]{5,9}+\//io) {	# NAAN
			$id = $id;
			$scheme = 'ark';
		}
		elsif ($id =~ m{^\w+\.(?:\w+\.?)+(?::\d+)?/}o) {
							# has a hostport
			$scheme = 'http';
		}
		elsif ($id =~ /^(\w+)=(.*)/io) {  # '=' separator, eg, INCHI
			$id = $2;
			$scheme = $1;
		}
		else {
			$scheme = $SCHEMELESS;
		}
		$scheme_raw = $scheme;
	}
	else {
		$scheme = $scheme_raw = $SCHEMELESS;
	}
	$rid = $id;	# init default root id, modified if we detect a suffix

# xxx now that we have $scheme_raw (Tom Gillespie case), what do we do
# with it?

	###### Now initialize various identifier parts.

	my $sid = "$scheme:$id";	# save scheme:id form in $sid

	# yyy done? change build_server_tree to permit file paths into
	#     resolver classify such paths as $SCHEMELESS
	# yyy failing that, rewrite SCHEMELESS to original and fail out,
	#     so that apache rewrite rules can have one more crack at them
	# yyy check them for post binder lookup too

	# xxx doc: caller to check this case first
	if ($scheme eq $SCHEMELESS) {	# prune this case and return
		idx_init( $idx );
		$idx->{scheme} = $scheme;
		$idx->{rid} = $rid;
		# NB: important that $idx->{partial} be zero
		$idx->{partial} = 0;		# eg, any server file path
		$idx->{full_id} = $sid;
		($idx->{slid} =			# 'slid' is rawest id form
			$sid) =~ s/^$SCHEMELESS//io;
		return $idx;
	}

	# xxx replace this test with n2tid scheme database lookup test
	#      lookup shoulder later (below), after scheme n'tion
	# yyy add $SCHEMELESS scheme to n2tid database ?
	#     lookup return will instruct on case normalization
	#     lookup return will instruct on encoding conversion, eg, uuid
	# yyy? new way to do uuids?  '9' suggesting 'g' (guid)
	#     ark:9/<32chars_or_c64encoding_or_ascii85>[checkchar][extensions]
	#     lookup return will instruct on check char verification
	#     will have descriptive metadata too
	# xxx eventually second part of || clause below will be obsolete

	#unless ($scheme =~ /^(?:ark|doi|urn|uuid|lsid|pmid|purl)$/) #
	if ($scheme =~ /^https?$/) {

		# like ARKs, HTTP(S) URLs are weird with the '//', ...
		$sid = $scheme . "://$id";		# so rewrite $sid
		use URI;				# assume it's a URI
		my $u = URI->new($sid)->canonical;	# normalize it

		idx_init( $idx );
		! $id and
			$idx->{partial} = PARTIAL_SO;
		$idx->{rid} = $rid;
		$idx->{full_id} = $u->as_string;
		$idx->{scheme} = $u->scheme;
		$idx->{naan} = $u->host;
		$idx->{shoshoblade} = $u->path;
		$idx->{query} = $u->query;
		return $idx;
	}

	$idx->{scheme} = $scheme;	# shouldn't change before we return

	# Now that we have a decent idea of what the scheme is, and having
	# dispensed with any received http or https "id", detach any query
	# string we find to protect the query from normalization, such as
	# case conversion and de-hyphenation.
	#
	$idx->{query} = '';
	$id =~ s/(\?.*)// and		# NB: removing query string from $id
		$idx->{query} = $1;
	$rid = $id;			# update default root id

	# The Scheme Local ID (SLID) is the id mean to be unique _within_
	# the scheme, which is a fancy way of saying everything between
	# colon and '?'.  The SLID is mostly for discipline-specific schemes
	# without as much hierarchy as the ARK or DOI or URN schemes; we
	# assume a $naan and a $naan_sep only for those three schemes.
	# xxx but IGSN has a $naan concept without a $naan_sep

# Also check flag $idx->{partial} to detect cases such as ...?
# Then use the flag to take on things that pfx_grok currently does
# watch out for "xxx" logic that strip /'s and "'s below

	## 3. A bit more shallow normalization, based on our own knowledge
	#     of ARK, DOI, URN, and UUID.  For these well-known schemes we
	#     hardcode some transformations.  Re-evaluate hardcoding pros
	#     (eg, speed) against benefits of describing transformations
	#     in the prefix database.
	#
	my $kludge = '';
	# naan_sep is really naan_terminator (goes after the NAAN)
	# yyy what about IGSN, which has no naan_sep?
	$idx->{naan_sep} = '/';		# default, but we didn't call idx_init
	if ($scheme eq 'ark') {
		#$id =~ s|^([^/]+)/*|| or	# must match else panic
		#	return undef;
		$id =~ s|^([^/]+)/*|| and	# isolate NAAN, remove any /'s
			$idx->{naan} = $1,
			$kludge = '/',		# '/' before (and after) NAAN
		1 or
			$idx->{naan} = '',
		;
		$id =~ s|-||g;			# remove hyphens
		#$id =~ s|[-\s]||g;	# remove hyphens and internal whitespace
		# NB: arks are weird with their '/' after the ':'
		# xxx this weirdness should go away one day when we change
		#     storage from ark:/12345/... to ark:12345/...
	}
	elsif ($scheme eq 'doi') {
		#$id =~ s|^([^/]+)/*|| or	# must match else panic
		#	return undef;
		$id =~ s|^([^/]+)/*|| and
			$idx->{naan} = $1,
		1 or
			$idx->{naan} = '',
		;
		$id = uc $id;			# DOIs normalize to uppercase
	}
	elsif ($scheme eq 'urn') {		# per RFC 2141, URN NID must be
		#$id =~ s|^([^:]+):*|| or	# be present (else panic) and
		#	return undef;		# case-insenstive
		$id =~ s|^([^:]+):*|| and	# present and case-insensitive
			$idx->{naan} = lc $1,	# NID in $naan
		1 or
			$idx->{naan} = '',
		;
		$idx->{naan_sep} = ':';
	}
	elsif ($scheme eq 'uuid') {		# for UUIDs there's no naan
		$id =~ s|-||g;			# our policy: remove hyphens
		$idx->{naan} = '';		# no $naan
	}
	else {					# other schemes don't have a
		$idx->{naan_sep} = '';		# $naan, hence no separator
		$idx->{naan} = '';		# no $naan
	}
	$rid = $id;			# update default root id
	# By the time we get here, we'll be done defining $idx->{naan} and
	# $idx->{naan_sep}.

	! $id and	# catches NAAN-only partials of type ARK, DOI, and URN
		$idx->{partial} = PARTIAL_US,	# UnSpecified
	1 or
	$scheme =~ /\*/ and
		$idx->{partial} = PARTIAL_ST,	# contains STar
	;
# yyy this fails to catch shoulders, which still pass through as if
#     they were ids ... maybe need to set flag here that, if set,
#     causes resolve() to check for exact match to shoulder record

	# NB: $kludge holds the inital '/' that begins (for now) ARK NAANs
	# but is empty otherwise; $idx->{naan} does NOT have an initial '/'.
	#
	my $fqnaan = $scheme . ':' . $kludge . $idx->{naan};
	$idx->{fqnaan} = $fqnaan;

	## Detect shoulder using the "first-digit" conventions.  But first
	# look up exceptions (yyy not yet implemented since not sure how
	# to do it efficiently).  First digit convention looks for a shoulder
	# as a string of zero or more letters ending in a digit.
	#
	# If we detect a shoulder, capture it and the blade, but don't
	# modify $id in doing so.
	# yyy the \w* looks weird (since it matches letters OR digits)
	#     but it sort of works too.
	# yyy make exception for non-standard shoulders and igsn shoulders
	# yyy is [a-z] ... i classy enough in international setting
	#
	# ($short_shoulder, $blade) = get_shoulder_exceptions(yyy not yet);

	# yyy could be a fictional shoulder for any but EZID ARKs and DOIs
	#     so can't trust this setting
	# NB: we can trust non-empty $idx->{naan} as naming a true NAA

	my ($blade, $short_shoulder) = ('', '');
	$id =~ m|^([a-z]*\d)(.*)|i and	# isolate shoulder but don't remove
		$short_shoulder = $1,
		$blade = $2;
	$idx->{blade} = $blade;

	my $foundation = $fqnaan . $idx->{naan_sep};
	my $fqshoulder = $foundation . $short_shoulder;
	#my $fqshoulder = $fqnaan . $idx->{naan_sep} . $short_shoulder;
	$idx->{fqshoulder} = $fqshoulder;
	$idx->{shoulder} =		# unqualified shoulder, eg, /12345/x5
		$kludge . $idx->{naan} . $idx->{naan_sep} . $short_shoulder;

	my ($base, $extension) = ($id, '');
	$base =~ s|[^\w_~].*|| and
		$extension = $&;
	# yyy this exact same [^\w_~] regex snippet is used in ??db_chopback
	$idx->{base_id} = $foundation . $base;
	$idx->{extension} = $extension;
	$idx->{checkstring} = $idx->{naan} . $idx->{naan_sep} . $base;

	# Note that the Scheme Local Id (SLID) (id unique within the scheme)
	# is formed from $naan.$naan_sep.$id, with '/' in front for ARKs.
	# The SLID is what we insert into a prefix entry's redirect rule.
	#
	#$idx->{slid} = $kludge . $idx->{naan} . $idx->{naan_sep} . $id;
	$idx->{slid} = $kludge . $idx->{naan} . $idx->{naan_sep} . $id;
	$idx->{shoshoblade} = $id;			# yyy needed??

	$idx->{full_id} = $scheme . ':' . $idx->{slid} . $idx->{query};

	# The ARK scheme is case-sensitive, but in practice all EZID ARKs
	# (after 11 years) are lowercase only, and we can prepare for a good
	# UX for those users who assume resolution is case-INsenstive, eg,
	# common in certain old-school government agencies.

	$scheme eq 'ark' and	# xxx check if shoulder flag denies this
		$idx->{full_id_case_insensitive} =
			$scheme . ':' . uc( $idx->{slid} ) . $idx->{query};

	$pfxs ||= $empty_hash;		# prevent exceptions from next three
	# read info on each of these, if any, but don't act on it
	#    shdr, naan, or scheme information
	$idx->{shdr_i}   = $pfxs->{$fqshoulder} || $empty_hash;
	$idx->{naan_i}   = $pfxs->{$fqnaan}     || $empty_hash;
	$idx->{scheme_i} = $pfxs->{$scheme}     || $empty_hash;

	# When we select one of these, usually because it's the first one
	# of the three to have a non-empty redirect, we want to know what
	# hash key (in this case, prefix) got us there, so we synthesize a
	# new element to save it.
	#
	$idx->{shdr_i}->{key} = $fqshoulder;
	$idx->{naan_i}->{key} = $fqnaan;
	$idx->{scheme_i}->{key} = $scheme;
	$idx->{rid} = $rid;

	#print STDERR "XXXXXXXXX idx scheme_i: ";
	#use Data::Dumper "Dumper"; print Dumper $idx->{scheme_i};
	#use Data::Dumper "Dumper"; print Dumper $sh->{pfxs}->{doi};

# If there's no lexically parsed blade, we MIGHT have a partial id.
# Whether we have a full id is determined by the binder -- if it's in
# the binder, it's a full id. If it's not in the binder, then we may
# inspect the $idx->{partial} flag for suggestions of what sort of
# partial id we might have.

#$idx->{partial} = ( $blade ? PARTIAL_SHDR$blade
#	if (! $id) {
#	}
#	$pfxs->{$scheme} and
#		$idx->{partial} = PARTIAL_SO;
#		# yyy not detecting partial matches on NAAN or shoulder

	# Because of $empty_hash, from now on we can confidently use
	# $idx->{*_i} as pointers without throwing an exception.

	return $idx;
}

=for transformation in id_...

	my $transform = $pinfo->{PFX_XFORM};	# defined, even if empty
	if ($transform) {
		index($transform, 'NH') < 0 or	# no hyphens
			$id =~ s/-//g;
		index($transform, '2U') < 0 or	# to upper
			$id = uc $id;
		index($transform, '2L') < 0 or	# to lower
			$id = lc $id;
		index($transform, 'NS') < 0 or	# no whitespace
			$id =~ s/\s+//g;
	}
	my $redirect = $pinfo->{PFX_RRULE};	# defined, even if empty
	$pinfo->{PFX_REDIR} = '';		# initialize to empty!
	$redirect and
		(($pinfo->{PFX_REDIRNOQ} = $redirect) =~ s/\$id\b/$id/g),
		($pinfo->{PFX_REDIR} = $pinfo->{PFX_REDIRNOQ} .
		$idx->{query});
	# Resolver can now just test if $pinfo->{PFX_REDIR} is non-empty.

=cut

########################################

use YAML::Tiny;
use Try::Tiny;			# to use try/catch as safer than eval
use Safe::Isa;

# return ref to HASH of hardwired prefixes, used as backup if file
# prefix is not available; right now it's empty since we handle ARK
# and DOI with hardwired code

# yyy stronger relationship between hardwired and default prefixes files?
#     should these be the same thing?
# yyy role of test prefixes for edge cases? -- maybe belongs purely in
#     test scripts
# yyy separate 3rd category is the pfx_base file that a service needs,
#     for interacting, possibly overriding, an expected ecosystem of
#     imported prefix files

sub hardwired_prefixes { my( $sh, $msgR )=@_;

	my $pfxs = {

	    ark => {
		type => 'scheme',
		name => 'Archival Resource Key',
		redirect => 'n2t.net/ark:$id',
	    },
	    doi => {
		type => 'scheme',
		name => 'Digital Object Identifier',
		redirect => 'http://doi.org/$id',
	    },
	    igsn => {
		type => 'scheme',
		name => 'International Geo Sample Number',
		redirect => 'http://hdl.handle.net/10273/$id',
	    },
	    hdl => {
		type => 'scheme',
		name => 'Handle System Identifier',
		alias => 'handle',
		redirect => 'http://hdl.handle.net/$id',
	    },
	    purl => {
		type => 'scheme',
		name => 'Persistent URL',
		redirect => 'http://purl.org/$id',
	    },
	};		# yyy missing? URNs?
	return tidy_prefix_hash( $sh, $pfxs, $msgR );
}

# First arg is a prefix filename, second arg a reference to a string that
# will be set to '' in most cases (success, or success with warning
# message), or to an error message on failure.  Returns reference to a
# prefix hash on success, undef on error.

sub load_prefix_hash { my( $sh, $pfx_file, $msgR )=@_;

	$$msgR = '';			# initialize return message
	! $pfx_file and
		return undef;

	my $pfxs;			# ref to HASH of all prefixes
	my $ok = try {
		$pfxs = YAML::Tiny::LoadFile($pfx_file);
	}
	catch {		# NB: catch this exception or resolver aborts
		$$msgR .= "YAML::Tiny::LoadFile failed on $pfx_file";
		return undef;	# returns from "catch", NOT from routine
	};
	#! defined($ok) and
	#	return...
	return tidy_prefix_hash( $sh, $pfxs, $msgR ); # yyy never returns undef?
}

sub tidy_prefix_hash { my( $sh, $pfxs, $msgR )=@_;

	# Step through each prefix info block (hash) to prepare the prefix
	# hash for resolution duty.
	#
	# 1. Add the canonical prefix under element "prefix", different
	#    from the "key" element added by id_decompose, the latter being
	#    the lookup string leading there, maybe via aliases and synonyms.
	#    Both elements come in handy when prefix info block is selected,
	#    eg, it has a redirect rule.
	# 2. Scrub redirect rules that point back to us.
	# 3. Promote aliases to hash keys.
	# 4. Add synonyms (and implied aliases).

	# yyy right now, it may be a little fragile, but we avoid
	#     redirect loops by pattern-matching on the hostname
	#     and eliminating such rules at prefix load time.
	#

	# yyy not well-tested
	my $ignore = $sh->{conf_flags}->{resolver_ignore_redirect_host}
		|| '';			# eg, 'n2t'

	#my $ignore = $config->{ ignore_redirect_host } || '';	# eg, 'n2t'
	#my $regex = qr|^(?:https?:/+)?[\w.-]*$ignore[\w.-]*|o;
	my $regex = qr|^(?:https?:/+)?[\w.-]*$ignore[\w.-]*/+([^:]+:?)|o;
	# now capture any scheme name in the redirect ------->^^^^^
	#  test below: if it doesn't end in ':' don't consider it a scheme name

	my (@resolver_aliases, @resolver_synonyms);
	my ($k, $prefix, $alias, $ename, $pinfo, $redirect, $scheme);
	while (($prefix, $pinfo) = each %$pfxs) {
		# xxx document this canonical ("prefix"), different from
		#     "key" added by id_decompose
		$pinfo->{prefix} = $prefix;	# add prefix string itself

		$alias = $pinfo->{alias} and
			push(@resolver_aliases, $alias, $prefix);
			# only works for schemes (not shoulders, naans), right?

		# shortcut check for type=synonym is non-empty "for" element
		# eg, prefix: ncbi/pubmed, for: pubmed
		$ename = $pinfo->{for} and	# Existing (previous) name
			push(@resolver_synonyms, $ename, $prefix);

		$redirect = $pinfo->{redirect} or
			next;
		# if here, there's a redirect rule we might need to ignore
		# figure out the scheme associated with the prefix
		($scheme = $prefix) =~ s/:.*//;
		$ignore and $redirect =~ $regex and
			$1 eq "$scheme:" and	# should have these outcomes
#print(STDERR "xxx 1=$1, prefix:=$prefix:, redirect=$redirect\n") and
				# ark:... -> n2t.net/ark:... (ignore)
				# minid:... -> n2t.net/ark:... (pass)
				# ark:... -> n2t.net/arkane... (ignore)
				$pinfo->{redirect} = '';	# kill redirect
				# annihilate redirect rule in some cases
	}
	# yyy n2tadds.yaml maintained under ~/shoulders on n2tprda, copied
	#     to $sa/htdocs/e by naans makefile, pulled to Mac via cron

	# post-process: add synonyms and aliases to hash
	# Map only scheme, not provider code
	# Need to map alias,prefix pairs to key,value pairs, such as:
	#   pmid alias under pubmed -> new key: pmid
	#   pmid alias hubmed/pubmed -> new keys: hubmed/pmid, hubmed/pubmed
	# Synonyms occur when a provider code names the same provider as
	# the unadorned scheme name (for n2t that's the primary provider,
	# but for identifiers.org, there's the synonym depends on which
	# provider has the fastest response time in the past 24 hours)
	# xxx reserve provider codes p=primary and q=quickest
	#
	while ($prefix = pop(@resolver_aliases)) {
		$alias = pop(@resolver_aliases) or	# should be defined
			next;				# but skip if not

		$pinfo = $pfxs->{$prefix} or
			next;
		($k = $prefix) =~ s|[^/]+$|$alias| and	# under modified key
			($pfxs->{$k} and $$msgR .= "overwriting prior $k " .
				"info adding alias for $prefix; "),
			# yyy this can happen when a commonspfx was added
			# before we understood what all the aliases were
			# for idot prefixes; should really process aliases
			# before adding commonspfx entries
			$pfxs->{$k} = $pinfo;		# store same pfx info
	}
	# Synonyms differ from aliases in that the former are alternate
	# names that consist of a provider_code + '/' + scheme, where
	# the scheme may be subject to further aliasing.  An alias,
	# however, is just an alternate name for a pure scheme name.
	# 
	# Example: synonym ncbi/pubmed "for" prefix pubmed causes creation of
	# new key ncbi/pubmed with pubmed info assigned to it.  Secondarily,
	# because pmid is an alias under pubmed, add the key ncbi/pmid also.
	#
	while ($prefix = pop(@resolver_synonyms)) {	# new key to create
		$ename = pop(@resolver_synonyms) or	# existing name
			next;				# but skip if not
		$pinfo = $pfxs->{$ename} or		# should already exist

			next;
		$pfxs->{$prefix} and $pfxs->{$prefix}->{for} ne $ename and
			$$msgR .= "overwriting prior info when adding " .
				"$prefix synonym for $ename; ";
		$pfxs->{$prefix} = $pinfo;		# this should be new
		$alias = $pinfo->{alias} or		# might have an alias
			next;				# if not, skip
		($k = $prefix) =~ s|[^/]+$|$alias| and	# under modified key
			($pfxs->{$k} and print(STDERR "overwriting prior $k ",
				"info adding synonym alias for $ename\n")),
			$pfxs->{$k} = $pinfo;		# store same pfx info
	}
	#YAML::Tiny::DumpFile( "$pfx_file.fixed", $pfxs ) or
	#	print(STDERR "could not dump prefixes for $pfx_file\n");
	# yyy dump fails because of circular references -- problem?

#while (my ($k, $v) = each %$pfxs) { print "$k=>$v, r=$v->{redirect}\n"; }

	return $pfxs;
}

# Tries hard to load a viable prefix file, and defines $sh->{pfxs} and
# $sh->{pfx_file_actual} as a side-effect. The caller can proceed with
# resolution if $sh->{pfxs} is defined after the call.  We don't want our
# resolver to fail catastrophically just because a prefix file can't be
# loaded.  Tries to create a default file if none, and loads hardwired
# prefixes if all else fails. 
#
# Returns a string consisting of any and all messages (possibly separated
# by newlines) in the process. An empty string means likely success, and
# a non-empty string should probably be logged by the caller.

sub load_prefixes { my( $sh )=@_;

	my ($msg, @msgs);			# returned message support
	my $pfx_file =
		(-e $sh->{pfx_file} ? $sh->{pfx_file} :
		(-e $sh->{pfx_file_default} ? $sh->{pfx_file_default} :
		'' ));			# else neither prefixes file exists

	if (! $pfx_file) {		# create a default prefixes file
		$pfx_file = $sh->{pfx_file_default};
		my $ok = try {
			use File::Path 'mkpath';
			$msg = mkpath($sh->{home});	# $msg unused here yyy
		}
		catch {
			push(@msgs,
			  "Couldn't create directory \"$sh->{home}\": $@");
			$msg = '';
			return undef;	# returns from "catch", NOT from routine
		};
		# not bothering to check status of $ok

		$msg = flvl("> $sh->{pfx_file_default}", $default_pfc);
		$msg and
			push(@msgs, $msg),
			$msg = '';
	}

	my $pfxs = load_prefix_hash( $sh, $pfx_file, \$msg );

	# But wait, user may want to force hardwired prefixes (eg, for testing)
	#
	if (defined($sh->{opt}->{pfx_file}) and $sh->{opt}->{pfx_file} eq '') {
		$pfxs = undef;			# throw away previous load
		$msg = 'option forcing hardwired prefixes';
		$sh->{pfx_file_actual} = 'HARDWIRED PREFIXES';
	}

	if (! $pfxs) {
		$msg ||= "unknown error loading $pfx_file";
		push(@msgs, $msg);
		$msg = '';
		$pfxs = hardwired_prefixes( $sh, \$msg );
		! $pfxs and
			push(@msgs, $msg),
			$msg = '';
	}

	$sh->{pfxs} = $pfxs;			# save prefix hash, maybe undef
	$sh->{pfx_file_actual} ||= $pfx_file;	# actual prefixes file used
	return
		join '; ', @msgs;
}

# NB: below use $exget instead of $exdb to test for exdb/indb case

sub resolve { my( $bh, $mods, $id, @headers )=@_;

	defined($id) or
		addmsg($bh, "no identifier specified to fetch"),
		return undef;

	my $lcmd = 'resolve';
	my $tag;			# for tracing calls to cnflect()
	my $sh = $bh->{sh};

	! authz_ok($bh, $id, OP_READ) and
		return undef;

	my ($hdrinfo, $accept, $proto) =
		get_headers( scalar(@headers) ? join(' ', @headers) : '' );

	#my ($hdrinfo, $accept, $proto);
	#scalar(@headers) and
	#	($hdrinfo, $accept, $proto) =
	#		get_headers(join ' ', @headers);

	my $txnid;		# undefined until first call to tlogger

	# Load the prefixes hash (once) if it's not yet defined.
	# Once done, the $sh->{pfxs} points to a hash of all known prefixes.
	#
	my $msg;
	if (! $sh->{pfxs}) {

		$msg = load_prefixes($sh);	# should define $sh->{pfxs}
		$msg ||= '';
		$msg =~ s/\n/%0a/g;
		if (! $sh->{pfxs}) {		# if truly unable to function
				# we only get here if all avenues exhausted
			tlogger $sh, $txnid, "resolve FATAL ERROR: $msg";
			return undef;
		}
		# XXX somehow ARKs are coming in terminated by ^M -- should
		#     they perhaps be removed before resolve or store?
		if ($msg) {	# we have some prefixes and a non-fatal error
			addmsg($bh, $msg);		# for return
			$txnid = tlogger $sh, $txnid,
				"resolve NON-FATAL: $msg";
		}
		$txnid = tlogger $sh, $txnid,
			"LOADED prefixes from $sh->{pfx_file_actual}";
	#print "xxx doi: $sh->{pfxs}->{doi}\n";
	#print "xxx doi: $sh->{pfxs}->{doi}->{redirect}\n";
	#use Data::Dumper "Dumper"; print Dumper $sh->{pfxs}->{doi};
	#use Data::Dumper "Dumper"; print Dumper $sh->{pfxs};
	}

	# At this point $id is the original id received.  It will be altered,
	# and at the end we log the altered id (normalized, shadow, etc).
	#
	my $ur_origid = $id;	# save original $id before transforming it
		# yyy we're starting a bit late in the routine (so timing may
		#     look a little faster) but we'll get less noise from each
		#     recursive call when resolverlist support gets added.
	my $exget = $sh->{fetch_exdb} // 0;
	#$txnid = tlogger $sh, $txnid, "BEGIN $lcmd $ur_origid $hdrinfo";
	$txnid = tlogger $sh, $txnid, "BEGIN"
		# yyy what's the indb equivalent?
# ZZZZZZZZZXXXXXXXXXXXX remove debug
# xxx document use of tlogger and $exget for debugging
#		. ($exget ? " bindername: $bh->{exdbname}" .
#			" connect_string: $sh->{exdb}->{connect_string}" : "")
		. " $lcmd $ur_origid $hdrinfo";

	my $db = $bh->{db};
	my $rpinfo = undef;	# redirect prefix info
	my @dups;

	# yyy doesn't seem right -- pre-normalize or not, it should go into
	#  one step
	# Local pre-normalization.
	# Pre-normalize to remove local Apache server artifacts, such as
	# initial "/" and "t-" (for resolver-specific tests).  These are
	# things that don't belong in a generic id_normalize() routine.
	# Thus what id_decompose returns as {origid} may be different
	# from the ur-original id that was logged.
	#
	$id =~ s|^/+||;		# remove initial slashes, eg, via REQUEST_URI
	$id =~ s|^t-||i;	# remove pattern from resolver-directed tests
	$id =~ s|^eoi:|doi:|i;	# xxx big kludge: temporary support for EOI

	my $rfs = $exget
		? flex_enc_exdb($id)
		: flex_enc_indb($id)
	;

	# We have to encode multiple times, since we gradually alter the input
	# id as we try different strategies. Once encoded, we lose some
	# structural chars, such as '.' in the compact id "foo.bar:zaf".
	# This was the first time.

	my $tg = EggNog::Binder::TRGT_MAIN;	# name of target element ('_t')


	# This next step lines up lots of analysis we may use later, eg, for
	# rule-based mapping and partial redirects.

	my $idx = id_decompose($sh->{pfxs}, $id);

	if (! $idx or $idx->{errmsg}) {
		$msg = $idx ? $idx->{errmsg} : '';
		return undef;
	}
	$idx->{ur_origid} = $ur_origid;

	#### Step 0 Redirect directives to look for _before_ binder lookup
	#  yyy as Last Step look up $SCHEMELESS ids post-binder-lookup
	# Also check flag $idx{partial} to detect cases such as
	# PARTIAL_SO scheme only
	# PARTIAL_SC scheme plus colon only
	# PARTIAL_SN scheme plus naan or prefix only
	# PARTIAL_SP scheme plus naan or prefix plus /
	# PARTIAL_SS scheme plus naan or prefix plus / non-empty shoulder
	# Then use the flag to take on things that pfx_grok currently does

	if ($idx->{scheme} eq $SCHEMELESS) {
		my $target =
			$sh->{conf_pre_redirs} ?
				$sh->{conf_pre_redirs}->{ $ur_origid } : '';
		$target and
			$dups[0] = $target;
		scalar(@dups) and
			return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
				$id, \@dups, $idx, "unknown", "aftereaster" );
		#$msg = "don't know what to do with $ur_origid";
		#return undef;
	}
	# if ($sh->{conf_post_redirs}) { yyy no post-binder-lookup yet }
	# yyy no look up of $SCHEMELESS ids post-binder-lookup

	#### Step 1. look up unnormalized (verbatim) id, query string intact.

	# Here's the first real lookup.
	# Check for one special reserved ARK that is an easter egg that
	# returns information about the Resolver Rewrite Map process.
	#
	$id eq RRMINFOARK and
		@dups = ( EggNog::Binder::rrminfo() ),		# easter egg
		# yyy move to after consulting $rpinfo?
	1 or							# or usual case
		@dups = ($exget
			? exdb_get_dup($bh, $rfs->{id}, $tg)
			: indb_get_dup($db, ($rfs->{id} . TSUBEL))
		),
	;
	#$tag = "aftereaster id=$id, origid=$origid";	# debug

	scalar(@dups) and
		return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
			$id, \@dups, $idx, "unnormalized", "aftereaster" );

	# if not found...
	#### Step 2. replace id with normalized id and lookup again
	#     this time with the query string stripped off (but still
	#     preserved for later processing (eg, inflections and
	#     suffix passthrough)
	# yyy do we do (a) vanilla n11n (all hardwired, only sensitive
	#     to a few schemes) or (b) scheme-specific n11n, and/or
	#     (c) naan- or shoulder-specific n11n?
	#     for shoulder-specific we might have to index a case-folded
	#     version of the shoulder for deterministic lookup

	# yyy consult prefix shoulder and naan info to see if case-folding or
	# other normalization can be applied, possibly iteratively
	# yyy later case-insensitive ARK id match as backup?
	# yyy later case-insensitive ARK shoulder match as backup?
	#
	# define new version of id_normalize($db, $idx) 

# yyy allow scheme name minus id to return description of scheme
# yyy Julie M: when scheme is unknown, produce message (log?) to that effect for
#   resolution

	# Here comes the second lookup. First try another form of the id and
	# re-encode it.

#say STDERR "xxx before idx->full_id replacement id=$id, full_id=$idx->{full_id}";
	$id = $idx->{full_id} || '';	# normalized id or defined empty string
			# any suffix or query string will still be attached
	$rfs = $exget
		? flex_enc_exdb($id)
		: flex_enc_indb($id)
	;
	@dups = $exget
		? exdb_get_dup($bh, $rfs->{id}, $tg)
		: indb_get_dup($db, $rfs->{id} . TSUBEL)
	;
	scalar(@dups) and
		return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
			$id, \@dups, $idx, "normalized" );

	# This will be fleshed out later AFTER ezid stops storing shadow
	# ARKs, but people still resolve shadow arks found in the wild.

# xxx remove this 2a code after all shadow ARKs are gone from the binder
#	# if still not found...
#	#### Step 2a. ... and we might store a shadow ARK for it (eg, doi:...)
#
#	if ($idx->{scheme} ne 'ark') {
#		my $shadow = id2shadow($id);
#		defined($shadow) and @dups =
#			indb_get_dup($db, $shadow . TSUBEL);
#		scalar(@dups) and
#			return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
#				$shadow, \@dups, $idx, "doi2shadow" );
#	}

	# if still not found...
	#### Step 2. ... and it might be a "shadow ARK" for it (eg, ark:/b...)
	# NB: EZID once supported this as a kind of alias for non-ARK ids,
	#     so we try to honor these

#say STDERR "xxx before shadow2id id=$id";
	if ($idx->{scheme} eq 'ark' and $idx->{naan} =~ /^[b-z]\d\d\d\d$/) {
		my $real_id = shadow2id($id);
		my $real_rfs = $exget
			? flex_enc_exdb($real_id)
			: flex_enc_indb($real_id)
		;
		defined($real_id) and @dups = ($exget
			? exdb_get_dup($bh, $real_rfs->{id}, $tg)
			: indb_get_dup($db, $real_rfs->{id} . TSUBEL)
		);
		scalar(@dups) and
			return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
				$real_id, \@dups, $idx, "doi2shadow" );
	}

#	# if still not found...
#	#### Step 2c. ... see what kind of redirect info there is
#
#	# The shoulder we parsed out of the id might itself be stored
#	#
#	#   1. as an id in a binder (eg, John Deck's ark:/21547/R2), or
#	#   2. as a "shoulder" type prefix in our prefix database.
#	#
#	# We choose the first one where we find target redirection info,
#	# or drop through to check the NAAN and scheme for redirection info.
#	#
#	# If it's in the binder (1) with non-empty _t element, that overrides
#	# any prefix database redirection (ie, we'll do SPT on the id).
#	# Otherwise, if we have redirection info from the prefix database,
#	# we'll do that instead.  If we drop through, we may end up doing SPT
#	# anyway, but we will have exhausted less expensive options first.
# 
# 	if ($idx->{fqshoulder}) {	# if there's a plausible shoulder
# 		my @sai;		# there may be stored "shoulder as id"
# 		# xxx as a backup, this should do a case-insensitive
# 		#    lookup lookup for some schemes (ARK?)
# 		@sai = indb_get_dup($db, $idx->{fqshoulder} . TSUBEL);
# 		scalar(@sai) and $sai[0] and	# non-empty target?
# 			$rpinfo = 'SAI';	# xxx kludge constant,
# 			# used once to avoid executing code block below
# 			# then undefined again
# 	}
# 
# 	# If $rpinfo wasn't set above, get prefix info for the first,
# 	# most-specific redirect rule that we find.
# 	$rpinfo ||=
# 		($idx->{shdr_i}->{redirect}   ? $idx->{ shdr_i } :
# 		($idx->{naan_i}->{redirect}   ? $idx->{ naan_i } :
# 		($idx->{scheme_i}->{redirect} ? $idx->{ scheme_i } :
# 		undef )));
# 
# #print "xxx shdr_i=$idx->{shdr_i}\n";
# #print_hash ("xxx rpinfo:", $rpinfo);
# 	# yyy if debug
# 	#print_hash("/ fqshoulder=$idx->{fqshoulder}", $idx->{shdr_i});
# 	#print_hash("/ fqnaan=$idx->{fqnaan}", $idx->{naan_i});
# 	#print_hash("/ scheme=$idx->{scheme}", $idx->{scheme_i});
######
# XXXXX
#  this is short-circuiting all SPT for all the prefixes we know about!
#   and that have a redirect rule!  ie, all ARKs!!!
# if ! $rpinfo then don't bother with SPT -- ie, fail now?
# then try SPT
# _then_ look at doing redirects
######
# 	if ($rpinfo and $rpinfo ne 'SAI') {
# 		# If we get here, we will redirect to the result of a
# 		# prefix-based redirect rule found in $rpinfo, into which
# 		# we insert the id to create the target URL.
# 
# 		# xxx we're not currently sensitive to whether the request
# 		#     came in via HTTP or HTTPS, and using that in case
# 		#     the redirect rule doesn't specify
# 		# yyy right now, it may be a little fragile, but we avoid
# 		#     redirect loops by pattern-matching on the hostname
# 		#     and eliminating such rules at prefix load time in
# 		#     load_prefix_hash().
# 
# 		$proto ||= 'http';		# usually set in $hdrinfo
# 		my $redirect = $rpinfo->{ redirect };
# 		#   ${a} replaced with string "after" the colon
# 		#   ${blade} replaced with blade part of id
# 		# $redirect =~ s/\${a}/$idx->{ slid }/g;	# maybe later
# #print "xxx before re=$redirect, ";
# 		$redirect =~ s/\${blade}/$idx->{ blade }/g;
# 		$redirect =~ s/\$id\b/$idx->{ slid }/g;
# #print "xxx after re=$redirect\n";
# 		$redirect =~ m|https?://| or	# if proto not specified by rule
# 			$redirect =~ s|^|$proto://|;	# go with user's choice
# 		return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
# 			$id, [ $redirect ], $idx );
# 	}
# 	elsif ($rpinfo and $rpinfo eq 'SAI') {		# xxx drop this kludge!
# 		$rpinfo = undef;
# 	}
######
#	# N. do range lookup on fqnaan to see if we have anything
#	#  serve ids for the shdr, naan, or scheme?
#	#    if yes, apply normalization rules for next lookup
#	#    eg, upper2lower for ARKs and DOIs on most shoulders
#	#    (we hardwire rules for our ARKs, DOIs, URNs, UUs, EOIs)
#	# xxx return full_id and norm_id (different)
#	# xxx return clear statement about whether we manage this thing
#
#
#	# if still not found...
#	#### Step 3. we may do suffix passthrough (SPT).  That could be
#	# costly, so the SPT routine first looks up the shoulder via a range
#	# search (yyy adjust eventually for multi-binder (resolverlist)
#	# case) to see if we even store any ids starting with it, and bail
#	# early if not.  Also bail if a shoulder or naan flag tells us not
#	# to do SPT.
#
#	# if still not found...
#	#### Step 4. if there's a prefix redirect rule, forward request
#	# eg, shoulders for escholarship and DSC
#	# eg, naans for UNT and BnF
#	# eg, schemes for PMID and RRID
######
# 3a. corollary: while any id can be an exception to what we're
# responsible for (1 and 2 above), the prefix db will prevent us from
# doing suffix PT on any such exceptions
# xxx make sure these are in prefixes because Joan and I PROMISED:
# XXX 'rrid' is currently IN PRODUCTION -- preserve this functionality!
#
# our ($scheme_test, $scheme_target) = (
#	'xyzzytestertesty', 'http://example.org/foo?gene=$id.zaf');
#
#	cangem => {	# yyy same as prefixes.yaml
#		PFX_RRULE => 'http://www.cangem.org/index.php?gene=$id',
#	yyy	   redirect: "http://www.cangem.org/index.php?gene=$id"
#		PFX_XFORM => '2U',
#	},
#	rrid => {	# xxx this rule is diff from prefixes.yaml
#		PFX_RRULE => 'https://scicrunch.org/resolver/$id',
#	XXX	   redirect: "https://scicrunch.org/resolver/RRID:$id"
#		PFX_XFORM => '2U',
#	},
#	$scheme_test => {
#		PFX_RRULE => $scheme_target,
#		PFX_XFORM => '2U,NH',
#		PFX_LOOK => 0,
#	},
#######
#
#	# yyy is this @suffixable array a holdover from proprietary code
#	#     worries? can it be adapted to support metadata passthrough?
#	# if nothing, try suffix pass thru
#	# @suffixable is also an array of elements that we're
#	# willing to do SPT on; we'll assume that _t is always in
#	# it rather than bother to check for each resolution.
#	#
# yyy isn't the test @suffixable deprecated; use scalar(@suffixable) instead?

	if (@suffixable) {
		my $suffix;
		# NB: next call defines $suffix (via a return parameter)
		@dups = suffix_pass($bh, $id,
				EggNog::Binder::TRGT_MAIN, $suffix);
		# NB: $suffix, hence $rid, are returned DEcoded, ie, they're
		# NOT flex_encoded
		# Also, the suffix has NOT yet been added to target.
		my $rid;			# rid = root id + suffix
		$rid = substr($id, 0, - length($suffix));
#say "xxx rid=$rid, suffix_pass returned suffix=$suffix";
		($idx->{suffix}, $idx->{rid}) = ($suffix, $rid);
		# At this point, $id includes the suffix, and $rid does not.

		scalar(@dups) and
			return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
				$id, \@dups, $idx, "spt" );
		#@suffixable and grep(/^\Q$elem\E$/, @suffixable) and
	}
	#
	# From here on, $idx->{suffix} is defined iff suffix_pass() was called.

	# if still nothing, try ancient noid-born rule-based mapping
	@dups = id2elemval($bh, $id, EggNog::Binder::TRGT_MAIN);
	scalar(@dups) and
		return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
			$id, \@dups, $idx, "id2elemval" );

# xxx problem: this is capturing web server file paths as if they were partial
# ids to send to pfx for lookup
	# If still nothing, see if we have a probable partial match.
	# This is risky as we might occlude rule-based redirection if
	# we'd flagged as partial something that ought to simply redirect.

 	if ($idx->{partial}) {		# scheme, or scheme+naan
		my $partial = 
			$idx->{shdr_i}->{key}
			|| $idx->{naan_i}->{key}
			|| $idx->{scheme_i}->{key};

# xxx to do: make "n2t.net/pmid:" work -- does it fail because it's an alias?

		return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
			$id, [ ], $idx, "partial=$partial" );
	}

	# If still nothing, try new rule-based mapping.
	# Select which redirection prefix we'll use (info obtained
	# earlier by id_decompose), choosing the first, most-specific
	# redirect rule that we find.
	# yyy when/where do we use the info blocks except for a thest
	#     that we found a redirect? the info itself will be provided
	#     by calling out to pfx (at least for now).

	$rpinfo ||=
 		($idx->{shdr_i}->{redirect}   ? $idx->{shdr_i} :
 		($idx->{naan_i}->{redirect}   ? $idx->{naan_i} :
 		($idx->{scheme_i}->{redirect} ? $idx->{scheme_i} :
 		undef )));
 
#print "xxx resolve: r=$idx->{scheme_i}->{redirect}\n";
#print "xxx idx: ";
#while (my ($k, $v) = (each %$idx)) {
#	print "$k => $v, ";
#}
#print "\n";
#use Data::Dumper 'Dumper';
#print Dumper $idx;

	if ($rpinfo) {
		# If we get here, we will redirect to the result of a
		# prefix-based redirect rule found in $rpinfo, into which
		# we insert the id to create the target URL.

		# xxx we're not currently sensitive to whether the request
		#     came in via HTTP or HTTPS, and using that in case
		#     the redirect rule doesn't specify
		# yyy right now, it may be a little fragile, but we avoid
		#     redirect loops by pattern-matching on the hostname
		#     and eliminating such rules at prefix load time in
		#     load_prefix_hash().

		$proto ||= 'http';		# usually set in $hdrinfo
		my $redirect = $rpinfo->{redirect};
		#   ${a} replaced with string "after" the colon
		#   ${blade} replaced with blade part of id
		# $redirect =~ s/\${a}/$idx->{ slid }/g;	# maybe later
#print "xxx before re=$redirect, ";
		$redirect =~ s/\${blade}/$idx->{blade}/g;
		$redirect =~ s/\$id\b/$idx->{slid}/g;
# XXX proto preservation should work for ALL targets, not just rule-based
		$redirect =~ m|https?://| or	# if proto not specified by rule
			$redirect =~ s|^|$proto://|;	# go with user's choice
		return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
			$id, [ $redirect ], $idx, "rulebased" );
	}

	$idx->{fail} = 1;	# failure indicated by this flag and
	@dups = ('');		# setting @dups to a single empty string,
				# which satisfies the rrm protocol

	return cnflect( $bh, $txnid, $db, $rpinfo, $accept,
		$id, \@dups, $idx, "failed" );
		#\@dups, $idx, $tag . " lastcall" ...
}

#########################

	# xxx good spot to check for transcription error via checksum
	#     (needs some shoulder knowledge)
	# xxx good spot to check for partial single match, eg,
	#        a.b.c/now-is-t  ->  a.b.c/now-is-the-time-for-all
	#     followed by handful of matches (< than N for N a small int)
	#     followed by a "lexically close" match (possible?), eg,
	#        a.b.c/xyzzRzzxxy  ->  a.b.c/xyzzBzzxxy
	#

# returns list consisting of inflection command plus args
# $idx->{rid} is the $id/$rid
# NB: elements in %$idx are not flex_encoded

sub inflect_cmd { my(   $bh, $eset, $format,  $idx )=
		    ( shift, shift,   shift, shift );	# plus other params

	$eset ||= 'brief';	# yyy may be input by user; check for validity 
				#     unused for the moment
	$format ||= 'anvl';	# yyy may be input by user; check for validity

	my $om = File::OM->new($format,		# output, released on return
		{ outhandle => 0 });		# output to a string

	my ($metablob, $briefblob) =		# args we manufacture
		EggNog::Egg::egg_inflect(
			$bh, { all => 1 },		# $mods->{all} = 1
			$om, $idx->{rid} );
# xxx final arg must not be encoded?
#     because it goes out in order to come back in via script?
#     where it would then be double-encoded?

my $rid = $idx->{rid};
$rid =~ s/ /\\ /g;
my $slid = $idx->{slid};
$slid =~ s/ /\\ /g;

	my @args = ( 'inflect',
#"id=$idx->{rid}",
"id=$rid",
# xxx arg must not be encoded?
			"eset=$eset",
			"format=$format",
			"metablob=$metablob",
			"briefblob=$briefblob",
			#"scheme=$idx->{scheme}",
			#"naan=$idx->{naan}",
			#"shoulder=$idx->{shoulder}",
			#"ac=$idx->{slid}",
			"scheme=$idx->{scheme}",
			"naan=$idx->{naan}",
			"shoulder=$idx->{shoulder}",
#"ac=$idx->{slid}",
"ac=$slid",
			#"shoshoblade=$idx->{shoshoblade}",
			"suffix=" . ($idx->{suffix} || ""),
	);
	push @args, @_;			# append any extra params from caller
	return @args;
}

sub quote_args {			# quote args
	my $argline = shift;		# but not 1st command word
	for my $arg (@_) {		# for all args but first
		$arg ||= '';		# shouldn't happen, but minimize errors
		# NB: must quote '?' lest Apache rewrite's "uri split"
		#     thinks it's found a query string to isolate
		$arg =~ s{ [ ?	"\n] }	# hex encode space, ?, tab, ", \n
			 { sprintf("%%%02x", ord($&))  }xeg;
		$argline .= qq@ "$arg"@;	# this is for bash
	}
	return $argline;
}

# Return single target given $bh, $id, $element
# Assume args arrive unencoded.

sub exdb_get_one { my( $bh )=( shift );		# leave other args in @_
	my $rfs = flex_enc_exdb(@_);		# remaining ars
	#my @dups = exdb_get_dup(@_);
#say STDERR "rfs: ", $rfs->{id}, join(", ", @{ $rfs->{elems} });
	my @dups = exdb_get_dup($bh, $rfs->{id}, @{ $rfs->{elems} });
	return scalar(@dups)
		? $dups[0]
		: ''
	;
}

# Return single target given $bh, $id, $element
# Assume args arrive unencoded.

# xxxxxx change other {elems}->[0] to just {elem} ?

#sub indb_get_one { my( $bh, $id, $element )=@_;
sub indb_get_one { my( $bh )=( shift );
	my $db = $bh->{db};
	my $target;
	my $rfs = flex_enc_indb(@_);		# remaining ars
	#return $db->db_get("$id$Se$element", $target)
#	my $xtarget = $db->db_get($rfs->{id} . $Se . $rfs->{elem}, $target)
#		? ''				# non-zero means not found
#		: $target			# zero means success
#	;
#say STDERR "xxx xtarget=$xtarget, key=", $rfs->{id} . $Se . $rfs->{elem};
#return $xtarget;
	return $db->db_get($rfs->{id} . $Se . $rfs->{elem}, $target)
		? ''				# non-zero means not found
		: $target			# zero means success
	;
}

# Some globals to set once and use below, which are really constants. yyy
# yyy same block is copied to t/egg_resolve.t (better way to share it?)

my $Rp = EggNog::Binder::RSRVD_PFIX;	# reserved sub-element prefix
my $Rs = EggNog::Binder::SUBELEM_SC	# reserved sub-element separator prefix
	. EggNog::Binder::RSRVD_PFIX;
my $Tm = EggNog::Binder::TRGT_METADATA;   # actually content negotiation
my $Ti = EggNog::Binder::TRGT_INFLECTION; # target for inflection


# NB: $id may be different (eg, shadow) from what's in $idx->{full_id} yyy
# ($tag is debugging tool to tell who called us)
# $rpinfo normally undefined; if defined, it is a hash for a prefix info
# block containing a redirect rule that supplied the target URL.

# Content Negotiation/Inflection

sub cnflect { my( $bh, $txnid, $db, $rpinfo, $accept, $id, 
				$dupsR, $idx, $op, $tag )=@_;

	my $sh = $bh->{sh};
	my $fail = $idx->{fail};
	my $rid = $idx->{rid};			# root id (no suffix)
	my $suffix = $idx->{suffix};
	my $ur_origid = $idx->{ur_origid} || '';
	my $st;
	$op ||= 'default';
	#$tag ||= "tag_undef, id=$id";	# debug tool to trace which caller

	# SPT has been attempted by now, xxx explain better in comments how
	# inflections work!!  I don't understand this code any more.

	# If we failed, $fail will already be defined near last call
	# to this routine, so something in @$dupsR means success.
	#
	! defined($fail) && scalar(@$dupsR) and
		$fail = 0;			# success - found something
	# From here on, scalar(@$dupsR) > 0 and $fail says if we failed.
	# Now we start defining script arguments that we might be using.

	#_,eTm,ContentType content negotiation target for ContentType
	#_,eTm,   default content negotiation target if no _.eTm.ContentType
	#         exists
	#_,eTi,Inflection    key to use for target for given Inflection
	#_,eTi,    key to use for default target if given Inflection has
	#      no corresponding key

	# Now check for inflections, which may redirect or call a script.
	# Don't test on $fail, an empty $suffix, or $suffix containing a
	# word char (xxx meaning we don't honor generalized THUMP requests!?)
	# Note that we don't check for multiple targets when doing inflection
	# or content negotation.
	#
	my $returnline = '';
	my $target = '';
	my $eset = 'brief';
	my $format = 'anvl';

#say STDERR "xxx before inflect_cmd: idx_rid=$idx->{rid}";
	if ($op =~ /^partial=(.*)/) {	# just scheme given, maybe naan too
		my $partial = $1;
		$returnline = quote_args(
			inflect_cmd( $bh, $eset, $format, $idx,
				"op=partial", "partial=$partial" ))
	}

	my $get_one = $bh->{sh}->{fetch_exdb}	# {ex,in}db-agnostic get 1 elem
		? \&exdb_get_one
		: \&indb_get_one
	;

	# yyy shouldn't this be checking $idx->{query}, not $suffix?
	#     because what if you want to do SPT _and_ inflections?
	#
	# If no returnline yet and we didn't fail the lookup and if there's
	# an inflection-like suffix (ie, if SPT was called and
	# returned a non-empty suffix that contains no word char...)

	#say "xxx before returnline=$returnline, fail=$fail, suffix=$suffix";

	if (! $returnline and ! $fail and $suffix and $suffix !~ /\w/) {
		# recall: $Rp is reserved sub-element prefix
		#     and $Rs is reserved sub-element separator prefix
		#     and $Ti is target for inflection
		#     and $Tm is target for metadata (actually, conneg)

		# now check the root id
		$target =
# xxx need to encode $rid before lookup!
			&$get_one($bh, $rid, $Rp.$Ti.$suffix) ||
			&$get_one($bh, $rid, $Rp.$Ti) || '';
#		$db->db_get("$rid$Rs$Ti$suffix", $target) and	# unless found
#			$db->db_get("$rid$Rs$Ti", $target) and	# unless found
#				$target = '';			# not found

+		#say "xxx after before returnline target=$target";
		$target and		# if $target found, redirect to it
		# xxx conneg uses redir303, but inflections are different
		#     is that a good idea?
			$returnline = "redir302 $target",
		1 or		# else check if "inflect" script handles it
		$suffix eq '?'   || $suffix eq '??'  ||  $suffix eq '!'  ||
				$suffix eq '/'   || $suffix eq './'  ||
				$suffix eq '/?'  || $suffix eq '/??' ||
				$suffix eq './?' || $suffix eq './??'
				and	# script may know what to do with it
			$returnline = quote_args(
				inflect_cmd( $bh, $eset, $format, $idx,
					"op=arkinflect"))	# mainstream
		;
	}

	# // How inflections differ from conneg
	# 1. Resolution of A? by default returns metadata from resolver.
	# 2. Resolution of A with conneg when a suffix is detected will
	#    redirect so that the target returns metadata.
	# These outcomes can be altered by setting $Tm and $Ti targets
 
 	# Check for content negotiation if $returnline is still empty
 	# (ie, if id was found but no valid inflection was detected).
	# Here we check $id, not $rid.

	if (! $returnline and ! $fail and ! $suffix and $accept) {

		# yyy old xref binder element names use _mT* not ._eT*

		$target =
			&$get_one($bh, $id, $Rp.$Tm.$accept) ||
			&$get_one($bh, $id, $Rp.$Tm) || '';
		$target and		# if $target found, redirect to it
			$returnline = "redir303 $target",	# http range-14!
		1 or		# else check if "inflect" script handles it
			$returnline = quote_args(
				inflect_cmd( $bh, $eset, $format, $idx,
					"op=cn.$accept"))
		;
	}
	#say "xxx before ! returnline";
	if (! $returnline) {
		my $newstr = $suffix || '';	# make sure it's defined string

		# This is the step where the suffix is appended to (by default)
		# or substituted for any ${suffix} inside the the target.
		# It is important that if there's no suffix, any "${suffix}"
		# construct should be erased from the redirect.

		@$dupsR = map {
			s/\${suffix}/$newstr/g && $_	# try substitution
				or			# or if that fails
			$_ . $newstr			# just append suffix
			} @$dupsR;
	}

	# Check for multiple redirection if $returnline is still empty
	# (ie, id was found but no inflection or content negotation).
	#
	! $returnline and scalar(@$dupsR) > 1 and
		# double quote each target and end list of targets with --
		$returnline = quote_args(
			inflect_cmd( $bh, $eset, $format, $idx,
				"op=multi", map("target=$_", @$dupsR)))
	;

	# Mainstream case.
	# At this point $returnline will still be empty if we're doing
	# ordinary redirection or if no id was found (and $dups[0] is "").
	# xxx should be sensing shoulder for default redirect code?

	# This list of "known" http redirect status codes comes from purl.org.
	#
	# 301	Moved permanently to a target URL	Moved Permanently
	# 302	Simple redirection to a target URL	Found
	# 303	See other URLs (for Semantic Web stuff)	See Other
	# 307	Temporary redirect to a target URL	Temporary Redirect
	# 404	Temporarily gone			Not Found
	# 410	Permanently gone			Gone
	#
#say "xxx before unless returnline=$returnline, dups0=<", $dupsR->[0], ">";
	unless ($returnline) {		# if $returnline not already set

		my $redircode = '302';			# default; $tgt might
		my $tgt = $dupsR->[0] // '';		# have own redircode
		# NB: this RE is a crude check and recovery for unknown codes
		$tgt =~ /^([34][01][012347]) +(.*)/ and		# if it does
			($redircode, $tgt) = ($1, $2);	# isolate real target
		$returnline =				# redirNNN+space+target
			"redir$redircode $tgt"		# $tgt might be empty
	}
#		my @tparts = split " ", $dupsR->[0];	# tokenize
#		my $tcnt = scalar @tparts;		# token count
#		my $redircode = $tcnt > 1 ?		# assume first is a
#			$tparts[0] : '302';		# digit string
#		$redircode =~ /^[34][01][012347]$/ or	# clumsy check&recover
#			$redircode = '302';		# for unknown codes;
#		$returnline = "redir$redircode "	# redirNNN + space +
#			. (! $dupsR->[0] ? '' :		# last token, which
#				$tparts[ $tcnt - 1 ]);	# might be empty
#	}
	#$returnline or			# if $returnline not already set
	#	$returnline = "redir302 $dupsR->[0]";

	$returnline =~ tr |\n||d and
		$txnid = tlogger($sh, $txnid,
			"INFO $id returnline had a newline inside!");

	# The main event, what everything as been building to.

	#$st = print( $returnline, $tag, "\n" );	# EXACTLY ONE newliine
	$st = print( $returnline, "\n" );	# EXACTLY ONE newliine

	# pass suffix so that pre-suffix (ancestor) metadata can be tagged

	#@$dupsR = join(" ; ", @$dupsR);	# to output on one line
	#	# xxx this assumes ANVL and overwrites @$dupsR
	#	# yyy little weird assigning a scalar to
	#	#     overwrite all array elements with just one element

	if ($txnid) {
		my $msg = 'END '
			. ($fail || ! $st ? 'FAIL' : 'SUCCESS');
		$msg .= " $ur_origid ($id)";
		$rpinfo and
			$msg .= " PFX $rpinfo->{key}";
		$msg .= " -> $returnline";
		$txnid = tlogger $sh, $txnid, $msg;
	}
	return $st;	# return code rarely correlates with failed lookup
}

# XXXXX feature from EZID UI redesign: list ids, eg, by user
# XXXXX feature from EZID UI redesign: sort, eg, by creation date

# Return $val constructed by mapping the element
# returns () if nothing found, or (undef) on error

# NB: rule creation is a privileged operation, since it has broad impact and
# should be reviewed for security implications. xxx document

sub id2elemval { my( $bh, $id, $elem )=@_;

	# NB: we don't look up $id in this routine, we only transform it.
	# We do use $elem for look up, so we do flex_encode it via $rfs.

	my $clean_id = $id;			# make a mutable copy
	$clean_id =~ tr |||d;		# drop delimiters
	if ($clean_id =~ m|^([-\@\w./:+]+)$|) { # try to untaint
		$clean_id = $1;		# removes taint flag
	}
	else {				# may be tainted
		addmsg($bh,
			"id2elemval id ($id) tainted");
		return ();
	}

	my $rfs;
	if ($bh->{sh}->{fetch_exdb}) {		# no fall through beyond

		my $recid = ":idmap/$elem";	# id for rules based on $elem
		$rfs = flex_enc_exdb($recid, $elem);
		my $encid = $rfs->{id};

		# Look for the rules record under id, $A/idmap/$elem, and
		# visit all element names(patterns) and values (substitutions)
		# until we succeed with a substitution.

		my $rech = exdb_get_id($bh, $encid);	# record hash

		# This loop visits each stored pattern for this element,
		# attempts a substition, and stops when either a substitution
		# was successful or we run out of stored patterns.

		my $pattern;
		my $va;				# value array (for dupes)
		#while (my ($pattern, $va) = each %{ $dups[0] }) 
		while (my ($pattern, $va) = each %$rech) {

			# The substitution $pattern is just the element name.
			# The replacement strings are in value array ($va).

			# Due to kludgy use of unlikely delimiters, crudely
			# remove any occurrences in the things we're going to
			# submit to eval. Also, $pattern was stored as an
			# element name, so we need to decode it.

			$pattern =~ s/\^([[:xdigit:]]{2})/chr hex $1/eg;
			$pattern =~ tr |||d;
			ref($va) ne 'ARRAY' and		# eg, _id elem not array
				next;
			while (my $val = pop @$va) {
				# First successful substitution stops search.
				# Need the eval below (and thus the untainting)
				# because the $va contain $N references to
				# captured regex sub-expressions.

				my $newval = $clean_id;
				eval '$newval =~ ' . qq@s$pattern$val@ and
					return ($newval);	# ok, so return
				$@ and				# unusual error
					addmsg($bh, "id2elemval eval: $@"),
					return (undef);
			}
		}
		return ();				# nothing found
	}

	my $db = $bh->{db};
	my $first = "$A/idmap/$elem";		# key to initialize cursor
	$rfs = flex_enc_indb($first);
	$first = $rfs->{id} . $Se;
	my $key = $first;
	my $value = 0;
	my $cursor = $db->db_cursor();
	my $status =				# set cursor to start of rules
		$cursor->c_get($key, $value, DB_SET_RANGE);
	$status and				# not found or error, so bail
		$cursor->c_close(),
		undef($cursor),
		addmsg($bh, "id2elemval: $status"),
		return (undef);
	$first ne substr($key, 0, length($first)) and	# if no rules, bail
		$cursor->c_close(),
		undef($cursor),
		return ();

	# This loop visits each stored pattern for this element, attempts a
	# substition, and stops when either a substitution was successful or
	# we run out of stored patterns. yyy we only do first dupe
	# XXX document that only the first dup works $cursor->c_get. (& fix?)

	my ($pattern, @dups);
	while (1) {

		# The substitution $pattern is extracted from the part of
		# $key that follows the $Se.
		#
		# We don't do the substr() version of the /^\Q.../
		# test since we actually need a regexp match.

		($pattern) = ($key =~ m|\Q$first\E(.+)|);
		if (defined $pattern) {			# if matched

			# Due to kludgy use of unlikely delimiters, crudely
			# remove any occurrences in the things we're going to
			# submit to eval.

			# $pattern was an element name, so we need to decode it.

			$pattern =~ s/\^([[:xdigit:]]{2})/chr hex $1/eg;
			$pattern =~ tr |||d;

			$value =~ tr |||d;
			my $newval = $clean_id;

			# The first successful substitution stops the search.
			# We need the eval below (and thus the untainting)
			# because the $value may contain $N references to
			# captured regex sub-expressions.

			eval '$newval =~ ' . qq@s$pattern$value@ and
				$cursor->c_close(),
				undef($cursor),
				return ($newval);	# succeeded, so return
			$@ and				# unusual error failure
				$cursor->c_close(),
				undef($cursor),
				addmsg($bh, "id2elemval eval: $@"),
				return (undef);
		}
		$cursor->c_get($key, $value, DB_NEXT) != 0 and	# none, so bail
			$cursor->c_close(),
			undef($cursor),
			return ();
		$first ne substr($key, 0, length($first)) and	# if no match
			$cursor->c_close(),		# and ran out of rules
			undef($cursor),
			return ();
	}
	$cursor->c_close();
	undef($cursor);
}

########### Code with special knowledge of DOIs and ARKs ############
# The d2n and doip2naan routines were imported from a non-eggnog script.

# The arg should be a DOI prefix tail, ie, the prefix part following "10.",
# and should consist of pure digits.
#
sub d2n { my $ptail = shift || '';

	my $last4 = sprintf "%04d", $ptail;	# ensure at least 4 digits
	$last4 =~ s/^\d+(\d{4})$/$1/;		# keep at most last 4 digits

	$ptail <= 9999 and
		return 'b' . $last4;
	$ptail <= 19999 and
		return 'c' . $last4;
	$ptail <= 29999 and
		return 'd' . $last4;
	$ptail <= 39999 and
		return 'f' . $last4;
	$ptail <= 49999 and
		return 'g' . $last4;
	$ptail <= 59999 and
		return 'h' . $last4;
	$ptail <= 69999 and
		return 'j' . $last4;
	$ptail <= 79999 and
		return 'k' . $last4;
	$ptail <= 89999 and
		return 'm' . $last4;
	$ptail <= 99999 and
		return 'n' . $last4;
	$ptail <= 199999 and
		return 'p' . $last4;
	$ptail <= 299999 and
		return 'q' . $last4;
	$ptail <= 399999 and
		return 'r' . $last4;
	$ptail <= 499999 and
		return 's' . $last4;
	$ptail <= 599999 and
		return 't' . $last4;
	$ptail <= 699999 and
		return 'v' . $last4;
	$ptail <= 799999 and
		return 'w' . $last4;
	$ptail <= 899999 and
		return 'x' . $last4;
	$ptail <= 999999 and
		return 'z' . $last4;

	return 'OUTofRANGE' . $last4;
}

# $prefix is really an identifier
# returns the id with the a 5-digit naan instead of 10.\d{1,5}
sub doip2naan { my $prefix = shift or return '';

	# Be flexible.  Work with pure Prefixes or embedded Prefixes.
	# xxx Test with doi:10.9876/ft91234 10.9 10.98 10.987
	# xxx Test with 19.9876
	#	# xxx need better error return protocol (stderr?)

	# replace with a NAAN what looks like a prefix;
	# if the prefix has no equivalent NAAN, return it untouched;
	# everything else will be untouched
	$prefix =~
		s{ \b (doi:)? 10\. (\d{1,5}) \b (\S*) }
		 {    "ark:/" . d2n($2) . "\L$3\E"    }ixeg;
	return $prefix;
}
# above two routines imported from doip2naan script

#### unofficial NAAN registration for shadow arks
# urn:uuid: -> 97720
# uuid: -> 97721
# purl: -> 97722
#
# This was removed from NAAN registry 2015.08.18
#naa:	
#who:    NAAN Reserved for Uniform Resource Names (=) URNS
#what:   97720
#when:   2011.11.15
#where:  http://n2t.net
#how:    NP | NR, OP | 2011 |
#!why:   ARK
#!contact: Kunze, John | California Digital Library || jak@ucop.edu
##! 97720 = Burns, Oregon

# We don't check, but both args should be non-empty strings,
# the first being an NCDA-acceptable char [bcdfghjk...].
# NCDA = Nog Check Digit Algorithm

sub n2d { my( $chr1, $final4 )=@_;

	my $finalpart = $final4;
	$finalpart =~ s/^0+//;		# remove 0 padding, if any
	# this ensures that we put out 10.12 instead of 10.0012
	my $firstpart =
		($chr1 eq 'b' ? '' :
		($chr1 eq 'c' ? '1' :
		($chr1 eq 'd' ? '2' :
		($chr1 eq 'f' ? '3' :
		($chr1 eq 'g' ? '4' :
		($chr1 eq 'h' ? '5' :
		($chr1 eq 'j' ? '6' :
		($chr1 eq 'k' ? '7' :
		($chr1 eq 'm' ? '8' :
		($chr1 eq 'n' ? '9' :
		($chr1 eq 'p' ? '10' :
		($chr1 eq 'q' ? '20' :
		($chr1 eq 'r' ? '30' :
		($chr1 eq 's' ? '40' :
		($chr1 eq 't' ? '50' :
		($chr1 eq 'v' ? '60' :
		($chr1 eq 'w' ? '70' :
		($chr1 eq 'x' ? '80' :
		($chr1 eq 'z' ? '90' :
				'OUTofRANGE'
	)))))))))))))))))));

	return $firstpart . $finalpart;
}

sub ark2doi { my( $ark )=@_;

	$ark =~ s { ^ (ark:/*)? ([bcdfghjkmnpqrstvwxz]) (\w{4}) \b (\S*) }
		  { "doi:10." . n2d($2, $3) . "\U$4\E" }xeg or
		  return undef;
	$ark =~ s/%([0-9A-Fa-f]{2})/uc chr hex $1/xeg;
	return $ark;
}

# Take shadow ARK (EZID kludge) to real (new) id (a DOI).

sub shadow2id { my( $id )=@_;		# $id assumed to be shadowing a DOI

	my $query = '';
	$id =~ s/(\?.*)// and
		$query = $1;
	my $origid = $id;
	my $doi;
	$doi = ark2doi($id) or
		return undef;		# not shadow id, so no transformation

	$doi ne $origid and		# if change occurred, return shadow and
		return $doi . $query;	#    restore un-normalized query string
	return undef;			# else no known shadow transformation
}

# Shadow ARKs (kludge)
# Take id to shadow ARK (EZID kludge) or shadow DOI (CrossRef kludge).
# (This is a non-reversible transformation.)
# Return nothing if no tranformation.
#
sub id2shadow { my( $id )=@_;

	# XXXX what about EOIs?
	# Detach any query string we find, which protects it from other
	# normalization, such as case conversion and de-hyphenation.
	#
	my $query = '';
	$id =~ s/(\?.*)// and
		$query = $1;
	my $origid = $id;

	$id =~ /^doi:10\.(\d{1,5})/ and
		$id =~ s/-//g,	# ok for shadow ARKs, but not for PURLs
		$id = doip2naan($id),
		$id = lc($id),
	1 or
	$id =~ /^purl:/ and		# use unregistered NAAN 97722
		$id =~ s{^purl:(.*)}{ark:/97722/$1},
	1 or
	$id =~ /^urn:uuid:/ and		# use unregistered NAAN 97720
		# A urn:uuid: id might have a extension (eg, starting with
		# / or .) and we want to preserve extension case.
		#
		$id =~ s/-//g,	# ok for shadow ARKs, but not for PURLs
		$id =~ s{^urn:uuid:([^/.]*)}{ark:/97720/\L$1\E},

		# Greg's URN:UUID encoding
		#$id = "urn:uuid:430c5f08-017e-11e1-858f-0025bce7cc84";
		# urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6
		# RFC 4122 implies that hyphens aren't significant in
		# lexical equivalence, but does leave them
		# but does explicitly represent uuids with hex digits;
	1 or
	$id =~ /^uuid:/ and		# use unregistered NAAN 97721
		# A uuid: id might have a extension (eg, starting with
		# / or .) and we want to preserve extension case.
		#
		$id =~ s/-//g,	# ok for shadow ARKs, but not for PURLs
		$id = 'uuid:' . uuid_normalize($id),
		$id =~ s{^uuid:([^/.]*)}{ark:/97721/\L$1\E},
		#$id = lc($id),
		#$id =~ s{^uuid:}{ark:/97721/},
	;					# else no change
	$id ne $origid and		# if change occurred, return shadow and
		return $id . $query;	#    restore un-normalized query string
	return undef;			# else no known shadow transformation
}

# xxx maybe c64 is how uuid should be stored
# we don't allow standard base64 encoding from users because / can be
# part of the base id and we reserve that for separating suffixes
#
sub uuid_normalize { my( $id )=@_;

	my $extension = '';
	# strip scheme and extension suffix, if any
	$id =~ s|^\s*uuid:([^/.]*)(.*)|$1| and
		$extension = $2;
	$id =~ tr|[g-zG-Z_~=]|| or	# efficiently looks for (counts) chars
		return $id . $extension;	# probably already hex-encoded

	# If we get here, we have a base64 or c64 (non-standard) encoding.
	# _ and ~ signal a c64 encoding, which we normalize and then decode
	$id =~ tr|_~|+/|;		# map _ and ~ to + and / (if any)
	use MIME::Base64;
	return
		( unpack( 'H*', MIME::Base64::decode $id ) . $extension );
}

sub html_head { my( $title )=@_;
	
	return
qq@<!DOCTYPE HTML PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<title>$title</title>
<link rel="shortcut icon" href="http://n2t.net/d/doc/favicon.ico">
<link rel="stylesheet" type="text/css" href="http://n2t.net/d/doc/style.css">
<script type="text/javascript" src="http://n2t.net/d/doc/jquery.js"></script>
<script type="text/javascript" src="http://n2t.net/d/doc/base.js"></script>

<script type="text/javascript">/*<![CDATA[*/
areMessages = false;

/*]]>*/</script>

<head>
<title
</head>
<body>
<center>
<h2>$title</h2>
@;
}

sub html_erc { my( $erc )=@_;
	
	return
qq@<!-- Electronic Resource Citation (http://dublincore.org/groups/kernel/)

erc:
$erc
-->
@;
}

sub html_tail {
	
	return
qq@
</center>
</body>
</html>
@;
}

# Returns first matching initial substring of $id or the empty string.
# yyy currently we only check first dup for a match
# The match is successful when $id has $element bound to $value under it.
# If $value is undefined, match the first $id for which $element exists
# (bound to anything or nothing).  If no $element is given either, match
# the first $id that exists in the database.  Note that matching occurs
# only by examination of the first dup.
#
# Chopping occurs at word boundaries, where words are strings of letters,
# digits, underscores, and '~' ('~' included for "gen_c64" ids).
#
# Example: given this $id
#   http://foo.example.com/ark:/12345/xt2rv8b/chap3/sect5//para4.txt?a=b&c=d/
# yyy but this example.com we'd never see, right? cos we only see n2t.net??
#
# chop from back into shorter $id's, looking up each, in this order:
#   http://n2t.net/ark:/12345/xt2rv8b/chap3/sect5//para4.txt?a=b&c=d/
#   http://n2t.net/ark:/12345/xt2rv8b/chap3/sect5//para4.txt?a=b&c=d
#   http://n2t.net/ark:/12345/xt2rv8b/chap3/sect5//para4.txt?a=b
#   http://n2t.net/ark:/12345/xt2rv8b/chap3/sect5//para4.txt
#   http://n2t.net/ark:/12345/xt2rv8b/chap3/sect5//para4
#   http://n2t.net/ark:/12345/xt2rv8b/chap3/sect5
#   http://n2t.net/ark:/12345/xt2rv8b/chap3
#   http://n2t.net/ark:/12345/xt2rv8b
#   http://n2t.net/ark:/12345/xt2       !!!! xxx shoulder -- not yet! ++
#   http://n2t.net/ark:/12345
#   http://n2t.net/ark
#   http://n2t.net
#   http://n2t
#   http
#
# ++ should shoulders be recognized just for ARKs? or also for DOIs, URLs, URNs?
#    if so, what's the pattern?  how about this pseudo-regexp:
#             (https?://)?Host/Scheme:/?Naan/[[:alpha:]]*\d
#	pros: enabled for all comers
#	cons: small slowdown due to one extra stop
#                      ^
# ++ does this generalize at all to support shoulderspace splitting, eg,
#     check if we know about this id (or it's ancestors by chopping),
#     and be prepared to return multiple redirects
#
# Note that the value check is a "not equals": chop until you find a value
# different from the given value (eg, non-empty, or different from "").
# XXX document at least one use case for the value check
#
# Loop logic
#
# The main loop is a classic Perl complex Boolean test (for speed) against
# an id that keeps getting its tail chopped off.  The loop's premise,
#   "Keep going until either the key is found OR we ran out of id"
# can be expressed as
#   "Keep going until either
#      (the key exists && we're not value-checking ||
#        the key exists && the key's lookup value ne $value)
#    OR we ran out of id"
# which is the same as
#   "Keep going until either
#      (the key exists && (we're not value-checking ||
#        the key's lookup value ne $value))
#    OR we ran out of id"
#
# What's encoded below is the result of turning the "until" into a
# "while" by negating the test to get:
#   "Keep going _while_ either
#      (the key doesn't exist || (we are value-checking &&
#        the key's lookup value eq $value))
#    AND we haven't run out of id"
#
# This routine assumes $id arg arrives already flexencoded.

sub indb_chopback { my( $bh, $verbose, $id, $stopchop, $element, $value )=@_;

# XXXXX the resolver MUST start enforcing ARK normalization, eg, no '-'s!
#       especially as '-'s in, eg, uuids, will really slow ??db_chopback down

	my $exget = $bh->{sh}->{fetch_exdb} // 0;
	my $dbh = $bh->{tied_hash_ref};

	$id ||= "";
	$stopchop ||= 0;
	my $tail = "";
	defined($element) and
		$tail .= "$Se$element";
	my $key = $id . $tail;
	my $valcheck = defined($value);
	# yyy what if $value defined but $element undefined?
	#$element ||= "";		# yyy edge case avoiding undef error

	# xxx allow opt to define its own ??db_chopback algorithm,
	# xxx allow opt to carry verbose and debug flags

	# Note that qr/\w_~/ matches c64 identifiers
	# In order for the loop below to terminate (to not be infinite),
	# $id must always end in word chars; this works in tandem with
	# $key (= $id . $tail).  But the first chop is handled specially
	# so we don't inadvertently drop an inflection (which is when $id
	# ends in non-word chars).
	# yyy these [^\w_~] regex strings are used several places in the
	#    code and should be turned into a variable that we compile
	#    once and use standard in every instance
	#
	#$id =~ s/[^\w_~]*$//;	    # trim any terminal non-word chars
	$id =~ s/[^\w_~]+$// and    # if terminal non-word chars got trimmed
		exists($dbh->{ $key=$id . $tail }) and	# and new key exists
		($verbose && say("id:$id")) and		# (optional chatter)
		! ($valcheck 				# we're checking values
			&&				# and
		    $dbh->{$key} eq $value) and		# it's the wrong value
			return (length($id) > $stopchop ? $id : "")
	;

	# See loop logic comments above.
	1 while (					# continue while
		! exists($dbh->{$key}) ||		# key doesn't exist or
		# XXX is there a faster way to check than calling exists()?
			($valcheck 			# we're checking values
				&&			# and
	# xxx document: not checking for dups
			$dbh->{$key} eq $value)		# it's the wrong value
		and					# and if, after
		($verbose and say("id=$id")),		# (optional chatter)
		($id =~ s/[^\w_~]*[\w_~]+$//),		# we chop off the tail
		# xxx is this next the most efficient way?
		#     maybe use substr as lval with replacement part?
		# any necessary $key encoding was already done
		($key = $id . $tail),			# and update our key,
		length($id) > $stopchop			# something's left
	);
	#
	# If we get here, we either ran out of $id or we found something.
	#
	# The caller gets the empty string when we ran out, and they have
	# to deal with what exactly that means.  Running out means the
	# boundary chopping algorithm chopped back (a) to before $stopchop
	# or (b) to when length($id) == $stopchop.  Case (a) is more
	# likely since we'll usually be called with $stopchop pointing to
	# the shoulder end (eg, to the 8 in ark:/12345/pq8xr6...), which
	# is not a chopping boundary.

	return length($id) > $stopchop ? $id : "";
}

# See comment block before indb_chopback() (above).
# This routine assumes $id arg arrives already flexencoded.
# We also assume $element is defined.

sub exdb_chopback { my( $bh, $verbose, $id, $stopchop, $elem, $value )=@_;

# XXXXX the resolver MUST start enforcing ARK normalization, eg, no '-'s!
#       especially as '-'s in, eg, uuids, will really slow ??db_chopback down

	$id ||= "";
	$stopchop ||= 0;
	my $valcheck = defined($value);

	# xxx allow opt to define its own ??db_chopback algorithm,
	# xxx allow opt to carry verbose and debug flags

	# Note that qr/\w_~/ matches c64 identifiers
	# In order for the loop below to terminate (to not be infinite),
	# $id must always end in word chars; this works in tandem with
	# $key (= $id . $tail).  But the first chop is handled specially
	# so we don't inadvertently drop an inflection (which is when $id
	# ends in non-word chars).
	# yyy these [^\w_~] regex strings are used several places in the
	#    code and should be turned into a variable that we compile
	#    once and use standard in every instance
	#
	#$id =~ s/[^\w_~]*$//;	    # trim any terminal non-word chars

#########################
# Problem: during chopback,
# the "...ed e?" should chop
#  to "ed e", but it looks like it went
#  to "ede"
# ???? who dropped that space?
# xxx notok result=0, id=ark:/12345/b^2ec^5ed e?, elem=_t
# xxx notok result=0, id=ark:/12345/b^2ec^5ede?, elem=_t
#########################

#say STDERR "xxx in exdb_chopback id=$id, stopchop=$stopchop";
	my @dups;
	if ($id =~ s/[^\w_~]+$//) { # if terminal non-word chars got trimmed
		$verbose and
			say("id:$id");			# optional chatter
		@dups = exdb_get_dup($bh, $id, $elem);
#say STDERR "xxx in trimmed non-word chars id=$id, elem=$elem, dups0=$dups[0]";
		scalar(@dups) and			# if the new key exists
		  ! ($valcheck 				# we're checking values
			&&				# and
		    $dups[0] eq $value) and		# it's the wrong value
			return (length($id) > $stopchop ? $id : "");
	}

	# See loop logic comments above.
	1 while (					# continue while
		! scalar(@dups = exdb_get_dup(		# key doesn't exist or
			$bh, $id, $elem)) ||
#		! exists($dbh->{$key}) ||		# key doesn't exist or
			($valcheck 			# we're checking values
				&&			# and
	# xxx document: not checking for dups
			$dups[0] eq $value)		# it's the wrong value
#			$dbh->{$key} eq $value)		# it's the wrong value
		and					# and if, after
		($verbose and say("id=$id")),		# (optional chatter)
		($id =~ s/[^\w_~]*[\w_~]+$//),		# we chop off the tail
		# xxx is this next the most efficient way?
		#     maybe use substr as lval with replacement part?
		# any necessary $key encoding was already done
		length($id) > $stopchop			# something's left
	);

#say STDERR "xxx after trim and loop, id=$id, elem=$elem";
	#
	# If we get here, we either ran out of $id or we found something.
	#
	# The caller gets the empty string when we ran out, and they have
	# to deal with what exactly that means.  Running out means the
	# boundary chopping algorithm chopped back (a) to before $stopchop
	# or (b) to when length($id) == $stopchop.  Case (a) is more
	# likely since we'll usually be called with $stopchop pointing to
	# the shoulder end (eg, to the 8 in ark:/12345/pq8xr6...), which
	# is not a chopping boundary.

	return length($id) > $stopchop ? $id : "";
}

# Discussion of Suffix Pass-Through
#
# xxx see PURL partial redirect flavors at
#     http://purl.org/docs/help.html#purladvcreate
# (all caps below indicate arbitrary path)
# 1. Partial  (register A -> X, submit A/B and go to X/B)
# 2. Partial-append-extension (reg A->X, submit A/foo/B?C -> X/B.foo?C)
# 3. Partial-ignore-extension (reg A->X, submit A/B.html -> X/B)
# 4. Partial-replace-extension (reg A->X, submit A/htm/B.html->X/B.htm)
# XXX find out what use case they had for 2, 3, and 4; perhaps these?
# ?for 2, stuff moved and extensions were added too
# ?for 3, stuff moved and extensions were removed too
# ?for 4, stuff moved and extensions were replaced too

# xxx looks like Noid has had this forever, but on a per resolver basis...
# xxx compare Handle "templates", quoting from "Handle Technical Manual"
#     server prefix 1234 could be configured with
#<namespace> <template delimiter="@">
# <foreach>
#  <if value="type" test="equals" expression="URL">
#   <if value="extension" test="matches"
#     expression="box\(([^,]*),([^,]*),([^,]*),([^,]*)\)" parameter="x">
#    <value data=
#        "${data}?wh=${x[4]}&amp;ww=${x[3]}&amp;wy=${x[2]}&amp;wx=${x[1]}" />
#   </if>
#   <else>
#    <value data="${data}?${x}" />
#   </else>
#  </if>
#  <else>
#   <value />
#  </else>
# </foreach>
#</template> </namespace>
#
# For example, suppose we have the above namespace value in 0.NA/1234,
# and 1234/abc contains two handle values:
#   1	URL	http://example.org/data/abc
#   2	EMAIL	contact@example.org
# Then 1234/abc@box(10,20,30,40) resolves with two handle values:
#   1	URL	http://example.org/data/abc?wh=40&ww=30&wy=20&wx=10
#   2	EMAIL	contact@example.org

# TBD: this next would be a generalization of suffix_pass that returns
# metadata (where not prohibited) for a registered ancestor of an
# extended id that's not registered
sub meta_inherit { my( $noid, $verbose, $id, $element, $value )=@_;
}

# Returns true if any key starts with the string, s, false if not.
# Returns a message on error. yyy how best to return a msg?
# Assumes that $s is already flex_encoded ready-for-storage.

sub any_key_starting { my( $bh, $s )=@_;

	if ($bh->{sh}->{fetch_exdb}) {
		my ($result, $msg);
		my $ok = try {				# exdb_get_dup
			my $coll = $bh->{sh}->{exdb}->{binder};	# collection
			$result = $coll->find(
				{ $PKEY => qr/^\Q$s/ }
			)
			// 0;		# 0 != undefined
			# find returns non-empty cursor, even if nothing found
			return	# return 1 from "catch" if at least one result
				($result && $result->next ? 1 : 0);
		}
		catch {
			$msg = "error fetching pattern \"/^$s/\": $_";
			return undef;	# returns from "catch", NOT from routine
		};
		! defined($ok) and 	# test for undefined since zero is ok
			addmsg($bh, $msg),
			return undef;
		return $ok;		# return from sub with "caught" value
	}
	my $db = $bh->{db};
	my ($key, $value) = ($s, 0);
	my $cursor = $db->db_cursor();
	my $status = $cursor->c_get($key, $value, DB_SET_RANGE);
	# yyy no error check, assume non-zero == DB_NOTFOUND
	$cursor->c_close();
	undef($cursor);
	$status != 0 and
		return 0;		# nothing found or error (silent)

	# If we get here (likely), something was found.
	return
		($s eq substr($key, 0, length($s)));

	#return ($key =~ /^\Q$id/ ? 1 : 0);
	#$status < 0 and
	#	return "any_key_starting: seq status/errno ($status/$!)";
}

# XXX consider dropping this routine! does anyone call it?

# Meant to be called if we know the binder has no individual ids stored
# under the apparent shoulder for $id, this routine looks at the $id's NAAN
# to see if the NAAN itself has stored redirection/inflection target(s),
# and if so appends the post-NAAN part of $id to the target, unless there's
# some inflection stuff happening.
# Assumes args are encoded ready-for-storage
# xxx returns ready-for-storage encoded value?
# yyy not sure what purpose this serves any more
# yyy does any part of resolver use/test this code?

sub check_naan { my( $bh, $naan, $id, $element )=@_;

	my $exget = $bh->{sh}->{fetch_exdb} // 0;
	my $db = $bh->{db};
	my $remainder =			# get this BEFORE next normalization
		substr $id, length($naan);
	$naan =~ s|/*$||;		# do some light normalization
	my @dups;
	@dups = $exget
		? exdb_get_dup($bh, $naan, $element)
		: indb_get_dup($db, "$naan$Se$element")
	;
	scalar(@dups) or
		return '';		# NAAN not found; can't help here

	my $newbase = $dups[0];		# yyy safe to ignore other dups?
	my $qs = $id;			# derive inflection from query string
	$qs =~ s|^[^?]*||;		# by dropping all chars up to 1st '?'

	# If there's no call for us to interfere, just pass given remainder.
	#
	! $qs || ($qs ne '?' && $qs ne '??') and
		return ($newbase . $remainder);

	# If we get here, $qs is ? or ??.  Now check ..._inflect element.
	#
	@dups = $exget
		? exdb_get_dup($bh, $naan, ($element . '_inflect'))
		: indb_get_dup($db, ("$naan$Se$element" . '_inflect'))
	;
	my $ifl = scalar(@dups) ? $dups[0] : '';
	#$ifl eq 'cgi' || $ifl eq 'thump' || $ifl eq 'noexpand' or
	$ifl eq 'thump' || $ifl eq 'noexpand' or
		$ifl = 'thump';		# default if no valid value given

	$ifl eq 'noexpand' and		# if noexpand, return
		return ($newbase . $remainder);		# ? or ?? intact

	$remainder =~ s|\?*$||;		# strip ? or ?? from remainder

	# If we get here, all that's left is 'thump' for this NAAN.

	return ( $newbase . ( $qs eq '?'    # yyy why both branches the same?
		? "?show(brief)as(anvl/erc)"
		: "?show(brief)as(anvl/erc)" )
	);
}

# ========== documentation support for "_t_am n" ==========
# ... on the shoulder or on the id no support yet for "q" or "t"
#
# DRAFT (xxx don't know if this is accurate any more (at all))
# This is the base target element "_t" used for resolution:
#
# _t T		# go to T for identical match AND "spt match"
#		# (identical match should really be against a
#		# normalized id--currently only lightly normalized).
# _t_inflect V	# In special NAAN case, _t means go to T with the entire
#		# remainder intact, except when just ? or ?? is given.
#		# In this case, the default action is to expand these
#		# inflections into explicit thump-like query parameters
#		# (to help orgs with Tomcat servers, or orgs who don't
#		# know how to expand the ? or ?? themselves; however, if
#		# the _t_inflect element is present its value V is taken
#		# into account.  Values of V are
#		#    thump		(default) THUMP expansion
#		#    noexpand		no expansion
#		#    cgi		CGI-type expansion (xxx not yet)
#
# The following values are only used during resolution and affect
# "ancestor match" (AM), which is when a given id matches nothing in
# the database, but an ancestor (initial substring) of it does match.
# Behavior depends on user-settable elements.  Below are special elements
# related to behavior for the "_t" element, so it affects resolution.
#
# For _t the affected behavior concerns suffix passthrough (SPT).
#
# _t_am n	# (none) don't do SPT at all; check this
#		# BEFORE calling ??db_chopback on a shoulder, but DISCOURAGE
#		# as spt is cool and paranoia spoils it for all
#		# ? can be applied to an id or to an entire shoulder
#		# (note: only for first-digit convention shoulders)
# _t_am q	# (query) go to T but with suffix in query string
#		# check after calling ??db_chopback
# _t_am t	# (truncate) go to T but without suffix
#		# check after calling ??db_chopback

# XXX add shoulder element tag that permits us to search shoulder AND
#     then, failing that, continue searching redirecting to a given NAAN

# XXXX suffix_pass routine should probably be called ancestor_match_spt
#      or something similar

# XXX Work with John Deck and Hank Bromley on these
# _t_am_equals X	# NO: go to T only on "proper" AM match"; go to X
#			# on identical match (requires checking on every
#			# sucessful lookup to see if _t_am_equals exists,
#			# and this is to support an edge case
#			# NOT A GOOD IDEA -- better to install a rewrite
#			# rule at the receiving server that routes back,
#			# or just suffer the 404.
# =========== end doc support =====================

# xxx dups!
# xxx stop chopping at after a certain point, eg, after base object
#     name reached and before backing into NAAN, "ark:/"
#     (means manually asking for something like n2t.net/ark:/13030? )

# xxx don't call this routine except for ARKs (initially, to illustrate)
#     maybe later call it for other schemes


# returns array of values, and returns $suffix_ret ($_[3]) (if any, or '')
# !!! assumes $valsR has been initialized to {}
# This routine tries to be generalized for any $element, but it's
# definitely warped (in thinking and in testing) towards the "_t"
# element.  Proceed with caution if you intend more general use.

# ???
# Assumes $id is already encoded, ready for lookup in storage.

#
# XXX should pass in results of normalization to save time in reparsing id

sub suffix_pass { my( $bh, $id, $element, $suffix_return )=@_;

# xxx convert check_naan and suffix_pass and chopback

# xxx need flex_get() routine that ...
#      flex_get( $exget, $from, $arg1, [ $arg2 ] )
#       where if ($exget) then ($bh, $id, $elem) = ($from, $arg1, $arg2)
#			  else ($db, $key) = ($from, $arg1, $arg2)
# xxx maybe need flex_gete($bh, $id, $elem) and flex_geti($db, $key)

	$_[3] = '';			# initialize $suffix_return
	my $raw_id = $id;		# save in case needed (not yet)

	my $exget = $bh->{sh}->{fetch_exdb} // 0;
	my $rfs;
	if ($exget) {
		$rfs = flex_enc_exdb($id);
		$id = $rfs->{id};
		$rfs = flex_enc_exdb($element);
		$element = $rfs->{id};		# unchanged for vanilla target
	}
	else {
		$rfs = flex_enc_indb($id);
		$id = $rfs->{id};
		$rfs = flex_enc_indb($element);
		$element = $rfs->{id};		# unchanged for vanilla target
	}

	my $origlen = length($id);
	my $db = $bh->{db};
	my $opt = $bh->{opt};	# xxx needed?
	my $st;
	my $verbose = $opt->{verbose};
	$verbose and
		print "start suffix passthrough (spt) on $id\n";

	my $value = "";			# because we want a non-empty value

	# We prepare to call ??db_chopback() to see if an ancestor (substring)
	# of the submitted $id exists in our db. Recall that we chopback from
	# right-hand end and move left towards the start. This is expensive,
	# so we optimize a little (a) by a pre-check (a kind of big pre-chop
	# to see if a bunch of little chops are worth it) to see if
	# the root is present at all and (b) by stopping the ??db_chopback when
	# we've reached (going right-to-left) into an uninteresting portion of
	# the identifier, eg, scheme, host, etc.  Use $stop to hold the
	# substring (minus some initial portion of the id) that will be
	# subject to chopping (when we reach back to the start of $stop, we're
	# done).

	my $stop = $id;		# initialize choppable portion

	# yyy what about ssh://, rsync://, etc?
	# yyy what about mailto:? eg, should we allow mail forwarding
	#     when you send to foo@n2t.net ?
	# yyy what's needed to support URLs?

	# If we can remove http://, https://, etc., also remove the NMA.
	# Allow flex_encoded chars in protocol. yyy needed?

	$stop =~ s|^[\w^]+:///?||	and	# http://, https://, etc.
		$stop =~ s|^[^/]*/*||	# host, port, ie, NMA
	;

	# If we can remove a uuid: label, also remove the NAA. xxx?
	$stop =~ s|^(?:urn:)?uuid:||i	and	# urn:uuid: or just uuid:
		$stop =~ s|^[^:]+:+||,	# the uuid: _was_ the NAA xxx!
	1
	or
	# If we can remove "ark:", "doi:", etc., also remove the NAA.
	# Allow flex_encoded chars in scheme (needed for compact id prefixes).

	$stop =~ s|^[\w^]+:/*||	and	# ark, doi, purl, hdl, etc.
		$stop =~ s|^[^/]+/||,	# NAAN
	;
	# xxx normalize id before this all started?
	#    eg, DOI->doi  ark:12345->ark:/12345

	# Record where we are, which will normally be at the end of
	# the NAAN (or NAA in URN case), just before the shoulder.

	my $naan = substr $id, 0, $origlen - length($stop);

	# Then eliminate shoulder, if any, assuming the "first digit
	# convention" (1st digit preceded by zero or more pure alphabetics).
	# Examples:  bcd4, fk5, t8, 7; but NOT t or "".

	$stop =~ s|^[A-Za-z]*\d||;	# first-digit shoulder

	# Record where we are now in $stopchop, which is really the
	# length of the portion of the original id that we don't want to
	# chop back into.

	my $stopchop = $origlen - length($stop);
	my $shoulder = substr $id, 0, $stopchop;

	# If we get here, $shoulder and $naan are properly encoded.

	# The next call to ??db_chopback() is potentially expensive, so let's
	# see if there are any easy reasons to avoid it.  First, see if
	# our database has any ids at all under (that start with) the
	# (fully-qualified) shoulder that starts the identifier.

#say STDERR "xxx before any_key_s id=$id";
	$st = $shoulder ? any_key_starting($bh, $shoulder)
		: 1;	# for edge case where $id doesn't look like a URL

	my (@dups, $newid);	# yyy over-doing this checking of dups thing?

	! $st and		# no shoulder matched; check NAAN match
		# xxx if OCA/IA binder is in resolver list, won't this
		# next check bypass that (or be redundant with it)?
		# yyy is check_naan code tested/used in real life?
		($newid = check_naan($bh, $naan, $id, $element)) and
			return $newid;

	# XXXX need a very important shoulder optimization to deal with
	#   millions of long ids stored MOSTLY elsewhere, that we want to
	#   avoid calling ??db_chopback() on, eg, Biocode  -- how to implement?

	! $st and	# no shoulder match, or external NAAN opportunity
		($verbose and print
			"skipping chopback; no keys start with $shoulder\n"),
		return ();

	my $am = $element . $ANCESTOR_MATCH_ELEM;
	@dups = $exget
		? exdb_get_dup($bh, $shoulder, $am)
		: indb_get_dup($db, "$shoulder$Se$am");
	my $amflag = scalar(@dups) ?
		$dups[0] : '';		# yyy safe to ignore other dups?
	$verbose and print "shoulder amflag=$amflag for $shoulder|$am\n";
	$amflag eq 'n' and
		($verbose and print("ancestor processing disallowed ",
			"at shoulder", $am eq '_t_am' ?
				', eg, no suffix passthrough' : '', "\n")),
		return ();

	$verbose and print
		"aim to stop before $stopchop chars in $id (before $stop)\n";

	#### The main event. ####

#say STDERR "xxx before chopback id=$id";
	$newid = $exget		# NB: returned $newid is already flex_encoded
		? exdb_chopback($bh, $verbose, $id, $stopchop, $element, $value)
		: indb_chopback($bh, $verbose, $id, $stopchop, $element, $value)
	;

#say STDERR "xxx raw_id=$raw_id, newid=$newid, origlen=$origlen";

	#$verbose and
	#	print "chopback id was $id\n";
	! $newid and
		# yyy are we over-doing this checking of dups thing?
		@dups = ($exget
			? exdb_get_dup($bh, $shoulder, $element)
			: indb_get_dup($db, "$shoulder$Se$element")
		),
		scalar(@dups) and
			$newid = $shoulder;

	$verbose and
		print "chopback for $id found ", ($newid ? "$newid\n"
			: "nothing, stopping at $shoulder\n");
	! $newid and
		return ();

	@dups = $exget				# check flag for $newid
		? exdb_get_dup($bh, $newid, $am)
		: indb_get_dup($db, "$newid$Se$am")
	;
	$amflag = scalar(@dups) ?	$dups[0] : '';
	$verbose and print "id amflag=$amflag for $newid|$am\n";
	$amflag eq 'n' and
		($verbose and print("ancestor processing disallowed ",
			"at id", $am eq '_t_am' ?
				', eg, no suffix passthrough' : '', "\n")),
		return ();

	$verbose and	# xxx this $verbose is more like $debug
		print "chopped back to $newid\n";

	# Found something.  Isolate the suffix by giving the original
	# id and a negative offset to substr().

#say STDERR "xxx substr $id, raw_id=$raw_id, newid=$newid, origlen=$origlen";

	my $suffix = substr $id, length($newid) - $origlen;
# xxxxxxxxx test this flex_decoding!
	$suffix =~ s/\^([[:xdigit:]]{2})/chr hex $1/eg;		# flex_dec
	$_[3] = $suffix;		# set $suffix_return

	$verbose and	# yyy this $verbose is more like $debug
		print "suffix for newid ($newid) is $suffix\n";
		# yyy shouldn't this use STDERR?

	# note that chopback looked this up, but not dup-sensitive;
	# so we look it up again, this time passing dups back

	@dups = $exget
		? exdb_get_dup($bh, $newid, $element)
		: indb_get_dup($db, "$newid$Se$element")
	;
	# @dups now has base target, but no appended or substituted suffix

	$verbose	and print "spt to: ", join(", ", @dups), "\n";

	return @dups;
}

1;

__END__


=head1 NAME

Resolver - routines to do advanced identifier resolution

=head1 SYNOPSIS

 use EggNog::Resolver;		    # import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2017 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<dbopen(3)>, L<perl(1)>, L<http://www.cdlib.org/inside/diglib/ark/>

=head1 AUTHOR

John A. Kunze

=cut
