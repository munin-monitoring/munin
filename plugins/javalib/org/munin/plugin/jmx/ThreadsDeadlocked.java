package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "ThreadsDeadlocked", vlabel = "threads", info = "Returns the number of deadlocked threads for the JVM. Usually not available at readonly access level.")
public class ThreadsDeadlocked extends AbstractAnnotationGraphsProvider {

	public ThreadsDeadlocked(Config config) {
		super(config);
	}

	@Field
	public int threadsDeadlocked() throws IOException {
		ThreadMXBean mxbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);

		long[] deadlockedThreads = mxbean.findMonitorDeadlockedThreads();
		if (deadlockedThreads == null) {
			return 0;
		} else {
			return deadlockedThreads.length;
		}
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
