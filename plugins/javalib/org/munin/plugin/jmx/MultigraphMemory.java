package org.munin.plugin.jmx;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

import org.munin.plugin.jmx.AbstractMemoryUsageProvider.UsageType;

public class MultigraphMemory extends AbstractMultiGraphsProvider {
	private static final String PREFIX = "_memory";

	public MultigraphMemory(Config config) {
		super(config);
		// can't set the PREFIX itself, because we also need to use config
		// without that prefix for the legacy data storage graphs
	}

	@Override
	protected Map<String, AbstractGraphsProvider> getProviders() {
		Map<String, AbstractGraphsProvider> providers = new LinkedHashMap<String, AbstractGraphsProvider>();
		providers.put(PREFIX, new MemoryAllocatedTotal(config));
		addWithAlias(providers, new MemoryAllocatedHeap(config),
				"_MemoryAllocatedHeap", PREFIX + ".heap");
		addWithAlias(providers, new MemoryAllocatedNonHeap(config),
				"_MemoryAllocatedNonHeap", PREFIX + ".non_heap");
		addWithAlias(providers, new GarbageCollectionInfo.Time(config),
				"_GCTime", PREFIX + ".gc_time");
		addWithAlias(providers, new GarbageCollectionInfo.Count(config),
				"_GCCount", PREFIX + ".gc_count");

		try {
			addPoolProviders(providers);
		} catch (Exception e) {
			e.printStackTrace();
		}

		return providers;
	}

	private void addPoolProviders(Map<String, AbstractGraphsProvider> providers)
			throws MalformedObjectNameException, IOException {
		ObjectName gcName = new ObjectName(
				ManagementFactory.MEMORY_POOL_MXBEAN_DOMAIN_TYPE + ",*");

		// ensure memory pools are sorted consistently
		Set<ObjectName> mbeans = new TreeSet<ObjectName>(getConnection()
				.queryNames(gcName, null));
		for (ObjectName objName : mbeans) {
			String poolName = objName.getKeyProperty("name");

			MemoryPoolUsageProvider usage = new MemoryPoolUsageProvider(config,
					objName, UsageType.USAGE);
			MemoryPoolUsageProvider peak = new MemoryPoolUsageProvider(config,
					objName, UsageType.PEAK);
			MemoryPoolUsageProvider postGC = new MemoryPoolUsageProvider(
					config, objName, UsageType.POST_GC);

			String legacyKey = "_" + getLegacyPoolKey(poolName);
			String key = PREFIX + ".pool_" + toFieldName(poolName);
			addWithAlias(providers, usage, legacyKey + "Usage", key, key
					+ ".usage");
			addWithAlias(providers, peak, legacyKey + "Peak", key + ".peak");
			addWithAlias(providers, postGC, legacyKey + "UsagePostGC", key
					+ ".postGC");
		}
	}

	private String getLegacyPoolKey(final String poolName) {
		LegacyPool legacyPool = LegacyPool.getLegacyPool(poolName);
		String poolKey;
		if (legacyPool != null) {
			poolKey = legacyPool.getName();
		} else {
			poolKey = toFieldName(poolName);
		}
		return "Memory" + poolKey;
	}

	public static void main(String[] args) {
		runGraph(args);
	}
}
