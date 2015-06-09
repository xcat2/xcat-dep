#
# Maintainer: GONG Jie <gongjie@linux.vnet.ibm.com>
#

SRC_RPM = grub2-2.02-0.16.ael7b.src.rpm
SPEC_TEMPLATE = grub2-xcat.spec.template

#BUILD_NUMBER_FILE = build-number.txt

build: rpm

rpm: grub2-xcat.noarch.rpm
deb: grub2-xcat.all.deb

grub2.ppc64.rpm: $(SRC_RPM)
	rpmbuild --rebuild $^ 2>&1 | tee rpmbuild.out
	cp -f $$(awk '/Wrote: .*\/grub2-[0-9].*\.rpm/ { print $$NF }' rpmbuild.out) \
		grub2.ppc64.rpm

timestamp.extract: grub2.ppc64.rpm
	umask 0022
	mkdir -p grub2
	rpm2cpio $^ | ( cd grub2 ; cpio -idv )
	touch timestamp.extract

timestamp.grub2.mknetdir: timestamp.extract
	umask 0022
	mkdir -p grub2-xcat/tftpboot
	grub2-mknetdir --directory=grub2/usr/lib/grub/powerpc-ieee1275 \
		--net-directory=grub2-xcat/tftpboot
	mkdir -p grub2-xcat/usr/share/doc/grub2-xcat/
	cp -f grub2/usr/share/doc/grub2-2.02/COPYING grub2-xcat/usr/share/doc/grub2-xcat/COPYING
	touch timestamp.grub2.mknetdir

#grub2-xcat.spec: $(SPEC_TEMPLATE) $(BUILD_NUMBER_FILE) timestamp.grub2.mknetdir
grub2-xcat.spec: $(SPEC_TEMPLATE)  timestamp.grub2.mknetdir
	umask 0022
	( cd grub2-xcat ; find tftpboot -type d -exec echo '%dir "/{}"' ';' ) >filelist
	( cd grub2-xcat ; find 'usr/share/doc/grub2-xcat' -type d -exec echo '%dir "/{}"' ';' ) >>filelist
	( cd grub2-xcat ; find tftpboot -type f -exec echo '"/{}"' ';' ) >>filelist
	( cd grub2-xcat ; find 'usr/share/doc/grub2-xcat' -type f -exec echo '"/{}"' ';' ) >>filelist


	cat $(SPEC_TEMPLATE) | sed -e \
		's@###<<<BUILD>>>###@snap'$$(date +"%Y%m%d%H%M")'@g' \
		-e 's@###<<<GRUB2RELEASE>>>###@'$$(rpm -qpf --qf "%{RELEASE}" $(SRC_RPM) )'@g' \
		-e 's@###<<<GRUB2VERSION>>>###@'$$(rpm -qpf --qf "%{VERSION}" $(SRC_RPM) )'@g' \
		-e 's@###<<<SRCRPM>>>###@'$$(echo $(SRC_RPM))'@g' \
		-e 's@###<<<GITHASH>>>###@'$$(git log --pretty=%h -1 ./)'@g' \
		-e '/%files/ r filelist' >$@
	$(RM) filelist

grub2-xcat.noarch.rpm: grub2-xcat.spec timestamp.grub2.mknetdir
	umask 0022
	mkdir -p grub2-xcat-repack
	( cd grub2-xcat ; tar cf - . ) | ( cd grub2-xcat-repack ; tar xf - )
	( cd grub2-xcat-repack ; rpmbuild -bb ../grub2-xcat.spec --buildroot=`pwd` ) 2>&1 | \
		tee rpmbuild.out.2
	cp -f $$(awk -F '/' '/Wrote: .*\/grub2-xcat-[0-9].*\.rpm/ { print $$NF }' \
		rpmbuild.out.2) grub2-xcat.noarch.rpm

grub2-xcat.all.deb: grub2-xcat.noarch.rpm
	LANG=C alien -d -c -k -g $^ 2>&1 | tee alien.out
	(DEBSRC=$$(awk  '/Directories .* prepared/ { print $$2 }' ./alien.out); \
         if [ -z "$$DEBSRC" ]; \
            then DEBSRC=$$(awk -F"'" '/cannot create directory .* File exists/ { print $$2 }' ./alien.out); \
         fi; \
         mv $$DEBSRC grub2-xcat-deb; \
         mv $$DEBSRC.orig grub2-xcat-deb.orig;\
         sed -i  -e 's!Homepage:.*!!'  \
         -e 's!Maintainer:.*!Maintainer:xCAT <xcat-user@lists.sourceforge.net> \nHomepage:http://xcat.sourceforge.net/!'  grub2-xcat-deb/debian/control; \
         cd grub2-xcat-deb; \
         debian/rules binary) 


#$(BUILD_NUMBER_FILE): $(SPEC_TEMPLATE) $(BINARY_RPM)
#	@if ! test -f $(BUILD_NUMBER_FILE); then echo 0 > $(BUILD_NUMBER_FILE); fi
#	@echo $$(($$(cat $(BUILD_NUMBER_FILE)) + 1)) > $(BUILD_NUMBER_FILE)

clean:
	$(RM) rpmbuild.out grub2.ppc64.rpm
	$(RM) -r timestamp.extract grub2
	$(RM) -r timestamp.grub2.mknetdir grub2-xcat
	$(RM) -r grub2-xcat.spec filelist
	$(RM) -r grub2-xcat-repack rpmbuild.out.2
	$(RM) grub2-xcat-*.noarch.rpm grub2-xcat.noarch.rpm
	$(RM) alien.out
	$(RM) -r grub2-xcat-deb grub2-xcat-deb.orig
	$(RM) grub2-xcat_*_all.deb grub2-xcat.all.deb

.PHONY: build clean deb rpm
