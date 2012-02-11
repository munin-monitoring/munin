package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryEdenUsage", vlabel = "bytes", info = "Returns an estimate of the memory usage of this memory pool")
public class MemoryEdenUsage extends AbstractMemoryPoolProvider {

	public MemoryEdenUsage(Config config) {
		super(config, LegacyPool.EDEN, UsageType.USAGE);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
