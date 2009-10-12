
import java.lang.management.ManagementFactory.*;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.MemoryPoolMXBean;
import java.util.List;

public class GCmain {

    private List<MemoryPoolMXBean> pools;
    private List<GarbageCollectorMXBean> gcmbeans;

    public static void main(String args[]) {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title GarbageCollector\n" +
                        "graph_vlabel Count\n" +
                        "graph_category Tomcat\n" +
                        "graph_info The Sun JVM defines garbage collection in two modes: Minor copy collections and Major Mark-Sweep-Compact collections. A minor collection runs relatively quickly and involves moving live data around the heap in the presence of running threads. A major collection is a much more intrusive garbage collection that suspends all execution threads while it completes its task. In terms of performance tuning the heap, the primary goal is to reduce the frequency and duration of major garbage collections.\n" +
                        "CopyCount.label MinorCount\n" +
                        "CopyCount.info The total number of collections that have occurred. This method returns -1 if the collection count is undefined for this collector.\n" +
                        "CopyTime.label MinorTime\n" +
			"CopyTime.info The approximate accumulated collection elapsed time in milliseconds. This method returns -1 if the collection elapsed time is undefined for this collector.\n" +
			"MarkSweepCompactCount.label MajorCount\n" +
                        "MarkSweepCompactTime.label MajorTime\n"); 
                
                
                
            }
        } else {
               String[] connectionInfo = ConfReader.GetConnectionInfo(args[0]);

            try {

                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + connectionInfo[0] + ":" + connectionInfo[1]+ "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();

                GarbageCollector collector = new GarbageCollector(connection);
                String[][] temp = collector.GC();



                System.out.println("CopyCount.value " + temp[0][0]);
                System.out.println("CopyTime.value " + temp[0][1]);
                 System.out.println("MarkSweepCompactCount.value " + temp[1][0]);
                System.out.println("MarkSweepCompactTime.value " + temp[1][1]);



            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}




