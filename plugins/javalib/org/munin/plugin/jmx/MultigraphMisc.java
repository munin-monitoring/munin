package org.munin.plugin.jmx;

import java.util.LinkedHashMap;
import java.util.Map;

public class MultigraphMisc extends AbstractMultiGraphsProvider {
	private static final String PREFIX = "_misc";

	public MultigraphMisc(Config config) {
		super(config);
		// can't set the PREFIX itself, because we also need to use config
		// without that prefix for the legacy data storage graphs
		// setPrefix(getPrefix() + PREFIX);
	}

	@Override
	protected Map<String, AbstractGraphsProvider> getProviders() {
		Map<String, AbstractGraphsProvider> providers = new LinkedHashMap<String, AbstractGraphsProvider>();
		addWithAlias(providers, new Uptime(config), "_Uptime", PREFIX, PREFIX
				+ ".uptime");
		addWithAlias(providers, new ClassesLoaded(config), "_ClassesLoaded", PREFIX + ".classes_loaded");
		addWithAlias(providers, new ClassesUnloaded(config), "_ClassesUnloaded", PREFIX + ".classes_unloaded");
		addWithAlias(providers, new ClassesLoadedTotal(config), "_ClassesLoadedTotal", PREFIX + ".classes_loaded_total");
		addWithAlias(providers, new CompilationTimeTotal(config), "_CompilationTimeTotal", PREFIX + ".compilation_time_total");
		addWithAlias(providers, new ProcessorsAvailable(config), "_ProcessorsAvailable", PREFIX + ".processors_available");
		return providers;
	}

	public static void main(String[] args) {
		runGraph(args);
	}
}
