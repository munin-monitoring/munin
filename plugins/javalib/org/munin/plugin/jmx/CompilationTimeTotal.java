package org.munin.plugin.jmx;

/**
 * @author Diyar
 */
import java.io.IOException;
import java.lang.management.CompilationMXBean;
import java.lang.management.ManagementFactory;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "CompilationTimeTotal", vlabel = "ms", info = "value does not indicate the level of performance of the Java virtual machine and is not intended for performance comparisons of different virtual machine implementations. The implementations may have different definitions and different measurements of the compilation time.")
public class CompilationTimeTotal extends AbstractAnnotationGraphsProvider {

	public CompilationTimeTotal(Config config) {
		super(config);
	}

	@Field(info = "The approximate elapsed time (in milliseconds) spent in compilation. If multiple threads are used for compilation, this value is summation of the approximate time that each thread spent in compilation.", type = "DERIVE", min = 0)
	public long compilationTimeTotal() throws IOException {
		CompilationMXBean osmxbean = ManagementFactory.newPlatformMXBeanProxy(
				getConnection(), ManagementFactory.COMPILATION_MXBEAN_NAME,
				CompilationMXBean.class);
		return osmxbean.getTotalCompilationTime();
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
