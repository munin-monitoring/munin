package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.RuntimeMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "Uptime", vlabel = "days", info = "Uptime of the Java virtual machine in days.")
public class Uptime extends AbstractAnnotationGraphsProvider {

	private static final double MILLISECONDS_PER_DAY = 1000 * 60 * 60 * 24d;

	public Uptime(Config config) {
		super(config);
	}

	@Field
	public double uptime() throws IOException {
		RuntimeMXBean osmxbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.RUNTIME_MXBEAN_NAME,
				RuntimeMXBean.class);

		return osmxbean.getUptime() / MILLISECONDS_PER_DAY;
	}

	public static void main(String args[]) {
		runGraph(args);
	}

}