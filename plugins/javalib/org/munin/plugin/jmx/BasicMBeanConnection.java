package org.munin.plugin.jmx;
import javax.management.remote.JMXServiceURL;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import java.io.IOException;
import java.net.MalformedURLException;

/* Inherit from this if you need another method for jboss/glassfish/etc */

public class BasicMBeanConnection {

    public static MBeanServerConnection get() throws IOException, MalformedURLException
    {
        String[] connectionInfo = ConfReader.GetConnectionInfo();

        JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
        JMXConnector c=JMXConnectorFactory.connect(u);
        MBeanServerConnection connection=c.getMBeanServerConnection();
        return (connection);
    }
}

