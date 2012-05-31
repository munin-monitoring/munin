package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;

public class ThreadsDeadlocked  {

    public static void main(String args[]) {
        String[] connectionInfo= ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title JVM (port " + connectionInfo[1] + ") ThreadsDeadlocked\n" +
		"graph_vlabel threads\n" +
		"graph_category " + connectionInfo[2] + "\n" +
		"graph_info Returns the number of deadlocked threads for the JVM.\n" +
		"ThreadsDeadlocked.label ThreadsDeadlocked");
            }
        else {
            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" +connectionInfo[0] + ":" + connectionInfo[1] + "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                ThreadMXBean mxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);

                System.out.print("ThreadsDeadlocked.value ");
		
		if(mxbean.findMonitorDeadlockedThreads() == null)
			System.out.println("0");
		else
			System.out.println(mxbean.findMonitorDeadlockedThreads().length + "");

            } catch (Exception e) {
                System.out.print(e);
            }
    }
}
}
}

