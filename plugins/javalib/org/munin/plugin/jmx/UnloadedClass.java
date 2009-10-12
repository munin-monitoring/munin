import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.FileNotFoundException;
import java.io.IOException;
public class UnloadedClass {

    public static void main(String args[]) throws FileNotFoundException, IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                 
                  "graph_info The total number of classes unloaded since the Java virtual machine has started execution.\n" +  
		  "graph_title UnloadedClass\n" +
                  "graph_vlabel UnloadedClass\n" + 
                  "graph_category Tomcat\n" +
                  "UnloadedClass.label UnloadedClass\n" 

          
             
                    );
            }
         else {

                   String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);
        try{
            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ClassLoadingMXBean classmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.CLASS_LOADING_MXBEAN_NAME, ClassLoadingMXBean.class);
            
            System.out.println("UnloadedClass.value "+classmxbean.getUnloadedClassCount());



            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}
}
