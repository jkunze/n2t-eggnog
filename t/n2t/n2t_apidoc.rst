.. role:: hl1
.. role:: hl2
.. role:: ext-icon

.. |lArr| unicode:: U+021D0 .. leftwards double arrow
.. |rArr| unicode:: U+021D2 .. rightwards double arrow
.. |X| unicode:: U+02713 .. check mark

.. _n2t: https://www.n2t.net
.. _Identifier Basics: https://ezid.cdlib.org/learn/id_basics
.. _Identifier Conventions: https://ezid.cdlib.org/learn/id_concepts
.. _Test server: https://n2t-stg.n2t.net/

The N2T API
=======================

//BEGIN//

Overview
---------

The Name-to-Thing (N2T) service provides public resolution of identifiers
– ARKs, DOIs, etc.  Identifiers used by the public look like an acronym,
a colon, and a string (eg, ark:/12345/fk1234), all appended to a URL
based at n2t.net, for example

  https://n2t.net/ark:/12345/fk1234

  http://n2t.net/doi:10.12345/FK4321

When an identifier is presented to N2T for resolution, the web server is
configured to do a database lookup and ask that the target (URL) *bound
under* the identifier be returned in the form of an HTTP redirect.
Arbitrary name/value pairs may be bound under an identifier.  

Targets are bound under the reserved metadata element name, "_t".  If a
target URL is found, the server redirects the client to it.  Other
metadata elements support inflections and content negotiation.

Identifiers and metadata are created and maintained via the N2T API,
which is the subject of this document.  The API supports

- minting – generating randomized strings that can be used in creating
  identifiers, and

- binding – associating metadata name/value pairs with identifier strings
  meant to be published as URLs.

Under the hood, N2T uses the EggNog software, with egg binders and nog
minters behind an Apache HTTP server.  Minting and binding require HTTP
Basic authentication over SSL.  The base *test* server URL for operating
the API is https://n2t-stg.n2t.net, abbreviated as $b below. You'll need
an N2T user name (known as a *populator*, "sam" below) and a password
("xyzzy", not a real password).  The following shell definitions are used
to shorten examples in this document. ::

  b=https://n2t-stg.n2t.net
  alias wg='wget -q -O - --no-check-certificate --user=sam --password=xyzzy'

For example, with proper credentials this shell command displays more API
functionality (for the egg part of Eggnog) than is described here. ::

  wg "$b/a/sam/b?help readme"

Minting
-------

Minting is optional, and is generally used if you wish to generate
randomized strings when you don't already have specific identifier
strings in mind. N2T minters are set up in advance (not using the API)
and are exclusively associated with particular N2T credentials. The
randomized strings they generate are called *spings*.  A *sping* (semi-opaque
string) is meant to be used as all or part of an identifier string.

Each minter is associated with a *shoulder*, usually a short string, such
as "fk4", that extends an identifier base, such as "99999" (see
`Identifier Basics`_ and `Identifier Conventions`_
for details).  The examples
that follow all use test spings beginning with 99999/fk4, as that
designates a test shoulder shared across all N2T credentials.

Anyone with a password can liberally mint *spings* from the test shoulder
and use them to create test identifiers. Test identifiers behave the same
as real identifiers except that they normally expire in a few weeks. To
mint a test sping, do ::

  wg "$b/a/sam/m/ark/99999/fk4?mint 1"

which returns something like ::

  s: 99999/fk4f30n

Note that most *spings* are auto-expanding in the sense that, as you keep
minting, at the moment the unique spings of a given length run out, the
next run of spings will be longer by 3 characters (at each next expansion
time). Auto-expansion allows you to enjoy shorter spings to start with
while not having to worry about running out of unique spings. So in
general it is best not to rely on spings being of a fixed length.

Binding
-------

N2T users have one or more binders (databases) for their exclusive use.
Roughly, an identifier is created when you bind a string (whether a
minted sping or not) to a thing. Underneath a given identifier string,
you can bind any element, such as the redirection target URL ("_t"). ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.set _t https://archive.org/details/AllAboutBooks"

The identifier comes into being when the first element is bound under it.
To verify what you just bound, you can fetch all current bindings or a
specific binding. ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.fetch _t"

You can change an element at any time using another "set" command with a
different value. Again, the identifier string you bind to doesn't have to
have been created using an N2T minter; you may bind any identifier string
of your choice. Also, you may bind any number of elements, of any name
you choose, under any identifier. 

Deleting
--------

To delete an element entirely, use "rm" or, to delete all elements under
an identifier (effectively deleting the identifier itself), "purge". ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.rm _t"
  wg "$b/a/sam/b?ark:/99999/fk4f30n.purge"

You can also check if an identifier exists. ::

  wg "$b/a/sam/b?ark:/99999/fk4f30n.exists"

Special characters
------------------

Some characters you may want to include are significant to the command
syntax, and there are a couple ways to deal with them. One way is to hex
encode them as "^hh" and insert a ":hx" modifier in front of the whole
command. For example, this command allows a newline to be used in the
identifier and the value: ::

  wg "$b/a/sam/b?:hx ark:/99999/fk4^0af30n.set _.eTm. http://example.com/content-negotiate/99999/fk4^0af30n"

.. xxx need smaller font to not wrap

Strings representing the identifier *i*, an element name *n*, and a data
value *d* must be less than 4GB in length and must not start with a literal
':', '&', or '@' unless it is encoded. Other literals that must be
encoded are any of the characters in "\|;()[]=:" anywhere in the strings i
and n, and any '<' at the start of i. 

The "set" command takes two arguments, so names or values that contain
spaces should be quoted. Normal shell-like quoting conventions work
(single or double quotes, plus backslash), so "a b\" c" would specify the
value: a b" c.

Bulk operations
---------------

You can submit lots of commands (thousands) as a batch inside the HTTP
Request body. N2T looks for a batch of commands when the query string
consists of just "-" (a hyphen). For example, you can set descriptive
metadata along with a target URL. ::

  wg "$b/a/sam/b?-" --post-data='
   ark:/13960/t6m042969.set _t http://www.archive.org/details/wonderfulwizardo00baumiala
   ark:/13960/t6m042969.set how text
   ark:/13960/t6m042969.set who "Baum, L. Frank (Lyman Frank), 1856-1919; Denslow, W. W. (William Wallace), 1856-1915"
   ark:/13960/t6m042969.set what "The wonderful wizard of Oz"
   ark:/13960/t6m042969.set when "1900, c1899"
  '

.. xxx need smaller font to not wrap

Identifier metadata
-------------------

While some metadata elements are optional, the four elements above (who,
what, when, how) are **required** to support basic metadata resolution,
which is done via inflections and content negotiation. The element
definitions follow.

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
                               base terms (further described below)
                               ``: text, image, audio, video, data, code, term,
                               service, agent, human, project, event, oba``
\_t                   yes      a target URL for redirecting content requests
\_,eTm,\ *contype*    no       (optional) a target URL for redirecting metadata
                               requests for a given ContentType contype
\_,eTi,\ *inflection* no       (optional) a target URL for redirecting
                               inflection requests for a given inflection
language              no       (optional) a language used in the content

peek                  no       (optional) a glimpse of the content as a
                               thumbnail, clip, or abstract; for non-text
                               values, use ``(:at)`` *URL_to_non-text_value*
===================== ======== ================================================

If you cannot enter an actual value for a **required element**, enter one
of these special reserved flavors for "missing value".

.. class:: leftheaders

========  ==========================================================
Literal   Definitions for missing values
========  ==========================================================
(:unac)   temporarily inaccessible
(:unal)   unallowed, suppressed intentionally
(:unap)   not applicable, makes no sense
(:unas)   value unassigned (e.g., Untitled)
(:unav)   value unavailable, possibly unknown
(:unkn)   known to be unknown (e.g., Anonymous, Inconnue)
(:none)   never had a value, never will
(:null)   explicitly and meaningfully empty
(:tba)    to be assigned or announced later
========  ==========================================================

You may optionally follow a reserved value with free text meant for human
interpretation. For example, ::

  who: (:unkn) Anonymous
  what: (:tba) Work in progress

Metatypes
---------

A "resource type" tells people that the identified object is of a certain
kind. Often the resource type seems to suggest things about the
surrounding metadata, for example, a resource of type book usually has
an author and publisher, but a geosample might not. It can also be seen
to suggest mappings to core concepts, such as, that the person
responsible the collector (geosample) or author (book).

A *metatype* (text, data, video, etc.) looks similar to a resource type,
but instead of describing the object it describes the surrounding
metadata. Why? To separate and clarify these two roles.  Metadata
curators often lack object access or disciplinary expertise to review
resource type assignments (eg, tissue sample? specimen?), but still want
to convey which type-specific elements and semantics should be present.
Without having to rely on a received resource type or risk making up
their own, they can with confidence apply a metatype that correctly
describes their finished metadata. Finally, metatypes also assert enough
information to permit basic mapping (crosswalking) between metadata sets.

Thus a metataype of "text" asserts only that the surrounding metadata
should include other elements that normally accompany text-like objects.
This is *not* an assertion that the object itself is of type "text" (it
is possible, for example, for an assigned metatype to differ from a
received resource type). Exactly which elements are implied by a given
metatype, along with core mappings to common metadata element sets, is
defined with the metatype term itself.

Metatypes consist of a machine-readable part followed by an optional free
text part. For example, ::

  how: (:metatype text) dissertation
  how: (:metatype data) financial spreadsheet
  how: (:metatype data+code set) time series analysis database
  how: (:metatype data+code) visualization and simulation
  how: (:metatype agent) fruit fly
  how: (:metatype agent set) orchestra

The machine-readable part must be preceded by "(:metatype " and followed
by ")", and may itself be composite. In general, this composite is

1. a sequence of one or more *base* metatypes separated by "+", and
2. is optionally followed by " set" (a space and the word "set") to
   indicate a group, collection, or aggregation

.. class:: leftheaders
.. xxx add links to definitions (see ongoing-notes)

The base metatypes are controlled values defined below.

=======    =============================================================
Literal    Definitions for base metatypes
=======    =============================================================
text	   words meant for reading
image	   still visual information other than text
audio	   information rendered as sounds
video	   visual information made of moving images, often with sound
data	   structured information meant for study and analysis
code	   retrievable computer program in source or compiled form
term	   word or phrase
service	   destination or automaton with which interaction is possible
agent	   person, organization, or automaton that can act
human	   specific kind of agent, namely, a person
event	   non-persistent, time-based occurrence
oba        none of the above (meaning "other" in Tagolog)
=======    =============================================================

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

  ``ark:/12345/fk3``

is in the same form as what is presented to n2t.net:

  ``http://n2t.net/ark:/12345/fk3``

More generally,

  ``n2t.net/<scheme>:[/]<naan>/<blade>``

//END//
