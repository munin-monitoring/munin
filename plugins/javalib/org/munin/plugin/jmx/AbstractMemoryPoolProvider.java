package org.munin.plugin.jmx;

import java.io.IOException;
import java.io.PrintWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.lang.reflect.AccessibleObject;
import java.util.Set;

import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

public abstract class AbstractMemoryPoolProvider extends
		AbstractMemoryUsageProvider {

	protected String threshold;

	private final LegacyPool pool;
	private final UsageType usage;

	protected AbstractMemoryPoolProvider(Config config, final LegacyPool pool,
			final UsageType usage) {
		super(config);

		this.usage = usage;
		this.pool = pool;
	}

	@Field(info = "The usage threshold value of this memory pool in bytes. The default value is zero.")
	public String threshold() {
		return threshold;
	}

	@Override
	protected void printGraphConfig(PrintWriter out, String title,
			String vlabel, String info, String args, boolean update,
			boolean graph) {
		String poolName;
		try {
			poolName = getMemoryPoolMXBean(pool).getName();
		} catch (Exception e) {
			poolName = "<unknown pool>";
		}
		super.printGraphConfig(out, title, vlabel, info + " (" + poolName
				+ ").", args, update, graph);
	}

	@Override
	protected void printFieldValue(PrintWriter out, AccessibleObject accessible) {
		super.printFieldValue(out, accessible);
	}

	/**
	 * <b>WARNING:</b> This method tries to fix the broken index-based access of
	 * 1.4 JMX plugins by finding the desired pool by the pool name instead.
	 * While that's an improvement it's still fundamentally broken, as pool
	 * names and even their existence is undefined and implementation- as well
	 * as configuration-dependent.
	 *
	 * A fully correct solution would dynamically create graphs for each pool
	 * encountered and not make any assumption. {@link MultigraphMemory} is such
	 * a fully dynamic implementation and should be preferred.
	 */
	protected void prepareValues() throws Exception {
		MemoryPoolMXBean poolMXBean = getMemoryPoolMXBean(pool);
		prepareMemoryUsage(poolMXBean, usage);
		long thresholdValue;
		try {
			switch (usage) {
			case USAGE:
				thresholdValue = poolMXBean.getUsageThreshold();
				break;
			// XXX does it make sense to return this threshold value for
			// peak usage graphs?
			case PEAK:
			case POST_GC:
				thresholdValue = poolMXBean.getCollectionUsageThreshold();
				break;
			default:
				throw new IllegalArgumentException("Unknown UsageType: "
						+ usage);
			}
			threshold = String.valueOf(thresholdValue);
		} catch (UnsupportedOperationException e) {
			threshold = "U";
		}
	}

	protected MemoryPoolMXBean getMemoryPoolMXBean(LegacyPool pool)
			throws MalformedObjectNameException, IOException {
		ObjectName gcName = new ObjectName(
				ManagementFactory.MEMORY_POOL_MXBEAN_DOMAIN_TYPE + ",*");

		Set<ObjectName> mbeans = getConnection().queryNames(gcName, null);
		for (ObjectName objName : mbeans) {
			MemoryPoolMXBean gc = ManagementFactory.newPlatformMXBeanProxy(
					getConnection(), objName.getCanonicalName(),
					MemoryPoolMXBean.class);
			LegacyPool gcPool = LegacyPool.getLegacyPool(gc.getName());
			if (gcPool == pool) {
				return gc;
			}
		}
		return null;
	}
}
