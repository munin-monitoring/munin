package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "Allocated Memory", vlabel = "bytes", args = "--base 1024 -l 0", info="The sum of heap and non-heap memory currently used by the Java virtual machine.")
public class MemoryAllocatedTotal extends AbstractMemoryUsageProvider {
	public MemoryAllocatedTotal(Config config) {
		super(config);
	}

	@Override
	protected void prepareValues() throws Exception {
		MemoryMXBean memoryMXBean = ManagementFactory.newPlatformMXBeanProxy(getConnection(),
				ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class);
		MemoryUsage heap = memoryMXBean.getHeapMemoryUsage();
		MemoryUsage nonHeap = memoryMXBean.getNonHeapMemoryUsage();
		long totalInit = heap.getInit()+nonHeap.getInit();
		long totalUsed = heap.getUsed() + nonHeap.getUsed();
		long totalCommitted = heap.getCommitted()+nonHeap.getCommitted();
		long totalMax = heap.getMax();
		if (nonHeap.getMax() == -1) {
			totalMax += nonHeap.getCommitted();
		} else {
			totalMax += nonHeap.getMax();
		}
		memoryUsage = new MemoryUsage(totalInit, totalUsed, totalCommitted, totalMax);
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
