package org.munin.plugin.jmx;

import java.lang.management.MemoryPoolMXBean;
import java.lang.management.MemoryUsage;

public abstract class AbstractMemoryUsageProvider extends
		AbstractAnnotationGraphsProvider {

	protected MemoryUsage memoryUsage;

	protected AbstractMemoryUsageProvider(Config config) {
		super(config);
	}

	@Override
	protected abstract void prepareValues() throws Exception;

	@Field(info = "The maximum amount of memory (in bytes) that can be used for memory management.", draw = "AREA", colour = "ccff00", position = 1)
	public long max() {
		return (memoryUsage == null ? -1 : memoryUsage.getMax());
	}

	@Field(info = "The amount of memory (in bytes) that is guaranteed to be available for use by the Java virtual machine.", draw = "LINE2", colour = "0033ff", position = 2)
	public long committed() {
		return (memoryUsage == null ? -1 : memoryUsage.getCommitted());
	}

	@Field(info = "The initial amount of memory (in bytes) that the Java virtual machine requests from the operating system for memory management during startup.", position = 3)
	public long init() {
		return (memoryUsage == null ? -1 : memoryUsage.getInit());
	}

	@Field(info = "represents the amount of memory currently used (in bytes).", draw = "LINE3", colour = "33cc00", position = 4)
	public long used() {
		return (memoryUsage == null ? -1 : memoryUsage.getUsed());
	}

	protected void prepareMemoryUsage(MemoryPoolMXBean memoryPool, UsageType usageType) {
		switch (usageType) {
		case USAGE:
			memoryUsage = memoryPool.getUsage();
			break;
		case POST_GC:
			memoryUsage = memoryPool.getCollectionUsage();
			break;
		case PEAK:
			memoryUsage = memoryPool.getPeakUsage();
			break;
		default:
			throw new IllegalArgumentException("Unknown UsageType: "
					+ usageType);
		}
	}

	public enum UsageType {
		USAGE, POST_GC, PEAK,
	}
}

