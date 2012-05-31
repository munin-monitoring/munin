Name:      lrrd
Version:   0.9.8
Release:   4
Copyright: GPL
BuildRoot: %{_tmppath}/%{name}-%{version}-root
URL:       http://www.linpro.no/
Source:    %{name}-%{version}.tar.gz
Group:     System Environment/Daemons
Summary:   Linpro RRD data agent

%description
see -client and -server.

%package client
Group: System Environment/Daemons
Summary: Linpro RRD data agent
BuildArchitectures: noarch
Requires: perl-Net-Server
#Requires: perl-Config-General
Requires: procps >= 2.0.7
Requires: sysstat

%description client
The Linpro RRD client returns statistical data on the request of a
Linpro RRD server.

%package server
Summary: Linpro RRD data collector and grapher
Group: System Environment/Daemons
BuildArchitectures: noarch
Provides: perl(RRDs)
Requires: perl-Config-General
Requires: perl-HTML-Template
Requires: perl-Net-Server
Requires: rrdtool

%description server
The Linpro RRD server queries a number of clients, and processes the data
using RRDtool and presents it on web pages.
%prep
%setup -q
mkdir -p %{buildroot}

%build

# htmldoc and html2text are not available for Red Hat. Quick hack with perl:
# Skip the PDFs.
perl -pi -e 's,htmldoc lrrd,cat lrrd, or s,html(2text|doc),# $&,' Makefile
make 	clean
make 	CONFIG=dists/redhat/Makefile.config \
	build

%install

## Client
make 	CONFIG=dists/redhat/Makefile.config \
	DOCDIR=%{buildroot}/%{_docdir}/lrrd \
	MANDIR=%{buildroot}/%{_mandir} \
	DESTDIR=%{buildroot} \
    	install-client install-client-plugins install-doc install-man

mkdir -p %{buildroot}/etc/init.d
mkdir -p %{buildroot}/etc/lrrd/client.d
mkdir -p %{buildroot}/var/lib/lrrd
mkdir -p %{buildroot}/var/log/lrrd

install -m 0755 client/redhat/lrrd-client %{buildroot}/etc/init.d/
install -m 0644 client/plugins.conf %{buildroot}/etc/lrrd/

## Server

make 	CONFIG=dists/redhat/Makefile.config \
	DESTDIR=%{buildroot} \
	install-server

# cf=%{buildroot}/etc/lrrd/server.conf; sed 's,/var/www/lrrd,/var/www/html/lrrd,g' < $cf > $cf.patch && mv $cf.patch $cf

mkdir -p %{buildroot}/var/www/html/lrrd
mkdir -p %{buildroot}/var/log/lrrd
mkdir -p %{buildroot}/etc/cron.d
# silly RPM triggers want to make debug enabled libraries.  let it try.
mkdir -p %{buildroot}/usr/lib/debug

install -m 0755 dists/debian/lrrd-server.cron.d %{buildroot}/etc/cron.d/lrrd-server
install -m 0644 server/lrrd-htaccess %{buildroot}/var/www/html/lrrd/.htaccess
install -m 0755 server/style.css %{buildroot}/var/www/html/lrrd/


%clean
[ -n "%{buildroot}" -a "%{buildroot}" != / ] && rm -rf %{buildroot}
 
%pre client
getent group lrrd >/dev/null || groupadd -r lrrd

%post client
chmod -R g+w /var/lib/lrrd/
if [ $1 = 1 ]
then
	/sbin/chkconfig --add lrrd-client
	/usr/sbin/lrrd-client-configure --shell | sh
fi

%preun client
if [ $1 = 0 ]
then
	/sbin/chkconfig --del lrrd-client
	rmdir /var/log/lrrd 2>/dev/null || echo " "
fi

%pre server
getent passwd lrrd >/dev/null || useradd -r -d /var/lib/lrrd lrrd

%post server
chown -R lrrd /var/www/html/lrrd

%postun server
if [ $1 = 0 ]
then
	userdel lrrd
fi

%files server
%defattr(-, root, root)
%doc %{_docdir}/lrrd/README.api
%doc %{_docdir}/lrrd/README.config
%doc %{_docdir}/lrrd/README.plugins
%{_bindir}/lrrd-cron
%{_datadir}/lrrd/lrrd-graph
%{_datadir}/lrrd/lrrd-html
%{_datadir}/lrrd/lrrd-nagios
%{_datadir}/lrrd/lrrd-update
%{_libdir}/perl5/*perl/5.*/LRRD.pm
%dir /etc/lrrd/templates
/etc/lrrd/templates/*
/etc/cron.d/lrrd-server
%config /etc/lrrd/server.conf
%attr(-, lrrd, root) %dir /var/lib/lrrd
%attr(-, lrrd, root) %dir /var/log/lrrd
%attr(-, lrrd, root) %dir /var/www/html/lrrd
%attr(-, lrrd, root) /var/www/html/lrrd/style.css
%config /var/www/html/lrrd/.htaccess
%doc %{_mandir}/man8/lrrd-graph*
%doc %{_mandir}/man8/lrrd-update*
%doc %{_mandir}/man8/lrrd-nagios*
%doc %{_mandir}/man8/lrrd-html*
%doc %{_mandir}/man8/lrrd-cron*
%doc %{_mandir}/man5/server.conf*

%files client
%defattr(-, root, root)
%config /etc/lrrd/client.conf
%config /etc/lrrd/plugins.conf
%config /etc/init.d/lrrd-client
%{_sbindir}/lrrd-run
%{_sbindir}/lrrd-client
%{_sbindir}/lrrd-client-configure
%dir /var/log/lrrd
%dir %{_datadir}/lrrd
%dir /etc/lrrd/client.d
%dir /var/lib/lrrd
%dir %attr(-, root, lrrd) /var/lib/lrrd/plugin-state
%{_datadir}/lrrd/plugins/*
%doc %{_docdir}/lrrd/lrrd-doc.html
%doc %{_docdir}/lrrd/lrrd-faq.html
%doc %{_mandir}/man8/lrrd-run*
%doc %{_mandir}/man8/lrrd-client*
%doc %{_mandir}/man5/client.conf*

%changelog
* Fri Oct 31 2003 Ingvar Hagelund <ingvar@linpro.no>
- Lot of small fixes. Now builds on more RPM distros
* Wed May 21 2003 Ingvar Hagelund <ingvar@linpro.no>
- Sync with CVS
- 0.9.5-1
* Tue Apr  1 2003 Ingvar Hagelund <ingvar@linpro.no>
- Sync with CVS
- Makefile-based install of core files
- Build doc (only pod2man)
* Thu Jan  9 2003 Ingvar Hagelund <ingvar@linpro.no>
- Sync with CVS, auto rpmbuild
* Thu Jan  2 2003 Ingvar Hagelund <ingvar@linpro.no>
- Fix spec file for RedHat 8.0 and new version of lrrd
* Wed Sep  4 2002 Ingvar Hagelund <ingvar@linpro.no>
- Small bugfixes in the rpm package
* Tue Jun 18 2002 Kjetil Torgrim Homme <kjetilho@linpro.no>
- new package


