package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "ClassesLoadedTotal", vlabel = "classes", info = "The total number of classes that have been loaded since the Java virtual machine has started execution.")
public class ClassesLoadedTotal extends AbstractAnnotationGraphsProvider {

	public ClassesLoadedTotal(Config config) {
		super(config);
	}

	@Field
	public long classesLoadedTotal() throws IOException {
		ClassLoadingMXBean classmxbean = ManagementFactory
				.newPlatformMXBeanProxy(getConnection(),
						ManagementFactory.CLASS_LOADING_MXBEAN_NAME,
						ClassLoadingMXBean.class);
		return classmxbean.getTotalLoadedClassCount();
	}

	public static void main(String[] args) {
		runGraph(args);
	}
}
