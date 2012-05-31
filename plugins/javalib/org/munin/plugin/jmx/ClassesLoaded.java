package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "ClassesLoaded", vlabel = "classes", info = "The number of classes that are currently loaded in the Java virtual machine.")
public class ClassesLoaded extends AbstractAnnotationGraphsProvider {
	@Field
	public int classesLoaded() throws IOException {
		ClassLoadingMXBean classmxbean = ManagementFactory
				.newPlatformMXBeanProxy(connection,
						ManagementFactory.CLASS_LOADING_MXBEAN_NAME,
						ClassLoadingMXBean.class);
		return classmxbean.getLoadedClassCount();
	}

	public static void main(String args[]) {
		runGraph(new ClassesLoaded(), args);
	}
}
