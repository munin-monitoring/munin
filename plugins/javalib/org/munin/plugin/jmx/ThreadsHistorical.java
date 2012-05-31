package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "Thread Totals", vlabel = "threads", info = "Returns the peak live thread count and the total number of threads started since the Java virtual machine started.")
public class ThreadsHistorical extends AbstractAnnotationGraphsProvider {

	private ThreadMXBean threadMXBean;

	public ThreadsHistorical(Config config) {
		super(config);
	}

	@Override
	protected void prepareValues() throws Exception {
		threadMXBean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);
	}

	@Field(info = "Maximum number of live threads since the JVM started or peak was reset.")
	public int threadsPeak() throws IOException {
		return threadMXBean.getPeakThreadCount();
	}

	@Field(type = "DERIVE", min = 0, info = "Number of threads created and started.")
	public long threadsStarted() throws IOException {
		// returning the total with type DERIVED means we get a nice
		// "number of threads started over time" graph
		return threadMXBean.getTotalStartedThreadCount();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
