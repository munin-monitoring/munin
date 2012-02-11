package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;


@Graph(title = "ClassesUnloaded", vlabel = "classes", info = "The total number of classes unloaded since the Java virtual machine has started execution.")
public class ClassesUnloaded extends AbstractAnnotationGraphsProvider {

	public ClassesUnloaded(Config config) {
		super(config);
	}

	@Field
	public long unloadedClass() throws IOException {
		ClassLoadingMXBean classmxbean = ManagementFactory
				.newPlatformMXBeanProxy(getConnection(),
						ManagementFactory.CLASS_LOADING_MXBEAN_NAME,
						ClassLoadingMXBean.class);
		return classmxbean.getUnloadedClassCount();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
