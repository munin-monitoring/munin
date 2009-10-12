package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
public class PeakLiveThreadCountSinceJVM 
{
	public static void main(String args[])
	{
	
	     ThreadMXBean threadmxbean = ManagementFactory.getThreadMXBean();
	     int g=threadmxbean.getPeakThreadCount();  // Returns the peak live thread count since the Java virtual machine started or peak was reset.
	     System.out.print(g+"\n");
	}


}

