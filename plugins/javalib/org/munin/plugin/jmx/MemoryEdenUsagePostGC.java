package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryEdenUsagePostGC", vlabel = "bytes", info = "Pool from which memory is initially allocated for most objects.")
public class MemoryEdenUsagePostGC extends AbstractMemoryPoolProvider {

	@Override
	public void prepareValues() throws Exception {
		preparePoolValues(3, UsageType.POST_GC);
	}

	public static void main(String args[]) {
		runGraph(new MemoryEdenUsagePostGC(), args);
	}
}
