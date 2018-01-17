all: n2t_apidoc.html about.html

n2t_apidoc.html: n2t_apidoc.rst makehtml.py
	./makehtml.py n2t_apidoc.rst "The N2T API and UI"

about.html: about.rst makehtml.py
	./makehtml.py about.rst "About N2T.net"
