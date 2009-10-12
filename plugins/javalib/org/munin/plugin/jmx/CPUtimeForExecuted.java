package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
public class CPUtimeForExecuted 
{
	public static void main(String args[])
	{
	
	     ThreadMXBean threadmxbean = ManagementFactory.getThreadMXBean();
	     long f=threadmxbean.getCurrentThreadUserTime(); //  Returns the CPU time that the current thread has executed in user mode in nanoseconds.
	     System.out.print(f + "\n");
	}


}

