FROM debian:buster-slim
RUN echo 'APT::Install-Suggests "0";' > /etc/apt/apt.conf.d/99-nosuggest.conf \
	&& echo 'APT::Install-Recommends "0";' >> /etc/apt/apt.conf.d/99-nosuggest.conf
RUN echo 'deb http://deb.debian.org/debian experimental main' > /etc/apt/sources.list.d/experimental.list
RUN echo 'deb http://deb.debian.org/debian testing main' > /etc/apt/sources.list.d/testing.list
RUN printf 'Package: munin*\nPin: release a=experimental\nPin-Priority: 800' >> /etc/apt/preferences
RUN apt-get update
RUN apt-get install -y wget
#RUN apt-get install -y libdbd-pg-perl
RUN apt-get install -y libdbd-sqlite3-perl


# Install Cron
RUN apt-get install -y cron
RUN touch /var/log/cron.log

# Install Munin

RUN apt-get install -y librrds-perl
COPY dev_scripts /tmp/dev_scripts
WORKDIR /tmp
RUN sh -x dev_scripts/deps


WORKDIR /
RUN apt-get install -y make
RUN apt-get install -y rrdtool
RUN apt-get install -y sqlite3
RUN apt-get install -y sudo
RUN apt-get install -y vim
# Slimming the install
RUN apt-get clean autoclean && apt-get autoremove --yes && rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN useradd munin
RUN mkdir -p /var/run/munin /var/lib/munin && chown munin /var/run/munin /var/lib/munin

COPY .. /munin/
WORKDIR /munin
RUN make
RUN make install
RUN cp /usr/local/etc/munin/munin.conf.sample /usr/local/etc/munin/munin.conf

# Run the command on container startup
CMD cron && tail -f /var/log/cron.log
