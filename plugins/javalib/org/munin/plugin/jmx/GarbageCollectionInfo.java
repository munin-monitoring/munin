package org.munin.plugin.jmx;

import java.io.IOException;
import java.io.PrintWriter;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Set;
import java.util.TreeSet;

import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;

public abstract class GarbageCollectionInfo extends
		AbstractAnnotationGraphsProvider {

	protected GarbageCollectionInfo(Config config) {
		super(config);
	}

	private Collection<GarbageCollectorMXBean> collectors;

	private Collection<GarbageCollectorMXBean> getCollectors() {
		if (collectors == null) {
			try {
				ObjectName gcName = new ObjectName(
						ManagementFactory.GARBAGE_COLLECTOR_MXBEAN_DOMAIN_TYPE
								+ ",*");

				// ensure that the MBeans are sorted consistently
				Set<ObjectName> mbeans = new TreeSet<ObjectName>(getConnection()
						.queryNames(gcName, null));
				collectors = new ArrayList<GarbageCollectorMXBean>(mbeans
						.size());
				for (ObjectName objectName : mbeans) {
					GarbageCollectorMXBean collector = ManagementFactory
							.newPlatformMXBeanProxy(getConnection(), objectName
									.getCanonicalName(),
									GarbageCollectorMXBean.class);
					collectors.add(collector);
				}
			} catch (IOException e) {
				e.printStackTrace();
			} catch (MalformedObjectNameException e) {
				e.printStackTrace();
			}
		}
		return collectors;
	}

	@Override
	protected void printFieldsConfig(PrintWriter out) {
		for (GarbageCollectorMXBean collector : getCollectors()) {
			String name = getFieldName(collector);
			String label = getFieldLabel(collector);
			String info = getFieldInfo(collector);
			printFieldConfig(out, name, label, info, "DERIVE", null, null, 0,
					Double.NaN);
		}
	}

	@Override
	public void printValues(PrintWriter out) {
			for (GarbageCollectorMXBean collector : getCollectors()) {
				String name = getFieldName(collector);
				printFieldAttribute(out, name, "value", getValue(collector));
			}
	}

	protected abstract String getFieldName(GarbageCollectorMXBean collector);

	protected abstract String getFieldLabel(GarbageCollectorMXBean collector);

	protected abstract String getFieldInfo(GarbageCollectorMXBean collector);

	protected abstract Object getValue(GarbageCollectorMXBean collector);

	protected String getCollectorInfo(GarbageCollectorMXBean collector) {
		StringBuilder builder = new StringBuilder(collector.getName());
		builder.append(" collector (handles these memory pools: ");
		boolean first = true;
		for (String poolName : collector.getMemoryPoolNames()) {
			builder.append(poolName);
			if (first) {
				first = false;
			} else {
				builder.append(", ");
			}
		}
		builder.append(")");
		return builder.toString();
	}

	@Graph(title = "Garbage Collection Count", vlabel = "count", info = "Shows the number of garbage collections for all existing garbage collectors in the target JVM.")
	public static class Count extends GarbageCollectionInfo {
		public Count(Config config) {
			super(config);
		}

		@Override
		protected String getFieldName(GarbageCollectorMXBean collector) {
			return "count_" + toFieldName(collector.getName());
		}

		@Override
		public String getFieldLabel(GarbageCollectorMXBean collector) {
			return "Collection count of " + collector.getName();
		}

		@Override
		protected String getFieldInfo(GarbageCollectorMXBean collector) {
			return "Number of collections that have occurred of the "
					+ getCollectorInfo(collector);
		}

		@Override
		public Object getValue(GarbageCollectorMXBean collector) {
			return collector.getCollectionCount();
		}

		public static void main(String args[]) {
			runGraph(args);
		}

	}

	@Graph(title = "Garbage Collection Time", vlabel = "ms", info = "Shows the time spent in garbage collections for all existing garbage collectors in the target JVM.")
	public static class Time extends GarbageCollectionInfo {
		public Time(Config config) {
			super(config);
			// TODO Auto-generated constructor stub
		}

		@Override
		protected String getFieldName(GarbageCollectorMXBean collector) {
			return "time_" + toFieldName(collector.getName());
		}

		@Override
		public String getFieldLabel(GarbageCollectorMXBean collector) {
			return "Collection time of " + collector.getName();
		}

		@Override
		protected String getFieldInfo(GarbageCollectorMXBean collector) {
			return "Approximate collection elapsed time in milliseconds of the "
					+ getCollectorInfo(collector);
		}

		@Override
		public Object getValue(GarbageCollectorMXBean collector) {
			return collector.getCollectionTime();
		}

		public static void main(String args[]) {
			runGraph(args);
		}

	}
}
