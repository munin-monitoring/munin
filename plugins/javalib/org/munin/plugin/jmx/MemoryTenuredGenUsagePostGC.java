package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;


@Graph(title = "MemoryTenuredGenUsagePostGC", vlabel = "bytes", info = "Pool containing long-lived objects.")
public class MemoryTenuredGenUsagePostGC extends AbstractMemoryPoolProvider {

	@Override
	public void prepareValues() throws Exception {
		preparePoolValues(0, UsageType.POST_GC);
	}

	public static void main(String args[]) {
		runGraph(new MemoryTenuredGenUsagePostGC(), args);
	}
}
