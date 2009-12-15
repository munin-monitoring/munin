package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import java.io.FileNotFoundException;
import java.io.IOException;
public class Threads {

    public static void main(String args[])throws FileNotFoundException, IOException {
        String[] connectionInfo = ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
                  "graph_title JVM (port " + connectionInfo[1] + ") Threads\n" +
                  "graph_vlabel threads\n" +
		  "graph_category " + connectionInfo[2] + "\n" +
                  "graph_info Returns the current number of live threads including both daemon and non-daemon threads.\n" +
                  "Threads.label Threads"
		);
            }
         else {
           try{
            MBeanServerConnection connection = BasicMBeanConnection.get();
            ThreadMXBean threadmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);
            
            System.out.println("Threads.value "+threadmxbean.getThreadCount());

            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}
}
