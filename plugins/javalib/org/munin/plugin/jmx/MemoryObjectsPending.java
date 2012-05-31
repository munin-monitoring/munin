package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemoryObjectsPending", vlabel = "objects", info = "The approximate number of objects for which finalization is pending.")
public class MemoryObjectsPending extends AbstractAnnotationGraphsProvider {

	public MemoryObjectsPending(Config config) {
		super(config);
	}

	@Field
	public int objects() throws IOException {
		MemoryMXBean mbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.MEMORY_MXBEAN_NAME,
				MemoryMXBean.class);

		return mbean.getObjectPendingFinalizationCount();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
