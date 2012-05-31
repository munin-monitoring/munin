package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryPermGenPeak", vlabel = "bytes", info = "Returns the peak memory usage of this memory pool since the Java virtual machine was started or since the peak was reset.")
public class MemoryPermGenPeak extends AbstractMemoryPoolProvider {

	@Override
	public void prepareValues() throws Exception {
		preparePoolValues(1, UsageType.PEAK);
	}

	public static void main(String args[]) {
		runGraph(new MemoryPermGenPeak(), args);
	}
}
