
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import com.sun.management.OperatingSystemMXBean;
public class SystemLoadAvgLastMin 
{
	public static void main(String args[])
	{
	
		 OperatingSystemMXBean osmxbean = (OperatingSystemMXBean) ManagementFactory.getOperatingSystemMXBean();
		 double tr=osmxbean.getSystemLoadAverage(); //Returns the system load average for the last minute.
	     System.out.print(tr+"\n");
	}


}

