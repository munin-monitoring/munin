package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory.*;
import javax.management.MBeanServerConnection;
import java.io.FileNotFoundException;
import java.io.IOException;
public class GCTime {

    public static void main(String args[]) throws FileNotFoundException,IOException {
        String[] connectionInfo = ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title JVM (port " + connectionInfo[1] + ") GarbageCollectionTime\n" +
                        "graph_vlabel ms\n" +
			"graph_category " + connectionInfo[2] + "\n" +
                        "graph_info The Sun JVM defines garbage collection in two modes: Minor copy collections and Major Mark-Sweep-Compact collections. A minor collection runs relatively quickly and involves moving live data around the heap in the presence of running threads. A major collection is a much more intrusive garbage collection that suspends all execution threads while it completes its task. In terms of performance tuning the heap, the primary goal is to reduce the frequency and duration of major garbage collections.\n" +
                        "CopyTime.label MinorTime\n" +
			"CopyTime.type DERIVE\n" +
			"CopyTime.info The approximate accumulated collection elapsed time in milliseconds. This method returns -1 if the collection elapsed time is undefined for this collector.\n" +
 		        "MarkSweepCompactTime.label MajorTime\n" +
 		        "MarkSweepCompactTime.type DERIVE\n" +
                        "MarkSweepCompactTime.info The approximate accumulated collection elapsed time in milliseconds. This method returns -1 if the collection elapsed time is undefined for this collector.The Java virtual machine implementation may use a high resolution timer to measure the elapsed time. This method may return the same value even if the collection count has been incremented if the collection elapsed time is very short. \n"
                        ); 
            }
         else {

            try {
                MBeanServerConnection connection = BasicMBeanConnection.get();

                GCTimeGet collector = new GCTimeGet(connection);
                String[] temp = collector.GC();

                System.out.println("CopyTime.value " + temp[0]);
                System.out.println("MarkSweepCompactTime.value " + temp[1]);

            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}
}

