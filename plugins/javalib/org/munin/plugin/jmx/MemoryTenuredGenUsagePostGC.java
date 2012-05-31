package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory.*;
import javax.management.MBeanServerConnection;
import java.io.FileNotFoundException;
import java.io.IOException;
public class MemoryTenuredGenUsagePostGC {

    public static void main(String args[])throws FileNotFoundException,IOException {
        String[] connectionInfo= ConfReader.GetConnectionInfo();

        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title JVM (port " + connectionInfo[1] + ") MemoryTenuredGenUsagePostGC\n" +
                        "graph_vlabel bytes\n" +
                        "graph_category " + connectionInfo[2] + "\n" +
                        "graph_info Pool containing long-lived objects.\n" +
                        "Max.label Max\n" +
                        "Max.info The maximum amount of memory (in bytes) that can be used for memory management.\n" +
                        "Max.draw AREA\n" +
                        "Max.colour ccff00\n" +
                        "Committed.label Committed\n" +
                        "Committed.info The amount of memory (in bytes) that is guaranteed to be available for use by the Java virtual machine. \n" +
                        "Committed.draw LINE2\n" +
                        "Committed.colour 0033ff\n" +
                        "Used.label Used\n" +
                        "Used.info The amount of memory currently used (in bytes).\n" +
                        "Used.draw LINE3\n" +
                        "Used.colour 33cc00\n" +
                        "Init.label Init\n" +
                        "Init.info The initial amount of memory (in bytes) that the Java virtual machine requests from the operating system for memory management during startup.\n"+
                        "Threshold.label Threshold\n" +
                        "Threshold.info The usage threshold value of this memory pool in bytes. The default value is zero.\n"
                        );
            }
         else {
            try {
                MBeanServerConnection connection = BasicMBeanConnection.get();

                GetCollectionUsage collector = new GetCollectionUsage(connection, 0);
                String[] temp = collector.GC();

                System.out.println("Committed.value " + temp[0]);
                System.out.println("Init.value " + temp[1]);
                System.out.println("Max.value "+temp[2]);
                System.out.println("Used.value "+temp[3]);
                System.out.println("Threshold.value "+temp[4]);

            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}


}
