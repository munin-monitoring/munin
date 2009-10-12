
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
public class CurrentThreadUserTime2 {

    public static void main(String args[])throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                        "graph_title CurrentThreadUserTime\n" + 
                        "graph_vlabel Nanoseconds\n" + 
			"graph_info Returns the CPU time that the current thread has executed in user mode in nanoseconds. The returned value is of nanoseconds precison but not necessarily nanoseconds accuracy.\n" +
                        "graph_category Tomcat\n" +
                        "CurrentThreadUserTime.label CurrentThreadUserTime\n" 
);
            }
         else {

                    String[] connectionInfo= ConfReader.GetConnectionInfo(args[0]);

            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" +connectionInfo[0] + ":" + connectionInfo[1] + "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);

                System.out.println("CurrentThreadUserTime.value " + threadmxbean.getCurrentThreadUserTime());

            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}


}
