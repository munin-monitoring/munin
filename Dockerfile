FROM bitnami/minideb:latest
RUN apt-get update
RUN apt-get install -y python-sphinx rrdtool sqlite3
COPY dev_scripts/deps /tmp/deps
RUN /tmp/deps
COPY . /munin/
RUN cd /munin && sh dev_scripts/install node
RUN cd /munin && sh dev_scripts/start_munin-node
