package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory.*;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.lang.management.MemoryPoolMXBean;
import java.io.FileNotFoundException;
import java.io.IOException;
public class CollectionUsagePermGen {


    public static void main(String args[]) throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title CollectionUsagePermGen\n" +
                        "graph_vlabel Bytes\n" +
                        "graph_category Tomcat\n" +
                        "graph_info Contains reflective data of the JVM itself, including class and memory objects\n" +
                        "Comitted.label Comitted\n" +
                        "Comitted.info The amount of memory (in bytes) that is guaranteed to be available for use by the Java virtual machine.\n" +
		        "Max.label Max\n" +
                        "Max.info The maximum amount of memory (in bytes) that can be used for memory management. \n" +
                        "Max.draw AREA\n" +
			"Init.label Init\n" +
                        "Init.info The initial amount of memory (in bytes) that the Java virtual machine requests from the operating system for memory management during startup.\n" +
			"Used.label Used\n" +
                        "Used.info represents the amount of memory currently used (in bytes).\n" +
			"Threshold.label Threshold\n" +
                        "Threshold.info The usage threshold value of this memory pool in bytes. The default value is zero.\n"
                        );



            }
         else {
                    String[] connectionInfo= ConfReader.GetConnectionInfo(args[0]);


            try {

                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" +connectionInfo[0] + ":" + connectionInfo[1] + "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();


                GetCollectionUsage collector = new GetCollectionUsage(connection, 1);
                String[] temp = collector.GC();



                System.out.println("Comitted.value " + temp[0]);
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
