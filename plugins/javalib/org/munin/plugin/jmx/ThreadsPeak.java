package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "ThreadsPeak", vlabel = "threads", info = "Returns the peak live thread count since the Java virtual machine started or peak was reset.")
public class ThreadsPeak extends AbstractAnnotationGraphsProvider {

	public ThreadsPeak(Config config) {
		super(config);
	}

	@Field
	public int threadsPeak() throws IOException {
		ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);

		return threadmxbean.getPeakThreadCount();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
