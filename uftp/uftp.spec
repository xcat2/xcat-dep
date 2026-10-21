Name:           uftp
Version:        5.0.4
Release:        1%{?dist}
Summary:        Encrypted UDP based file transfer with multicast
License:        GPL-3.0-or-later WITH GPL-3.0-linking-source-exception
URL:            https://uftp-multicast.sourceforge.net/

# https://downloads.sourceforge.net/project/uftp-multicast/source-tar/uftp-5.0.4.tar.gz.
# SHA256SUMS holds its digest.
Source0:        uftp-%{version}.tar.gz
# Fixes to the 5.0.4 release. Drop each one when a release carries it.
Patch1:         0001-Reject-STATUS-for-a-section-the-file-does-not-have.patch
Patch2:         0002-Keep-the-client-lists-of-the-proxy-inside-the-packet.patch
Patch3:         0003-Reject-encrypted-messages-from-a-client-without-encr.patch
Patch4:         0004-Reject-FILESEG-for-a-block-the-file-does-not-have.patch
Patch5:         0005-Keep-each-received-block-inside-the-disk-cache.patch
Patch6:         0006-Reject-a-last-FILESEG-of-the-wrong-length.patch
Patch7:         0007-Reject-DONE-for-a-section-the-file-does-not-have.patch
Patch8:         0008-Reject-ANNOUNCE-with-a-block-size-the-sender-does-no.patch
Patch9:         0009-Check-every-component-of-a-file-name-for.patch
Patch10:        0010-Match-an-absolute-file-name-only-below-a-whole-D-dir.patch
Patch11:        0011-Reject-a-file-path-that-goes-through-a-symbolic-link.patch
Patch12:        0012-Reject-a-file-whose-section-count-does-not-fit.patch
Patch13:        0013-Grow-the-list-of-moved-files-as-needed.patch
Patch14:        0014-Check-the-path-of-a-file-again-before-cleanup-change.patch
Patch15:        0015-Allocate-the-whole-NAK-list-that-STATUS-sends.patch
Patch16:        0016-Leave-a-file-at-cleanup-that-another-group-replaced.patch
Patch17:        0017-Check-the-path-of-a-restart-file-before-deleting-it.patch
Patch18:        0018-Send-the-whole-NAK-list-of-a-full-section-from-the-p.patch
Patch19:        0019-Read-the-NAKs-of-a-client-STATUS-after-its-whole-hea.patch
Patch20:        0020-Check-the-path-of-a-backup-file-before-using-it.patch
Patch21:        0021-Reject-a-file-name-that-names-its-destination-direct.patch
Patch22:        0022-Keep-the-block-number-of-seek_block-unsigned.patch
Patch23:        0023-Mark-the-xCAT-build-in-the-version-string.patch

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  openssl-devel

%description
UFTP sends files to many receivers at the same time over IP multicast, and
encrypts the transfer by default. This package contains the uftp sender, the
uftpd receiver, the uftpproxyd proxy and the uftp_keymgt key tool. It
installs no service: uftpd runs only when it is started.

%prep
%autosetup -p1

%build
%set_build_flags
%make_build

%install
%make_install

%check
# Upstream has no test suite. Key generation runs the OpenSSL code that the key exchange uses.
./uftp_keymgt -g ec:secp256r1 check.key
./uftp_keymgt check.key 2>&1 | grep 'ECDSA, curve'

%files
%license LICENSE.txt
%doc ReadMe.txt Changes.txt
%{_bindir}/uftp
%{_bindir}/uftpd
%{_bindir}/uftpproxyd
%{_bindir}/uftp_keymgt
%{_mandir}/man1/uftp.1*
%{_mandir}/man1/uftpd.1*
%{_mandir}/man1/uftpproxyd.1*
%{_mandir}/man1/uftp_keymgt.1*

%changelog
* Mon Oct 19 2026 xCAT <xcat-user@lists.sourceforge.net> - 5.0.4-1
- Package UFTP 5.0.4
- Reject a STATUS for a section that the file does not have
- Keep the client lists of the proxy inside the packet buffer
- Reject encrypted messages from a client without encryption state
- Reject a FILESEG for a block that the file does not have
- Keep each received block inside the disk cache of the client
- Reject a last FILESEG of the wrong length
- Reject a DONE for a section that the file does not have
- Reject an ANNOUNCE with a block size that the sender does not accept
- Reject a file name with .. in any component
- Match an absolute file name only below a whole -D directory
- Reject a file path that goes through a symbolic link
- Reject a file whose section count does not fit
- Grow the list of moved files as needed
- Check the path of a file again before cleanup changes it
- Allocate the whole NAK list that STATUS sends
- Leave a file at cleanup that another group replaced
- Check the path of a restart file before deleting it
- Send the whole NAK list of a full section from the proxy
- Read the NAKs of a client STATUS after its whole header in the proxy
- Check the path of a backup file before using it
- Reject a file name that names its destination directory
- Keep the block number of seek_block() unsigned
- Mark the xCAT build in the version string
