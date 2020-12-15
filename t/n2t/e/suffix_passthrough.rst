.. role:: hl1
.. role:: hl2
.. role:: ext-icon

.. |date| date::
.. |lArr| unicode:: U+021D0 .. leftwards double arrow
.. |rArr| unicode:: U+021D2 .. rightwards double arrow
.. |X| unicode:: U+02713 .. check mark
.. |sm| unicode:: U+2120 .. service mark superscript

.. _EZID: https://ezid.cdlib.org
.. _ARK: /e/ark_ids.html
.. _ARK request form: https://goo.gl/forms/bmckLSPpbzpZ5dix1
.. _ARKs FAQ: https://wiki.lyrasis.org/display/ARKs/ARK+Identifiers+FAQ
.. _DOI: https://www.doi.org
.. _EZID.cdlib.org: https://ezid.cdlib.org
.. _DataCite: https://www.datacite.org
.. _ARKs in the Open: https://wiki.lyrasis.org/display/ARKs/ARKs+in+the+Open+Project
.. _California Digital Library: https://www.cdlib.org
.. _N2T Partners: /e/partners.html
.. _N2T API Documentation: /e/n2t_apidoc.html
.. _Original N2T vision: /e/n2t_vision.html

.. _PDF version: https://n2t.net/ark:/13030/c7cv4br18
.. _TXT version: /e/arkspec.txt 
.. _Towards Electronic Persistence Using ARK Identifiers: /e/Towards_Electronic_Persistence_Using_ARK_Identifiers.pdf
.. _ARK and CDL Identifier conventions: http://ezid.cdlib.org/learn/id_concepts
.. _Archival Resource Key - Wikipedia: http://en.wikipedia.org/wiki/Archival_Resource_Key
.. _Noid (Nice Opaque Identifiers): /e/noid.html
.. _Noid: /e/noid.html
.. _ARK plugin for Omeka: https://github.com/Daniel-KM/ArkAndNoid4Omeka
.. _ARK module for Drupal: https://www.drupal.org/project/ark
.. _EZID service: https://ezid.cdlib.org
.. _N2T.net resolver: /
.. _The registry: http://www.cdlib.org/services/uc3/naan_registry.txt
.. _Identifier conventions: http://ezid.cdlib.org/learn/id_concepts

//BEGIN//

What is Suffix Passthrough?
===========================

Suffix Passthrough (SPT) is a feature that a resolver (a web server that
specializes in forwarding incoming requests) might support in order to greatly
increase the number of identifiers that it can forward. N2T.net supports this
feature for all identifiers that it stores.

SPT dramatically reduces the burden of maintaining multiple identifiers by
permitting one identifier to stand in for many. In fact there is no limit to
how many, and N2T has hundreds of stored ARKs, each one standing in for
thousands. The way it works, given a URL for a stored identifier, if it arrives
with an appended suffix, N2T will re-append it ("pass it through") to the
identifier's stored forwarding destination during resolution. Usually end
providers leverage SPT by publishing (advertizing) URLs with specific suffixes
that they know will return provider content. While less common, nothing
prevents an end user from using a provider's suffix pattern to append suffixes
that also resolve correctly.

Basically, Suffix Passthrough makes every ARK the root of its own "namespace".
Any provider-added (or user-added) suffix, which is a common way to form
sub-object identifiers, will be passed through to the stored target object.
For example, a dataset with 10,000 component parts and just this one "ancestor"
ARK, ::

 http://n2t.net/ark:/12345/x98765

would effectively allow access to 10,000 ARKs, but only require you to manage
the ancestor ARK. Those sub-object ARKs might look like: ::

 http://n2t.net/ark:/12345/x98765/study1/location1/day1.cs
 http://n2t.net/ark:/12345/x98765/study1/location3/day19.cs
  ...
 http://n2t.net/ark:/12345/x98765/study92/location18/day96.xlsx

.. image:: /e/images/learn_spt_in_action.gif
   :align: center
   :width: 80 %
   :alt: A suffix passing from the end of a submitted ARK to the end of a stored target URL.

When a user clicks on one of those ARKs, it is submitted to N2T. Failing to
find it stored, N2T scans backwards starting from the end of the
user-supplied ARK string and stops at the first ancestor ARK that is
stored.

The part that was scanned over, stretching from the first stored ancestor
ARK to the end of the original string, comprises the suffix. ::

 http://n2t.net/ark:/12345/x98765/study92/location18/day96.xlsx
 \______________________________/\____________________________/
           ancestor ARK                      suffix

Then it redirects the user's browser to the ancestor's target URL, appending
the suffix that it scanned. So if the ancestor ARK's target was, ::

 http://n2t.net/ark:/12345/x98765  -->  http://datazoo.example.com/carbon288
 \______________________________/       \__________________________________/
        ancestor ARK                          ancestor ARK's target URL

the user would be (hypothetically) redirected to ::

 http://datazoo.example.com/carbon288/study92/location18/day96.xlsx
 \__________________________________/\____________________________/
        ancestor's target URL                    suffix

Note that SPT is only useful when the target server can respond to the suffixes
it receives. For example, you would not instruct users how to add suffixes to
the above ARK unless the target server was prepared to provide access to its
10,000 sub-objects. Fortunately, SPT is easy to illustrate in some cases, such
as when the target server extends resource names with query strings or ordinary
URL paths.

**Rule:** *if identifier A has target T, suffix passthrough means the extended identifier A/X has targetT/X.*

Using more words, for an identifier A stored in N2T that has the target URL T,
if you add a suffix X to A and resolve (eg, click on) the URL A/X, you will be
redirected to the URL T/X.

Some limitations and exceptions apply. For example, during the backwards scan,
potential ancestor ARKs are tested (to see if they are stored) only at each
"word" boundary, where a word here means a string of letters and digits. Also,
scanning stops when the NAAN (the 5-digit number after the "ark:/") is reached.

Suffix Passthrough Examples
---------------------------

You can see SPT in action by clicking on the extended ARKs below. These are
"ARKs" (for illustration purposes only, not long-term stable) that are not
stored in the N2T resolver, but are formed by adding a suffix to an ARK
that is stored.

Example 1. One stored ARK standing in for several CDL service page "ARKs".

- Stored: ark:/12345/fk1234
- Its target URL: http://www.cdlib.org/services
- An extended ARK: http://n2t.net/ark:/12345/fk1234/uc3/ezid/

Example 2. One stored ARK standing in for any number of Wikipedia article "ARKs".

- Stored: ark:/12345/fk1235
- Its target URL: http://en.wikipedia.org/wiki
- An extended ARK: http://n2t.net/ark:/12345/fk1235/Persistent_identifier

Example 3. One stored ARK standing in for any number of internet search "ARKs".

- Stored: ark:/12345/fk3
- Its target URL: http://www.google.com/#q=
- Extended ARK: http://n2t.net/ark:/12345/fk3pqrst

You can experiment easily by pasting this stored ARK, ::

 http://n2t.net/ark:/12345/fk3

into your browser's location field and appending (no spaces) a "search term"
suffix of your choice.

*Last modified:* |date|

//END//
