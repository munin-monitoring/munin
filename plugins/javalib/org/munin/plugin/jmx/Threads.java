package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "Threads", vlabel = "threads", info = "Returns the current number of live threads including both daemon and non-daemon threads.")
public class Threads extends AbstractAnnotationGraphsProvider {

	@Field
	public int threads() throws IOException {
		ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(
				connection, ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);
		return threadmxbean.getThreadCount();
	}

	public static void main(String args[]) {
		runGraph(new Threads(), args);
	}
}
