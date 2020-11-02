.. role:: hl1
.. role:: hl2
.. role:: ext-icon

.. |lArr| unicode:: U+021D0 .. leftwards double arrow
.. |rArr| unicode:: U+021D2 .. rightwards double arrow
.. |X| unicode:: U+02713 .. check mark

.. _EZID: https://ezid.cdlib.org
.. _ARK: /e/ark_ids.html
.. _ARKs in the Open: http://ARKsInTheOpen.org
.. _DOI: https://www.doi.org
.. _suffix passthrough: https://ezid.cdlib.org/learn/suffix_passthrough
.. _DuraSpace: http://lyrasis.org/
.. _LYRASIS: http://lyrasis.org/
.. _EZID.cdlib.org: https://ezid.cdlib.org
.. _Internet Archive: https://archive.org
.. _YAMZ.net metadictionary: https://yamz.net
.. _DataCite: https://www.datacite.org
.. _Crossref: https://crossref.org
.. _European Bioinformatics Institute: https://www.ebi.ac.uk
.. _California Digital Library: https://www.cdlib.org
.. _Uniform Resolution of Compact Identifiers for Biomedical Data: https://doi.org/10.1101/101279
.. _Prefix Commons: https://prefixcommons.org
.. _RFC 2168: https://tools.ietf.org/rfc/rfc2168
.. _SNAC: http://snaccooperative.org
.. _NIH: http://www.nih.gov
.. _Force11: https://www.force11.org/
.. _partners: /e/partners.html
.. _N2T API Documentation: /e/n2t_apidoc.html
.. _N2T Architecture: /e/images/N2T_Anatomy.jpg
.. _Compact, prefixed identifiers at N2T.net: /e/compact_ids.html
.. _Original N2T vision: /e/n2t_vision.html

.. _n2t: https://n2t.net
.. _Identifier Basics: https://ezid.cdlib.org/learn/id_basics
.. _Identifier Conventions: https://ezid.cdlib.org/learn/id_concepts

//BEGIN//

About N2T.net
=============

N2T.net (Name-to-Thing) is a "resolver," a kind of server that specializes
in *indirection* by forwarding most incoming requests to other servers.
Rather than serving content directly (this page is an exception), resolvers
are good at redirecting requests to content servers, similar to URL shorteners
like bit.ly.

Origins of N2T
--------------

N2T's name was inspired by a set of URN mapping operations, N2R (Name to
Resource), N2L (Name to URL), and N2C (Name to URC) envisioned in 1997 (`RFC
2168`_). The technical infrastructure arose out of a demand for a global ARK
(Archival Resource Key) resolver. All a basic resolver needs is software to do
table lookup given an incoming string and issue a "server redirect", as
found in every web server since 1992. One approach, taken by the Handle and
DOI systems, is to create a "silo" that only works for one type of identifier.
Since making lookups fail except for certain parts of the alphabet would be
artificial, exclusionary, and extra work, the ARK resolver took a different
approach following basic principles of openness and generality. The result was
N2T, a scheme-agnostic resolver that currently works for over 900 types of
identifier, including ARKs, DOIs, Handles, PURLs, URNs, ORCIDs, ISSNs, etc.

The main use of N2T is for "persistent identifiers." An archive or publisher
who gives out content links (URLs) starting with n2t.net doesn't need to worry
about their breaking. That's because even though content eventually moves to
different servers, links starting with n2t.net remain stable and still work
provided forwarding rules at N2T are updated. While all persistent identifier
services work similarly (ARK, DOI, Handle, PURL, URN), N2T.net is unusually
open and flexible in including services to all identifier types.

Features Unique to the N2T Resolver
-----------------------------------

Unlike URL shorteners, N2T can store more than one "target" (forwarding
link) for an identifier, as well as any kind or amount of metadata
(descriptive information). When forwarding doesn't work for some reason,
such as temporary outage or insufficient permission at the target server,
N2T can nonetheless return persistent information about the identified
object. N2T also supports CORS (Cross-Origin Resource Sharing) to securely
enable JavaScript access to public content with identifiers based at N2T.

- **Suffix passthrough.** N2T supports "`suffix passthrough`_", which
  drastically reduces the number of individual identifiers that providers need
  to maintain.
- **Inflections.** It supports "inflections" and "content negotiation", which
  allow you to request descriptive information for identifiers that have it.
- **Identifier-scheme-agnostic.** N2T.net is unusual among resolvers because it
  is not a silo that works with only one kind of identifier. It stores
  individual identifiers of any kind, including both ARK_\ s and DOI_\ s, and
  provides equal services to all kinds, regardless of origin.
- **Cross-scheme features.** As a result N2T easily supports feature
  combinations that some have found surprising, such as ARK-style inflections
  for DOIs and ARKs that return DataCite_ DOI metadata via content negotiation.
- **Resolver and meta-resolver.** Unusually, N2T.net is a "meta-resolver" that
  also stores about 50 million identifiers. As a meta-resolver, it recognizes
  over 900 well-known identifier types, including all those known to
  identifiers.org, and knows where their respective servers are. Failing to
  find forwarding information for an identifier it stores, it uses the
  identifier's type to look for an overall target rule.
- **Prefix extension.** N2T supports a "prefix extension" feature that permits
  developers to extend a scheme or an ARK NAAN (both of which "prefix" an
  identifier) with ``-dev`` in order to forward to an alternate destination.
  For example, if the NAAN ``12345`` forwards to domain ``a.b.org``, then
  ``ark:/12345-dev/678`` forwards to ``a-dev.b.org/678``. It works similarly
  for schemes, for example, if scheme ``xyzzy`` forwards to ``a.b.org/$id``,
  then ``xyzzy-dev:foo`` forwards to ``a-dev.b.org/foo``. Just for NAANs,
  the ``-dev`` part can actually be a hyphen (``-``) followed by any string
  that works in a hostname.

Audience
--------

The primary audience for N2T services is the global community of people
engaged in research, academic, and cultural heritage endeavors. Together
with our primary partners_, EZID_ and `Internet Archive`_, we work with
national, university, and public libraries, academic and society
publishers, natural history and art museums, as well as companies and
funders that support education and research.

N2T identifiers are used for everything from citing scholarly works to
referencing tissue samples. They link to cutting edge scientific datasets,
historic botanists, evolving semantic web term definitions, and living people.

Organizational Backing
----------------------

N2T is maintained at the `California Digital Library`_ (CDL) within the
University of California (UC) Office of the President (UCOP). CDL supports
electronic library services for ten UC campuses and affiliated law
schools, medical centers, and national laboratories, as well as hundreds
of museums, herbaria, botanical gardens, etc.

N2T runs in the AWS (Amazon Web Services) cloud. Security and privacy rests on
CDL and UCOP privacy safeguards, patching policies, access restrictions, and
firewall controls, layered over the foundational physical, network, and
procedural security maintained in AWS datacenters based in the United
States of America.

Recognizing the important global role that the resolver plays, in 2018 CDL
and DuraSpace_ (now LYRASIS_) launched an initiative, called
`ARKs in the Open`_, to establish broad and sustainable community ownership
of N2T's technological, administrative, and policy infrastructure.
With support from 31 organizations on 4 continents, the initiative
has three active working groups.

- N2T partners_
- `N2T API Documentation`_
- `Original N2T vision`_
- `N2T Architecture`_ diagram

Maintenance Window
------------------

The N2T service may occasionally be suspended or interrupted for up to one hour
during the routine maintenance window. If maintenance is scheduled, it takes
place on Sundays beginning at 08:00 in California, UTC-08:00 (standard time),
UTC-07:00 (daylight savings).

//END//
