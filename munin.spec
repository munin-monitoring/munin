Name:      munin
Version:   2.0
Release:   1%{?dist}
Summary:   Network-wide graphing framework (grapher/gatherer)
License:   GPLv2 and Bitstream Vera
Group:     System Environment/Daemons
URL:       http://munin.projects.linpro.no/

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

#Source0: http://downloads.sourceforge.net/sourceforge/munin/%{name}-%{version}.tar.gz
Source0: %{name}-%{version}.tar.gz

Source1: munin-1.2.4-sendmail-config
Source2: munin-1.2.5-hddtemp_smartctl-config
Source3: munin-node.logrotate
Source4: munin.logrotate
Source6: munin-1.2.6-postfix-config

BuildArchitectures: noarch

BuildRequires: perl-Module-Build
# needed for hostname for the defaut config
BuildRequires: net-tools
BuildRequires: perl-HTML-Template
BuildRequires: perl-Log-Log4perl
BuildRequires: perl-Net-Server
BuildRequires: perl-Net-SSLeay
BuildRequires: perl-Net-SNMP

# java buildrequires on fedora
%if 0%{?rhel} > 4 || 0%{?fedora} > 6 
BuildRequires: java-1.6.0-devel
BuildRequires: mx4j
BuildRequires: jpackage-utils
%endif

Requires: %{name}-common = %{version}
Requires: perl-Net-Server 
Requires: perl-Net-SNMP
Requires: rrdtool
Requires: logrotate
Requires: /bin/mail
Requires(pre): shadow-utils
Requires: perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
%if 0%{?rhel} > 5 || 0%{?fedora} > 6
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
BuildArchitectures: noarch
Requires: %{name}-common = %{version}
Requires: perl-Net-Server
Requires: procps >= 2.0.7
Requires: sysstat, /usr/bin/which, hdparm
Requires(pre): shadow-utils
Requires(post): /sbin/chkconfig
Requires(preun): /sbin/chkconfig
Requires(preun): /sbin/service
Requires: perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

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
BuildArchitectures: noarch
Requires: perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description common
Munin is a highly flexible and powerful solution used to create graphs of
virtually everything imaginable throughout your network, while still
maintaining a rattling ease of installation and configuration.

This package contains common files that are used by both the server (munin)
and node (munin-node) packages. 

%if 0%{?rhel} > 4 || 0%{?fedora} > 6
%package java-plugins
Group: System Environment/Daemons
Summary: java-plugins for munin
Requires: %{name}-node = %{version}
BuildArchitectures: noarch

%description java-plugins
java-plugins for munin-node. 
%endif

%prep
%setup -q

%build
%if 0%{?rhel} > 4 || 0%{?fedora} > 6
export  CLASSPATH=plugins/javalib/org/munin/plugin/jmx:$(build-classpath mx4j):$CLASSPATH
%endif
make 	CONFIG=dists/redhat/Makefile.config

%install

## Node
make	CONFIG=dists/redhat/Makefile.config \
%if 0%{?rhel} > 4 || 0%{?fedora} > 6
	JAVALIBDIR=%{buildroot}%{_datadir}/java \
%endif
	PREFIX=%{buildroot}%{_prefix} \
 	DOCDIR=%{buildroot}%{_docdir}/%{name}-%{version} \
	MANDIR=%{buildroot}%{_mandir} \
	DESTDIR=%{buildroot} \
	install

mkdir -p %{buildroot}/etc/rc.d/init.d
mkdir -p %{buildroot}/etc/munin/plugins
mkdir -p %{buildroot}/etc/munin/node.d
mkdir -p %{buildroot}/etc/munin/plugin-conf.d
mkdir -p %{buildroot}/etc/munin/conf.d
mkdir -p %{buildroot}/etc/logrotate.d
mkdir -p %{buildroot}/var/lib/munin
mkdir -p %{buildroot}/var/log/munin

# 
# don't enable munin-node by default. 
#
cat dists/redhat/munin-node.rc | sed -e 's/2345/\-/' > %{buildroot}/etc/rc.d/init.d/munin-node
chmod 755 %{buildroot}/etc/rc.d/init.d/munin-node

install -m0644 dists/tarball/plugins.conf %{buildroot}/etc/munin/plugin-conf.d/munin-node

# 
# remove the Sybase plugin for now, as they need perl modules 
# that are not in extras. We can readd them when/if those modules are added. 
#
rm -f %{buildroot}/usr/share/munin/plugins/sybase_space

## Server

mkdir -p %{buildroot}/var/www/html/munin
mkdir -p %{buildroot}/var/log/munin
mkdir -p %{buildroot}/etc/cron.d
mkdir -p %{buildroot}%{_docdir}/%{name}-%{version}

install -m 0644 dists/redhat/munin.cron.d %{buildroot}/etc/cron.d/munin
cp -a master/www/* %{buildroot}/var/www/html/munin/

# install config for sendmail under fedora
install -m 0644 %{SOURCE1} %{buildroot}/etc/munin/plugin-conf.d/sendmail
# install config for hddtemp_smartctl
install -m 0644 %{SOURCE2} %{buildroot}/etc/munin/plugin-conf.d/hddtemp_smartctl
# install logrotate scripts
install -m 0644 %{SOURCE3} %{buildroot}/etc/logrotate.d/munin-node
install -m 0644 %{SOURCE4} %{buildroot}/etc/logrotate.d/munin
# install config for postfix under fedora
install -m 0644 %{SOURCE6} %{buildroot}/etc/munin/plugin-conf.d/postfix

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
#%{_datadir}/munin/munin-graph
%{_datadir}/munin/munin-html
%{_datadir}/munin/munin-limits
%{_datadir}/munin/munin-update
%{_datadir}/munin/munin-datafile2storable
%{_datadir}/munin/munin-storable2datafile
%{perl_vendorlib}/Munin/Master
%dir /etc/munin/templates
%dir /etc/munin/static
%dir /etc/munin
%dir /etc/munin/conf.d
%config(noreplace) /etc/munin/templates/*
%config /etc/munin/static/*
%config(noreplace) /etc/cron.d/munin
%config(noreplace) /etc/munin/munin.conf
%config(noreplace) /etc/logrotate.d/munin
%attr(-, munin, munin) %dir /var/lib/munin
%attr(-, munin, munin) %dir /var/lib/munin/plugin-state
%attr(-, munin, munin) %dir /var/run/munin
%attr(-, munin, munin) %dir /var/log/munin
%attr(-, munin, munin) /var/www/html/munin
%doc %{_mandir}/man8/munin*
%doc %{_mandir}/man5/munin.conf*

%files node
%defattr(-, root, root)
%config(noreplace) /etc/munin/munin-node.conf
%dir /etc/munin/plugin-conf.d
%dir /etc/munin/node.d
%config(noreplace) /etc/munin/plugin-conf.d/munin-node
%config(noreplace) /etc/munin/plugin-conf.d/sendmail
%config(noreplace) /etc/munin/plugin-conf.d/hddtemp_smartctl
%config(noreplace) /etc/munin/plugin-conf.d/postfix
%config(noreplace) /etc/logrotate.d/munin-node
/etc/rc.d/init.d/munin-node
%{_sbindir}/munin-run
%{_sbindir}/munin-node
%{_sbindir}/munin-sched
%{_sbindir}/munin-node-configure
%attr(-, munin, munin) %dir /var/log/munin
%dir %{_datadir}/munin
%dir /etc/munin/plugins
%dir /etc/munin
%attr(-, munin, munin) %dir /var/lib/munin
%dir %attr(-, munin, munin) /var/lib/munin/plugin-state
%{_datadir}/munin/munin-async-client
%{_datadir}/munin/munin-async-server
%{_datadir}/munin/plugins/
%doc %{_docdir}/%{name}-%{version}/
%doc %{_mandir}/man5/munin-node*
%doc %{_mandir}/man3/Munin*
%doc %{_mandir}/man1/munin*
%{perl_vendorlib}/Munin/Node
%{perl_vendorlib}/Munin/Plugin*

%files common
%defattr(-, root, root)
%doc Announce-1.4.0 ChangeLog COPYING HACKING.pod perltidyrc README RELEASE UPGRADING
%dir %{perl_vendorlib}/Munin
%{perl_vendorlib}/Munin/Common

%if 0%{?rhel} > 4 || 0%{?fedora} > 6
%files java-plugins
%defattr(-, root, root)
%{_datadir}/java/%{name}-jmx-plugins.jar
%endif

%changelog
* Fri Jul 29 2011  - 2.0-1
- new package for 2.0

