package org.munin.plugin.jmx;

/**
 * This enum represents the 4 pool type known by the 1.4 Munin JMX plugins. The
 * 1.4-era JMX Pluginwas hard-coded to those names and expected them at a
 * specific location in the returned MBeans (which is not portable and has lead
 * to several mis-represented values at best).
 *
 * Generally speaking pool names hsould not be hard-coded at all in the JMX
 * plugins, as they are not specified and can vary between JVMs, JVM versions
 * and even based on the settings used to run the JVM (ConcurrentMarkSweep vs.
 * "normal" GC, ...). This class can still be used to map known pool names to
 * the 4 pools expected by the 1.4-era plugins.
 */
public enum LegacyPool {
	SURVIVOR("Survivor", "survivor space"), EDEN("Eden", "eden space"), TENURED_GEN(
			"TenuredGen", "old gen", "tenured gen"), PERM_GEN("PermGen",
			"perm gen");

	private final String name;
	private final String[] matchStrings;

	private LegacyPool(final String name, final String... matchStrings) {
		this.name = name;
		this.matchStrings = matchStrings;
	}

	public String getName() {
		return name;
	}

	public static LegacyPool getLegacyPool(final String poolName) {
		String generalPoolName = poolName.toLowerCase().replaceFirst(
				"^(cms|ps) ", "");
		for (LegacyPool pool : values()) {
			for (String matchString : pool.matchStrings) {
				if (generalPoolName.equals(matchString)) {
					return pool;
				}
			}
		}
		return null;
	}
}
