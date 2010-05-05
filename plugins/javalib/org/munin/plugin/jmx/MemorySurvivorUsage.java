package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemorySurvivorUsage", vlabel = "bytes", info = "Returns an estimate of the memory usage of this memory pool.")
public class MemorySurvivorUsage extends AbstractMemoryPoolProvider {

	@Override
	public void prepareValues() throws Exception {
		preparePoolValues(4, UsageType.USAGE);
	}

	public static void main(String args[]) {
		runGraph(new MemorySurvivorUsage(), args);
	}
}
