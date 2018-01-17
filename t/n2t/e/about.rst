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
.. _SNAC: http://snaccooperative.org/

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

Compact Identifiers
-------------------

N2T.net can be seen as a kind of URL shortener-plus-hardener in the sense
that URLs such as ::

 https://n2t.net/pdb:2gc4
 https://n2t.net/taxon:9606
 https://n2t.net/ark:/47881/m6g15z54

made possible by N2T are shorter and stabler than their non-N2T
counterpart URLs::

 http://www.rcsb.org/pdb/explore/explore.do?structureId=2gc4
 http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=9606
 http://bibnum.univ-lyon1.fr/nuxeo/nxfile/default/49e1576c-0cae-4b4b-a63b-73370f476681/blobholder:0/THm_2014_NGUYEN_Marie_France.pdf

These are examples of "compact identifiers", a term that arose from a
cooperative agreement between the Identifiers.org resolver and N2T.net to
serve a common set of over 600 identifier schemes (or prefixes). A scheme
is represented by the characters after "n2t.net/" and before the colon,
which, in the examples, are `pdb`, `taxon`, and `ark`.  This work and our
plans to reach out to publishers adopting inline citation of compact
identifiers is described in `Uniform Resolution of Compact Identifiers
for Biomedical Data`_.

N2T.net Partners
----------------

Individual identifiers are stored in N2T.net by a number of partners.

- `EZID.cdlib.org`_ - making long-term identifiers easy
- `Archive.org`_ - the Internet Archive
- `YAMZ.net metadictionary`_ - open vocabulary of metadata terms 

Scheme (prefix) records are stored in N2T.net in partnership with

- `European Bioinformatics Institute`_ - identifiers.org
- `Prefix Commons`_ - prefixcommons.org

While not currently storing individual identifiers for them, N2T stores
"NAAN" and "shoulder" (described in `Identifier Basics`_) records for
over 500 different ARK providers, including

- National Library of France
- Portico Digital Preservation Service
- FamilySearch
- The University of North Texas
- The British Library
- The University of Chicago
- Social Networks and Archival Context (SNAC_)

We also have replication arrangements with

- National Library of France
- US National Library of Medicine
- University of Edinburgh

Finally, we engage in ongoing projects and grant work with consortia of
data archives and publishers such as

- DataCite_
- Crossref_

//END//
