# xxx for Namaste, use \Q$dtname\E to disable .dir_ matching xdir_

package EggNog::Help;

use 5.10.1;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw(
	help
);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

# Author:  John A. Kunze, jak@ucop.edu, California Digital Library
# 
# Copyright 2011-2012 UC Regents.  Open source BSD license.

use Pod::Usage;

sub help { my( $fh, $topic )=@_;

# xxx use $om->elem?

	$fh ||= *main::DATA;	# default is to use POD from calling script
	$topic ||= "";

	my @topics;		# array constructed by reading embedded POD
	my $t = undef;		# topic possibly returned by lookup
	my $indent = '    ';

	if (ref($fh) eq "HASH") {	# don't use POD, use hash approach
		my $href = $fh;		# keys are topic names, values content
		@topics = sort keys %$href;

		$topic and	# take first match, including partial match
			$t = (grep(/^$topic/i, @topics))[0];

		defined($t) or		# nothing found or nothing asked for
			print("$indent", join($indent, @topics), "\n"),
			return 1;

		# If we get here, we found a topic, so print it's the doc
		# as the value stored under the topic key ($t) and return.
		#
		print "$href->{$t}";
		return 1;
	}

	my $section_level = 0;	# running =headN nesting level (N=1, 2, ...)
	my %groups;		# sort_groups seen

	# Read special "=for help" pod directives from script itself.
	#
	for (<$fh>) {		# build array of help topics
		/^=head(\d+)/ and
			$section_level = $1,	# update =headN level
			next;
		s/^=for help\s+(\w+)\s+/$section_level $1 / and
			($groups{$1} = 1),
			push @topics, $_;
	}
	#
	# When we get here, each element of @topics should have the form
	#   $section_level $sort_group $topic_word $topic_title
	# The loop above added the first two tokens.

	my $n;			# section_level returned by lookup
	# yyy grep first for ^$t and then for .$t
	# xxx help mint gets mint and peppermint

	$topic and
		defined($t = (grep(/^\d+\s+\w+\s+$topic/i, @topics))[0]) and
		# take first match, if any, including partial match
		# take first word & num
			($n, $t) = $t =~ m/^(\d+)\s+\w+\s+(\S+)/;

	if (! defined $t) {	# if no topic supplied or no match found
		$topic and			# if a topic was supplied
			print "unknown topic: $topic\n";
		## Print minimal usage info followed by topic list.
		#pod2usage(-exitval => 'NOEXIT', -verbose => 0);

		my @sort_groups = sort keys %groups;
		foreach my $g (@sort_groups) {

			print "$g:\n"	# show group name if more than 1 group
				if scalar(@sort_groups) > 1;

			print "$indent", join($indent,		# indent lines
				grep /./,	# omit lines not in this group
				sort map	# get info relevant to the user
					{/^\d+\s+$g\s+(.*\n)/ && $1} @topics),
				"\n";
		}
		return 1;
	}

	# Next pod2usage requires some mysterious arguments, among them a
	# set of =headN title-matching regexes separated by '/' chars.
	# There must be one ".*/" for each =headN level title below head1.
	#
	$t =  ".*/" x ($n - 1) . ".*(?i)$t.*";	# allow stuff around it

	return pod2usage(
		-exitval => 'NOEXIT',
		-verbose => 99,		# magic for section extraction
		-sections => $t,	# see perldoc Pod::Select
	);
}

1;

__END__

=head1 NAME

Help - command-line "help" access to POD sub-sections

=head1 SYNOPSIS

 use EggNog::Help;	    # import routines into a Perl script

 EggNog::Help::help($filehandle, $topic);

=head1 DESCRIPTION

This routine provides topic-related "help" information derived from POD
(Plain Old Documentation) markup.  Given a $topic argument, it calls
pod2usage() with some magic parameters that extract and display a specific
section that has been linked to $topic by a special "=for help" convention.

Any text under a =head1, =head2, etc. heading can be made extractable to
help() by appending a blank line and a line of the form

     =for help   Category   TopicWord   One-line_title_goes_here

This POD line acts as a smart comment that encodes the display category,
display word (used to retrieve that section), and display title.
For example,

    =head2 GRAMMAR Z<>-Z<> OVERVIEW
    
    =for help Other grammar - overview

TopicWord must match the first title word of the immediately surrounding
"=headN" section directive.  If you don't need distinguished categories,
just consistently use one category name (eg, "topic"), in that case no
category name will ever be displayed.  This routine will not process
inline POD markup on "=for help" lines.

With no $topic argument, help() displays all extractable topics
sorted by category.  Given one or more arguments, it performs a
case-insensitive lookup against the first topic word ("grammar" in the
above example).  Partial matches with initial substrings should work (eg,
"gram"), and the first match wins in the case of multiple matches.

Use the $filehandle argument to specify where the POD document will be
found that forms the basis for all "help" topic selection.  If
$filehandle is null, *main::DATA is assumed, which uses the POD embedded
at the end of the calling script.

=head1 LIMITATIONS

Reads <DATA> , which means POD must be at end of script.

Requested topic cannot contain '/'.

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2011-2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<perl(1)>

=head1 AUTHOR

John A. Kunze

=cut

# Print a blank (space) in front of every newline.
# First arg must be a filehandle.
#
sub bprint { my( $out, @args )=@_;
	map {s/\n/\n /g} @args;
	return print $out @args;
}

# xxx make work with $om
# Always returns 1 so it can be used in boolean blocks.
#
sub xusage { my( $in_error, $brief, $topic )=@_;

	$in_error ||= 1;		# default is to treat as error
	$in_error and
		$| = 1;			# flush any pending output
	my $out =			# where to send output
		($in_error ? *STDERR : *STDOUT);
	! defined($brief) and
		$brief = 1;		# default is to be brief
	$topic ||= "intro";
	$topic = lc($topic);

	return (bindusage($out, $in_error, $brief, $topic))
		if ($WeAreBinder);

	# Initialize info topics if need be.
	#
	! @valid_helptopics and
		init_help();
	my @blurbs = grep(/^$topic/, @valid_helptopics);
	if (scalar(@blurbs) != 1) {
		print $out (scalar(@blurbs) < 1
			? qq@Sorry: nothing under "$topic".\n@
			: "Help: Your request ($topic), matches more than one "
				. "topic:\n\t(" . join(", ", @blurbs) . ").\n"
			),
			" You might try one of these topics:";
		my @topics = @valid_helptopics;
		my $n = 0;
		my $topics_per_line = 8;
		while (1) {
			! @topics and
				print("\n "),
				last
			or
			$n++ % $topics_per_line == 0 and
				print("\n\t")
			or
				print(" ", shift(@topics))
			;
		}
		print "\n\n";
		return 1;
	}
	# If we get here, @blurbs names one story.
	my $blurb = shift @blurbs;

	# Big if-elsif clause to switch on requested topic.
	#
	# Note that we try to make the output conform to ANVL syntax;
	# in the case of help output, every line tries to be a continuation
	# line for the value of an element called "Usage".  To do this we
	# pass all output through a routine that just adds a space after
	# every newline.  The end of the output should end the ANVL record,
	# so we print "\n\n" at the end.
	#
	my ($t, $i);
	if ($blurb eq "intro") {
		bprint $out,
qq@Usage:
              noid [-f Dbdir] [-v] [-h] Command Arguments@, ($brief ? qq@
              noid -h             (for help with a Command summary).@
	: qq@

Dbdir defaults to "." if not found from -f or a NOG environment variable.
For more information try "perldoc noid" or "noid help Command".  Summary:
@);
		$brief and
			print("\n\n"),
			return(1);
		for $t (@$valid_commandsR) {
			$i = $info{"$t/brief"};
			! defined($i) || ! $i and
				next;
			bprint $out, $i;
		}
bprint $out, qq@
If invoked as "noidu...", output is formatted for a web client.  Give Command
as "-" to run a block of noid Commands read from stdin or from POST data.@;
		print "\n\n";
		return(1);
	}
	#elsif $blurb eq "dbcreate" and print $out $info{$blurb}
	#or
	#$blurb eq "bind" and print $out
	$brief and
		$blurb .= "/brief";
	$t = $info{$blurb};
	if (! defined($t) || ! $t) {
		print $out qq@Sorry: no information on "$blurb".\n\n@;
		return(1);
	}
	bprint $out, $t;
	print "\n";
	return(1);

# yyy fix these verbose messages

my $yyyy = qq@
Called as "noid", an id generator accompanies every COMMAND.  Called as
"noi", the id generator is supplied implicitly by looking first for a
NOG environment variable and, failing that, for a file calld ".noid" in
the current directory.  Examples show the explicit form.  To create a
generator, use

	noid ck8 dbcreate TPL SNAA

where you replace TPL with a template that defines the shape and number
of all identifiers to be minted by this generator.  You replace SNAA with
the name (eg, the initials) of the sub NAA (Name Assigning Authority) that
will be responsible for this generator; for example, if the Online Archive
of California is the sub-authority for a template, SNAA could be "oac".
This example of generator intialization,

	noid oac.noid dbcreate pd2.wwdwwdc oac

sets up the "oac.noid" identifier generator.  It can create "nice opaque
identifiers", such as "pd2pq5dk9z", suitable for use as persistent
identifiers should the supporting organization wish to provide such a
level of commitment.  This generator is also capable of holding a simple
sequential counter (starting with 1), which some callers may wish to use
as an internal number to keep track of minted external identifiers.
[ currently accessible only via the count() routine ]

In the example template, "pd2" is a constant prefix for an identifier
generator capable of producing 70,728,100 identifiers before it runs out.
A template has the form "prefix.mask", where 'prefix' is a literal string
prepended to each identifier and 'mask' specifies the form of the generated
identifier that will appear after the prefix (but with no '.' between).
Mask characters are 'd' (decimal digit), 'w' (limited alpha-numeric
digit), 'c' (a generated check character that may only appear in the
terminal position).

Alternatively, if the mask contains an 's' (and no other letters), dbcreate
initializes a generator of sequential numbers.  Instead of seemingly random
creates sequentially generated number.  Use '0s'
to indicate a constant width number padded on the left with zeroes.
@;
	return(1);
}

sub init_help {

	# For convenient maintenance, we store individual topics in separate
	# array elements.  So as not to slow down script start up, we don't
	# pre-load anything.  In this way only the requester of help info,
	# who does not need speed for this purpose, pays for it.
	#
	@valid_helptopics = qw(
		intro all templates
	);
	push(@valid_helptopics, @$valid_commandsR);
	%info = (
		'bind/brief' =>
q@
   noid bind How Id Element Value	# to bind an Id's Element, where
      How is set|add|insert|new|replace|mint|append|prepend|delete|purge.
      Use an Id of :idmap/Idpattern, Value=PerlReplacementPattern so that
      fetch returns variable values.  Use ":" as Element to read Elements
      and Values up to a blank line from stdin (up to EOF with ":-").
@,
		'bind' =>
q@@,
		'dbinfo/brief' =>
q@@,
		'dbinfo' =>
q@@,
		'dbcreate/brief' =>
q@
   noid dbcreate [ Template (long|-|short) [ NAAN NAA SubNAA ] ]
      where Template=prefix.Tmask, T=(r|s|z), and mask=string of (e|d|k)
@,

		'dbcreate' =>
q|
To create an identifier minter governed by Template and Term ("long" or "-"),

   noid dbcreate [ Template Term [ NAAN NAA SubNAA ] ]

The Template gives the number and form of generated identifiers.  Examples:

    .rddd        minter of random 3-digit numbers that stops after the 1000th
    .zd          sequential numbers without limit, adding new digits as needed
  bc.sdddd       sequential 4-digit numbers with constant prefix "bc"
    .rdedeede    .7 billion random ids, extended-digits at chars 2, 4, 5 and 7
  fk.rdeeek      .24 million random ids with prefix "fk" and final check char

For persistent identifiers, use "long" for Term, and specify the NAAN, NAA,
and SubNAA.  Otherwise, use "-" for Term or omit it.  The NAAN is a globally
registered Name Assigning Authority Number; for identifiers conforming to the
ARK scheme, this is a 5-digit number registered with ark@cdlib.org, or 00000.
The NAA is the character string equivalent registered for the NAAN; for
example, the NAAN, 13030, corresponds to the NAA, "cdlib.org".  The SubNAA
is also a character string, but it is a locally determined and possibly
structured subauthority string (e.g., "oac", "ucb/dpg", "practice_area") that
is not globally registered.
|,
		'fetch/brief' =>
q@
   noid fetch Id Element ...		# fetch/map one or more Elements
@,
		'fetch' =>
q@
To bind,

   noid bind replace fk0wqkb myGoto http://www.cdlib.org/foobar.html

sets "myGoto" element of identifier "fk0wqkb" to a string (here a URL).
@,
		'get/brief' =>
q@
   noid get Id Element ...		# fetch/map Elements without labels
@,
		'get' =>
q@@,
		'hello/brief' =>
q@@,
		'hello' =>
q@@,
		'hold/brief' =>
q@
   noid hold (set|release) Id ...	# place or remove a "hold" on Id(s)
@,
		'hold' =>
q@@,
		'mint/brief' =>
q@
   noid mint N [ Elem Value ]	# to mint N identifiers (optionally binding)
@,
		'mint' =>
q@@,
		'note/brief' =>
q@@,
		'note' =>
q@@,
		'peppermint/brief' =>
q@@,
		'peppermint' =>
q@@,
		'queue/brief' =>
q@
   noid queue (now|first|lvf|Time) Id ...	# queue (eg, recycle) Id(s)
      Time is NU, meaning N units, where U= d(ays) | s(econds).
      With "lvf" (Lowest Value First) lowest value of id will mint first.
@,
		'queue' =>
q@@,

		'validate/brief' =>
q@
   noid validate Template Id ...	# to check if Ids are valid
      Use Template of "-" to use the minter's native template.
@,
		'validate' =>
q@@,
	);
	return(1);
}

