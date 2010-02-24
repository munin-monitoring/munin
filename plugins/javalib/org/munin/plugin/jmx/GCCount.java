package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory.*;
import javax.management.MBeanServerConnection;
import java.io.FileNotFoundException;
import java.io.IOException;

public class GCCount {

    public static void main(String args[])throws FileNotFoundException,IOException {
        String[] connectionInfo = ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title JVM (port " + connectionInfo[1] + ") GarbageCollectionCount\n" +
                        "graph_vlabel count\n" +
			"graph_category " + connectionInfo[2] + "\n" +
                        "graph_info The Sun JVM defines garbage collection in two modes: Minor copy collections and Major Mark-Sweep-Compact collections. A minor collection runs relatively quickly and involves moving live data around the heap in the presence of running threads. A major collection is a much more intrusive garbage collection that suspends all execution threads while it completes its task. In terms of performance tuning the heap, the primary goal is to reduce the frequency and duration of major garbage collections.\n" +
			"CopyCount.label MinorCount\n" +
			"CopyCount.type DERIVE\n" +
			"CopyCount.min 0\n" +
			"CopyCount.info The total number of collections that have occurred. This method returns -1 if the collection count is undefined for this collector. \n" +
			"MarkSweepCompactCount.label MajorCount\n" +
			"MarkSweepCompactCount.type DERIVE\n" +
			"MarkSweepCompactCount.min 0\n" +
                        "MarkSweepCompactCount.info the total number of collections that have occurred. This method returns -1 if the collection count is undefined for this collector.\n"
                        ); 
            }
         else {
            try {

                MBeanServerConnection connection = BasicMBeanConnection.get();

                GCCountGet collector = new GCCountGet(connection);
                String[] temp = collector.GC();

                System.out.println("CopyCount.value " + temp[0]);
                System.out.println("MarkSweepCompactCount.value " + temp[1]);
            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}

}
