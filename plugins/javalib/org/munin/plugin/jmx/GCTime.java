package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;


@Graph(title="GarbageCollectionTime", vlabel="ms", info="The Sun JVM defines garbage collection in two modes: Minor copy collections and Major Mark-Sweep-Compact collections. A minor collection runs relatively quickly and involves moving live data around the heap in the presence of running threads. A major collection is a much more intrusive garbage collection that suspends all execution threads while it completes its task. In terms of performance tuning the heap, the primary goal is to reduce the frequency and duration of major garbage collections.")
public class GCTime extends AbstractAnnotationGraphsProvider {

	public GCTime(Config config) {
		super(config);
	}

	private long[] times;

	@Override
	protected void prepareValues() throws Exception {
		GCTimeGet collector = new GCTimeGet(getConnection());
		times = collector.GC();
	}

	@Field(label="MinorTime", info="The approximate accumulated collection elapsed time in milliseconds. This method returns -1 if the collection elapsed time is undefined for this collector.", type="DERIVE", min=0)
	public long copyTime() {
		return times[0];
	}

	@Field(label="MajorTime", info="The approximate accumulated collection elapsed time in milliseconds. This method returns -1 if the collection elapsed time is undefined for this collector.", type="DERIVE", min=0)
	public long markSweepCompactTime() {
		return times[1];
	}

	public static void main(String[] args) {
		runGraph(args);
	}
}
