package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.OperatingSystemMXBean;
import javax.management.MBeanServerConnection;

public class ProcessorsAvailable  {

    public static void main(String args[]) {
        String[] connectionInfo= ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title JVM (port " + connectionInfo[1] + ") ProcessorsAvailable\n" +
		"graph_vlabel processors\n" +
		"graph_category " + connectionInfo[2] + "\n" +
		"graph_info Returns the number of processors available to the Java virtual machine. This value may change during a particular invocation of the virtual machine.\n" +
		"ProcessorsAvailable.label ProcessorsAvailable");
            }
        else {
            try {
                MBeanServerConnection connection = BasicMBeanConnection.get();
                OperatingSystemMXBean osmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.OPERATING_SYSTEM_MXBEAN_NAME, OperatingSystemMXBean.class);

                System.out.println("ProcessorsAvailable.value " + osmxbean.getAvailableProcessors());

            } catch (Exception e) {
                System.out.print(e);
            }
        }
}
}
}
