#!/usr/bin/env perl

# NB: this filename starts with 'z' so that it is more likely run last
#     when "make test" is run, and that gives a green light to a
#     subsequent "n2t rollout" or "pfx rollout", which will find that
#     directory's "tested_ok" flag file intact (so you
#     don't have to run "pfx test" one more time just to set it).
# NB: this part of the eggnog source DEPENDS on pfx,
#     defined in another source code repo (n2t_create)

use 5.10.1;
use Test::More;

use strict;
use warnings;

use EggNog::ValueTester ':all';
use File::Value ':all';
use EggNog::ApacheTester ':all';

#my ($td, $cmd) = script_tester "egg";		# yyy needed?
#my ($td2, $cmd2) = script_tester "nog";		# yyy needed?

my ($td, $cmd, $homedir, $tdata, $hgbase, $indb, $exdb) = script_tester "egg";
$td or			# if error
	exit 1;

my ($td2, $cmd2);
($td2, $cmd2, $homedir, $tdata, $hgbase, $indb, $exdb) = script_tester "nog";
$ENV{EGG} = $hgbase;		# initialize basic --home and --testdata values

# Tests for resolver mode look a little convoluted because we have to get
# the actual command onto STDIN in order to test resolver mode.  This
# subroutine makes it a little simpler.
#
sub resolve_stdin { my( $opt_string, @ids )=@_;
	my $script = '';
	$script .= "$_.resolve\n"
		for @ids;
	my $msg = file_value("> $td/getcmd", $script);
	$msg		and return $msg;
	return `$cmd --rrm $opt_string - < $td/getcmd`;
}

# xxx Args ( $opt_string, $tag1, $id1, $header1, $tag2, $id2, $header2, ... )
#     where $tags are mnemonics printed on the line that must match in test
#     and help to debug!
# Args ( $opt_string, $id1, $header1, $id2, $header2, ... )
sub resolve_stdin_hdr {
	my $opt_string = shift;
	my $script = '';
	my ($id, $hdr);
	while ($id = shift) {
		$hdr = shift || '';
		$hdr and
			$hdr = ' ' . $hdr;
		$script .= "$id.resolve$hdr\n";
	}
	my $msg = file_value("> $td/getcmd", $script);
	$msg		and return $msg;
	return `$cmd --rrm $opt_string - < $td/getcmd`;
}

# Args ( $opt_string, $id1, $header1, $id2, $header2, ... )

sub nresolve_stdin_hdr {

	use IPC::Open2;

	my $opt_string = shift;		# first arg is $opt_string

	# The remaining args come in a sequence of 4-tuples:
	#   id to resolve
	#   header (optional) to submit with it (eg, conneg)
	#   response expected (eg, 302 https://...)
	#   label to print along with test result

	my ($CHLDOUT, $CHLDIN);		# child output and input
	my $pid = open2($CHLDOUT, $CHLDIN, "$cmd --rrm $opt_string -");

	#$pid = open2($CHLDOUT, $CHLDIN, 'some cmd and args');
	# or without using the shell
	#$pid = open2($CHLDOUT, $CHLDIN, 'some', 'cmd', 'and', 'args');

	my $script = '';
	my ($id, $hdr, $response, $label);
	while ($id = shift) {			# id arg
		if ($id eq 'ZZZEXIT') {
			say "ZZZ premature exit";
			last;
		}
		$hdr = shift || '';		# header arg, if any
		$hdr and
			$hdr = ' ' . $hdr;
		$response = shift || '';	# target URL pattern to match
		$label = shift || '';		# label to print with test

		say $CHLDIN "$id.resolve$hdr";	# submit $id to be resolved
		my $line = <$CHLDOUT>;		# read resolver response
		defined($line) or		# EOF is not supposed to happen
			return "resolver closed unexpectedly";

		like $line, qr/\Q$response/, $label;
	}
	close($CHLDIN);
	close($CHLDOUT);
	waitpid($pid, 0);
	my $child_exit_status = $? >> 8;
	return $child_exit_status;
}

# This set of tests runs off of a configuration directory that defines
# the web server, creates binders and minters (see make_populator), etc.
#
#my $cfgdir = "t/n2t";		# this is an N2T web server test
my $cfgdir = "n2t";		# this is an N2T web server test

my $webclient = 'wget';
my $which = `which $webclient`;
#$which =~ /wget/ or plan skip_all =>
#	"why: web client \"$webclient\" not found";
# XXX use exit 1 to get build to fail properly instead of silently
$which =~ /wget/ or
	say("\n  ERROR: bailing out -- no web client $webclient found\n"),
	exit 1;


# xxx how many of these things returned by prep_server do we actually need?
my ($msg, $src_top, $webcl,
		$srvport, $srvbase_u, $ssvport, $ssvbase_u,
	) = prep_server $cfgdir;
$msg and
	plan skip_all => $msg;

# XXX use exit 1 to get build to fail properly instead of silently
# XXX use exit 1 to get build to fail properly instead of silently
! $ENV{EGNAPA_TOP} and plan skip_all =>
	"why: no Apache server (via EGNAPA_TOP) detected";

plan 'no_plan';		# how we usually roll -- freedom to test whatever

SKIP: {

# Make sure server is stopped in case we failed to stop it last time.
# We don't bother checking the return as it would usually complain.

apachectl('graceful-stop');

# Note: $td and $td2 are barely used here.
# Instead we use non-temporary dirs $ntd and $ntd2.
# XXX change t/apachebase.t to use these type of dirs

my $buildout_root = $ENV{EGNAPA_BUILDOUT_ROOT};
my $binders_root = $ENV{EGNAPA_BINDERS_ROOT};
my $minters_root = $ENV{EGNAPA_MINTERS_ROOT};
my ($ntd, $ntd2) = ($binders_root, $minters_root);
my $pfxfile = "$buildout_root/prefixes.yaml";

! -f "$pfxfile" and
	print("\n     ERROR: bailing out -- no $pfxfile file!\n\n"),
	exit 1;

remake_td($td, $tdata);
remake_td($td2, $tdata);

$hgbase = "--home $buildout_root";	# and we know better in this case
my $tda = "--testdata $tdata";
$hgbase .= " $tda";
$ENV{EGG} = "$hgbase ";		# initialize basic --home and --tdata values

my ($x, $y);
$x = apachectl('start');
skip "failed to start apache ($x)"
	if $x;

# This section tests resolution and prefixes via egg --rrm, and therefore
# a bit more raw than via apache, which produces some other effects we
# right now only test with t/post_install_n2t.t.

# ZZZ problem here with binder creation
#
$x = `$cmd --verbose -d $td/dummy --user n2t mkbinder`;
like $x, qr/opening binder.*dummy/,
	'set up dummy binder that will keep --rrm mode happy';

# new resolver tester

$x = nresolve_stdin_hdr( "--home $buildout_root -d $td/dummy",

	'zzztestprefix:foo', '',	# test default with unspecifed proto
	  '302 http://id.example.org/foo',
	  'tester prefix redirects without protocol, defaulting to http', 
	'zzztestprefix:foo', '!!!pr=http!!!',	# ... now incoming with http
	  '302 http://id.example.org/foo',
	  'tester prefix redirects without protocol, passes http through', 
	'zzztestprefix:foo', '!!!pr=https!!!',	# ... now incoming with https
					# should work for ark, doi, hdl, purl
	  '302 https://id.example.org/foo',
	  'tester prefix redirects without protocol, passes https through', 
	'ark:/99998/pfx8bc3gh', '!!!pr=https!!!',	# blade substitution
							#  normally: "lc"
	  '302 https://id.example.org/bc3gh&null',
	  'tester shoulder redirects via blade, passes https through', 
	'ark:/99997/6andmore', '',	# minimal 1st-digit shoulder
					#  normally: "mc"
	  '302 http://id.example.org/nothing_to_subst',
	  'minimal first digit tester shoulder redirects via const target', 

	'ark:12148/btv1b8426258c', '',	# BnF, and no :/
	  '302 http://ark.bnf.fr/ark:/12148/btv1b8426258c',
	  'ark naan (BnF) prefix redirect, with only : instead of :/',
	'minid:b97957', '',		# minid to ark test
	  '302 http://n2t.net/ark:/57799/b97957',
	  'n2t.net/minid:... redir to n2t.net/ark:... (recursion exception)',

	#'ZZZEXIT', 			# XXXXXX premature exit

	'ark:/12148-foo.bar/zaf', '',	# NAAN with alt-host
	  '302 http://ark-foo.bar.bnf.fr/ark:/12148/zaf',
	  'ark naan (BnF) with alt host doing "prefix extension"',

	'pdb-dev:foo', '',		# Scheme with alt-host
	  '302 https://www-dev.rcsb.org/pdb/explore/explore.do?structureId=foo',
	  'scheme (pdb) with alt host doing "prefix extension"',

	'ark:/67531/metapth346793', '',	# UNT example from ARK docs
	  '302 http://digital.library.unt.edu/ark:/67531/metapth346793',
	  'ark naan (UNT) prefix redirect from ARK documentation',
	'ark:/99166/w6qz2nsx', '',	# SNAC (303)
	  '303 http://socialarchive.iath.virginia.edu/ark:/99166/w6qz2nsx',
	  'ark naan (SNAC) prefix redirect with 303 redirect',
	'ark:/76951/jhcs23vum3', '',	# SPMC, using n2t.net by agreement
	  'http://ark.spmcpapers.com/ark:/76951/jhcs23vum3',
	  'remotely managed ark naan (SPMC) prefix redirect via n2t',
	'urn:nbn:fi:tkk-004781', '',	# URN:NBN -> NBN:
	  'http://nbn-resolving.org/resolver?identifier=urn:nbn:fi:tkk-004781&verb=redirect',
	  'URN:NBN special case strips URN: to go to NBN',
	'rrid:AB_262044', '',		# service level agreement via DCIP
	  '302 https://scicrunch.org/resolver/RRID:AB_262044',
	  'rrid scheme prefix redirect', 
	'grid:grid.419696.5', '',	# grid verbose
	  '302 https://www.grid.ac/institutes/grid.419696.5',
	  'GRID scheme prefix redirect',
	'pubmed:16333295', '',		# legacy
	  '302 https://www.ncbi.nlm.nih.gov/pubmed/16333295',
	  'straight pubmed prefix redirect',
	'hubmed/pubmed:16333296', '',	# idot (identifiers.org) harmonization
	  '302 http://www.hubmed.org/display.cgi?uids=16333296',
	  'alternate provider hubmed/pubmed prefix redirect',
	'ncbi/pubmed:16333297', '',	# default provider made explicit
	  '302 https://www.ncbi.nlm.nih.gov/pubmed/16333297',
	  'explicit but primary ncbi/pubmed prefix redirect',
	'pmid:16333298', '',		# alias
	  '302 https://www.ncbi.nlm.nih.gov/pubmed/16333298',
	  'alias prefix (pmid) redirect',
	'ncbi/pmid:16333299', '',	# alias plus provider
	  '302 https://www.ncbi.nlm.nih.gov/pubmed/16333299',
	  'provider code with alias prefix (ncbi/pmid) redirect',
	'igsn:SSH000SUA', '',		# n2tadds
	  '302 http://hdl.handle.net/10273/SSH000SUA',
	  'igsn scheme redirect',
	'purl:dc/terms/creator', '',	# n2tadds
	  '302 http://purl.org/dc/terms/creator',
	  'purl scheme redirect',
	'hdl:4263537/4000', '',		# n2tadds
	  '302 http://hdl.handle.net/4263537/4000',
	  'hdl scheme redirect',
	'handle:4263537/4001', '',	# n2tadds
	  '302 http://hdl.handle.net/4263537/4001',
	  'handle alias (for hdl) scheme redirect',
	'polydoms:NP_009056', '',	# commonspfx
	  '302 http://polydoms.cchmc.org/polydoms/GD?DISP_OPTION=[?NonSynonymous/Synonymous]&field1=NP_009056',
	  'polydoms scheme (commonspfx) redirect',

	'inchi=1S/C2H6O/c1-2-3/h3H,2H2,1H3', '',	# quietly supported
	  '302 http://webbook.nist.gov/cgi/cbook.cgi?1S/C2H6O/c1-2-3/h3H,2H2,1H3',
	  'inchi scheme redirect, with = instead of : (inchi=)',

	'mgi:2442293', '',		# biorxiv article
	  '302 http://www.informatics.jax.org/accession/MGI:2442293',
	  'biorxiv article scheme redirect -- mgi',
	'epmc/pubmed:16333290', '',	# biorxiv article
	  '302 http://europepmc.org/abstract/MED/16333290',
	  'biorxiv article scheme redirect -- epmc/pubmed',
	'amigo/go:0006916', '',		# biorxiv article
	  '302 http://amigo.geneontology.org/amigo/term/GO:0006916',
	  'biorxiv article scheme redirect -- amigo/go',
	'rcsb/pdb:2gc5', '',		# biorxiv article
	  '302 https://www.rcsb.org/pdb/explore/explore.do?structureId=2gc5',
	  'biorxiv article scheme redirect -- rcsb/pdb',

	'flybase:FBgn0011293', '',	# biorxiv article
	  '302 http://flybase.org/reports/FBgn0011293.html',
	  'biorxiv article scheme redirect -- flybase',
	'taxon:9606', '',		# biorxiv article
	  '302 https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=9606',
	  'biorxiv article scheme redirect -- taxon',

	'go:0006915', '',		# biorxiv article
	  '302 http://amigo.geneontology.org/amigo/term/GO:0006915',
	  'biorxiv article scheme redirect -- go',

	'ec:1.1.1.1', '',		# biorxiv article
	  '302 https://www.ebi.ac.uk/intenz/query?cmd=SearchEC&ec=1.1.1.1',

	  'biorxiv article scheme redirect -- ec',
	'ec-code:1.1.1.2', '',		# biorxiv article
	  '302 https://www.ebi.ac.uk/intenz/query?cmd=SearchEC&ec=1.1.1.2',

	  'biorxiv article scheme redirect -- ec-code',
	'pdb:2gc4', '',			# biorxiv article
	  '302 https://www.rcsb.org/pdb/explore/explore.do?structureId=2gc4',
	  'biorxiv article scheme redirect -- pdb',

	'kegg:hsa00190', '',		# biorxiv article
	  '302 http://www.kegg.jp/entry/hsa00190',
	  'biorxiv article scheme redirect -- kegg',
	'ncbigene:100010', '',		# biorxiv article
	  '302 https://www.ncbi.nlm.nih.gov/gene/100010',
	  'biorxiv article scheme redirect -- ncbigene',
	'uniprot:P62158', '',		# biorxiv article
	  '302 https://purl.uniprot.org/uniprot/P62158',
	  'biorxiv article scheme redirect -- uniprot',
	'chebi:36927', '',		# biorxiv article
	 
	  '302 https://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI:36927',
	  'biorxiv article scheme redirect -- chebi:',
	'pmc:PMC3084216', '',		# biorxiv article
	  '302 http://europepmc.org/articles/PMC3084216',
	  'biorxiv article scheme redirect -- pmc',

	'geo:GDS1234', '',		# biorxiv article
	  '302 https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GDS1234',
	  'biorxiv article scheme redirect -- geo',
	'ena:BN000065', '',		# biorxiv article
	  '302 http://www.ebi.ac.uk/ena/data/view/BN000065',
	  'biorxiv article scheme redirect -- ena',
	'ena.embl:BN000066', '',	# biorxiv article
	  '302 https://www.ncbi.nlm.nih.gov/nuccore/BN000066',
	  'biorxiv article scheme redirect -- ena.embl',
	'rfc:2413', '',			# RFC number
	  '302 https://tools.ietf.org/rfc/rfc2413',
	  'IETF RFC number -- rfc',
	'repec:pdi221', '',		# RePEc id
	  '302 http://econpapers.repec.org/pdi221',
	  'Research Papers in Economics -- RePEc',
	'urn:lsid:ipni.org:names:77145066-1:1.4', '',	# URN-ish LSID
	  '302 http://www.lsid.info/urn:ipni.org:names:77145066-1:1.4',
	  'URN-ish Life Sciences Identifier -- lsid',
	'url:www.w3c.org', '',		# URL
	  '302 http://www.w3c.org',
	  'Uniform Resource Locator -- url',
	'e/naan_request', '',		# path-like request lookup
	  '302 https://goo.gl/forms/',
	  'pre-binder-lookup redirect for externally hosted content',
	'e/arks_eoi', '',		# path-like request lookup
	  '302 https://bit.ly/',
	  'pre-binder-lookup redirect for ARKs in the Open EOI form',
);

#say "xxx x=$x";
#$x = apachectl('graceful-stop'); #	and say "$x";
#say "######### temporary testing stop #########"; exit;

# as a batch, test some prefixes important to n2t
#$x = resolve_stdin_hdr( "--pfxfile $buildout_root/prefixes.yaml",
# $x = resolve_stdin_hdr( "--home $buildout_root -d $td/dummy",
# 
# 	'zzztestprefix:foo', '',	# test default with unspecifed proto
# 	'zzztestprefix:foo', '!!!pr=http!!!',	# ... now incoming with http
# 	'zzztestprefix:foo', '!!!pr=https!!!',	# ... now incoming with https
# 					# should work for ark, doi, hdl, purl
# 	'ark:/99998/pfx8bc3gh', '!!!pr=https!!!',	# blade substitution
# 			#  normally: "lc"
# 	'ark:/99997/6andmore', '',	# minimal 1st-digit shoulder
# 			#  normally: "mc"
# 
# 
# 	'ark:12148/btv1b8426258c', '',	# BnF, and no :/
# 	'minid:b97957', '',		# minid to ark test
# 	'ark:/67531/metapth346793', '',	# UNT example from ARK docs
# 	'ark:/99166/w6qz2nsx', '',	# SNAC (303)
# 	'ark:/76951/jhcs23vum3', '',	# SPMC, using n2t.net by agreement
# 	'urn:nbn:fi:tkk-004781', '',	# URN:NBN -> NBN:
# 	'rrid:AB_262044', '',		# service level agreement via DCIP
# 	'grid:grid.419696.5', '',	# grid verbose
# 	'pubmed:16333295', '',		# legacy
# 	'hubmed/pubmed:16333296', '',	# idot (identifiers.org) harmonization
# 	'ncbi/pubmed:16333297', '',	# default provider made explicit
# 	'pmid:16333298', '',		# alias
# 	'ncbi/pmid:16333299', '',	# alias plus provider
# 	'igsn:SSH000SUA', '',		# n2tadds
# 	'purl:dc/terms/creator', '',	# n2tadds
# 	'hdl:4263537/4000', '',		# n2tadds
# 	'handle:4263537/4001', '',	# n2tadds
# 	'polydoms:NP_009056', '',	# commonspfx
# 	'inchi=1S/C2H6O/c1-2-3/h3H,2H2,1H3', '',	# quietly supported
# 
# 	'mgd:2442292', '',		# biorxiv article
# 	'mgi:2442293', '',		# biorxiv article
# 	'epmc/pubmed:16333290', '',	# biorxiv article
# 	'amigo/go:0006916', '',		# biorxiv article
# 	'rcsb/pdb:2gc5', '',		# biorxiv article
# 	'flybase:FBgn0011293', '',	# biorxiv article
# 	'taxon:9606', '',		# biorxiv article
# 
# 	'go:0006915', '',		# biorxiv article
# 	'ec:1.1.1.1', '',		# biorxiv article
# 	'ec-code:1.1.1.2', '',		# biorxiv article
# 	'pdb:2gc4', '',			# biorxiv article
# 	'kegg:hsa00190', '',		# biorxiv article
# 	'ncbigene:100010', '',		# biorxiv article
# 
# 	'uniprot:P62158', '',		# biorxiv article
# 	'chebi:36927', '',		# biorxiv article
# 	'pmc:PMC3084216', '',		# biorxiv article
# 	'geo:GDS1234', '',		# biorxiv article
# 	'ena:BN000065', '',		# biorxiv article
# 	'ena.embl:BN000066', '',	# biorxiv article
# 	'rfc:2413', '',			# RFC number
# 	'repec:pdi221', '',		# RePEc id
# 	'urn:lsid:ipni.org:names:77145066-1:1.4', '',	# URN-ish LSID
# 	'url:www.w3c.org', '',		# URL
# 	'e/naan_request', '',		# path-like request lookup
# 	'e/arks_eoi', '',		# path-like request lookup
# 
# );
# #is index($x, 'emsg='), -1,
# #	'no errors or warnings on prefix file load';
# 
# 
# # # does the head (line 1) of $block match $pattern?
# # # modifies first arg ($block) by consuming first line
# # sub hdlike { my( $block, $substring, $msg )=@_;
# # 	$_[0] =~ s/^.*\n?// or			# modifies first arg
# # 		print "no lines left to consume\n";
# # 	like $&, qr/\Q$substring/, $msg);
# # }
# 
# isnt index($x, '302 http://id.example.org/foo'), -1,
# 	'tester prefix redirects without protocol, defaulting to http'; 
# 
# #say "xxx x=$x";
# #$x = apachectl('graceful-stop'); #	and say "$x";
# #say "######### temporary testing stop #########"; exit;
# 
# isnt index($x, '302 http://id.example.org/foo'), -1,
# 	'tester prefix redirects without protocol, passes http through'; 
# isnt index($x, '302 https://id.example.org/foo'), -1,
# 	'tester prefix redirects without protocol, passes https through'; 
# isnt index($x, '302 https://id.example.org/bc3gh&null'), -1,
# 	'tester shoulder redirects via blade, passes https through'; 
# isnt index($x, '302 http://id.example.org/nothing_to_subst'), -1,
# 	'minimal first digit tester shoulder redirects via const target'; 
# 
# isnt index($x, '302 http://ark.bnf.fr/ark:/12148/btv1b8426258c'), -1,
# 	'ark naan (BnF) prefix redirect, with only : instead of :/'; 
# isnt index($x, '302 http://n2t.net/ark:/57799/b97957'), -1,
# 	'n2t.net/minid:... redirects to n2t.net/ark:... (recursion exception)'; 
# #===========
# isnt index($x, '302 http://digital.library.unt.edu/ark:/67531/metapth346793'),
# 	-1, 'ark naan (UNT) prefix redirect from ARK documentation'; 
# isnt index($x, '303 http://socialarchive.iath.virginia.edu/ark:/99166/w6qz2nsx'), -1,
# 	'ark naan (SNAC) prefix redirect with 303 redirect'; 
# isnt index($x, 'http://ark.spmcpapers.com/ark:/76951/jhcs23vum3'), -1,
# 	'remotely managed ark naan (SPMC) prefix redirect via n2t'; 
# isnt index($x, 'http://nbn-resolving.org/resolver?identifier=urn:nbn:fi:tkk-004781&verb=redirect'), -1,
# 	'URN:NBN special case strips URN: to go to NBN'; 
# isnt index($x, '302 https://scicrunch.org/resolver/RRID:AB_262044'), -1,
# 	'rrid scheme prefix redirect'; 
# isnt index($x, '302 https://www.grid.ac/institutes/grid.419696.5'), -1,
# 	'GRID scheme prefix redirect'; 
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/pubmed/16333295'), -1,
# 	'straight pubmed prefix redirect'; 
# isnt index($x, '302 http://www.hubmed.org/display.cgi?uids=16333296'), -1,
# 	'alternate provider hubmed/pubmed prefix redirect'; 
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/pubmed/16333297'), -1,
# 	'explicit but primary ncbi/pubmed prefix redirect'; 
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/pubmed/16333298'), -1,
# 	'alias prefix (pmid) redirect'; 
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/pubmed/16333299'), -1,
# 	'provider code with alias prefix (ncbi/pmid) redirect'; 
# isnt index($x, '302 http://hdl.handle.net/10273/SSH000SUA'), -1,
# 	'igsn scheme redirect'; 
# isnt index($x, '302 http://purl.org/dc/terms/creator'), -1,
# 	'purl scheme redirect'; 
# isnt index($x, '302 http://hdl.handle.net/4263537/4000'), -1,
# 	'hdl scheme redirect'; 
# isnt index($x, '302 http://hdl.handle.net/4263537/4001'), -1,
# 	'handle alias (for hdl) scheme redirect'; 
# isnt index($x, '302 http://polydoms.cchmc.org/polydoms/GD?DISP_OPTION=[?NonSynonymous/Synonymous]&field1=NP_009056'), -1,
# 	'polydoms scheme (commonspfx) redirect';
# 
# isnt index($x, '302 http://webbook.nist.gov/cgi/cbook.cgi?1S/C2H6O/c1-2-3/h3H,2H2,1H3'),
# 	-1, 'inchi scheme redirect, with = instead of : (inchi=)';
# 
# isnt index($x, '302 http://www.informatics.jax.org/accession/MGI:2442293'), -1,
# 	'biorxiv article scheme redirect -- mgi'; 
# isnt index($x, '302 http://europepmc.org/abstract/MED/16333290'), -1,
# 	'biorxiv article scheme redirect -- epmc/pubmed'; 
# isnt index($x, '302 http://amigo.geneontology.org/amigo/term/GO:0006916'), -1,
# 	'biorxiv article scheme redirect -- amigo/go'; 
# isnt index($x, '302 https://www.rcsb.org/pdb/explore/explore.do?structureId=2gc5'),
# 	-1, 'biorxiv article scheme redirect -- rcsb/pdb'; 
# 
# isnt index($x, '302 http://flybase.org/reports/FBgn0011293.html'), -1,
# 	'biorxiv article scheme redirect -- flybase'; 
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=9606'), -1,
# 	'biorxiv article scheme redirect -- taxon'; 
# 
# isnt index($x, '302 http://amigo.geneontology.org/amigo/term/GO:0006915'), -1,
# 	'biorxiv article scheme redirect -- go'; 
# 
# isnt index($x, '302 https://www.ebi.ac.uk/intenz/query?cmd=SearchEC&ec=1.1.1.1'),
# 	-1, 'biorxiv article scheme redirect -- ec'; 
# isnt index($x, '302 https://www.ebi.ac.uk/intenz/query?cmd=SearchEC&ec=1.1.1.2'),
# 	-1, 'biorxiv article scheme redirect -- ec-code'; 
# isnt index($x, '302 https://www.rcsb.org/pdb/explore/explore.do?structureId=2gc4'),
# 	-1, 'biorxiv article scheme redirect -- pdb'; 
# isnt index($x, '302 http://www.kegg.jp/entry/hsa00190'), -1,
# 	'biorxiv article scheme redirect -- kegg'; 
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/gene/100010'), -1,
# 	'biorxiv article scheme redirect -- ncbigene'; 
# isnt index($x, '302 https://purl.uniprot.org/uniprot/P62158'), -1,
# 	'biorxiv article scheme redirect -- uniprot'; 
# isnt index($x,
# 	'302 https://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI:36927'), -1,
# 	'biorxiv article scheme redirect -- chebi:'; 
# isnt index($x, '302 http://europepmc.org/articles/PMC3084216'), -1,
# 	'biorxiv article scheme redirect -- pmc'; 
# 
# #isnt index($x, '302 http://www.ncbi.nlm.nih.gov/sites/GDSbrowser?acc=GDS1234'), -1,
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GDS1234'), -1,
# 	'biorxiv article scheme redirect -- geo'; 
# isnt index($x, '302 http://www.ebi.ac.uk/ena/data/view/BN000065'), -1,
# 	'biorxiv article scheme redirect -- ena'; 
# isnt index($x, '302 https://www.ncbi.nlm.nih.gov/nuccore/BN000066'), -1,
# 	'biorxiv article scheme redirect -- ena.embl';
# isnt index($x, '302 https://tools.ietf.org/rfc/rfc2413'), -1,
# 	'IETF RFC number -- rfc';
# isnt index($x, '302 http://econpapers.repec.org/pdi221'), -1,
# 	'Research Papers in Economics -- RePEc';
# #isnt index($x, '302 http://repec.org/pdi221'), -1,
# #	'Research Papers in Economics -- RePEc';
# isnt index($x, '302 http://www.lsid.info/urn:ipni.org:names:77145066-1:1.4'), -1,
# 	'URN-ish Life Sciences Identifier -- lsid';
# isnt index($x, '302 http://www.w3c.org'), -1,
# 	'Uniform Resource Locator -- url';
# isnt index($x, '302 https://goo.gl/forms/'), -1,
# 	'pre-binder-lookup redirect for externally hosted content';
# isnt index($x, '302 https://bit.ly/'), -1,
# 	'pre-binder-lookup redirect for ARKs in the Open EOI form';

#say "xxx x=$x";
#$x = apachectl('graceful-stop'); #	and say "$x";
#say "######### temporary testing stop #########"; exit;

$x = apachectl('graceful-stop')	and print("$x\n");

if (Test::More->builder->is_passing) {	# NB: this step is very important as
	system 'pfx tested_ok';		# it sets a flag permitting n2t rollout
}
else {
	diag 'at least one prefix test failed';	# from Test::More
}

remove_td($td, $tdata);
remove_td($td2, $tdata);
}
