Name:      munin
Version:   1.0.0pre3
Release:   2
Copyright: GPL
BuildRoot: %{_tmppath}/%{name}-%{version}-root
URL:       http://www.linpro.no/
Source:    %{name}-%{version}.tar.gz
Group:     System Environment/Daemons
Summary:   Munin is the Linpro RRD data agent
BuildArchitectures: noarch
Provides: perl(RRDs)
Requires: perl-Config-General
Requires: perl-HTML-Template
Requires: perl-Net-Server
Requires: rrdtool
Obsoletes: lrrd-server

%description
Munin, formerly known as The Linpro RRD server, queries a number of
nodes, and processes the data using RRDtool and presents it on web
pages.

%package node
Group: System Environment/Daemons
Summary: Linpro RRD data agent
BuildArchitectures: noarch
Requires: perl-Net-Server
#Requires: perl-Config-General
Requires: procps >= 2.0.7
Requires: sysstat
Obsoletes: lrrd-client

%description node
The Munin node package returns statistical data on the request of a
Munin server.

%prep
%setup -q
mkdir -p %{buildroot}

%build

# htmldoc and html2text are not available for Red Hat. Quick hack with perl:
# Skip the PDFs.
perl -pi -e 's,htmldoc munin,cat munin, or s,html(2text|doc),# $&,' Makefile
perl -pi -e 's,\$\(INSTALL.+\.(pdf|txt) \$\(DOCDIR,# $&,' Makefile
make 	clean
make 	CONFIG=dists/redhat/Makefile.config \
	build

%install

## Node
make 	CONFIG=dists/redhat/Makefile.config \
	DOCDIR=%{buildroot}%{_docdir}/munin \
	MANDIR=%{buildroot}%{_mandir} \
	DESTDIR=%{buildroot} \
    	install-node install-node-plugins install-doc install-man

mkdir -p %{buildroot}/etc/init.d
mkdir -p %{buildroot}/etc/munin/plugins
mkdir -p %{buildroot}/etc/munin/plugin-conf.d
mkdir -p %{buildroot}/var/lib/munin
mkdir -p %{buildroot}/var/log/munin

#install -m 0755 node/redhat/munin-node %{buildroot}/etc/init.d/
install -m0755 dists/redhat/munin-node.rc %{buildroot}/etc/init.d/munin-node
install -m 0644 dists/tarball/plugins.conf %{buildroot}/etc/munin/
install -m0644 dists/tarball/plugins.conf %{buildroot}/etc/munin/plugin-conf.d/munin-node

chmod -x %{buildroot}%{_datadir}/munin/plugins/sybase_space
## Server

make 	CONFIG=dists/redhat/Makefile.config \
	DESTDIR=%{buildroot} \
	install-main

# cf=%{buildroot}/etc/munin/munin.conf; sed 's,/var/www/munin,/var/www/html/munin,g' < $cf > $cf.patch && mv $cf.patch $cf

mkdir -p %{buildroot}/var/www/html/munin
mkdir -p %{buildroot}/var/log/munin
mkdir -p %{buildroot}/etc/cron.d
# silly RPM triggers want to make debug enabled libraries.  let it try.
mkdir -p %{buildroot}/usr/lib/debug

install -m 0755 dists/redhat/munin.cron.d %{buildroot}/etc/cron.d/munin
install -m 0644 server/munin-htaccess %{buildroot}/var/www/html/munin/.htaccess
install -m 0755 server/style.css %{buildroot}/var/www/html/munin

install -m 0644 ChangeLog %{buildroot}%{_docdir}/munin/ChangeLog


%clean
[ -n "%{buildroot}" -a "%{buildroot}" != / ] && rm -rf %{buildroot}
 
%pre node
getent group munin >/dev/null || groupadd -r munin
getent passwd munin > /dev/null || useradd -r -d /var/lib/munin -g munin munin

%post node
chmod -R g+w /var/lib/munin/
if [ $1 = 1 ]
then
	/sbin/chkconfig --add munin-node
	/usr/sbin/munin-node-configure --shell | sh
fi
chown -R munin /var/lib/munin


%preun node
if [ $1 = 0 ]
then
	/sbin/chkconfig --del munin-node
	rmdir /var/log/munin 2>/dev/null || echo " "
fi

%pre
getent group munin >/dev/null || groupadd -r munin
getent passwd munin > /dev/null || useradd -r -d /var/lib/munin -g munin munin

%post
chown -R munin /var/www/html/munin
chown -R munin /var/log/munin
chown -R munin /var/lib/munin

%postun
if [ $1 = 0 ]
then
	userdel munin
fi

%files
%defattr(-, root, root)
%doc %{_docdir}/munin/README.api
#%doc %{_docdir}/munin/README.config
%doc %{_docdir}/munin/README.plugins
%doc %{_docdir}/munin/COPYING
%doc %{_docdir}/munin/ChangeLog
%{_bindir}/munin-cron
%{_datadir}/munin/munin-graph
%{_datadir}/munin/munin-html
%{_datadir}/munin/munin-nagios
%{_datadir}/munin/munin-update
%{_libdir}/perl5/*perl/5.*/Munin.pm
%dir /etc/munin/templates
%dir /etc/munin
/etc/munin/templates/*
/etc/cron.d/munin
%config /etc/munin/munin.conf
%attr(-, munin, root) %dir /var/lib/munin
%attr(-, munin, root) %dir /var/log/munin
%attr(-, munin, root) %dir /var/www/html/munin
%attr(-, munin, root) /var/www/html/munin/style.css
%config /var/www/html/munin/.htaccess
%doc %{_mandir}/man8/munin-graph*
%doc %{_mandir}/man8/munin-update*
%doc %{_mandir}/man8/munin-nagios*
%doc %{_mandir}/man8/munin-html*
%doc %{_mandir}/man8/munin-cron*
%doc %{_mandir}/man5/munin.conf*

%files node
%defattr(-, root, root)
%config /etc/munin/munin-node.conf
%config /etc/munin/plugin-conf.d/munin-node
%config /etc/init.d/munin-node
%{_sbindir}/munin-run
%{_sbindir}/munin-node
%{_sbindir}/munin-node-configure
%dir /var/log/munin
%dir %{_datadir}/munin
%dir /etc/munin/plugins
%dir /etc/munin
%dir /var/lib/munin
%dir %attr(-, root, munin) /var/lib/munin/plugin-state
%{_datadir}/munin/plugins/*
%doc %{_docdir}/munin/COPYING
%doc %{_docdir}/munin/munin-doc.html
%doc %{_docdir}/munin/munin-faq.html
%doc %{_mandir}/man8/munin-run*
%doc %{_mandir}/man8/munin-node*
%doc %{_mandir}/man5/munin-node*
#%doc %{_mandir}/man5/node.conf*

%changelog
* Sun Feb 01 2004 Ingvar Hagelund <ingvar@linpro.no>
- Sync with CVS. Version 1.0.0pre2
* Sun Jan 18 2004 Ingvar Hagelund <ingvar@linpro.no>
- Sync with CVS. Change names to munin.
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


