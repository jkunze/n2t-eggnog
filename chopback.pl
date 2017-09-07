# xxx combine $noid as object pointer with $opts

use warnings ;
use strict ;
use DB_File ;

my ($filename, $x, %h) ;
$filename = "tree" ;
-e $filename and unlink $filename || die "Cannot unlink $filename: $!\n";

# Enable duplicate records
$DB_BTREE->{'flags'} = R_DUP ;
$x = tie %h, "DB_File", $filename, O_RDWR|O_CREAT, 0666, $DB_BTREE
    or die "Cannot open $filename: $!\n";
my $noid = \%h;
my $nospt = "_nospt";		# xxx Greg tells me what this is called
my $verbose = 1;

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
#   http://n2t.net/ark:/12345
#   http://n2t.net/ark
#   http://n2t.net
#   http://n2t
#   http
#
# Loop logic
#
# The main loop is a classic Perl complex Boolean test (for speed) against
# an id that keeps getting its tail chopped off.  The loop's premise,
#   "Keep going until either the key is found OR we ran out of id"
# can be expressed as
#   "Keep going until either
#      (the key exists && we're not value-checking ||
#        the key exists && the key's lookup value eq $value)
#    OR we ran out of id"
# which is the same as
#   "Keep going until either
#      (the key exists && (we're not value-checking ||
#        the key's lookup value eq $value))
#    OR we ran out of id"
#
# What's encoded below is the result of turning the "until" into a
# "while" by negating the test to get:
#   "Keep going _while_ either
#      (the key doesn't exist || (we are value-checking &&
#        the key's lookup value ne $value))
#    AND we haven't run out of id"
#
sub chopback { my( $noid, $verbose, $id, $stopchop, $element, $value )=@_;

	$id ||= "";
	$stopchop ||= 0;
	my $tail = "";
	defined($element) and
		$tail .= "\t$element";
	my $key = $id . $tail;
	my $valcheck = defined($value);
	# yyy what if $value defined but $element undefined?
	#$element ||= "";		# yyy edge case avoiding undef error

# xxx allow noid_opt to define its own chopback algorithm,
# xxx allow noid_opt to carry verbose and debug flags

	# Note that qr/\w_~/ matches c64 identifiers
	$id =~ s/[^\w_~]*$//;		# trim any terminal non-word chars
	# See loop logic comments above.
	1 while (					# continue while
		! exists($$noid{$key}) ||		# key doesn't exist or
			($valcheck 			# we're checking values
				&&			# and
			$$noid{$key} ne $value)		# it's the wrong value
		and					# and if,
		($verbose and print("id=$id\n")),	# (optional chatter)
		($id =~ s/[^\w_~]*[\w_~]+$//),		# after we chop tail
		($key = $id . $tail),			# and update our key,
		length($id) > $stopchop			# something's left
	);
	# If we get here, we either ran out of $id or we found something.

	return length($id) > $stopchop ? $id : "";
}

# TBD: this would be a generalization of suffix_pass that returns
# metadata (where not prohibited) for a registered ancestor of an
# extended id that's not registered
sub meta_inherit { my( $noid, $verbose, $id, $element, $value )=@_;
}

sub suffix_pass { my( $noid, $verbose, $id, $element, $value )=@_;

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

# xxx nix the $element and $value args
# xxx dups!
# xxx stop chopping at after a certain point, eg, after base object
#     name reached and before backing into NAAN, "ark:/"
#     (means manually asking for something like n2t.net/ark:/13030? )

# xxx don't call this routine except for ARKs (initially, to illustrate)
#     maybe call it for other schemes

	my $origid = $id;
	my $origlen = length($origid);
	$verbose and print "chopping $id\n";
	#my $element = "_target";
	$element = "_target";

	# Don't chopback beyond object identifier into scheme, host, etc.
	#
	my $stop = $origid;		# figure out what we'll ignore
	$stop =~ s,^\w+://[^/]*/*,,;		# urls: http, ftp, then
	$stop =~ s,^urn:[^:]+:+,,	or		# urn or
		$stop =~ s,^\w+:/*[\d.]+/+,,;		# ark, doi, hdl
	my $stopchop = $origlen - length($stop);
	$verbose and
		print "aim to stop before $stopchop chars (before $stop)\n";

	$id = chopback($noid, $verbose, $id, $stopchop, $element, $value);
	#length($id) <= $stopchop or
	$id or
		($verbose and print "chopback found nothing\n"),
		return "";

	# Found something.  Extract suffix by presenting the original
	# id and a negative offset to substr().
	#
	# xxx this $verbose is more like $debug
	$verbose and print "chopped back to $id\n";
	my $suffix = substr $origid, length($id) - $origlen;

	my $target = $$noid{"$id\t$element"};
	$verbose and print "target=$target, suffix=$suffix\n";

	# yyy if we had a "no passthru" flag check, it would go here.
	#exists($$noid{"$id\t$nospt"}) and
	#	($verbose and print "passthru prevented by $nospt flag\n"),
	#	return "";

	return $target . $suffix;
}

# Add some key/value pairs to the file
#
my $base = "http://foo.example.com/ark:/12345/xt2rv8b";
my $extension = "/chap3/sect5//para4.txt?a=b&c=d/";
my $elem = "_target";
# xxx must pay attention to delimiters recorded for orig id and target URLs
$$noid{"$base\t$elem"} = "http://bar.example.com";
$$noid{"$base\t_nospt"} = "";		# no suffix passthru
$$noid{"$base/chap3\t$elem"} = "a3zaf";
$$noid{"$base/chap3/sect5\t$elem"} = "35zaff";
$$noid{"$base/chap3/sect5//para4\t$elem"} = undef;

suffix_pass($noid, $verbose, "$base$extension", $elem);
	print "  should have found undefined target\n";
suffix_pass($noid, $verbose, "$base$extension", $elem, "a3zaf");
	print "  should have found target 3zaf after chap3\n";
#suffix_pass($noid, $verbose, "$base$extension", $elem);
#	print "  should have found target, but nospt flag prevents passthru\n";

# xxx Consider what if target id is
#   a/b?c=d
# user submits e/f?g=h and we have registered
#   e -> a/b?c=d/f?g=h  ?  or a/b/f?c=dg=h  (not so good as if user said &g=h)
#  (1st isn't so bad, as receiver can parse 2nd ? as &)
#   e/f -> a/b?c=d?g=h  ?
#   e/f?g -> a/b?c=d=h  ?
#   e/f?g=h -> a/b?c=d
# and if user submits e/f#foo
#   e -> a/b?c=d/f#foo  ?  or a/b/f?c=d#foo  ?
# what are precedence rules around # and ? 

# consider if target id is
#   i/j#k
# user submits l/m#o and registered are
#   l -> i/j#k/m#o  ? i/j/m#k#o
#   l/m#o -> i/j#k

# OTOH, maybe being heuristically smart (chancy anyway) is not a good idea...
# xxx What about supporting vocabulary lookup? eg, pretty URL redirecting
#     to fragment, such as,
# dk/who -> dkdoc?term=/who by registering dk with target dkdoc?term=
# (better than #who, which returns everything after who as well)

