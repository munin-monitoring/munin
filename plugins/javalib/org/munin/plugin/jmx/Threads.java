package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "Threads", vlabel = "threads", info = "Shows the number of live threads including both daemon and non-daemon threads.")
public class Threads extends AbstractAnnotationGraphsProvider {

	private ThreadMXBean threadMXBean;

	public Threads(Config config) {
		super(config);
	}

	@Override
	protected void prepareValues() throws Exception {
		threadMXBean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);
	}

	@Field(info="number of live threads in total", draw = "AREA", position=1)
	public int threads() throws IOException {
		return threadMXBean.getThreadCount();
	}

	@Field(info="number of live daemon threads", position = 2)
	public int threadsDaemon() throws IOException {
		return threadMXBean.getDaemonThreadCount();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
