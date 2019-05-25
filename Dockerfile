FROM debian:stretch-slim
RUN echo 'APT::Install-Suggests "0";' > /etc/apt/apt.conf.d/99-nosuggest.conf \
	&& echo 'APT::Install-Recommends "0";' >> /etc/apt/apt.conf.d/99-nosuggest.conf
#RUN echo 'deb http://deb.debian.org/debian experimental main' > /etc/apt/sources.list.d/experimental.list
#RUN echo 'deb http://deb.debian.org/debian testing main' > /etc/apt/sources.list.d/testing.list
#RUN printf 'Package: munin*\nPin: release a=experimental\nPin-Priority: 800' >> /etc/apt/preferences
RUN apt-get update
RUN apt-get install -y wget
#RUN apt-get install -y libdbd-pg-perl
RUN apt-get install -y libdbd-sqlite3-perl


# Install Cron
RUN apt-get install -y cron
RUN touch /var/log/cron.log

# Install Munin

RUN apt-get install -y librrds-perl

WORKDIR /
RUN apt-get install -y make
RUN apt-get install -y rrdtool
RUN apt-get install -y sqlite3
RUN apt-get install -y sudo
RUN apt-get install -y vim
RUN apt-get install -y git
RUN apt-get install -y strace ltrace
RUN apt-get install -y procps
RUN apt-get install -y procps

RUN apt-get install -y procps libdbd-pg-perl libdbd-sqlite3-perl libdbi-perl libdevel-cover-perl libdevel-nytprof-perl libfile-copy-recursive-perl libfile-readbackwards-perl libfile-slurp-perl libhtml-template-perl libhtml-template-pro-perl libhttp-server-simple-perl libio-socket-inet6-perl libio-stringy-perl liblist-moreutils-perl liblog-dispatch-perl libmodule-build-perl libnet-dns-perl libnet-ip-perl libnet-server-perl libnet-snmp-perl libnet-ssleay-perl libparallel-forkmanager-perl libparams-validate-perl librrds-perl libtest-class-perl libtest-deep-perl libtest-differences-perl libtest-longstring-perl libtest-mockmodule-perl libtest-mockobject-perl libtest-perl-critic-perl liburi-perl libwww-perl libxml-dumper-perl libxml-libxml-perl libxml-parser-perl python3-sphinx rrdtool rrdcached sqlite3 wget

# Slimming the install
#RUN apt-get clean autoclean && apt-get autoremove --yes && rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN useradd munin -G sudo -p '$6$F9v4FpTZ$FkyF0eM21Ua2OPe.7ADETMSqt/H9/qlAxAInYw7OXilqUXwh3VWWdxgz45SmUgc7uynCsYfP7yGEclp.JJXug0'

RUN mkdir -p /var/run/munin /var/lib/munin && chown munin /var/run/munin /var/lib/munin

# Install Munin Deps
WORKDIR /tmp
COPY dev_scripts/deps /tmp/deps
RUN sh -x deps
WORKDIR /

COPY . /munin
COPY RELEASE.docker /munin/RELEASE
RUN chown -R munin /munin
USER munin
WORKDIR /munin
RUN dev_scripts/install node
RUN rm sandbox/etc/munin-conf.d/node.ipv6.sandbox.local.conf
RUN for i in $(seq 1 10); do printf "[ipv4-$i.sandbox.local]\naddress localhost\nport 4947\n" > sandbox/etc/munin-conf.d/node.ipv4_$i.sandbox.local.conf; done
