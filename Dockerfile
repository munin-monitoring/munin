FROM munin:base

COPY . /munin
COPY RELEASE.docker /munin/RELEASE
RUN chown -R munin /munin
RUN mkdir -p /var/log/munin && chown -R munin /var/log/munin
USER munin
WORKDIR /munin
RUN eatmydata dev_scripts/install node
RUN rm sandbox/etc/munin-conf.d/node.ipv6.sandbox.local.conf
RUN for i in $(seq 1 10); do printf "[ipv4-$i.sandbox.local]\naddress localhost\nport 4947\n" > sandbox/etc/munin-conf.d/node.ipv4_$i.sandbox.local.conf; done
