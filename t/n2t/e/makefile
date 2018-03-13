all: about.html ark_ids.html compact_ids.html n2t_apidoc.html partners.html

about.html: about.rst makehtml.py
	./makehtml.py about.rst "About N2T.net"

ark_ids.html: ark_ids.rst makehtml.py
	./makehtml.py ark_ids.rst "ARK"

n2t_apidoc.html: n2t_apidoc.rst makehtml.py
	./makehtml.py --date n2t_apidoc.rst "N2T API and UI"

partners.html: partners.rst makehtml.py
	./makehtml.py partners.rst "N2T partners"

compact_ids.html: compact_ids.rst makehtml.py
	./makehtml.py compact_ids.rst "Compact prefixed identifiers at N2T.net"

test: all
	cp -pr *.html *.txt *.pdf css fonts images \
		$(HOME)/sv/cur/apache2/htdocs/e/
