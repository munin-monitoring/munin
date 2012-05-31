package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "ThreadsStartedTotal", vlabel = "threads", info = "Returns the total number of threads created and also started since the Java virtual machine started.")
public class ThreadsStartedTotal extends AbstractAnnotationGraphsProvider {

	public ThreadsStartedTotal(Config config) {
		super(config);
	}

	@Field
	public long threadsStartedTotal() throws IOException {
		ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);

		return threadmxbean.getTotalStartedThreadCount();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
