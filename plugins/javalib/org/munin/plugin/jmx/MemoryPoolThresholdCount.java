package org.munin.plugin.jmx;
import java.lang.management.ManagementFactory.*;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.lang.management.MemoryPoolMXBean;
import java.io.FileNotFoundException;
import java.io.IOException;
public class MemoryPoolThresholdCount {


    public static void main(String args[])throws FileNotFoundException,IOException {
        if (args.length == 1) {
            if (args[0].equals("config")) {
                System.out.println("graph_title MemoryPoolThreshold\n" +
                        "graph_vlabel Bytes\n" +
                        "graph_category Tomcat\n" +
                        "graph_info Returns the number of times that the Java virtual machine has detected that the memory usage has reached or exceeded the collection usage threshold.\n" +
                        "TenuredGen.label TenuredGen\n" +
                        "TenuredGen.info Thresholdcount for Tenured Gen \n" +
                        "PermGen.label PermGen\n" +
                        "PermGen.info ThresholdCount for Perm Gen\n" +
			"Eden.label Eden\n" +
                        "Eden.info Thresholdcount for Eden.\n" +
                        "Survivor.label Survivor\n" +
                        "Survivor.info ThresholdCount for Survivor." 
                        );



            }
         else {
                    String[] connectionInfo= ConfReader.GetConnectionInfo(args[0]);


            try {
                JMXServiceURL u = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" +connectionInfo[0] + ":" + connectionInfo[1] + "/jmxrmi");
                JMXConnector c = JMXConnectorFactory.connect(u);
                MBeanServerConnection connection = c.getMBeanServerConnection();
                GetMemoryPoolThresholdCount collector = new GetMemoryPoolThresholdCount(connection);
                String[] temp = collector.GC();


                
                System.out.println("Survivor.value "+temp[3]);
                System.out.println("TenuredGen.value " + temp[0]);
                System.out.println("PermGen.value " + temp[1]);
                System.out.println("Eden.value "+temp[2]);



            } catch (Exception e) {
                System.out.print(e);
            }
        }
    }
}
}
