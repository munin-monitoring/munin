package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.ArrayList;
import java.util.Set;

import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

class GCTimeGet {

	private ArrayList<GarbageCollectorMXBean> gcmbeans;
	private String[] GCresult = new String[2];
	private MBeanServerConnection connection;

	public GCTimeGet(MBeanServerConnection connection) {
		this.connection = connection;
	}

	public String[] GC() throws IOException, MalformedObjectNameException {
		ObjectName gcName = null;

		gcName = new ObjectName(
				ManagementFactory.GARBAGE_COLLECTOR_MXBEAN_DOMAIN_TYPE + ",*");

		Set<ObjectName> mbeans = connection.queryNames(gcName, null);
		if (mbeans != null) {
			gcmbeans = new ArrayList<GarbageCollectorMXBean>();
			for (ObjectName objName : mbeans) {
				GarbageCollectorMXBean gc = ManagementFactory
						.newPlatformMXBeanProxy(connection, objName
								.getCanonicalName(),
								GarbageCollectorMXBean.class);
				gcmbeans.add(gc);
			}
		}

		int i = 0;

		for (GarbageCollectorMXBean gc : gcmbeans) {
			GCresult[i++] = formatMillis(gc.getCollectionTime());
		}
		
		return GCresult;
	}

	private String formatMillis(long ms) {
		return String.format("%.4f", ms / (double) 1000);
	}
}
