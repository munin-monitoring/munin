package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;


@Graph(title = "MemorySurvivorUsagePostGC", vlabel = "bytes", info = "containing objects that have survived Eden space garbage collection")
public class MemorySurvivorUsagePostGC extends AbstractMemoryPoolProvider {

	public MemorySurvivorUsagePostGC(Config config) {
		super(config, LegacyPool.SURVIVOR, UsageType.POST_GC);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
