.. role:: hl1
.. role:: hl2
.. role:: ext-icon

.. |lArr| unicode:: U+021D0 .. leftwards double arrow
.. |rArr| unicode:: U+021D2 .. rightwards double arrow
.. |X| unicode:: U+02713 .. check mark

.. _n2t: https://n2t.net
.. _Identifier Basics: https://ezid.cdlib.org/learn/id_basics
.. _Identifier Conventions: https://ezid.cdlib.org/learn/id_concepts
.. _Suffix Passthrough Explained: https://ezid.cdlib.org/learn/suffix_passthrough
.. _test server: https://n2t-stg.n2t.net/
.. _EggNog software: https://bitbucket.org/cdl/n2t-eggnog
.. _inflections: https://confluence.ucop.edu/display/Curation/ARK
.. _metatype: https://n2t.net/ark:/99152/h3865
.. _set: https://n2t.net/ark:/99152/h3866
.. _text: https://n2t.net/ark:/99152/h3867
.. _image: https://n2t.net/ark:/99152/h3868
.. _audio: https://n2t.net/ark:/99152/h3869
.. _video: https://n2t.net/ark:/99152/h3870
.. _data: https://n2t.net/ark:/99152/h3871
.. _code: https://n2t.net/ark:/99152/h3872
.. _term: https://n2t.net/ark:/99152/h3873
.. _service: https://n2t.net/ark:/99152/h3874
.. _agent: https://n2t.net/ark:/99152/h3875
.. _human: https://n2t.net/ark:/99152/h3876
.. _event: https://n2t.net/ark:/99152/h3877
.. _oba: https://n2t.net/ark:/99152/h1193
.. _unac: https://n2t.net/ark:/99152/h3878
.. _unal: https://n2t.net/ark:/99152/h3880
.. _unap: https://n2t.net/ark:/99152/h3881
.. _unas: https://n2t.net/ark:/99152/h3882
.. _unav: https://n2t.net/ark:/99152/h3883
.. _unkn: https://n2t.net/ark:/99152/h3884
.. _none: https://n2t.net/ark:/99152/h3885
.. _null: https://n2t.net/ark:/99152/h3886
.. _etal: https://n2t.net/ark:/99152/h3887
.. _tba: https://n2t.net/ark:/99152/h3888
.. _at: https://n2t.net/ark:/99152/h3889

//BEGIN//

The N2T API and UI
==================

User interface overview
-----------------------

The Name-to-Thing (N2T.net) service provides public resolution of identifiers –
ARKs, DOIs, etc.  Identifiers used by the public look like an acronym, a colon,
and a string (eg, ark:/12345/fk1234), all appended to a URL based at n2t.net,
for example,

  https://n2t.net/ark:/12345/fk1234

  http://n2t.net/doi:10.12345/FK4321

When an identifier is presented to N2T for resolution, the web server is
configured to do a database lookup and ask that the target URL bound with the
identifier be returned in the form of an HTTP redirect.

The target value (a URL) is metadata stored in a reserved element name, ``_t``,
and it is considered to be *bound under* its identifier. Arbitrary name/value
pairs may be bound under an identifier. Other metadata elements support
inflections_ and content negotiation.

On resolution if a target URL is found, the server redirects the client to it.
Failing to find a bound identifier, the N2T.net resolver then looks for a
redirection rule associated with the identifier. It does so by inspecting its
hierarchical ancestors, namely, shorter strings formed by successively chopping
from the end. For example, ::

  ark:/12345/fk1234        # original identifier string
  ark:/12345/fk1           # "shoulder"
  ark:/12345               # NAAN (Name Assigning Authority Number)
  ark                      # "scheme" (identifier class, aka, prefix)

That briefly describes the minimal UI (user interface) that N2T.net has.
More about how N2T uses identifiers can be found in `Identifier Basics`_
and `Identifier Conventions`_.

Branded vs opaque identifier strings
------------------------------------

Opaque identifier strings, which reveal little about the objects they identify
or their origins, are generally considered good choices for persistent
identifiers because they age and travel well. Often, however, organizations
feel pressure to include branding in their strings to aid with visibility,
promotion, and funding. How best to accommodate these seemingly conflictual
aims of identifier and organizational sustainability?

The approach advocated by N2T is to set up a specially branded DNS CNAME
pointing to n2t.net and use it to advertise their identifiers. For example, if
"Acme Rockets" has an identifier ark:/12345/6789, instead of publishing it as
the opaque identifier,

  n2t.net/ark:/12345/6789

they would publish it as the dual-branded,

  n2t.acme.example.org/ark:/12345/6789

where n2t.acme.example.org is a CNAME that Acme Rockets' DNS administrator will
have set up to forward all traffic to n2t.net. The CNAME provides branding and
needs almost no maintenance. Should the acme.example.org domain ever lapse, the
published identifier will no longer resolve "as is", but since the N2T brand is
also present, it provides a social hint to future recipients that the
well-known n2t.net resolver might still be able to resolve the part of the
identifier after the hostname.

This document
-------------

The API (application programming interface) is used to create and maintain
identifiers and metadata. The API, the main subject of this document, supports

- minting – generating randomized strings that can be used in creating
  identifiers, and

- binding – associating metadata name/value pairs with identifier strings
  meant to be published as URLs.

Under the hood, N2T.net uses the `EggNog software`_, with egg binders and
nog (nice opaque generator) minters behind an Apache HTTP server.
Minting and binding require HTTP Basic authentication over SSL.  The base
`test server`_ URL for operating the API is https://n2t-stg.n2t.net,
abbreviated as $b below.  You'll need an N2T user name (known as a
*populator*, ``sam`` below) and a password (``xyzzy``, not a real password).
The following shell definitions are used to shorten examples in this
document. ::

  b=https://n2t-stg.n2t.net
  alias wg='wget -q -O - --no-check-certificate --user=sam --password=xyzzy'

For example, with proper credentials this shell command displays more API
functionality (for the egg part of Eggnog) than is described here. ::

  wg "$b/a/sam/b?help readme"

Yes, there's a space inside that URL, which you may hex encode if you prefer.

Minting
-------

Minting is optional, and is generally used if you wish to generate
randomized strings when you don't already have specific identifier
strings in mind. N2T minters are set up in advance (not using the API)
and are exclusively associated with particular N2T credentials. To
avoid common confusion with identifiers, identifier strings, and minter
output, the randomized strings that minters generate are called *spings*.

A *sping* (semi-opaque string) is meant to be used as all or part of an
identifier string. We do not consider an identifier to be created until its
association with something is publicized widely enough to be difficult to
withdraw.

Minters are useful to generate names at different levels in a hierarchical
namespace. To help with this, each minter has a *shoulder*, usually a short
string, such as ``fk4``, that extends an identifier base, such as ``99999`` (see
`Identifier Basics`_ and `Identifier Conventions`_ for details). The examples
that follow all use test spings beginning with 99999/fk4, as that designates a
test shoulder shared across all N2T credentials.

Anyone with a password can liberally mint *spings* from the test shoulder and
use them to create test identifiers. Test identifiers behave the same as real
identifiers except that you must not count on them to persist. For example, the
EZID populator of N2T actively expires its test identifiers a few weeks after
their creation. To mint a test sping, do ::

  wg "$b/a/sam/m/ark/99999/fk4?mint 1"

which returns something like ::

  s: 99999/fk4f30n

Note that most *spings* are auto-expanding in the sense that, as you keep
minting, at the moment the unique spings of a given length run out, the
next run of spings will be longer by 3 characters (at each next expansion
time). Auto-expansion allows you to enjoy shorter spings to start with
while not having to worry about running out of unique spings. So in
general it is best not to rely on spings being of a fixed length.

Typically, N2T API minting calls look like 

  wg "$b/a/sam/m/<Minter>?mint <Number>"

where Number is a positive integer.

Binding
-------

N2T users have one or more binders (databases) for their exclusive use.
Roughly, an identifier is created when you bind a string (whether a
minted sping or not) to a thing. Underneath a given identifier string,
you can bind any element, such as the redirection target URL (``_t``). ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.set _t https://archive.org/details/AllAboutBooks"

The identifier comes into being when the first element is bound under it.
To verify what you just bound, you can fetch all current bindings or a
specific binding. ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.fetch _t"

You can change an element at any time using another ``set`` command with a
different value. Again, the identifier string you bind to doesn't have to
have been created using an N2T minter; you may bind any identifier string
of your choice. Also, you may bind any number of elements, of any name
you choose, under any identifier. 

Suffix Passthrough
------------------

In a special case, if a thing you identify has lots of sub-things at a web
server under your control, you may want to take advantage of N2T.net's
"suffix passthrough" feature. This allows you to bind one identifier to
the top-level thing and advertise sub-thing (descendant) identifiers by adding
a suffix to (thus lengthening) the original identifier. ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.set _t http://example.org/d?suffix="

For the above target, the following identifier resolutions would occur::

 ark:/99999/fk4f30n             -> http://example.org/d?suffix=
 ark:/99999/fk4f30n/doc1        -> http://example.org/d?suffix=doc1
 ark:/99999/fk4f30n/doc999      -> http://example.org/d?suffix=doc999
 ark:/99999/fk4f30n/doc8/chap7  -> http://example.org/d?suffix=doc8/chap7

See `Suffix Passthrough Explained`_ for more information.

Typically, N2T API binder calls look like 

  wg "$b/a/<User>/b?<Modifier> <Identifier>.<Operation> <Element> <Value>"

where Operation may be ``set``, ``add``, ``rm``, ``purge``, ``exists``, etc, and
Modifier, Element, and Value are conditionally present (see below).
The API closely resembles Eggnog's CLI (command line interface).

Deleting
--------

To delete an element entirely, use ``rm`` or, to delete all elements under
an identifier (effectively deleting the identifier itself), ``purge``. ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.rm _t"
  wg "$b/a/sam/b?ark:/99999/fk4f30n.purge"

You can also check if an identifier exists. ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.exists"

Special characters
------------------

Some characters you may want to include are significant to the command
syntax, and there are a couple ways to deal with them. One way is to hex
encode them as "^hh" and insert a ``:hx`` modifier in front of the whole
command. For example, this command allows a newline to be used in the
identifier (a contrived example, since newlines are not allowed in ARK
identifiers) and the value: ::

  wg "$b/a/sam/b?:hx ark:/99999/fk4^0af30n.set _.eTm. http://example.com/content-negotiate/99999/fk4^0af30n"

Strings representing the identifier *i*, an element name *n*, and a data value
*d* must be less than 4GB in length and must not start with a literal ':', '&',
or '@' unless it is encoded. Other literals that must be encoded are any of the
characters in "\|;()[]=:" anywhere in the strings *i* and *n*, and any '<' at
the start of *i*. 

The ``set`` command takes two arguments, so names or values that contain
spaces should be quoted. Normal shell-like quoting conventions work
(single or double quotes, plus backslash), so "a b\" c" would specify the
value: a b" c.

Bulk operations
---------------

You can submit lots of commands as a batch inside the HTTP Request body.
N2T looks for a batch of commands when the query string consists of just
"-" (a hyphen). For example, this command sets descriptive metadata along
with a target URL. ::

  wg "$b/a/sam/b?-" --post-data='
   ark:/13960/t6m042969.set _t http://www.archive.org/details/wonderfulwizardo00baumiala
   ark:/13960/t6m042969.set how (:mtype text)
   ark:/13960/t6m042969.set who "Baum, L. Frank (Lyman Frank), 1856-1919; Denslow, W. W. (William Wallace), 1856-1915"
   ark:/13960/t6m042969.set what "The wonderful wizard of Oz"
   ark:/13960/t6m042969.set when "1900, c1899"
  '

Great efficiency is possible. For example, if a file named "ids-to-purge"
contains 9 million identifiers, one per line, the following server-side
shell script (or its client-side equivalent) would purge them. ::

  #!/bin/env bash
  
  binder=~/sv/cur/apache2/binders/ezid
  batchsize=5000
  bigbatch=ids-to-purge
  linestotal=$( wc -l < ids-to-purge )
  
  split --lines=$batchsize $bigbatch batch
  date > pout
  
  n=0
  for f in batch??
  do
      sed 's/$/.purge/' $f | egg -d $binder - >> pout
      (( n+=$batchsize ))
      (( percent=(( $n * 100 ) / $linestotal ) ))
      echo Processed batch $f, progress $percent%
      sleep 2      # pause, releasing DB lock so others can use it too
  done

Identifier metadata
-------------------

Resolution does not require metadata other than target URLs, however, to be
considered in good standing, ARKs and some other identifiers require a minimum
set of descriptive elements. In order to achieve that standing, the four
elements above (who, what, when, how) are **required** to support *basic
metadata resolution*, which is done via inflections and content negotiation.
Definitions of both required and optional elements follow.

.. class:: leftheaders

===================== ======== ================================================
Element Name          Required Definition
===================== ======== ================================================
who                   yes      a responsible person or party
what                  yes      a name or other human-oriented identifier
when                  yes      a date important in the object's lifecycle
where                 yes      a machine-oriented identifier; NB: *no need to*
                               *supply, as it is implied by the identifier*
                               *string itself and any target information*
how                   yes      a *metatype* constructed from the following
                               base terms (described below)
                               ``: text, image, audio, video, data, code, term,
                               service, agent, human, project, event, oba``;
			       optionally followed by a human-readable object
			       (resource) type
\_t                   yes      a target URL for redirecting content requests;
                               if the URL is preceded by an integer and a
                               space, the integer is used as a redirect code
\_,eTm,\ *contype*    no       (optional) a target URL for redirecting metadata
                               requests for a given ContentType contype
\_,eTi,\ *inflection* no       (optional) a target URL for redirecting
                               inflection requests for a given inflection
language              no       (optional) a language used in the content

peek                  no       (optional) a glimpse of the content as a
                               thumbnail, clip, or abstract; for non-text
                               values, use (:at_) *URL_to_non-text_value*
size                  no       (optional) one or more ";"-separated quantities,
                               which may be human- or machine-readable
===================== ======== ================================================

If you cannot enter an actual value for a **required element**, enter one
of these special reserved flavors for "missing value".

.. class:: leftheaders

========  ==========================================================
Literal   Definitions for missing values
========  ==========================================================
(:unac_)  temporarily inaccessible
(:unal_)  unallowed, suppressed intentionally
(:unap_)  not applicable, makes no sense
(:unas_)  value unassigned (e.g., Untitled)
(:unav_)  value unavailable, possibly unknown
(:unkn_)  known to be unknown (e.g., Anonymous, Inconnue)
(:none_)  never had a value, never will
(:null_)  explicitly and meaningfully empty
(:etal_)  other values too numerous to list
(:tba_)   to be assigned or announced later
(:at_)    present value is an indirect reference to the real value
========  ==========================================================

You may optionally follow a reserved value with free text meant for human
interpretation. For example, ::

  who: (:unkn) Anonymous
  what: (:tba) Work in progress

Metatypes
---------

A "resource type" tells people that the identified object is of a certain
kind. Often the resource type *also* seems to suggest things about the
surrounding metadata, for example, a resource of type book usually has
an author and publisher, but a geosample does not. Moreover it suggests
mappings to core concepts, such as, that the person responsible was the
collector (geosample) or the author (book). This double duty sometimes causes
confusion.

A metatype_ (text, data, video, etc.) looks similar to a resource type,
but instead of characterizing the object it gives a functional description
of the surrounding metadata. Why? To separate and clarify these two roles. A
metatype assignment only reflects properties of the metadata and need not
consider or match the resource type at all. Similarity between metatypes and
resource types should be common, but never required.

For one thing, metadata curators often lack object access or disciplinary
expertise to review resource type assignments (eg, tissue sample vs
specimen? map vs image vs pdf?), but still want to convey which
type-specific elements and semantics should be present.
Without having to rely on a received resource type or risk making up
their own, they can with confidence apply a metatype that correctly
describes their finished metadata (not the object). Finally, metatypes also
assert enough information to permit basic mapping (crosswalking) between
metadata sets.

Thus a metataype of "text" asserts only that the surrounding metadata
should include other elements that normally accompany text-like objects.
This is *not* an assertion that the object itself is of type "text". Exactly
which elements are implied by a given metatype, along with core mappings to
common metadata element sets, is defined with the metatype term itself.

The metatype and resource type both appear in the kernel element "how", which
permits machine-readable parts followed by optional human readable parts.
For example, ::

  how: (:mtype text) dissertation
  how: (:mtype data) financial spreadsheet
  how: (:mtype data+code set) time series analysis database
  how: (:mtype data+code) visualization and simulation
  how: (:mtype agent) fruit fly
  how: (:mtype agent set) orchestra

The machine-readable part must be preceded by ``(:mtype `` and followed
by ``)``, and may itself be composite. In general, this composite is

1. a sequence of one or more *base* metatypes separated by "+", and
2. is optionally followed by `` set`` (a space and the word "set_") to
   indicate that the metadata describes a group, collection, or aggregation

.. class:: leftheaders

The base metatypes are controlled values defined below.

=========    =============================================================
Metatype     Typical corresponding resource type
=========    =============================================================
text_	     words meant for reading
image_	     still visual information other than text
audio_	     information rendered as sounds
video_	     visual information made of moving images, often with sound
data_	     structured information meant for study and analysis
code_	     retrievable computer program in source or compiled form
term_	     word or phrase
service_     destination or automaton with which interaction is possible
agent_	     person, organization, or automaton that can act
human_	     specific kind of agent, namely, a person
event_	     non-persistent, time-based occurrence
oba_         none of the above (meaning "other" in Tagolog)
=========    =============================================================

Optional descriptive metadata
-----------------------------

To enable richer descriptions, supplement the required elements with any
other named metadata elements that you wish to make publicly viewable,
and don't worry if some of the values already appear among the required
elements (eg, "who" and "author", "when" and "published"). Note use of
the "add" command to add an extra "who" element instead of the "set"
command, which overwrites all pre-existing "who" elements. ::

  wg "$b/a/sam/b?-" --post-data='
   ark:/13960/t6m042969.set _t http://www.archive.org/details/wonderfulwizardo00baumiala
   ark:/13960/t6m042969.set how text
   ark:/13960/t6m042969.set who "Baum, L. Frank (Lyman Frank), 1856-1919"
   ark:/13960/t6m042969.add who "Denslow, W. W. (William Wallace), 1856-1915"
   ark:/13960/t6m042969.set what "The wonderful wizard of Oz"
   ark:/13960/t6m042969.set when "1900, c1899"
   ark:/13960/t6m042969.set language English
   ark:/13960/t6m042969.set peek "(:at) https://archive.org/services/img/wonderfulwizardo00baumiala"
   ark:/13960/t6m042969.set author "Baum, L. Frank (Lyman Frank), 1856-1919; Denslow, W. W. (William Wallace), 1856-1915"
   ark:/13960/t6m042969.set title "The wonderful wizard of Oz"
   ark:/13960/t6m042969.set published "1900, c1899"
   ark:/13960/t6m042969.set topics "Adventure and adventurers | Wizards"
   ark:/13960/t6m042969.set pages 216
   ark:/13960/t6m042969.set "possible copyright status" NOT_IN_COPYRIGHT
  '

Users and API paths
-------------------

A *populator* is an N2T user (eg, "ezid"). Each populator has its own
password and a set of binders and minters for its exclusive use.
Components for the API are all laid out under n2t.net/a/... as follows,
in this case, for the "ezid" populator/user::

  n2t.net/a/ezid/b                 # main ezid binder
  n2t.net/a/ezid_test/b            # test ezid binder
  n2t.net/a/ezid/m/ark/99999/fk4   # to mint spings for fake/test ARKs
  n2t.net/a/ezid/m/ark/b5072/fk2   # to mint spings for fake/test DOIs
  n2t.net/a/ezid/m/ark/.../...     # all other ezid minters

You can try these paths in the browser (requiring authentication). For
the base path, some helpful information is printed. See, for example, the
information printed for both of these URLs::

  https://n2t-stg.n2t.net/a/ezid/b
  https://n2t-stg.n2t.net/a/ezid/b?help%20readme

Resolution
----------

N2T resolution requires a fully qualified identifier, which essentially means that the identifier that is stored, such as,

  ark:/12345/fk3

is in the same form as what is presented to n2t.net:

  \https://n2t.net/ark:/12345/fk3

More generally, the form follows n2t.net/*scheme:[/]naan/string*.

//END//
