package org.munin.plugin.jmx;
import javax.management.remote.JMXConnector;
import java.util.HashMap;
import java.util.Map;

public class ConfReader {

    private static final String IP_PARAM        = "ip";
    private static final String PORT_PARAM      = "port";
    private static final String CATEGORY_PARAM  = "category";
    private static final String USERNAME_PARAM  = "username";
    private static final String PASSWORD_PARAM  = "password";

    private static String ip;
    private static String port;
    private static String category;
    private static String username;
    private static String password;
                
    public static String[] GetConnectionInfo()
    {
        ip       = System.getenv(IP_PARAM);
        port     = System.getenv(PORT_PARAM);
        category = System.getenv(CATEGORY_PARAM);
        username = System.getenv(USERNAME_PARAM);
        password = System.getenv(PASSWORD_PARAM);

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
	    category = "jvm";
	}

        return new String[]{ip , port, category, username, password};
    }

    public static Map<String, Object> GetConnectionCredentials() {

        Map<String, Object> credentials = null;

        if (username == null || password == null)
        {
            return null;
        }

        credentials = new HashMap<String, Object>();

        credentials.put(JMXConnector.CREDENTIALS, 
                        new String[] {username,
                                      password});
        return credentials;
    }

}

