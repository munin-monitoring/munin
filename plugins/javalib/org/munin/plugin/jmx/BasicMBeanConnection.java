package org.munin.plugin.jmx;
import java.io.IOException;
import java.net.MalformedURLException;
import java.util.Map;

import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;

/* Inherit from this if you need another method for jboss/glassfish/etc */

public class BasicMBeanConnection {

    public static MBeanServerConnection get(Config config) throws IOException, MalformedURLException
    {
		JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + config.getIp() + ":" + config.getPort()+ "/jmxrmi");
        Map<String, Object> credentials = config.getConnectionCredentials();
        JMXConnector c=JMXConnectorFactory.connect(u,credentials);
        MBeanServerConnection connection=c.getMBeanServerConnection();
        return (connection);
    }
}

