package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryPermGenUsage", vlabel = "bytes", info = "Returns an estimate of the memory usage of this memory pool")
public class MemoryPermGenUsage extends AbstractMemoryPoolProvider {

	public MemoryPermGenUsage(Config config) {
		super(config, LegacyPool.PERM_GEN, UsageType.USAGE);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
