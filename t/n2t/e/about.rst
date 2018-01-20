.. role:: hl1
.. role:: hl2
.. role:: ext-icon

.. |lArr| unicode:: U+021D0 .. leftwards double arrow
.. |rArr| unicode:: U+021D2 .. rightwards double arrow
.. |X| unicode:: U+02713 .. check mark

.. _EZID: https://ezid.cdlib.org
.. _ARK: https://confluence.ucop.edu/display/Curation/ARK
.. _DOI: https://www.doi.org
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

The N2T.net (Name-to-Thing) resolver is a server that specializes in
keeping public identifiers stable by redirecting web requests to the most
appropriate locations. N2T stores redirection and descriptive information
(metadata) for individual identifiers and, when it doesn't know about a
particular identifier, relies on stored information relevant to the kind
of identifier it is.

The primary audience for N2T services is the global community of people
engaged in reseach, academic, and cultural heritage endeavors. Together
with our primary partner, EZID_, we work with national and university
libraries, academic and society publishers, natural history and art
museums, as well as companies and funders that support education and
research. N2T identifiers are used for everything from citing scholarly
works to referencing tissue samples. They link to cutting edge scientific
datasets, historic botanists, evolving semantic web term definitions, and
living people.

N2T.net is unusual among resolvers because it stores individual
identifiers of more than one kind, including both ARK_\ s and DOI_\ s.
As such it provides equal services to all identifiers, regardless of
origin. For example, it supports ARK-style inflections for DOIs and
DataCite_ DOI metadata via content negotiation for ARKs.

N2T is currently maintained at the `California Digital Library`_ (CDL)
within the University of California (UC) Office of the President. CDL
supports electronic library services for ten UC campuses and a dozen law
schools, medical centers, and national labs, as well as hundreds of
museums, herbaria, botanical gardens, etc.  Recognizing the important
global role that the resolver plays, we are actively seeking to establish
broad and sustainable community ownership of N2T's technological,
administrative, and policy infrastructure.

- `N2T Partners`_
- `N2T API Documentation`_
- `Original N2T vision`_

//END//
