package org.munin.plugin.jmx;

import org.munin.plugin.jmx.AbstractAnnotationGraphsProvider.Graph;

@Graph(title = "MemorythresholdPostGCCount", vlabel = "count", info = "Returns the number of times that the Java virtual machine has detected that the memory usage has reached or exceeded the collection usage threshold.")
public class MemorythresholdPostGCCount extends
		AbstractAnnotationGraphsProvider {

	public MemorythresholdPostGCCount(Config config) {
		super(config);
	}

	private long[] gcValues;

	@Override
	protected void prepareValues() throws Exception {
		GetMemoryPoolThresholdCount collector = new GetMemoryPoolThresholdCount(
				getConnection());
		gcValues = collector.GC();
	}

	@Field(info = "ThresholdCount for Tenured Gen", position = 1)
	public long tenuredGen() {
		return gcValues[0];
	}

	@Field(info = "ThresholdCount for Perm Gen", position = 2)
	public long permGen() {
		return gcValues[1];
	}

	@Field(info = "Thresholdcount for Eden", position = 3)
	public long eden() {
		return gcValues[2];
	}

	@Field(info = "Thresholdcount for Survivor", position = 4)
	public long survivor() {
		return gcValues[3];
	}

	public static void main(String args[]) {
		runGraph(args);
	}
}
