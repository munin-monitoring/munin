Name:		munin
Version:	1.0.2
Release:	1

Summary:	Network-wide graphing framework (grapher/gatherer)
License:	GPL
Group:		System Environment/Daemons
URL:		http://munin.sourceforge.net
Packager:	Dagfinn Ilmari Mannsaker <ilmari@linpro.no>
Vendor:		Linpro AS
Distribution:	Linpro Red Hat Software Archives
Source0:	%{name}-%{version}.tar.gz
Source1:	Makefile.config
Source2:	munin-node.rc
Source3:	munin.cron.d
Source4:	munin.logrotate
Source5:	munin-node.logrotate
Source6:	munin-node.cron.d
Patch0:		pidfilepath.patch
Patch1:		no-data-dumper.patch
BuildRoot:	%{_tmppath}/%{name}-%{version}-root
Prereq:		/sbin/chkconfig, /sbin/service
BuildArch:	noarch

%description
Munin is a highly flexible and powerful solution used to create graphs of
virtually everything imaginable throughout your network, while still
maintaining a rattling ease of installation and configuration.

This package contains the grapher/gatherer. You will only need one instance of
it in your network. It will periodically poll all the nodes in your network
it's aware of for data, which it in turn will use to create graphs and HTML
pages, suitable for viewing with your graphical web browser of choice.

It is also able to alert you if any value is outside of a preset boundary,
useful if you want to be alerted if a filesystem is about to grow full, for
instance. Currently you can only do this by letting Munin send messages to
a Nagios server.

Munin is written in Perl, and relies heavily on Tobi Oetiker's excellent
RRDtool. To see a real example of Munin in action, take a peek at
<http://www.linpro.no/projects/munin/example/>.

%package node
Group:		System Environment/Daemons
Summary:	Network-wide graphing framework (node)
BuildArch:	noarch

%description node
Munin is a highly flexible and powerful solution used to create graphs of
virtually everything imaginable throughout your network, while still
maintaining a rattling ease of installation and configuration.

This package contains node software. You should install it on all the nodes
in your network. It will know how to extract all sorts of data from the
node it runs on, and will wait for the gatherer to request this data for
further processing.

It includes a range of plugins capable of extracting common values such as
cpu usage, network usage, load average, and so on. Creating your own plugins
which are capable of extracting other system-specific values is very easy,
and is often done in a matter of minutes. You can also create plugins which
relay information from other devices in your network that can't run Munin,
such as a switch or a server running another operating system, by using
SNMP or similar technology.

Munin is written in Perl, and relies heavily on Tobi Oetiker's excellent
RRDtool. To see a real example of Munin in action, take a peek at
<http://www.linpro.no/projects/munin/example/>.

%prep
%setup -q
%patch0 -p1
%patch1 -p0
mkdir -p %{buildroot}

%build
# htmldoc and html2text are not available for Red Hat. Quick hack with perl:
# Skip the PDFs.
perl -pi -e 's,htmldoc munin,cat munin, or s,html(2text|doc),# $&,' Makefile
perl -pi -e 's,\$\(INSTALL.+\.(pdf|txt) \$\(DOCDIR,# $&,' Makefile

make 	clean
make 	CONFIG=%{SOURCE1} \
	build

%install

## Node
make 	CONFIG=%{SOURCE1} \
	DOCDIR=%{buildroot}%{_docdir}/munin \
	MANDIR=%{buildroot}%{_mandir} \
	DESTDIR=%{buildroot} \
    	install-node install-node-plugins install-doc install-man

mkdir -p %{buildroot}/var/lib/munin/plugin-state
mkdir -p %{buildroot}/var/log/munin
mkdir -p %{buildroot}/var/run/munin

install -m0644 plugins.conf %{buildroot}/etc/munin/plugin-conf.d/munin-node

# ugly hack, to prevent DBD::Sybase to become a dependency, as it's not
# available in RHEL, and doesn't easily build with cpanflute. I don't know
# enough rpm-fu to prevent it in a clean manner..
find %{buildroot}/usr/share/munin/plugins -name '*sybase*' -print0 | xargs -0 chmod -x

## Server
make 	CONFIG=%{SOURCE1} \
	DESTDIR=%{buildroot} \
	install-main

mkdir -p %{buildroot}/var/www/html/munin
mkdir -p %{buildroot}/var/log/munin
mkdir -p %{buildroot}/var/lib/munin
mkdir -p %{buildroot}/var/run/munin

mkdir -p %{buildroot}/etc/init.d
install -m0755 %{SOURCE2} %{buildroot}/etc/init.d/munin-node
mkdir -p %{buildroot}/etc/cron.d
install -m0644 %{SOURCE3} %{buildroot}/etc/cron.d/munin
install -m0644 %{SOURCE6} %{buildroot}/etc/cron.d/munin-node
mkdir -p %{buildroot}/etc/logrotate.d
install -m0644 %{SOURCE4} %{buildroot}/etc/logrotate.d/munin
install -m0644 %{SOURCE5} %{buildroot}/etc/logrotate.d/munin-node

install -m0644 ChangeLog %{buildroot}%{_docdir}/munin/ChangeLog


%clean
[ -n "%{buildroot}" -a "%{buildroot}" != / ] && rm -rf %{buildroot}
 
## Server

%pre

getent group munin >/dev/null || groupadd -r munin
getent passwd munin > /dev/null || useradd -r -d /var/lib/munin -g munin munin

%post
mkdir -p /var/log/munin
mkdir -p /var/lib/munin
chown -R munin:munin /var/www/html/munin
chown -R munin:munin /var/log/munin
chown -R munin:munin /var/run/munin
chown -R munin:munin /var/lib/munin


## Node

%pre node

getent group munin >/dev/null || groupadd -r munin
getent passwd munin > /dev/null || useradd -r -d /var/lib/munin -g munin munin

%post node
if [ $1 = 1 ]
then
	/sbin/chkconfig --add munin-node
	/usr/sbin/munin-node-configure --shell | sh
fi
mkdir -p /var/log/munin
mkdir -p /var/lib/munin/plugin-state
chown -R munin:munin /var/log/munin
chown -R munin:munin /var/lib/munin
chmod g+w /var/lib/munin/plugin-state
find /usr/share/munin/plugins -name '*sybase*' -print0 | xargs -0 chmod +x

%preun node
if [ $1 = 0 ]
then
	/sbin/service munin-node stop > /dev/null 2>&1
	/sbin/chkconfig --del munin-node
	rmdir /var/log/munin 2>/dev/null || true
fi

%files
%defattr(-, root, root)
%doc %{_docdir}/munin/README.api
%doc %{_docdir}/munin/README.plugins
%doc %{_docdir}/munin/COPYING
%doc %{_docdir}/munin/ChangeLog
%doc %{_mandir}/man8/munin-graph*
%doc %{_mandir}/man8/munin-update*
%doc %{_mandir}/man8/munin-nagios*
%doc %{_mandir}/man8/munin-html*
%doc %{_mandir}/man8/munin-cron*
%doc %{_mandir}/man5/munin.conf*
%{_bindir}/munin-cron
%{_datadir}/munin/munin-graph
%{_datadir}/munin/munin-html
%{_datadir}/munin/munin-nagios
%{_datadir}/munin/munin-update
%{_libdir}/perl5/*perl/5.*/Munin.pm
%config /etc/munin/templates/*
%config /etc/cron.d/munin
%config /etc/munin/munin.conf
%config /etc/logrotate.d/munin
%dir /var/www/html/munin
%dir /var/run/munin

%files node
%defattr(-, root, root)
%doc %{_docdir}/munin/COPYING
%doc %{_docdir}/munin/munin-doc.html
%doc %{_docdir}/munin/munin-faq.html
%doc %{_mandir}/man8/munin-run*
%doc %{_mandir}/man8/munin-node*
%doc %{_mandir}/man5/munin-node*
%{_sbindir}/munin-run
%{_sbindir}/munin-node
%{_sbindir}/munin-node-configure
%{_datadir}/munin/plugins/*
%config /etc/munin/munin-node.conf
%config /etc/munin/plugin-conf.d/munin-node
%config /etc/init.d/munin-node
%config /etc/cron.d/munin-node
%config /etc/logrotate.d/munin-node
%dir /etc/munin/plugins

%changelog
* Thu Sep 09 2004 Dagfinn Ilmari Mannsaker <ilmar@linpro.no>
- Update to version 1.0.2.
* Wed Jul 07 2004 Tore Anderson <tore@linpro.no>
- Update to version 1.0.0.
- Modify the spec file quite heavily.  Beware of ugly hax.
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
