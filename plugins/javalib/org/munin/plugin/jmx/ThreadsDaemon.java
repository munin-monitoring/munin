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

	private ThreadMXBean threadMXBean;

	public ThreadsDaemon(Config config) {
		super(config);
	}

	@Override
	protected void prepareValues() throws Exception {
		threadMXBean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);
	}

	@Field
	public int threadsDaemon() throws IOException {
		return threadMXBean.getDaemonThreadCount();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
