package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.util.ArrayList;
import java.util.Set;

import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

class GetUsageThresholdCount {
	private ArrayList<MemoryPoolMXBean> gcmbeans;
	private String[] GCresult = new String[2];
	private MBeanServerConnection connection;

	public GetUsageThresholdCount(MBeanServerConnection connection) {
		this.connection = connection;
	}

	public String[] GC() throws IOException, MalformedObjectNameException {
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

		try {
			GCresult[0] = gcmbeans.get(0).getUsageThresholdCount() + "";
		} catch (UnsupportedOperationException u) {
			GCresult[0] = "U";
		}

		try {
			GCresult[1] = gcmbeans.get(1).getUsageThresholdCount() + "";
		} catch (UnsupportedOperationException u) {
			GCresult[1] = "U";
		}

		return GCresult;
	}
}
