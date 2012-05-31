package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryTenuredGenUsage", vlabel = "bytes", info = "Returns an estimate of the memory usage of this memory pool.")
public class MemoryTenuredGenUsage extends AbstractMemoryPoolProvider {

	@Override
	public void prepareValues() throws Exception {
		preparePoolValues(0, UsageType.USAGE);
	}

	public static void main(String args[]) {
		runGraph(new MemoryTenuredGenUsage(), args);
	}
}
