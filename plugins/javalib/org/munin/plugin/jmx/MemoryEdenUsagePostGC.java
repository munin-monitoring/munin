package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryEdenUsagePostGC", vlabel = "bytes", info = "Pool from which memory is initially allocated for most objects")
public class MemoryEdenUsagePostGC extends AbstractMemoryPoolProvider {

	public MemoryEdenUsagePostGC(Config config) {
		super(config, LegacyPool.EDEN, UsageType.POST_GC);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
