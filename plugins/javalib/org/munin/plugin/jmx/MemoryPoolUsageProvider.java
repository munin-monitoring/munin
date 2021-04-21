package org.munin.plugin.jmx;

import java.io.PrintWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;

import javax.management.ObjectName;

public class MemoryPoolUsageProvider extends AbstractMemoryUsageProvider {
	private final ObjectName poolName;
	private final UsageType usageType;

	public MemoryPoolUsageProvider(final Config config, final ObjectName poolName,
			final UsageType usageType) {
		super(config);
		this.poolName = poolName;
		this.usageType = usageType;
	}

	@Override
	/*
	 * We need to write the graph config manually, since it's dynamic and can't
	 * be specified in annotations.
	 */
	protected void printGraphConfig(PrintWriter out) {
		String name = poolName.getKeyProperty("name");
		String usagePhrase = "";
		switch (usageType) {
		case POST_GC:
			usagePhrase ="collection ";
			break;
		case PEAK:
			usagePhrase = "peak ";
			break;
		}
		String graphTitle = "JVM (port " + config.getPort() + ") " + name + " Memory Pool " + usagePhrase + "usage";
		String graphVlabel = "bytes";
		String graphArgs = "--base 1024 -l 0";
		String graphInfo = usagePhrase + "memory usage of the " + name + " memory pool";

		printGraphConfig(out, graphTitle, graphVlabel, graphInfo, graphArgs, true, true);
	}

	@Override
	protected void prepareValues() throws Exception {
		MemoryPoolMXBean pool = ManagementFactory
				.newPlatformMXBeanProxy(getConnection(),
						poolName.getCanonicalName(), MemoryPoolMXBean.class);
		prepareMemoryUsage(pool, usageType);
	}
}
