#
# Maintainer: GONG Jie <gongjie@linux.vnet.ibm.com>
#

SRC_RPM = grub2-2.02-0.16.xcat.src.rpm
SPEC_TEMPLATE = grub2-xcat.spec.template

BUILD_NUMBER_FILE = build-number.txt

build: rpm

rpm: grub2-xcat.noarch.rpm
deb: grub2-xcat.all.deb

grub2.ppc64.rpm: $(SRC_RPM)
	rpmbuild --rebuild $^ 2>&1 | tee rpmbuild.out
	ln -sf $$(awk '/Wrote: .*\/grub2-[0-9].*\.rpm/ { print $$NF }' rpmbuild.out) \
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
	touch timestamp.grub2.mknetdir

grub2-xcat.spec: $(SPEC_TEMPLATE) $(BUILD_NUMBER_FILE) timestamp.grub2.mknetdir
	umask 0022
	( cd grub2-xcat ; find tftpboot -type d -exec echo '%dir "/{}"' ';' ) >filelist
	( cd grub2-xcat ; find tftpboot -type f -exec echo '"/{}"' ';' ) >>filelist
	cat $(SPEC_TEMPLATE) | sed -e \
		's@###<<<BUILD>>>###@build'$$(cat $(BUILD_NUMBER_FILE))'.xcat@g' \
		-e '/%files/ r filelist' >$@
	$(RM) filelist

grub2-xcat.noarch.rpm: grub2-xcat.spec timestamp.grub2.mknetdir
	umask 0022
	mkdir -p grub2-xcat-repack
	( cd grub2-xcat ; tar cf - . ) | ( cd grub2-xcat-repack ; tar xf - )
	( cd grub2-xcat-repack ; rpmbuild -bb ../grub2-xcat.spec --buildroot=`pwd` ) 2>&1 | \
		tee rpmbuild.out.2
	ln -sf $$(awk -F '/' '/Wrote: .*\/grub2-xcat-[0-9].*\.rpm/ { print $$NF }' \
		rpmbuild.out.2) grub2-xcat.noarch.rpm

grub2-xcat.all.deb: grub2-xcat.noarch.rpm
	alien -d -c -k $^ 2>&1 | tee alien.out
	ln -sf $$(awk '/grub2-xcat_.*_all.deb generated/ { print $$1 }' \
		alien.out) grub2-xcat.all.deb

$(BUILD_NUMBER_FILE): $(SPEC_TEMPLATE) $(BINARY_RPM)
	@if ! test -f $(BUILD_NUMBER_FILE); then echo 0 > $(BUILD_NUMBER_FILE); fi
	@echo $$(($$(cat $(BUILD_NUMBER_FILE)) + 1)) > $(BUILD_NUMBER_FILE)

clean:
	$(RM) rpmbuild.out grub2.ppc64.rpm
	$(RM) -r timestamp.extract grub2
	$(RM) -r timestamp.grub2.mknetdir grub2-xcat
	$(RM) -r grub2-xcat.spec filelist
	$(RM) -r grub2-xcat-repack rpmbuild.out.2
	$(RM) grub2-xcat-*.noarch.rpm grub2-xcat.noarch.rpm
	$(RM) alien.out
	$(RM) grub2-xcat_*_all.deb grub2-xcat.all.deb

.PHONY: build clean rpm
