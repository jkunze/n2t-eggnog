use 5.010;
use Test::More;

plan 'no_plan';		# how we usually roll -- freedom to test whatever

use strict;
use warnings;

use File::ValueTester ':all';
use File::Value ':all';

my ($td, $cmd, $homedir, $bgroup, $hgbase, $indb, $exdb) = script_tester "egg";
$ENV{EGG} = $hgbase;		# initialize basic --home and --bgroup values

{		# some simple ? and ?? tests
remake_td($td);

use File::Resolver ':all';
my $pfx = {};
my $x;

#$x = id_normalize($pfx, "  ark:12345/crowd-\n\t sourced ");
#like $x, qr|^ark:/12345/crowdsourced$|,

$x = id_decompose($pfx, "  ark:12345/crowd-\n\t sourced ");
like $x->{full_id}, qr|^ark:/12345/crowdsourced$|,
	'ark: space-and-newline trimmed, hyphen removed, slash added';

#my ($full_id, $scheme, $naan, $shoulder, $id, $query, $slid, $pinfo);
#($full_id, $scheme, $naan, $shoulder, $id, $query) =

$x = id_decompose($pfx, " ark://b2345/s3cr--owd-\n xyz?-z-?");
like $x->{full_id}, qr|^ark:/b2345/s3crowdxyz\?-z-\?$|,
	'ark: trimmed, hyphens removed in list context';

#print "xxx premature end\n";
#exit; ###############

like $x->{scheme}, qr|^ark$|, 'ark scheme returned';

like $x->{naan}, qr|^b2345$|, 'ark naan returned';

# NB: an ark shoulder technically begins just after the ':', ie, with '/'
like $x->{shoulder}, qr|^/b2345/s3$|, 'ark shoulder returned';

like $x->{shoshoblade}, qr|^s3crowdxyz$|,
	'ark $id returned minus naan and query';

like $x->{query}, qr|^\?-z-\?$|, 'query returned with hyphen intact';

# xxx document "base identifier", not quite defined yet in
#    http://ezid.cdlib.org/learn/id_concepts 
$x = id_decompose($pfx, "ark:b2345/3bladepart.foo/afterbasepart?qpart");
like $x->{blade}, qr|^bladepart.foo/afterbasepart$|,
	'ark with minimal first-digit shoulder';

like $x->{base_id}, qr|^ark:/b2345/3bladepart$|,
	'base_id identifier';

like $x->{checkstring}, qr|^b2345/3bladepart$|,
	'checkstring to be used for potential checkdigit calculation';

#print "xxx premature end\n";
#exit; ###############

=for later?

# see Resolver.pm for these, ($scheme_test, $scheme_target), something like
#      'xyzzytestertesty' => 'http://example.org/foo?gene=$id.zaf'
#
my ($i, $q) = ('987AbCd654', '-z-?');
($full_id, $scheme, $naan, $shoulder, $id, $query, $slid, $pinfo) =
$x = id_normalize($pfx, " $File::Resolver::scheme_test:$i?$q ");

# PFX_TABLE PFX_RRULE PFX_XFORM PFX_LOOK PFX_REDIR PFX_REDIRNOQ

# xxx replace this test
#is $pinfo->{PFX_LOOK}, 0,
#	"don't lookup in binder before redirect via rule";

my ($targetquery);
my ($target, $xform) = ($pinfo->{PFX_REDIR}, $pinfo->{PFX_XFORM});

$target = $File::Resolver::scheme_target;
$xform =~ /2U/ and
	$i = uc $i;
$xform =~ /2L/ and
	$i = lc $i;
$xform =~ /NH/ and
	$i =~ s/-//g;
$target =~ s/\$id\b/$i/g;

is $pinfo->{PFX_REDIR}, "$target?$q",	# full id plus query
	'rule-based mapping returns rule with case-corrected id';

is $pinfo->{PFX_REDIRNOQ}, "$target",
	'rule-based redirect triggered, target_noquery set';

=cut

my ($i, $q) = ('ab_262044', '-z-?');
$x = id_decompose($pfx, "RRiD: $i?$q ");

is $x->{slid}, "$i",
    "RRID 'SLID' returned, space after ':' removed";

#$x = id_normalize($pfx, "  DOI:10.12345/croWD-\n\t sOUrced?lower");
$x = id_decompose($pfx, "  DOI:10.12345/croWD-\n\t sOUrced?lower");
like $x->{full_id}, qr|^doi:10\.12345/CROWD-SOURCED\?lower$|,
	'doi: trimmed, hyphen preserved, uppercased except for query';

$x = id_decompose($pfx, " b2345/foo ");
like $x->{full_id}, qr|^ark:/b2345/foo$|,
	'ark inferred from extended digits';

$x = id_decompose($pfx, " 10.12345/foo ");
like $x->{full_id}, qr|^doi:10\.12345/FOO$|, 'doi inferred from 10....';

$x = id_decompose($pfx, " a.com/bar ");
like $x->{full_id}, qr|^http://a\.com/bar$|,
	'http url inferred from hostname';

$x = id_decompose($pfx, " https://a.com/bar? ");
like $x->{full_id}, qr|^https://a\.com/bar\?$|,
	'https url preserved with inflection';

$x = id2shadow("doi:10.123/THIS-THat?NO-W");
like $x, qr|ark:/b0123/thisthat\?NO-W|,
  'shadow doi: drops hyphens except in query and preserves query case';

my $uu = 'F81d4fae-7dec-11d0-a765-00a0c91e6bf6';
$x = id2shadow("urn:uuid:$uu/FoO?NO-W");
like $x, qr|ark:/97720/f81d4fae7dec11d0a76500a0c91e6bf6/FoO\?NO-W|,
  'shadow urn:uuid drops - except in query, keeps extension case';

my $pl = "dcterms/Crea-tor";
$x = id2shadow("purl:$pl.FOo?NO-W");
like $x, qr|ark:/97722/$pl\.FOo\?NO-W|,
  'shadow purl keeps - and case, everywhere';

#$x = id_decompose($pfx, "purl:$pl");
#like $x->{full_id}, qr|ark:/97722/$pl\.FOo\?NO-W|,
#  'shadow purl keeps - and case, everywhere';

#$x = id_normalize($pfx, "urn:uuid:430c5f08-017e-11e1-858f-0025bce7cc84/bar?NO-W");
$x = id2shadow("uuid:$uu.FOo?NO-W");
like $x, qr|ark:/97721/f81d4fae7dec11d0a76500a0c91e6bf6\.FOo\?NO-W|,
  'shadow uuid drops - except in query, keeps extension case';

#$x = id_normalize($pfx, "urn:uuid:430c5f08-017e-11e1-858f-0025bce7cc84/bar?NO-W");
#like $x, qr|^https://a\.com/bar\?$|,
#	'urn:uuid normalize preserved with inflection';
#
#$uu = '430c5f08-017e-11e1-858f-0025bce7cc84';
#$x = id2shadow("urn:uuid:$uu/bar?NO-W");
#like $x, qr|ark:/97720/f81d4fae7dec11d0a76500a0c91e6bf6/bar\?NO-W|,
#  '2shadow urn:uuid drops - except in query, keeps extension case';

use File::Resolver 'uuid_normalize';
use MIME::Base64 ();
# take uuidgen hex output: $hexstring
my $hexstring = lc '509F11E1597442E692F1684AA7846877';
# convert to binary and then to base64
$x = MIME::Base64::encode( pack( 'H*', $hexstring ) );
is uuid_normalize($x), $hexstring,
	'roundtrip verify hex decode -> b64 encode -> uuid_normalize';

# xxx maybe c64 is how uuid should be stored
my $c64string = 'iHEG_S5G5RGiZ3~rzJcoFg';
my $b64string = $c64string;
$b64string =~ tr|_~|+/|;	# map _ and ~ to + and / to create base64
$hexstring = unpack( 'H*', MIME::Base64::decode $b64string );
$x = id2shadow("uuid:$c64string?NO-W");
like $x, qr|ark:/97721/$hexstring\?NO-W|,
  'shadow uuid that is c64 encoded';

#exit; ###############
#my ($full_id, $scheme, $naan, $shoulder, $id, $query, $slid, $pinfo);
#
#($full_id, $scheme, $naan, $shoulder, $id, $query, $slid, $pinfo) =
$x = id_decompose($pfx, " uuid:$c64string?-z-?");
is $x->{scheme}, 'uuid', 'uuid scheme returned';
is $x->{naan}, '', 'uuid naan empty';

# xxx must humor need to have a minder
$x = `$cmd -p $td mkbinder foo`;
$x = `$cmd -d $td/foo ark:12345/e-f?g-h.norm`;
like $x, qr|ark:/12345/ef\?g-h|, 'command line norm';

$x = `$cmd -d $td/foo urn:uuid:$uu.shadow`;
my $y = lc $uu;
$y =~ s/-//g;
like $x, qr|ark:/97720/$y|, 'command line shadow';

remove_td($td);
}
