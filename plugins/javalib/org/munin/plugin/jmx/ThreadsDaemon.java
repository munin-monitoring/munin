package org.munin.plugin.jmx;

/**
 * @author Diyar
 */
import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "ThreadsDaemon", vlabel = "threads", info = "Returns the current number of live daemon threads.")
public class ThreadsDaemon extends AbstractAnnotationGraphsProvider {

	@Field
	public int threadsDaemon() throws IOException {
		ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(
				connection, ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);
		return threadmxbean.getDaemonThreadCount();
	}

	public static void main(String args[]) {
		runGraph(new ThreadsDaemon(), args);
	}
}
