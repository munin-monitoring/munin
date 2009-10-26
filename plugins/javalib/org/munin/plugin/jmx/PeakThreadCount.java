package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class PeakThreadCount {

    public static void main(String args[])throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                   "graph_title PeakThreadCount\n" + 
                   "graph_vlabel PeakThreadCount\n" +
                   "graph_info Returns the peak live thread count since the Java virtual machine started or peak was reset.\n" +
                   "graph_category jvm\n" +
                   "PeakThreadCount.label PeakThreadCount" 


);
            }
         else {
               String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);

           try{
            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ThreadMXBean threadmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);
            
            System.out.println("PeakThreadCount.value "+threadmxbean.getPeakThreadCount());


            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}


}
