package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;


@Graph(title = "MemorySurvivorUsagePostGC", vlabel = "bytes", info = "containing objects that have survived Eden space garbage collection.")
public class MemorySurvivorUsagePostGC extends AbstractMemoryPoolProvider {

	@Override
	public void prepareValues() throws Exception {
		preparePoolValues(4, UsageType.POST_GC);
	}

	public static void main(String args[]) {
		runGraph(new MemorySurvivorUsagePostGC(), args);
	}
}
