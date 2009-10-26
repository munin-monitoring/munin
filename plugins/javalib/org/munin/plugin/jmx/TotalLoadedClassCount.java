package org.munin.plugin.jmx;
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class TotalLoadedClassCount {

    public static void main(String args[]) throws FileNotFoundException, IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                   "graph_info The total number of classes that have been loaded since the Java virtual machine has started execution. \n" +
                   "graph_title TotalLoadedClassCount\n" +
                   "graph_vlabel TotalLoadedClassCount\n" +
                   "graph_category jvm\n" +    
                   "TotalLoadedClassCount.label TotalLoadedClassCount\n" 
          
             
                    );
            }
         else {
                  String[] connectionInfo = ConfReader.GetConnectionInfo();
          try{
            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ClassLoadingMXBean classmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.CLASS_LOADING_MXBEAN_NAME, ClassLoadingMXBean.class);
            
            System.out.println("TotalLoadedClassCount.value "+classmxbean.getTotalLoadedClassCount());


            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}
}
