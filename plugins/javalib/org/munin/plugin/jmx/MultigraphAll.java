package org.munin.plugin.jmx;

import java.io.PrintWriter;
import java.util.Arrays;
import java.util.List;

public class MultigraphAll extends AbstractGraphsProvider {
	private final List<AbstractMultiGraphsProvider> providers = Arrays.asList(
			new MultigraphMemory(config), new MultigraphThreads(config),
			new MultigraphMisc(config));

	public MultigraphAll(Config config) {
		super(config);
	}

	@Override
	public void printConfig(PrintWriter out) {
		for (AbstractMultiGraphsProvider provider : providers) {
			provider.printConfig(out);
		}
	}

	@Override
	public void printValues(PrintWriter out) {
		for (AbstractMultiGraphsProvider provider : providers) {
			provider.printValues(out);
		}
	}

	public static void main(String[] args) {
		runGraph(args);
	}
}
