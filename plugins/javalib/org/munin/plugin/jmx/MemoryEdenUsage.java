package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryEdenUsage", vlabel = "bytes", info = "Returns an estimate of the memory usage of this memory pool.")
public class MemoryEdenUsage extends AbstractMemoryPoolProvider {

	@Override
	public void prepareValues() throws Exception {
		preparePoolValues(3, UsageType.USAGE);
	}

	public static void main(String args[]) {
		runGraph(new MemoryEdenUsage(), args);
	}
}
