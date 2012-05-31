package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemorySurvivorPeak", vlabel = "bytes", info = "Returns the peak memory usage of this memory pool since the Java virtual machine was started or since the peak was reset")
public class MemorySurvivorPeak extends AbstractMemoryPoolProvider {

	public MemorySurvivorPeak(Config config) {
		super(config, LegacyPool.SURVIVOR, UsageType.PEAK);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
