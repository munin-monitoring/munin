package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;


@Graph(title = "MemoryTenuredGenUsagePostGC", vlabel = "bytes", info = "Pool containing long-lived objects")
public class MemoryTenuredGenUsagePostGC extends AbstractMemoryPoolProvider {

	public MemoryTenuredGenUsagePostGC(Config config) {
		super(config, LegacyPool.TENURED_GEN, UsageType.POST_GC);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
