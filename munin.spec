Name:      munin
Version:   2.0.2
Release:   1%{?dist}
Summary:   Network-wide graphing framework (grapher/gatherer)
License:   GPLv2 and Bitstream Vera
Group:     System Environment/Daemons
URL:       http://munin.projects.linpro.no/
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
Source: http://downloads.sourceforge.net/sourceforge/munin/%{name}-%{version}.tar.gz

%if %{?rhel}%{!?rhel:0} > 4
BuildRequires: java-1.6.0-devel
BuildRequires: mx4j
BuildRequires: jpackage-utils
%elseif %if %{?fedora}%{!?fedora:0} >= 6
BuildRequires: java-1.6.0-devel
BuildRequires: mx4j
BuildRequires: jpackage-utils
%endif

BuildArch: noarch

BuildRequires: perl-Module-Build
# needed for hostname for the defaut config
BuildRequires: net-tools
BuildRequires: perl-HTML-Template
BuildRequires: perl-Log-Log4perl
BuildRequires: perl-Net-Server
BuildRequires: perl-Net-SSLeay
BuildRequires: perl-Net-SNMP

# java buildrequires on fedora

Requires: %{name}-common = %{version}
Requires: perl-Net-Server 
Requires: perl-Net-SNMP
Requires: rrdtool
Requires: logrotate
Requires: /bin/mail
Requires(pre): shadow-utils
Requires: perl
%if %{?rhel}%{!?rhel:0} > 5
Requires: dejavu-sans-mono-fonts
%elseif %if %{?fedora}%{!?fedora:0} > 6
Requires: dejavu-sans-mono-fonts
%else
Requires: bitstream-vera-fonts
%endif

%description
Munin is a highly flexible and powerful solution used to create graphs of
virtually everything imaginable throughout your network, while still
maintaining a rattling ease of installation and configuration.

This package contains the grapher/gatherer. You will only need one instance of
it in your network. It will periodically poll all the nodes in your network
it's aware of for data, which it in turn will use to create graphs and HTML
pages, suitable for viewing with your graphical web browser of choice.

Munin is written in Perl, and relies heavily on Tobi Oetiker's excellent
RRDtool. 

%package node
Group: System Environment/Daemons
Summary: Network-wide graphing framework (node)
BuildArch: noarch
Requires: %{name}-common = %{version}
Requires: perl-Net-Server
Requires: procps >= 2.0.7
Requires: sysstat, /usr/bin/which, hdparm
Requires(pre): shadow-utils
Requires(post): /sbin/chkconfig
Requires(preun): /sbin/chkconfig
Requires(preun): /sbin/service
Requires: perl 

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
RRDtool. 

%package common
Group: System Environment/Daemons
Summary: Network-wide graphing framework (common files)
BuildArch: noarch
Requires: perl 

%description common
Munin is a highly flexible and powerful solution used to create graphs of
virtually everything imaginable throughout your network, while still
maintaining a rattling ease of installation and configuration.

This package contains common files that are used by both the server (munin)
and node (munin-node) packages. 

%if %{?rhel}%{!?rhel:0} > 4
%package java-plugins
Group: System Environment/Daemons
Summary: java-plugins for munin
Requires: %{name}-node = %{version}
BuildArch: noarch

%description java-plugins
java-plugins for munin-node. 
%elseif %{?fedora}%{!?fedora:0} > 6
%package java-plugins
Group: System Environment/Daemons
Summary: java-plugins for munin
Requires: %{name}-node = %{version}
BuildArch: noarch

%description java-plugins
java-plugins for munin-node. 
%endif

%prep
%setup -q

%build
%if %{?rhel}%{!?rhel:0} > 4
export  CLASSPATH=plugins/javalib/org/munin/plugin/jmx:$(build-classpath mx4j):$CLASSPATH
%elseif %{?fedora}%{!?fedora:0} > 6
export  CLASSPATH=plugins/javalib/org/munin/plugin/jmx:$(build-classpath mx4j):$CLASSPATH
%endif
make 	CONFIG=dists/redhat/Makefile.config

%install

## Node
make	CONFIG=dists/redhat/Makefile.config \
	PREFIX=%{buildroot}%{_prefix} \
 	DOCDIR=%{buildroot}%{_docdir}/%{name}-%{version} \
	MANDIR=%{buildroot}%{_mandir} \
	DESTDIR=%{buildroot} \
%if %{?rhel}%{!?rhel:0} > 4
	JAVALIBDIR=%{buildroot}%{_datadir}/java \
%elseif %{?fedora}%{!?fedora:0} > 6
	JAVALIBDIR=%{buildroot}%{_datadir}/java \
%endif
	install

mkdir -p %{buildroot}%{_sysconfdir}/rc.d/init.d
mkdir -p %{buildroot}%{_sysconfdir}/munin/plugins
mkdir -p %{buildroot}%{_sysconfdir}/munin/node.d
mkdir -p %{buildroot}%{_sysconfdir}/munin/plugin-conf.d
mkdir -p %{buildroot}%{_sysconfdir}/munin/conf.d
mkdir -p %{buildroot}%{_sysconfdir}/logrotate.d
mkdir -p %{buildroot}/var/lib/munin
mkdir -p %{buildroot}/var/log/munin

# 
# don't enable munin-node by default. 
#
cat dists/redhat/munin-node.rc | sed -e 's/2345/\-/' > %{buildroot}%{_sysconfdir}/rc.d/init.d/munin-node
chmod 755 %{buildroot}%{_sysconfdir}/rc.d/init.d/munin-node

install -m0644 dists/tarball/plugins.conf %{buildroot}%{_sysconfdir}/munin/plugin-conf.d/munin-node

# 
# remove the Sybase plugin for now, as they need perl modules 
# that are not in extras. We can readd them when/if those modules are added. 
#
rm -f %{buildroot}/usr/share/munin/plugins/sybase_space

## Server

mkdir -p %{buildroot}/var/www/html/munin
mkdir -p %{buildroot}/var/log/munin
mkdir -p %{buildroot}%{_sysconfdir}/cron.d
mkdir -p %{buildroot}%{_docdir}/%{name}-%{version}

install -m 0644 dists/redhat/munin.cron.d %{buildroot}%{_sysconfdir}/cron.d/munin
cp -a master/www/* %{buildroot}/var/www/html/munin/

# install config for sendmail under fedora
install -m 0644 dists/redhat/munin-1.2.4-sendmail-config %{buildroot}%{_sysconfdir}/munin/plugin-conf.d/sendmail
# install config for hddtemp_smartctl
install -m 0644 dists/redhat/munin-1.2.5-hddtemp_smartctl-config %{buildroot}%{_sysconfdir}/munin/plugin-conf.d/hddtemp_smartctl
# install logrotate scripts
install -m 0644 dists/redhat/munin-node.logrotate %{buildroot}%{_sysconfdir}/logrotate.d/munin-node
install -m 0644 dists/redhat/munin.logrotate %{buildroot}%{_sysconfdir}/logrotate.d/munin
# install config for postfix under fedora
install -m 0644 dists/redhat/munin-1.2.6-postfix-config %{buildroot}%{_sysconfdir}/munin/plugin-conf.d/postfix

# Use system font
rm -f $RPM_BUILD_ROOT/%{_datadir}/munin/DejaVuSansMono.ttf
rm -f $RPM_BUILD_ROOT/%{_datadir}/munin/DejaVuSans.ttf

%clean
rm -rf $RPM_BUILD_ROOT

#
# node package scripts
#
%pre node
getent group munin >/dev/null || groupadd -r munin
getent passwd munin >/dev/null || \
useradd -r -d /var/lib/munin -s /bin/bash \
    -c "Munin user" munin
exit 0

%post node
/sbin/chkconfig --add munin-node
# Only run configure on a new install, not an upgrade.
if [ "$1" = "1" ]; then
     /usr/sbin/munin-node-configure --shell 2> /dev/null | sh >& /dev/null || :
fi

%preun node
test "$1" != 0 || %{_initrddir}/munin-node stop &>/dev/null || :
test "$1" != 0 || /sbin/chkconfig --del munin-node

# 
# main package scripts
#
%pre
getent group munin >/dev/null || groupadd -g 786 -r munin
getent passwd munin >/dev/null || \
useradd -u 786 -r -g munin -d /var/lib/munin -s /bin/bash \
    -c "Munin user" munin
exit 0
 
%files
%defattr(-, root, root)
%doc %{_docdir}/%{name}-%{version}/
%{_bindir}/munin-cron
%{_bindir}/munindoc
%{_bindir}/munin-check
%dir %{_datadir}/munin
%{_datadir}/munin/munin-graph
%{_datadir}/munin/munin-html
%{_datadir}/munin/munin-limits
%{_datadir}/munin/munin-update
%{_datadir}/munin/munin-datafile2storable
%{_datadir}/munin/munin-storable2datafile
%{perl_vendorlib}/Munin/Master
%dir %{_sysconfdir}/munin/templates
%dir %{_sysconfdir}/munin/static
%dir %{_sysconfdir}/munin
%dir %{_sysconfdir}/munin/conf.d
%config(noreplace) %{_sysconfdir}/munin/templates/*
%config %{_sysconfdir}/munin/static/*
%config(noreplace) %{_sysconfdir}/cron.d/munin
%config(noreplace) %{_sysconfdir}/munin/munin.conf
%config(noreplace) %{_sysconfdir}/logrotate.d/munin
%attr(-, munin, munin) %dir /var/lib/munin
%attr(-, munin, munin) %dir /var/lib/munin/plugin-state
%attr(-, munin, munin) %dir /var/run/munin
%attr(-, munin, munin) %dir /var/log/munin
%attr(-, munin, munin) /var/www/html/munin
%doc %{_mandir}/man8/munin*
%doc %{_mandir}/man5/munin.conf*

%files node
%defattr(-, root, root)
%config(noreplace) %{_sysconfdir}/munin/munin-node.conf
%dir %{_sysconfdir}/munin/plugin-conf.d
%dir %{_sysconfdir}/munin/node.d
%config(noreplace) %{_sysconfdir}/munin/plugin-conf.d/munin-node
%config(noreplace) %{_sysconfdir}/munin/plugin-conf.d/sendmail
%config(noreplace) %{_sysconfdir}/munin/plugin-conf.d/hddtemp_smartctl
%config(noreplace) %{_sysconfdir}/munin/plugin-conf.d/postfix
%config(noreplace) %{_sysconfdir}/logrotate.d/munin-node
%{_sysconfdir}/rc.d/init.d/munin-node
%{_sbindir}/munin-run
%{_sbindir}/munin-node
%{_sbindir}/munin-sched
%{_sbindir}/munin-node-configure
%attr(-, munin, munin) %dir /var/log/munin
%dir %{_datadir}/munin
%dir %{_sysconfdir}/munin/plugins
%dir %{_sysconfdir}/munin
%attr(-, munin, munin) %dir /var/lib/munin
%dir %attr(-, munin, munin) /var/lib/munin/plugin-state
%{_datadir}/munin/munin-async
%{_datadir}/munin/munin-asyncd
%{_datadir}/munin/plugins/
%doc %{_docdir}/%{name}-%{version}/
%doc %{_mandir}/man5/munin-node*
%doc %{_mandir}/man3/Munin*
%doc %{_mandir}/man1/munin*
%{perl_vendorlib}/Munin/Node
%{perl_vendorlib}/Munin/Plugin*

%files common
%defattr(-, root, root)
%doc Announce-2.0 ChangeLog COPYING HACKING.pod perltidyrc README RELEASE UPGRADING
%dir %{perl_vendorlib}/Munin
%{perl_vendorlib}/Munin/Common

%if %{?rhel}%{!?rhel:0} > 4
%files java-plugins
%defattr(-, root, root)
%{_datadir}/java/%{name}-jmx-plugins.jar
%elseif %{?fedora}%{!?fedora:0} > 6
%files java-plugins
%defattr(-, root, root)
%{_datadir}/java/%{name}-jmx-plugins.jar
%endif

%changelog
* Fri Jul  6 2012 Matt West <mwest@zynga.com> - 2.0.2-1
- New upstream release

* Fri Jun  8 2012 Matt West <mwest@zynga.com> - 2.0.0-1
- New upstream release

* Thu Jun 03 2010 Ingvar Hagelund <ingvar@linpro.no> - 1.4.5-1
- New upstream relase

* Mon Mar 01 2010 Kevin Fenzi <kevin@tummy.com> - 1.4.4-1
- Update to 1.4.4
- Add more doc files. Fixes bug #563824
- fw_forwarded_local fixed upstream in 1.4.4. Fixes bug #568500

* Sun Jan 17 2010 Kevin Fenzi <kevin@tummy.com> - 1.4.3-2
- Fix owner on state files. 
- Add some BuildRequires.
- Make munin-node-configure only run on install, not upgrade. bug 540687

* Thu Dec 31 2009 Kevin Fenzi <kevin@tummy.com> - 1.4.3-1
- Update to 1.4.3

* Thu Dec 17 2009 Ingvar Hagelund <ingvar@linpro.no> - 1.4.2-1
- New upstream release
- Removed upstream packaged fonts
- Added a patch that makes rrdtool use the system bitstream vera fonts on 
rhel < 6 and fedora < 11

* Fri Dec 11 2009 Ingvar Hagelund <ingvar@linpro.no> - 1.4.1-3
- More correct fedora and el versions for previous font path fix
- Added a patch that fixes a quoting bug in GraphOld.pm, fixing fonts on el4

* Wed Dec 09 2009 Ingvar Hagelund <ingvar@linpro.no> - 1.4.1-2
- Remove jmx plugins when not supported (like on el4 and older fedora)
- Correct font path on older distros like el5, el4 and fedora<11

* Fri Dec 04 2009 Kevin Fenzi <kevin@tummy.com> - 1.4.1-1
- Update to 1.4.1

* Sat Nov 28 2009 Kevin Fenzi <kevin@tummy.com> - 1.4.0-1
- Update to final 1.4.0 version

* Sat Nov 21 2009 Kevin Fenzi <kevin@tummy.com> - 1.4.0-0.1.beta
- Update to beta 1.4.0 version. 
- Add common subpackage for common files. 

* Sun Nov 08 2009 Kevin Fenzi <kevin@tummy.com> - 1.4.0-0.1.alpha
- Initial alpha version of 1.4.0 

* Sat Jul 25 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 1.2.6-10
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Wed Feb 25 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 1.2.6-9
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Sat Jan 24 2009 Andreas Thienemann <andreas@bawue.net> - 1.2.6-8
- Updated dependencies to better reflect plugin requirements
- Added hddtemp_smartctl patch to only scan for standby state on /dev/[sh]d? devices.

* Sat Jan 17 2009 Kevin Fenzi <kevin@tummy.com> - 1.2.6-7
- Adjust font requires for new dejavu-sans-mono-fonts name (fixes #480463)

* Mon Jan 12 2009 Kevin Fenzi <kevin@tummy.com> - 1.2.6-6
- Fix to require the correct font

* Sun Jan 11 2009 Kevin Fenzi <kevin@tummy.com> - 1.2.6-5
- Switch to using dejavu-fonts instead of bitstream-vera

* Sun Jan 04 2009 Kevin Fenzi <kevin@tummy.com> - 1.2.6-4
- Require bitstream-vera-fonts-sans-mono for Font (fixes #477428)

* Mon Aug 11 2008 Kevin Fenzi <kevin@tummy.com> - 1.2.6-3
- Move Munin/Plugin.pm to the node subpackage (fixes #457403)

* Sat Jul 12 2008 Kevin Fenzi <kevin@tummy.com> - 1.2.6-2
- Apply postfix patch (fixes #454159)
- Add perl version dep and remove unneeded perl-HTML-Template (fixes #453923)

* Fri Jun 20 2008 Kevin Fenzi <kevin@tummy.com> - 1.2.6-1
- Upgrade to 1.2.6

* Tue May 20 2008 Kevin Fenzi <kevin@tummy.com> - 1.2.5-5
- Rebuild for new perl

* Wed Dec 26 2007 Kevin Fenzi <kevin@tummy.com> - 1.2.5-4
- Add patch to fix ampersand and degrees in plugins (fixes #376441)

* Fri Nov 30 2007 Kevin Fenzi <kevin@tummy.com> - 1.2.5-3
- Removed unnneeded plugins.conf file (fixes #288541)
- Fix license tag.
- Fix ip_conntrack monitoring (fixes #253192)
- Switch to new useradd guidelines.

* Tue Mar 27 2007 Kevin Fenzi <kevin@tummy.com> - 1.2.5-2
- Fix directory ownership (fixes #233886)

* Tue Oct 17 2006 Kevin Fenzi <kevin@tummy.com> - 1.2.5-1
- Update to 1.2.5
- Fix HD stats (fixes #205042)
- Add in logrotate scripts that seem to have been dropped upstream

* Sun Aug 27 2006 Kevin Fenzi <kevin@tummy.com> - 1.2.4-10
- Rebuild for fc6

* Tue Jun 27 2006 Kevin Fenzi <kevin@tummy.com> - 1.2.4-9
- Re-enable snmp plugins now that perl-Net-SNMP is available (fixes 196588)
- Thanks to Herbert Straub <herbert@linuxhacker.at> for patch. 
- Fix sendmail plugins to look in the right place for the queue

* Sat Apr 22 2006 Kevin Fenzi <kevin@tummy.com> - 1.2.4-8
- add patch to remove unneeded munin-nagios in cron. 
- add patch to remove buildhostname in munin.conf (fixes #188928)
- clean up prep section of spec. 

* Fri Feb 24 2006 Kevin Fenzi <kevin@scrye.com> - 1.2.4-7
- Remove bogus Provides for perl RRDs (fixes #182702)

* Thu Feb 16 2006 Kevin Fenzi <kevin@tummy.com> - 1.2.4-6
- Readded old changelog entries per request
- Rebuilt for fc5

* Sat Dec 24 2005 Kevin Fenzi <kevin@tummy.com> - 1.2.4-5
- Fixed ownership for /var/log/munin in node subpackage (fixes 176529)

* Wed Dec 14 2005 Kevin Fenzi <kevin@tummy.com> - 1.2.4-4
- Fixed ownership for /var/lib/munin in node subpackage

* Wed Dec 14 2005 Kevin Fenzi <kevin@tummy.com> - 1.2.4-3
- Fixed libdir messup to allow builds on x86_64

* Mon Dec 12 2005 Kevin Fenzi <kevin@tummy.com> - 1.2.4-2
- Removed plugins that require Net-SNMP and Sybase 

* Tue Dec  6 2005 Kevin Fenzi <kevin@tummy.com> - 1.2.4-1
- Inital cleanup for fedora-extras

* Thu Apr 21 2005 Ingvar Hagelund <ingvar@linpro.no> - 1.2.3-4
- Fixed a bug in the iostat plugin

* Wed Apr 20 2005 Ingvar Hagelund <ingvar@linpro.no> - 1.2.3-3
- Added the missing /var/run/munin

* Tue Apr 19 2005 Ingvar Hagelund <ingvar@linpro.no> - 1.2.3-2
- Removed a lot of unecessary perl dependencies

* Mon Apr 18 2005 Ingvar Hagelund <ingvar@linpro.no> - 1.2.3-1
- Sync with svn

* Tue Mar 22 2005 Ingvar Hagelund <ingvar@linpro.no> - 1.2.2-5
- Sync with release of 1.2.2
- Add some nice text from the suse specfile
- Minimal changes in the header
- Some cosmetic changes
- Added logrotate scripts (stolen from debian package)

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
