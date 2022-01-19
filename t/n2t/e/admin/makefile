FORM_URL= https://${EGNAPA_HOST}/e/admin/naanq2e.html
NEWFORM_URL= https://${EGNAPA_HOST}/e/admin/regupdate.html
WEBFILES= q2e.pl form2naa.pl naanq2e.html regup.pl regupdate.html regupdate.pl
PUBDIR=  $(HOME)/sv/cur/apache2/htdocs/e/admin

# This "all" target is a no-op (build_server_tree does the file copying
# that we need). This makefile really exists for the "test" target below.
all:

# This "test" target lets developers easily test web form edits
# without having to perform frequent, heavy system rollouts.
test:
	cp -pr $(WEBFILES) $(PUBDIR)/
	@echo "Visit $(FORM_URL) to test."
	@echo "NEW: Visit $(NEWFORM_URL) to test."
