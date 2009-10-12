import java.io.IOException;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.Set;
import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

class GetMemoryPoolThresholdCount{
    private ArrayList<MemoryPoolMXBean> gcmbeans;
    private String[] GCresult = new String[4];
    private MBeanServerConnection connection;

   public GetMemoryPoolThresholdCount(MBeanServerConnection connection)
   { 
       this.connection = connection;
   }

    public String[] GC() throws IOException, MalformedObjectNameException {
        ObjectName gcName = null;

        gcName = new ObjectName(ManagementFactory.MEMORY_POOL_MXBEAN_DOMAIN_TYPE+",*");//GARBAGE_COLLECTOR_MXBEAN_DOMAIN_TYPE + ",*");



        Set mbeans = connection.queryNames(gcName, null);
        if (mbeans != null) {
            gcmbeans = new ArrayList<MemoryPoolMXBean>();
            Iterator iterator = mbeans.iterator();
            while (iterator.hasNext()) {
                ObjectName objName = (ObjectName) iterator.next();
                MemoryPoolMXBean gc = ManagementFactory.newPlatformMXBeanProxy(connection, objName.getCanonicalName(),
                        MemoryPoolMXBean.class);
                gcmbeans.add(gc);
            }
        }





        int i = 0;
            GCresult[i++] =gcmbeans.get(0).getCollectionUsageThresholdCount()+ "";
            GCresult[i++] = gcmbeans.get(1).getCollectionUsageThresholdCount()+ "";	
	    GCresult[i++] = gcmbeans.get(3).getCollectionUsageThresholdCount()+"";
	    GCresult[i++] = gcmbeans.get(4).getCollectionUsageThresholdCount()+"";
           //System.out.println(gcmbeans.get(memtype).getName());// denne printer Tenured Gen
           //GCresult[i++]=gcmbeans.get(memtype).getCollectionUsageThreshold()+"";

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

