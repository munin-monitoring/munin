SUBJECT_CA = /C=MU/ST=Province of Munin/L=Munin Town/O=Munin Inc./OU=CA/CN=127.0.0.1/emailAddress=munin@example.org/
SUBJECT_MASTER = /C=MU/ST=Province of Munin/L=Munin Town/O=Munin Inc./OU=Master/CN=127.0.0.1/emailAddress=munin@example.org/
SUBJECT_NODE = /C=MU/ST=Province of Munin/L=Munin Town/O=Munin Inc./OU=Node/CN=127.0.0.1/emailAddress=munin@example.org/


.PHONY: all clean

all:
	mkdir CA
	mkdir CA/newcerts CA/private 
	touch CA/index.txt
	echo '01' > CA/serial
	openssl req -new -nodes -x509 -extensions v3_ca -subj "$(SUBJECT_CA)" -keyout CA/private/ca_key.pem -out CA/ca_cert.pem -days 3650 -config ./openssl.cnf
	openssl req -new -nodes -subj "$(SUBJECT_NODE)" -keyout node_key.pem -out node_req.pem -config ./openssl.cnf
	openssl req -new -nodes -subj "$(SUBJECT_MASTER)" -keyout master_key.pem -out master_req.pem -config ./openssl.cnf
	yes | openssl ca -out node_cert.pem -in node_req.pem -config ./openssl.cnf -days 3650
	yes | openssl ca -out master_cert.pem -in master_req.pem -config ./openssl.cnf -days 3650

clean:
	rm -r CA
	rm *.pem
