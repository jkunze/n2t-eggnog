all: about.html ark_ids.html compact_ids.html noid.html n2t_apidoc.html partners.html index.html admin/naanq2e.html

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

test: all
	# *.html means homepage.html changes also get copied in
	cp -pr *.html *.txt *.pdf *.gz css fonts images \
		$(HOME)/sv/cur/apache2/htdocs/e/
	cp -pr admin/*.html \
		$(HOME)/sv/cur/apache2/htdocs/e/admin/
