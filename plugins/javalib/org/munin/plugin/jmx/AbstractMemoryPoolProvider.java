package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

public abstract class AbstractMemoryPoolProvider extends
		AbstractMemoryUsageProvider {

	protected String threshold;

	@Field(info = "The usage threshold value of this memory pool in bytes. The default value is zero.")
	public String threshold() {
		return threshold;
	}

	/**
	 * <b>WARNING:</b> using a simple integer index to select the memory pool to
	 * query here assumes a lot about the target VM and the JMX implementation
	 * and can result in effectively random results (and errors) when those
	 * assumptions are not held. In the interest of bug-for-bug compatibility
	 * with previous versions this code does <b>not</b> fix this issue.
	 */
	protected void preparePoolValues(int memtype, UsageType usageType)
			throws MalformedObjectNameException, IOException {
		MemoryPoolMXBean poolMXBean = getMemoryPoolMXBean(memtype);
		long thresholdValue;
		try {
			switch (usageType) {
			case USAGE:
				memoryUsage = poolMXBean.getUsage();
				thresholdValue = poolMXBean.getUsageThreshold();
				break;
			case POST_GC:
				memoryUsage = poolMXBean.getCollectionUsage();
				thresholdValue = poolMXBean.getCollectionUsageThreshold();
				break;
			case PEAK:
				memoryUsage = poolMXBean.getPeakUsage();
				// XXX does it make sense to return this threshold value for
				// peak usage graphs?
				thresholdValue = poolMXBean.getCollectionUsageThreshold();
				break;
			default:
				throw new IllegalArgumentException("Unknown UsageType: " + usageType);
			}
			threshold = String.valueOf(thresholdValue);
		} catch (UnsupportedOperationException e) {
			threshold = "U";
		}
	}

	/**
	 * The warning on {@link #prepareValues()} applies here as well.
	 */
	protected MemoryPoolMXBean getMemoryPoolMXBean(int memtype)
			throws MalformedObjectNameException, IOException {
		ObjectName gcName = new ObjectName(
				ManagementFactory.MEMORY_POOL_MXBEAN_DOMAIN_TYPE + ",*");

		Set<ObjectName> mbeans = connection.queryNames(gcName, null);
		List<MemoryPoolMXBean> gcmbeans = new ArrayList<MemoryPoolMXBean>();
		for (ObjectName objName : mbeans) {
			MemoryPoolMXBean gc = ManagementFactory.newPlatformMXBeanProxy(
					connection, objName.getCanonicalName(),
					MemoryPoolMXBean.class);
			gcmbeans.add(gc);
		}
		return gcmbeans.get(memtype);
	}

	public enum UsageType {
		USAGE, POST_GC, PEAK,
	}
}
