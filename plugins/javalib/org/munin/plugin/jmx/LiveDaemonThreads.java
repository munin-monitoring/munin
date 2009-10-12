
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
public class LiveDaemonThreads 
{
	public static void main(String args[])
	{
	
	     ThreadMXBean threadmxbean = ManagementFactory.getThreadMXBean();
	     int h=threadmxbean.getDaemonThreadCount(); //  Returns the current number of live daemon threads.
	     System.out.print(h+"\n");
	}


}

