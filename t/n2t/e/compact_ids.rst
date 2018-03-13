.. role:: hl1
.. role:: hl2
.. role:: ext-icon

.. |lArr| unicode:: U+021D0 .. leftwards double arrow
.. |rArr| unicode:: U+021D2 .. rightwards double arrow
.. |X| unicode:: U+02713 .. check mark

.. _EZID: https://ezid.cdlib.org
.. _ARK: /e/ark_ids.html
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

.. _n2t: https://n2t.net
.. _Identifier Basics: https://ezid.cdlib.org/learn/id_basics
.. _Identifier Conventions: https://ezid.cdlib.org/learn/id_concepts

//BEGIN//

Compact Prefixed Identifiers
============================

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
serve a common set of over 600 identifier schemes (or prefixes).

A *scheme* is represented by the characters after "n2t.net/" and before the
colon, which, in the examples, are `pdb`, `taxon`, and `ark`.  This work and
our plans to reach out to publishers to encourage adoption of inline citation
of compact identifiers is described in `Uniform Resolution of Compact
Identifiers for Biomedical Data`_.

//END//
