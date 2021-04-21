package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "CurrentThreadUserTime", vlabel = "ns", info = "Returns the CPU time that the current thread has executed in user mode in nanoseconds. The returned value is of nanoseconds precision but not necessarily nanoseconds accuracy.")
public class CurrentThreadUserTime extends AbstractAnnotationGraphsProvider {
	public CurrentThreadUserTime(Config config) {
		super(config);
	}

	@Field
	public long currentThreadUserTime() throws IOException {
		ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);
		return threadmxbean.getCurrentThreadUserTime();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
