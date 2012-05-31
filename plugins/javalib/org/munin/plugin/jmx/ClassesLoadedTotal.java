package org.munin.plugin.jmx;
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class ClassesLoadedTotal {

    public static void main(String args[]) throws FileNotFoundException, IOException {
        String[] connectionInfo = ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                   "graph_title JVM (port " + connectionInfo[1] + ") ClassesLoadedTotal\n" +
                   "graph_vlabel classes\n" +
		   "graph_category " + connectionInfo[2] + "\n" +
                   "graph_info The total number of classes that have been loaded since the Java virtual machine has started execution. \n" +
                   "ClassesLoadedTotal.label ClassesLoadedTotal\n" 
                    );
            }
         else {
          try{
            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ClassLoadingMXBean classmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.CLASS_LOADING_MXBEAN_NAME, ClassLoadingMXBean.class);
            
            System.out.println("ClassesLoadedTotal.value "+classmxbean.getTotalLoadedClassCount());

            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}
}
