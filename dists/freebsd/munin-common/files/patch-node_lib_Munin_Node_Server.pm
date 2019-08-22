Backporting: https://github.com/munin-monitoring/munin/commit/8ff5d5a9ec8b7ffd99dce61fee42defe7bda3b29
See also: http://munin-monitoring.org/ticket/1451

--- node/lib/Munin/Node/Server.pm.orig	2018-12-19 20:56:49 UTC
+++ node/lib/Munin/Node/Server.pm
@@ -340,7 +340,7 @@ sub _print_service {
 sub _list_services {
     my ($session, $node) = @_;
 
-    $node ||= $config->{fqdn};
+    $node ||= lc($config->{fqdn});
 
     if (exists $nodes{$node}) {
         my @services = @{$nodes{$node}};
