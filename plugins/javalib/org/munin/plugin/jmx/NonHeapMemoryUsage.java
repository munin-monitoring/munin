package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class NonHeapMemoryUsage {

    public static void main(String args[])throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                       "graph_title NonHeapMemoryUsage\n" +
                       "graph_args --base 1024 -l 0 --vertical-label Bytes\n" +
                       "graph_category jvm\n" +   
                       "Committed.info The amount of memory (in bytes) that is guaranteed to be available for use by the Java virtual machine.\n" +  
                       "Committed.label Committed\n" +
                       "Max.info The maximum amount of memory (in bytes) that can be used for memory management.\n" +
                       "Max.label Max\n" +
                       "Max.draw AREA\n" +
                       "Max.colour ccff00\n" +
                       "Init.info  The initial amount of memory (in bytes) that the Java virtual machine requests from the operating system for memory management during startup.\n" +
                       "Init.label Init\n" + 
                       "Used.info  represents the amount of memory currently used (in bytes).\n" +          
                       "Used.label Used\n" 
                );
            }
         else {
        String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);
          try {


            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c = JMXConnectorFactory.connect(u);
            MBeanServerConnection connection = c.getMBeanServerConnection();

         MemoryMXBean mbean = ManagementFactory.newPlatformMXBeanProxy(connection,ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class);

            System.out.println("Committed.value " + mbean.getNonHeapMemoryUsage().getCommitted());
            System.out.println("Max.value " + mbean.getNonHeapMemoryUsage().getMax());
            System.out.println("Init.value " + mbean.getNonHeapMemoryUsage().getInit());
            System.out.println("Used.value " + mbean.getNonHeapMemoryUsage().getUsed());

            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}

}
