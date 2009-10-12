
import java.io.IOException;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.Set;
import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

class GarbageCollector {

    private ArrayList<GarbageCollectorMXBean> gcmbeans;
    private String[][] GCresult = new String[2][2];
    private MBeanServerConnection connection;
    
   public GarbageCollector(MBeanServerConnection connection)
   {
       this.connection = connection;
   }
    
    public String[][] GC() throws IOException, MalformedObjectNameException {
        ObjectName gcName = null;

        gcName = new ObjectName(ManagementFactory.GARBAGE_COLLECTOR_MXBEAN_DOMAIN_TYPE + ",*");



        Set mbeans = connection.queryNames(gcName, null);
        if (mbeans != null) {
            gcmbeans = new ArrayList<GarbageCollectorMXBean>();
            Iterator iterator = mbeans.iterator();
            while (iterator.hasNext()) {
                ObjectName objName = (ObjectName) iterator.next();
                GarbageCollectorMXBean gc = ManagementFactory.newPlatformMXBeanProxy(connection, objName.getCanonicalName(),
                        GarbageCollectorMXBean.class);
                gcmbeans.add(gc);
            }
        }


  
        int i = 0;
        int j = 0;
        for (GarbageCollectorMXBean gc : gcmbeans) {
        
            GCresult[i][j++] = gc.getCollectionCount() + "";
            GCresult[i++][j--] = formatMillis(gc.getCollectionTime());
            
        }
    return GCresult;
    }

    private String formatMillis(long ms) {
        return String.format("%.4f", ms / (double) 1000);
    }

    private String formatBytes(long bytes) {
        long kb = bytes;
        if (bytes > 0) {
            kb = bytes / 1024;
        }
        return kb + "";
    }
}
