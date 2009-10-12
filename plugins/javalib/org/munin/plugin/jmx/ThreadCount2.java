/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

/**
 *
 * @author Diyar
 */
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.ThreadMXBean;
import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
public class ThreadCount2
{
    public static void main(String args[])
    {
        try{
            JMXServiceURL u=new JMXServiceURL("service:jmx:rmi:///jndi/rmi://"+"128.39.73.242"+":"+5400+"/jmxrmi");
            JMXConnector c=JMXConnectorFactory.connect(u);
            MBeanServerConnection connection=c.getMBeanServerConnection();
            ThreadMXBean threadmxbean=ManagementFactory.newPlatformMXBeanProxy(connection, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);
            
            System.out.println("ThreadCount.value "+threadmxbean.getThreadCount());
            
        }
        catch(Exception e)
        {
            System.out.print(e);
        }
    }

}

