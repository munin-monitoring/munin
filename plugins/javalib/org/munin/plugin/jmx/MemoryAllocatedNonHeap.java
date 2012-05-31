package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "Allocated Non-Heap Memory", vlabel = "bytes", args = "--base 1024 -l 0", info = "The current memory usage of non-heap memory that is used by the Java virtual machine.")
public class MemoryAllocatedNonHeap extends AbstractMemoryUsageProvider {

	public MemoryAllocatedNonHeap(Config config) {
		super(config);
	}

	@Override
	protected void prepareValues() throws Exception {
		memoryUsage = ManagementFactory.newPlatformMXBeanProxy(getConnection(),
				ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class)
				.getNonHeapMemoryUsage();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
