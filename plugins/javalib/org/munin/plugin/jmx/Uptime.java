package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.RuntimeMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class Uptime {

    public static void main(String args[])throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
		"graph_title Uptime\n" +
		"graph_vlabel Days\n" +
		"graph_info Uptime of the Java virtual machine in days.\n" +
		"graph_category jvm\n" +
		"Uptime.label Uptime");
            }
         else {

                  String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);

            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                RuntimeMXBean osmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.RUNTIME_MXBEAN_NAME, RuntimeMXBean.class);

                System.out.println("Uptime.value " + osmxbean.getUptime()/(1000*60*60*24));

            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}

}
