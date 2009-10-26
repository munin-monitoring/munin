package org.munin.plugin.jmx;
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class CurrentThreadCpuTime {

    public static void main(String args[])throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("" +
                        "graph_title CurrentThreadCpuTime\n" +
                        "graph_vlabel Nanoseconds\n" +
                        "graph_info Returns the total CPU time for the current thread in nanoseconds. The returned value is of nanoseconds precison but not necessarily nanoseconds accuracy. If the implementation distinguishes between user mode time and system mode time, the returned CPU time is the amount of time that the current thread has executed in user mode or system mode.\n" +
                        "graph_category jvm\n" +
                        "CurrentThreadCpuTime.label CurrentThreadCpuTime\n");
            }
         else {

                    String[] connectionInfo= ConfReader.GetConnectionInfo();

            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" +connectionInfo[0] + ":" + connectionInfo[1] + "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);

                System.out.println("CurrentThreadCpuTime.value " + threadmxbean.getCurrentThreadCpuTime());

            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}

}
