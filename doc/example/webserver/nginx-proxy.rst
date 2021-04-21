.. _example-webserver-nginx-proxy:

===========================
 Nginx Proxy Configuration
===========================

You can use `nginx as a proxy`_ in front of :ref:`munin-httpd`.

This enables you to add `transport layer security`_ and
`http authentication`_ (not included in this example).


Site Configuration
==================

.. index::
   triple: example; munin-httpd; nginx configuration

::

    location /munin/static/ {
        alias /etc/munin/static/;
    }

    location /munin/ {
        proxy_pass http://localhost:4948/;
    }


.. _`nginx as a proxy`:
   http://nginx.org/en/docs/http/ngx_http_proxy_module.html

.. _`transport layer security`:
   http://nginx.org/en/docs/http/configuring_https_servers.html

.. _`http authentication`:
   http://nginx.org/en/docs/http/ngx_http_auth_basic_module.html
