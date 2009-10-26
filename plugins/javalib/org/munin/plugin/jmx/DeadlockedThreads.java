package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;



public class DeadlockedThreads  {

    public static void main(String args[]) {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title DeadlockedThreads\n" +
		"graph_vlabel count\n" +
		"graph_info Returns the number of deadlocked threads for the JVM.\n" +
		"graph_category jvm\n" +
		"DeadlockedThreads.label DeadlockedThreads");
            }
 }
        else {


            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + args[0] + ":" + args[1]+ "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                ThreadMXBean mxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);

	
                System.out.print("DeadlockedThreads.value ");
		
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

