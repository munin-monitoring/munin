package org.munin.plugin.jmx;

public class ConfReader {

    private static final String SERVICE_PARAM   = "SERVICE";
    private static final String IP_PARAM        = "ip";
    private static final String PORT_PARAM      = "port";
    private static final String CATEGORY_PARAM  = "category";
                
    public static String[] GetConnectionInfo(String servicename)
    {
        String service_value = System.getenv(SERVICE_PARAM);
                                
        if (service_value == null) 
        {
            System.out.println("SERVICE is not configured");
            System.exit(1);
        }

        if (!service_value.equals(servicename)) 
        {
            System.out.println("Service name does not match: " + servicename);
            System.exit(1);
        }

        String ip       = System.getenv(IP_PARAM);
        String port     = System.getenv(PORT_PARAM);
        String category = System.getenv(CATEGORY_PARAM);

        if( ip == null || ip.equals("null") || port == null || port.equals("null") )
        {
            System.out.println(
                                "The following parameters were not configured:" + 
                                (ip == null ? " ip" : "") + 
                                (port == null ? " port" : "") 
                              );
            System.exit(1);
        }
	if( category == null || category.equals("null") )
	{
	    category = "java";
	}

        return new String[]{ip , port, category};
    }
}

