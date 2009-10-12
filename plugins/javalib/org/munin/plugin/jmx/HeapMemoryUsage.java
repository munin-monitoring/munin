
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
public class HeapMemoryUsage 
{
	public static void main(String args[])
	{

        MemoryMXBean memorymxbean = ManagementFactory.getMemoryMXBean();



 System.out.println("HeapMemoryUsageCommitted.value " +   memorymxbean.getHeapMemoryUsage().getCommitted());	
 System.out.println("HeapMemoryUsageMax.value " + memorymxbean.getHeapMemoryUsage().getMax());
 System.out.println("HeapMemoryUsageInit.value " + memorymxbean.getHeapMemoryUsage().getInit());
 System.out.println("HeapMemoryUsageUsed.value " + memorymxbean.getHeapMemoryUsage().getUsed());

	}


}

