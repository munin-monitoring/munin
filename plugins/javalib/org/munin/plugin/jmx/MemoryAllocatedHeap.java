package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryAllocatedHeap", vlabel = "bytes", args = "--base 1024 -l 0")
public class MemoryAllocatedHeap extends AbstractMemoryUsageProvider {
	@Override
	public void prepareValues() throws Exception {
		memoryUsage = ManagementFactory.newPlatformMXBeanProxy(connection,
				ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class).getHeapMemoryUsage();
	}

	public static void main(String args[]) {
		runGraph(new MemoryAllocatedHeap(), args);
	}
}
