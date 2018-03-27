package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;


@Graph(title = "CurrentThreadCpuTime", vlabel = "ns", info = "Returns the total CPU time for the current thread in nanoseconds. The returned value is of nanoseconds precision but not necessarily nanoseconds accuracy. If the implementation distinguishes between user mode time and system mode time, the returned CPU time is the amount of time that the current thread has executed in user mode or system mode.")
public class CurrentThreadCpuTime extends AbstractAnnotationGraphsProvider {

	public CurrentThreadCpuTime(Config config) {
		super(config);
	}

	@Field
	public long currentThreadCpuTime() throws IOException {
		ThreadMXBean threadmxbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.THREAD_MXBEAN_NAME,
				ThreadMXBean.class);
		return threadmxbean.getCurrentThreadCpuTime();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
