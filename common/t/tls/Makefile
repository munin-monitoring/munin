
.PHONY: all clean

all:
	mkdir CA
	mkdir CA/newcerts CA/private 
	touch CA/index.txt
	echo '01' > CA/serial
	openssl req -new -nodes -x509 -extensions v3_ca -keyout CA/private/ca_key.pem -out CA/ca_cert.pem -days 3650 -config ./openssl.cnf
	openssl req -new -nodes -keyout node_key.pem -out node_req.pem -config ./openssl.cnf
	openssl req -new -nodes -keyout master_key.pem -out master_req.pem -config ./openssl.cnf
	yes | openssl ca -out node_cert.pem -in node_req.pem -config ./openssl.cnf -days 3650
	yes | openssl ca -out master_cert.pem -in master_req.pem -config ./openssl.cnf -days 3650

clean:
	rm -r CA
	rm *.pem
