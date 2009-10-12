package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class ThreadCount {

    public static void main(String args[])throws FileNotFoundException, IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                  "graph_title ThreadCount\n" +
                  "graph_vlabel ThreadCount\n" +
                  "graph_info Returns the current number of live threads including both daemon and non-daemon threads.\n" +
                  "graph_category Tomcat\n" +
                  "ThreadCount.label ThreadCount"
 


);
            }
         else {
                 String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);
           try{
            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ThreadMXBean threadmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);
            
            System.out.println("ThreadCount.value "+threadmxbean.getThreadCount());


            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}
}
