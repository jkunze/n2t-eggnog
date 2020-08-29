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
.. _EZID.cdlib.org: https://ezid.cdlib.org
.. _Internet Archive: https://archive.org
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

N2T.net (Name-to-Thing) is a "resolver," a kind of web server that stores
little content itself and usually forwards incoming requests to other
servers. Similar to URL shorteners like bit.ly, N2T serves content
*indirectly*.

The main use of N2T is "persistent identifiers." An archive or publisher
who gives out content links (URLs) starting with n2t.net doesn't need to
worry about their breaking. That's because even though content eventually
moves to different servers, links starting with n2t.net are stable and
still work when forwarding rules at N2T are updated. While all persistent
identifier services work similarly (ARK, DOI, Handle, PURL, URN), N2T.net
is unusually open and flexible in extending services to all identifier
types rather than excluding all but just one type.

Unlike URL shorteners, N2T can store more than one "target" (forwarding
link) for an identifier, as well as any kind or amount of metadata
(descriptive information). When forwarding doesn't work for some reason,
such as temporary outage or insufficient permission at the target server,
N2T can nonetheless return persistent information about the identified
object.

Unique Features
---------------

- N2T supports "`suffix passthrough`_", which drastically reduces the
  number of individual identifiers that providers need to maintain.
- It supports "inflections" and "content negotiation", which allow you to
  request descriptive information for identifiers that have it.
- N2T.net is unusual among resolvers because it is not a silo that works
  with only one kind of identifier. It stores individual identifiers of
  any kind, including both ARK_\ s and DOI_\ s, and provides equal
  services to all kinds, regardless of origin.
- As a result N2T easily supports feature combinations that some have
  found startling, such as ARK-style inflections for DOIs, and ARKs that
  return DataCite_ DOI metadata via content negotiation.
- N2T.net is also a "meta-resolver". In collaboration with identifiers.org,
  it recognizes over 600 well-known identifier types and knows where their
  respective servers are. Failing to find forwarding information for a
  specific individual identifier, it uses the identifier's type to look
  for an overall target rule.

Audience
--------

The primary audience for N2T services is the global community of people
engaged in research, academic, and cultural heritage endeavors. Together
with our primary partners_, EZID_ and `Internet Archive`_, we work with
national, university, and public libraries, academic and society
publishers, natural history and art museums, as well as companies and
funders that support education and research. N2T identifiers are used for
everything from citing scholarly works to referencing tissue samples.
They link to cutting edge scientific datasets, historic botanists,
evolving semantic web term definitions, and living people.

Organizational Backing
----------------------

N2T is maintained at the `California Digital Library`_ (CDL) within the
University of California (UC) Office of the President (UCOP). CDL supports
electronic library services for ten UC campuses and affiliated law
schools, medical centers, and national laboratories, as well as hundreds
of museums, herbaria, botanical gardens, etc.

N2T runs in the AWS (Amazon Web Services) cloud. Security and privacy
rests on the foundational physical, network, and procedural security
maintained within AWS datacenters based in the United States of America,
with additional CDL and UCOP privacy safeguards, patching policies, access
restrictions, firewall controls, etc. layered on top of that.

Recognizing the important global role that the resolver plays, in 2018 CDL
and DuraSpace_ (now LYRASIS) launched an initiative, called
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
