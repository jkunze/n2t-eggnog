.. role:: hl1
.. role:: hl2
.. role:: ext-icon

.. |lArr| unicode:: U+021D0 .. leftwards double arrow
.. |rArr| unicode:: U+021D2 .. rightwards double arrow
.. |X| unicode:: U+02713 .. check mark

.. _joint N2T/Identifiers.org prefix list: /e/cdl_ebi_prefixes.yaml
.. _full set of N2T prefix records: /e/n2t_full_prefixes.yaml
.. _On the road to robust data citation: https://doi.org/10.1038/sdata.2018.95
.. _add a prefix: /e/prefix_request
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
.. _Memorandum of Understanding Between CDL and EMBL-EBI: https://n2t.net/ark:/13030/c7bn9x29q
.. _Uniform Resolution of Compact Identifiers for Biomedical Data: https://doi.org/10.1038/sdata.2018.95
.. _Prefix Commons: https://prefixcommons.org
.. _SNAC: http://snaccooperative.org
.. _NIH: http://www.nih.gov
.. _Force11: https://www.force11.org/

.. _n2t: https://n2t.net
.. _Identifier Basics: https://ezid.cdlib.org/learn/id_basics
.. _Identifier Conventions: https://ezid.cdlib.org/learn/id_concepts

//BEGIN//

.. |br| raw:: html

   <br />

Compact Identifiers
===================

.. parsed-literal::

 **Examples**                         **PDB**:2gc4
                                **Taxon**:9606
                                  **DOI**:10.5281/ZENODO.1289856
                                  **ark**:/47881/m6g15z54
				 **IGSN**:SSH000SUA

 **General format**                *Prefix*:*LocalId*

 **Registry links**      -> `full set of N2T prefix records`_
                     -> `joint N2T/Identifiers.org prefix list`_
                     -> request to `add a prefix`_ to the list
 **Early adoption**      -> Nature Scientic Data: `On the road to robust data citation`_
 **Formal support**      -> `Memorandum of Understanding Between CDL and EMBL-EBI`_

How they work
=============

N2T.net is a kind of URL shortener for persistent identifiers. The above
*compact identifiers* become actionable when appended to a URL based at
N2T.net::

 https://n2t.net/PDB:2gc4
 https://n2t.net/Taxon:9606
 https://n2t.net/DOI:10.5281/ZENODO.1289856
 https://n2t.net/ark:/47881/m6g15z54
 https://n2t.net/IGSN:SSH000SUA

Besides storing and resolving individual identifiers, N2T.net also stores
resolution rules for entire classes, based on the prefixes. Failing to find
a match after looking up an individual identifier, N2T looks for a rule
associated with the identifier's prefix. Rules for the above identifiers
result in the following redirects, respectively::

 > http://www.rcsb.org/pdb/explore/explore.do?structureId=2gc4
 > http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=9606
 > https://zenodo.org/record/1289856
 > http://bibnum.univ-lyon1.fr/nuxeo/nxfile/default/49e1576c-0cae-4b4b-a63b-73370f476681/blobholder:0/THm_2014_NGUYEN_Marie_France.pdf
 > https://app.geosamples.org/sample/igsn/SSH000SUA

There is a formal agreement between Identifiers.org and N2T.net to serve a
common set of prefixes. You can read more about this effort and our plans to
reach out to publishers to encourage adoption of inline citation of compact
identifiers in `Uniform Resolution of Compact Identifiers for Biomedical
Data`_.

//END//
