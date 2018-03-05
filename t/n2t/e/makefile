all: about.html n2t_apidoc.html partners.html compact_ids.html

about.html: about.rst makehtml.py
	./makehtml.py about.rst "About N2T.net"

n2t_apidoc.html: n2t_apidoc.rst makehtml.py
	./makehtml.py --date n2t_apidoc.rst "N2T API and UI"

partners.html: partners.rst makehtml.py
	./makehtml.py partners.rst "N2T partners"

compact_ids.html: compact_ids.rst makehtml.py
	./makehtml.py compact_ids.rst "Compact prefixed identifiers at N2T.net"

test:
	cp -p *.html $(HOME)/sv/cur/apache2/htdocs/e/
