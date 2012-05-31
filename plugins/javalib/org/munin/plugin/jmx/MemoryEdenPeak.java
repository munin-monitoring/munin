package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryEdenPeak", vlabel = "bytes", info = "The peak memory usage of this memory pool since the Java virtual machine was started or since the peak was reset")
public class MemoryEdenPeak extends AbstractMemoryPoolProvider {

	public MemoryEdenPeak(Config config) {
		super(config, LegacyPool.EDEN, UsageType.PEAK);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
