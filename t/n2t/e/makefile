all: about.html ark_ids.html compact_ids.html noid.html n2t_apidoc.html partners.html suffix_passthrough.html index.html

# The makehtml.py script calls standard rst2html transformation; second arg
# is the title to stick in the <title> tag; for info on markdown used, see
# https://docutils.sourceforge.io/docs/ref/rst/directives.html with basics
# at https://docutils.sourceforge.io/docs/ref/rst/restructuredtext.html

about.html: about.rst makehtml.py
	./makehtml.py about.rst "About N2T.net"

index.html: index.rst makehtml.py
	./makehtml.py index.rst "e/..."

ark_ids.html: ark_ids.rst makehtml.py
	./makehtml.py ark_ids.rst "ARK"

compact_ids.html: compact_ids.rst makehtml.py
	./makehtml.py compact_ids.rst "Compact Identifiers"

noid.html: noid.rst makehtml.py
	./makehtml.py noid.rst "NOID"

n2t_apidoc.html: n2t_apidoc.rst makehtml.py
	./makehtml.py --date n2t_apidoc.rst "N2T API and UI"

partners.html: partners.rst makehtml.py
	./makehtml.py partners.rst "N2T partners"

suffix_passthrough.html: suffix_passthrough.rst makehtml.py
	./makehtml.py suffix_passthrough.rst "Suffix Passthrough Explained"

# *.html means homepage.html changes also get copied in
test: all
	cp -pr *.html *.txt *.pdf *.gz css fonts images \
		$(HOME)/sv/cur/apache2/htdocs/e/

# xxx placeholder
ruu:
	#cp -pr ruu.app/*.html \
	#	$(HOME)/sv/cur/apache2/htdocs/e/
	# xxx temporary kludge to test live virtual host
	egrep -v '(header|footer|breadcrumb_ark_ids).html' ark_ids.html \
		> ../ruu.app/arks.html
	#cp -pr admin/*.{pl,html} admin/form2naa \
	#	$(HOME)/sv/cur/apache2/htdocs/e/admin/
	cp -pr ../ruu.app/*.html \
		$(HOME)/sv/cur/apache2/htdocs/ruu.app/
