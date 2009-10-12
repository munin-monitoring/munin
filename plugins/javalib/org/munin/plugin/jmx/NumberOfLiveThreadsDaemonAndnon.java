
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
public class NumberOfLiveThreadsDaemonAndnon 
{
	public static void main(String args[])
	{
	
	     ThreadMXBean threadmxbean = ManagementFactory.getThreadMXBean();
	     int t=threadmxbean.getThreadCount(); //Returns the current number of live threads including both daemon and non-daemon threads.
	     System.out.print(t+"\n");
	}


}

