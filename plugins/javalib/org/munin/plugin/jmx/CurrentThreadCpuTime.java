package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import java.io.FileNotFoundException;
import java.io.IOException;
public class CurrentThreadCpuTime {

    public static void main(String args[])throws FileNotFoundException,IOException {
        String[] connectionInfo= ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("" +
                        "graph_title JVM (port " + connectionInfo[1] + ") CurrentThreadCpuTime\n" + 
                        "graph_vlabel ns\n" + 
			"graph_category " + connectionInfo[2] + "\n" +
                        "graph_info Returns the total CPU time for the current thread in nanoseconds. The returned value is of nanoseconds precison but not necessarily nanoseconds accuracy. If the implementation distinguishes between user mode time and system mode time, the returned CPU time is the amount of time that the current thread has executed in user mode or system mode.\n" +
                        "CurrentThreadCpuTime.label CurrentThreadCpuTime\n");
            }
         else {

            try {
                MBeanServerConnection connection = BasicMBeanConnection.get();
                ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);

                System.out.println("CurrentThreadCpuTime.value " + threadmxbean.getCurrentThreadCpuTime());

            } catch (Exception e) {
                System.out.print(e);
            }
        }

    }
}

}
