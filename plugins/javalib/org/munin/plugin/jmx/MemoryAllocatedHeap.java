package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "Allocated Heap Memory", vlabel = "bytes", args = "--base 1024 -l 0", info = "The current memory usage of the heap that is used for object allocation.")
public class MemoryAllocatedHeap extends AbstractMemoryUsageProvider {
	public MemoryAllocatedHeap(Config config) {
		super(config);
	}

	@Override
	protected void prepareValues() throws Exception {
		memoryUsage = ManagementFactory.newPlatformMXBeanProxy(getConnection(),
				ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class).getHeapMemoryUsage();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
