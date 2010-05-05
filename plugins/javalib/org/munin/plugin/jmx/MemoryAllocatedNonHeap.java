package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryAllocatedNonHeap", vlabel = "bytes", args = "--base 1024 -l 0")
public class MemoryAllocatedNonHeap extends AbstractMemoryUsageProvider {

	@Override
	public void prepareValues() throws Exception {
		memoryUsage = ManagementFactory.newPlatformMXBeanProxy(connection,
				ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class)
				.getNonHeapMemoryUsage();
	}

	public static void main(String args[]) {
		runGraph(new MemoryAllocatedNonHeap(), args);
	}
}
