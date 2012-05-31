package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory;
import java.lang.management.RuntimeMXBean;
import javax.management.MBeanServerConnection;
import java.io.FileNotFoundException;
import java.io.IOException;
public class Uptime {

    private static final double MILLISECONDS_PER_DAY = 1000*60*60*24;

    public static void main(String args[])throws FileNotFoundException,IOException {
	String[] connectionInfo = ConfReader.GetConnectionInfo();
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println(
		"graph_title JVM (port " + connectionInfo[1] + ") Uptime\n" +
		"graph_vlabel Days\n" +
		"graph_info Uptime of the Java virtual machine in days.\n" +
		"graph_category " + connectionInfo[2] + "\n" +
		"Uptime.label Uptime");
            }
         else {
            try {
                MBeanServerConnection connection = BasicMBeanConnection.get();
                RuntimeMXBean osmxbean = ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.RUNTIME_MXBEAN_NAME, RuntimeMXBean.class);

                System.out.println("Uptime.value " + osmxbean.getUptime()/MILLISECONDS_PER_DAY);

            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}

}
