
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
public class CPUtimeForCurrentThread 
{
	public static void main(String args[])
	{
	
	     ThreadMXBean threadmxbean = ManagementFactory.getThreadMXBean();
	     long e=threadmxbean.getCurrentThreadCpuTime(); //Returns the total CPU time for the current thread in nanoseconds.
	     System.out.print(e + "\n");
	}


}

