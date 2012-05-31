package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.util.ArrayList;
import java.util.Set;

import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

class GetMemoryPoolThresholdCount {
	private ArrayList<MemoryPoolMXBean> gcmbeans;
	private long[] GCresult = new long[4];
	private MBeanServerConnection connection;

	public GetMemoryPoolThresholdCount(MBeanServerConnection connection) {
		this.connection = connection;
	}

	public long[] GC() throws IOException, MalformedObjectNameException {
		ObjectName gcName = null;

		gcName = new ObjectName(
				ManagementFactory.MEMORY_POOL_MXBEAN_DOMAIN_TYPE + ",*");

		Set<ObjectName> mbeans = connection.queryNames(gcName, null);
		if (mbeans != null) {
			gcmbeans = new ArrayList<MemoryPoolMXBean>();
			for (ObjectName objName : mbeans) {
				MemoryPoolMXBean gc = ManagementFactory.newPlatformMXBeanProxy(
						connection, objName.getCanonicalName(),
						MemoryPoolMXBean.class);
				gcmbeans.add(gc);
			}
		}

		int i = 0;
		GCresult[i++] = gcmbeans.get(0).getCollectionUsageThresholdCount();
		GCresult[i++] = gcmbeans.get(1).getCollectionUsageThresholdCount();
		GCresult[i++] = gcmbeans.get(3).getCollectionUsageThresholdCount();
		GCresult[i++] = gcmbeans.get(4).getCollectionUsageThresholdCount();

		return GCresult;
	}
}
