package org.munin.plugin.jmx;

import java.util.LinkedHashMap;
import java.util.Map;

public class MultigraphThreads extends AbstractMultiGraphsProvider {
	private static final String PREFIX = "_threads";

	public MultigraphThreads(Config config) {
		super(config);
		// can't set the PREFIX itself, because we also need to use config
		// without that prefix for the legacy data storage graphs
		// setPrefix(getPrefix() + PREFIX);
	}

	@Override
	protected Map<String, AbstractGraphsProvider> getProviders() {
		Map<String, AbstractGraphsProvider> providers = new LinkedHashMap<String, AbstractGraphsProvider>();
		addWithAlias(providers, new Threads(config), "_Threads", PREFIX, PREFIX
				+ ".threads");
		providers.put(PREFIX + ".historical", new ThreadsHistorical(config));
		addWithAlias(providers, new ThreadsDeadlocked(config),
				"_ThreadsDeadlocked", PREFIX + ".deadlocked");
		return providers;
	}

	public static void main(String[] args) {
		runGraph(args);
	}
}
