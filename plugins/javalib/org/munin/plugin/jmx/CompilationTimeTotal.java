package org.munin.plugin.jmx;
/**
 *
 * @author Diyar
 */
import java.lang.management.ManagementFactory;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.lang.management.CompilationMXBean;
import java.io.FileNotFoundException;
import java.io.IOException;
public class CompilationTimeTotal {

    public static void main(String args[])throws FileNotFoundException, IOException {
        String[] connectionInfo = ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title JVM (port " + connectionInfo[1] + ") CompilationTimeTotal\n" +
			           "graph_vlabel ms\n" +
	       	                   "graph_info value does not indicate the level of performance of the Java virtual machine and is not intended for performance comparisons of different virtual machine implementations. The implementations may have different definitions and different measurements of the compilation time.\n" +
				   "graph_category " + connectionInfo[2] + "\n" +
                                   "CompilationTimeTotal.label CompilationTimeTotal\n" +
                                   "CompilationTimeTotal.info The approximate accumlated elapsed time (in milliseconds) spent in compilation. If multiple threads are used for compilation, this value is summation of the approximate time that each thread spent in compilation." ); 
            }
         else {
            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                CompilationMXBean osmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.COMPILATION_MXBEAN_NAME, CompilationMXBean.class);

                System.out.println("CompilationTimeTotal.value " + osmxbean.getTotalCompilationTime() );

            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}
}
