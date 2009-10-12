package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
public class TotalNumberOfThreadsSinceJVM 
{
	public static void main(String args[])
	{
	
	     ThreadMXBean threadmxbean = ManagementFactory.getThreadMXBean();
	     long s=threadmxbean.getTotalStartedThreadCount();// Returns the total number of threads created and also started since the Java virtual machine started.
	     System.out.print(s+"\n");
	}


}

