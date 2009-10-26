package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class TotalStartedThreadCount {

    public static void main(String args[]) throws FileNotFoundException, IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                  "graph_info Returns the total number of threads created and also started since the Java virtual machine started. \n" +
                  "graph_title TotalStartedThreadCount\n" +
                  "graph_vlabel TotalStartedThreadCount\n" +
                  "graph_category jvm\n" +
                  "TotalStartedThreadCount.label TotalStartedThreadCount"

          
             
                    );
            }
         else {
                    String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);
        try{
            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ThreadMXBean threadmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);

            System.out.println("TotalStartedThreadCount.value "+threadmxbean.getTotalStartedThreadCount());




            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}
}
