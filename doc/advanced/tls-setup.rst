:tocdepth: 3

.. _tls-setup:

=========
TLS Setup
=========

If your Munin installations reside in a hostile network environment, or if you just don't want anyone passing by with a network sniffer to know the CPU load of your Munin nodes, a quick solution is to enable Munin's built-in `Transport Layer Security <https://en.wikipedia.org/wiki/Transport_Layer_Security>`_ (TLS) support. Other tricks involve using :ref:`SSH tunnels <ssh-tunneling>` and key logins, methods "outside of" Munin.

Requirements
============

In order for this to work you need the Perl package ``Net::SSLEay`` available. If you are running Debian or Ubuntu this is available in the package ``libnet-ssleay-perl``.


Scenarios
=========

The test setups described below consist of two servers, *Aquarium* and *Laudanum* (the Norwegian names of two of the Roman fortifications outside the village of Asterix the Gaul). *Laudanum* is a Munin master and *Aquarium* is a Munin slave.


.. _tls-setup_non-paranoid:

Non-paranoid TLS setup
----------------------

This first setup will only provide TLS encrypted communication, not a complete verification of certificate chains. This means that the communication will be encrypted, but that anyone with a certificate, even an invalid one, will be able to talk to the node.

First of all, you must create an `X.509 <https://en.wikipedia.org/wiki/X509>`_ key and certificate pair. That is somewhat outside the scope of this howto (it should be inside the scope, if anyone is willing to include the needed openssl commands and commentary that would be good -janl), but `this link <https://security.ncsa.uiuc.edu/research/grid-howtos/usefulopenssl.php>`_ explains it in detail. On a Debian system, you can install the `ssl-cert package <https://packages.debian.org/sid/ssl-cert>`_, which automatically creates a dummy key/certificate pair, stored as ``/etc/ssl/private/ssl-cert-snakeoil.key`` and ``/etc/ssl/certs/ssl-cert-snakeoil.pem``. Please note that the permissions on the key file must be restrictive, e.g. ``chmod 700``.

Instead of creating your own CA and certificates, you may want to use :ref:`Let's Encrypt <tls-setup_letsencrypt>` instead.

On the Munin master
'''''''''''''''''''

To make :ref:`munin-update` on *Laudanum* do TLS enabled requests, add the following to :ref:`munin.conf`:

.. code::

    tls enabled
    tls_verify_certificate no
    tls_private_key /etc/ssl/private/ssl-cert-snakeoil.key
    tls_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem

And, believe it or not, that's actually it on the Munin-master side. If we run :ref:`munin-update` now, we see that the traffic is now encrypted after the command STARTTLS has been issued.

On the Munin node
'''''''''''''''''

Even though we've now asked the Munin master to perform all its requests in TLS mode, but anyone can still request data from the Munin node in plain text. So how should we restrict that? Well, that's quite simple as well! Add the following lines to :ref:`munin-node.conf`, replacing the paths to the certificate and key as appropriate for your server. Don't forget to restart the :ref:`munin-node` process afterwards.

.. code::

    tls enabled
    tls_verify_certificate no
    tls_private_key /etc/ssl/private/ssl-cert-snakeoil.key
    tls_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem

This will let munin-node accept TLS encrypted communication, but will not check the validity of the certificate presented.

Now, when we try to pump the Munin node for information without starting TLS, this is what happens:

.. code-block:: bash

    laudanum:~# telnet 192.168.1.163 4949
    Trying 192.168.1.163...
    Connected to 192.168.1.163.
    Escape character is '^]'.
    # munin node at aquarium
    list
    # I require TLS. Closing.
    Connection closed by foreign host.
    laudanum:~#


TLS configuration with complete certificate chain
-------------------------------------------------

If we switch to a stricter mode, munin-node will only accept update requests from a master presenting a certificate signed by the same CA as its own certificate.

For this setup, the tools provided with OpenSSL can be used to create a `CA (Certificate Authority) <https://en.wikipedia.org/wiki/Certificate_authority>`_ and one certificate per server signed by the same CA. Creating your own CA should be more that sufficient, unless you really want to spend money on certificates from a real CA. Remember that the "common name" of the server certificate must be the host's fully qualified domain name as it is known in DNS.

The TLS directives are the same on both master and node. This setup requires that both key/cert pairs are signed by the same CA, and the CA certificate must be distributed to each Munin node. Also note that the `passphrase protection must be removed from the keys <http://www.modssl.org/docs/2.8/ssl_faq.html#ToC31>`_ so that the :ref:`munin-update` and :ref:`munin-node` processes won't require manual intervention every time they start.

On the Munin master
'''''''''''''''''''

This extract is from :ref:`munin.conf` on the master, *Laudanum*:

.. code::

    tls paranoid
    tls_verify_certificate yes
    tls_private_key /etc/opt/munin/laudanum.key.pem
    tls_certificate /etc/opt/munin/laudanum.crt.pem
    tls_ca_certificate /etc/opt/munin/cacert.pem
    tls_verify_depth 5


On the Munin node
'''''''''''''''''

This extract is from :ref:`munin-node.conf` on the node, *Aquarium*:

.. code::

    tls paranoid
    tls_verify_certificate yes
    tls_private_key /etc/opt/munin/aquarium.key.pem
    tls_certificate /etc/opt/munin/aquarium.crt.pem
    tls_ca_certificate /etc/opt/munin/cacert.pem
    tls_verify_depth 5


What to expect in the logs
''''''''''''''''''''''''''

Note that log contents have been formatted for readability.

In munin-update.log (in versions above 1.4.4, the TLS lines only show up in debug mode):

.. code::

    Starting munin-update
    Processing domain: aquarium
    Processing node: aquarium
    Processed node: aquarium (0.05 sec)
    Processed domain: aquarium (0.05 sec)
    [TLS] TLS enabled.
    [TLS] Cipher `AES256-SHA'.
    [TLS] client cert:
        Subject Name: /C=NO/ST=Oslo/O=Example/CN=aquarium.example.com/emailAddress=bjorn@example.com\n
        Issuer  Name: /C=NO/ST=Oslo/O=Example/CN=CA master/emailAddress=bjorn@example.com
    Configured node: aquarium (0.07 sec)
    Fetched node: aquarium (0.00 sec)
    connection from aquarium -> aquarium (31405)
    connection from aquarium -> aquarium (31405) closed
    Munin-update finished (0.14 sec)

In munin-node.log, something like will show up (in versions above 1.4.4, the TLS lines only show up in debug mode):

.. code::

    CONNECT TCP Peer: "192.168.1.161:2104" Local: "192.168.1.163:4949"
    TLS Notice: TLS enabled.
    TLS Notice: Cipher `AES256-SHA'.
    TLS Notice: client cert:
        Subject Name: /C=NO/ST=Oslo/O=Example/CN=laudanum.example.com/emailAddress=bjorn@example.com\n
        Issuer  Name: /C=NO/ST=Oslo/O=Example/CN=CA master/emailAddress=bjorn@example.com


Miscellaneous
=============

Intermediate Certificates / Certificate Chains
----------------------------------------------

It is common that external Certificate Authorities use a multi-layer certification process, e.g. the root certificate signs an `intermediate certificate <https://en.wikipedia.org/wiki/Public_key_certificate#Intermediate_certificate>`_, which is used for signing the client or server certificates.

In this case you should assemble the TLS related files in the following way:

* ``tls_certificate``:
    1. the *leaf* certificate (for the client or server)
* ``tls_ca_certificate``:
    1. intermediate certificate
    2. root certificate


Selective TLS
-------------

If you want to run munin-node on the Munin master server, you shouldn't need to enable TLS for that connection as one can usually trust localhost connections. Likewise, if some of the nodes are on a trusted network they probably won't need TLS. In Munin, TLS is enabled on a per node basis.

The node definitions in :ref:`munin.conf` on *Laudanum* looks like this (``tls disabled`` for localhost communication):

.. code-block:: ini

    [Group;laudanum]
    address 127.0.0.1
    use_node_name yes
    tls disabled

    [Group;aquarium]
    address 192.168.1.163
    use_node_name yes

From the source code, it seems you can even use different certificates for different hosts. This, however, has not been tested for the purpose of this article.


.. _tls-setup_letsencrypt:

Let's Encrypt
-------------

You may want to use certificates from the `Let's Encrypt CA <https://letsencrypt.org/>`_. Technically they work fine. But please note, that you will not be able to restrict access to specific peers. Instead all users of *Let's Encrypt* will be able to connect to your nodes and your nodes will be unable to distinguish between *your* master and *any other* master connecting with a certificate from the CA.

Thus by using certificates from *Let's Encrypt* you are following a :ref:`non-paranoid <tls-setup_non-paranoid>` approach.
