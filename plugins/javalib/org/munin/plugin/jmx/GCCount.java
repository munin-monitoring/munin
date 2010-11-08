package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "GarbageCollectionCount", vlabel = "count", info = "The Sun JVM defines garbage collection in two modes: Minor copy collections and Major Mark-Sweep-Compact collections. A minor collection runs relatively quickly and involves moving live data around the heap in the presence of running threads. A major collection is a much more intrusive garbage collection that suspends all execution threads while it completes its task. In terms of performance tuning the heap, the primary goal is to reduce the frequency and duration of major garbage collections.")
public class GCCount extends AbstractAnnotationGraphsProvider {

	public GCCount(Config config) {
		super(config);
	}

	private String[] gcValues;

	@Override
	protected void prepareValues() throws Exception {
		GCCountGet collector = new GCCountGet(getConnection());
		gcValues = collector.GC();
	}

	@Field(label = "MinorCount", info = "The total number of collections that have occurred. This method returns -1 if the collection count is undefined for this collector.", type = "DERIVE", min = 0)
	public String copyCount() {
		return gcValues[0];
	}

	@Field(label = "MajorCount", info = "The total number of collections that have occurred. This method returns -1 if the collection count is undefined for this collector.", type = "DERIVE", min = 0)
	public String markSweepCompactCount() {
		return gcValues[1];
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
