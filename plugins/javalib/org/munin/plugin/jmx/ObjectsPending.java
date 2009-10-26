package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class ObjectsPending {

    public static void main(String args[])throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                       "graph_title ObjectsPending\n" +
                       "graph_vlabel Objects\n" +
                       "graph_category jvm\n" +   
                       "Objects.info  The approximate number of objects for which finalization is pending.\n" +  
                       "Objects.label Objects\n" 

);
            }
         else {

        String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);
          try {


            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c = JMXConnectorFactory.connect(u);
            MBeanServerConnection connection = c.getMBeanServerConnection();

         MemoryMXBean mbean = ManagementFactory.newPlatformMXBeanProxy(connection,ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class);

            System.out.println("Objects.value " + mbean.getObjectPendingFinalizationCount());

 } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}

}
