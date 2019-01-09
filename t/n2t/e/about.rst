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
.. _DuraSpace: http://duraspace.org/
.. _EZID.cdlib.org: https://ezid.cdlib.org
.. _Archive.org: https://archive.org
.. _YAMZ.net metadictionary: https://yamz.net
.. _DataCite: https://www.datacite.org
.. _Crossref: https://crossref.org
.. _European Bioinformatics Institute: https://www.ebi.ac.uk
.. _California Digital Library: https://www.cdlib.org
.. _Uniform Resolution of Compact Identifiers for Biomedical Data: https://doi.org/10.1101/101279
.. _Prefix Commons: https://prefixcommons.org
.. _SNAC: http://snaccooperative.org
.. _NIH: http://www.nih.gov
.. _Force11: https://www.force11.org/
.. _N2T Partners: /e/partners.html
.. _N2T API Documentation: /e/n2t_apidoc.html
.. _Compact, prefixed identifiers at N2T.net: /e/compact_ids.html
.. _Original N2T vision: /e/n2t_vision.html

.. _n2t: https://n2t.net
.. _Identifier Basics: https://ezid.cdlib.org/learn/id_basics
.. _Identifier Conventions: https://ezid.cdlib.org/learn/id_concepts

//BEGIN//

About N2T.net
=============

N2T.net (Name-to-Thing) is a "resolver," a kind of web server that stores
little content itself and usually forwards incoming requests to other
servers. Similar to URL shorteners like bit.ly, N2T serves content
*indirectly*.

The main use of N2T is "persistent identifiers." An archive or publisher
who gives out content links (URLs) starting with n2t.net doesn't need to
worry about their breaking. That's because even though content eventually
moves to different servers, links starting with n2t.net are stable and
still work when forwarding rules at N2T are updated. All persistent
identifier services work similarly (ARK, DOI, Handle, PURL, URN), but
N2T is unusually open and flexible.

Unlike URL shorteners, N2T can store more than one "target" (forwarding
link) for an identifier, as well as any kind or amount of metadata
(descriptive information). When forwarding doesn't work for some reason,
such as temporary outage or permission problems at the target server, N2T
can meanwhile return information about the identified object.

Features
--------

- Supports "`suffix passthrough`_", which drastically reduces the number
  of individual identifiers that providers need to maintain.
- Supports "inflections" and "content negotiation", which allow you to
  request descriptive information for identifiers that have it.
- N2T.net is unusual among resolvers because it is not a silo that works
  with only one kind of identifier. It stores individual identifiers of
  any kind, including both ARK_\ s and DOI_\ s. As such it provides equal
  services to all identifiers, regardless of origin. For example, it
  supports ARK-style inflections for DOIs and DataCite_ DOI metadata via
  content negotiation for ARKs.
- N2T.net is also a "meta-resolver". In collaboration with identifiers.org,
  it recognizes over 600 well-known identifier types and knows where their
  respective servers are. Failing to find forwarding information for a
  specific individual identifier, it uses the identifier's type to look
  for an overall target rule.

Audience
--------

The primary audience for N2T services is the global community of people
engaged in research, academic, and cultural heritage endeavors. Together
with our primary partner, EZID_, we work with national and university
libraries, academic and society publishers, natural history and art
museums, as well as companies and funders that support education and
research. N2T identifiers are used for everything from citing scholarly
works to referencing tissue samples. They link to cutting edge scientific
datasets, historic botanists, evolving semantic web term definitions, and
living people.

Organizational Backing
----------------------

N2T is maintained at the `California Digital Library`_ (CDL) within the
University of California (UC) Office of the President. CDL supports
electronic library services for ten UC campuses and a dozen law schools,
medical centers, and national labs, as well as hundreds of museums,
herbaria, botanical gardens, etc.

Recognizing the important global role that the resolver plays, in 2018 CDL
and DuraSpace_ launched an initiative (`ARKs in the Open`_), in part to
establish broad and sustainable community ownership of N2T's technological,
administrative, and policy infrastructure.

- `N2T Partners`_
- `N2T API Documentation`_
- `Original N2T vision`_

//END//
