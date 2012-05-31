package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.OperatingSystemMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "ProcessorsAvailable", vlabel = "processors", info = "Returns the number of processors available to the Java virtual machine. This value may change during a particular invocation of the virtual machine.")
public class ProcessorsAvailable extends AbstractAnnotationGraphsProvider {

	public ProcessorsAvailable(Config config) {
		super(config);
	}

	@Field
	public int processorsAvailable() throws IOException {
		OperatingSystemMXBean osmxbean = ManagementFactory
				.newPlatformMXBeanProxy(getConnection(),
						ManagementFactory.OPERATING_SYSTEM_MXBEAN_NAME,
						OperatingSystemMXBean.class);
		return osmxbean.getAvailableProcessors();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
