package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.OperatingSystemMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;



public class AvailableProcessors  {

    public static void main(String args[]) {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title AvailableProcessors\n" +
		"graph_vlabel Number of used processors\n" +
		"graph_info Returns the number of processors available to the Java virtual machine. This value may change during a particular invocation of the virtual machine.\n" +
		"graph_category Tomcat\n" +
		"AvailableProcessors.label AvailableProcessors");
            }
 }
        else {


            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + args[0] + ":" + args[1]+ "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                OperatingSystemMXBean osmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.OPERATING_SYSTEM_MXBEAN_NAME, OperatingSystemMXBean.class);

                System.out.println("AvailableProcessors.value " + osmxbean.getAvailableProcessors());

            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}

