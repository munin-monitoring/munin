package org.munin.plugin.jmx;
/**
 *
 * @author Diyar
 */
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
public class ThreadsDaemon
{
    public static void main(String args[])throws FileNotFoundException,IOException
    {
         String[] connectionInfo= ConfReader.GetConnectionInfo();

         if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                        "graph_title JVM (port " + connectionInfo[1] + ") ThreadsDaemon\n" +
                        "graph_vlabel threads\n" +
			"graph_category " + connectionInfo[2] + "\n" +
                        "graph_info Returns the current number of live daemon threads.\n" +  
                        "ThreadsDaemon.label ThreadsDaemon\n"
		);
            }
         else {
        try{
            JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" +connectionInfo[0] + ":" + connectionInfo[1] + "/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ThreadMXBean threadmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);
            
            System.out.println("ThreadsDaemon.value "+threadmxbean.getDaemonThreadCount());
            
        }
        catch(Exception e)
        {
            System.out.print(e);
        }
    }

}
}
}
