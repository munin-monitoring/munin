package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryPermGenUsagePostGC", vlabel = "bytes", info = "Contains reflective data of the JVM itself, including class and memory objects")
public class MemoryPermGenUsagePostGC extends AbstractMemoryPoolProvider {

	public MemoryPermGenUsagePostGC(Config config) {
		super(config, LegacyPool.PERM_GEN, UsageType.POST_GC);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}