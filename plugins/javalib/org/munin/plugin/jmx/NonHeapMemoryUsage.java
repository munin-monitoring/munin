package org.munin.plugin.jmx;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
public class NonHeapMemoryUsage 
{
	public static void main(String args[])
	{

        MemoryMXBean memorymxbean = ManagementFactory.getMemoryMXBean();



 System.out.println("NonHeapMemoryUsageCommitted.value " +   memorymxbean.getNonHeapMemoryUsage().getCommitted());	
 System.out.println("NonHeapMemoryUsageMax.value " + memorymxbean.getNonHeapMemoryUsage().getMax());
 System.out.println("NonHeapMemoryUsageInit.value " + memorymxbean.getNonHeapMemoryUsage().getInit());
 System.out.println("NonHeapMemoryUsageUsed.value " + memorymxbean.getNonHeapMemoryUsage().getUsed());

	}


}

