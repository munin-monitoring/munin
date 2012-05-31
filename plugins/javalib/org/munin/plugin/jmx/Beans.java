package org.munin.plugin.jmx;

import java.io.IOException;
import java.io.PrintWriter;
import java.net.MalformedURLException;
import javax.management.MBeanServerConnection;
import javax.management.ObjectName;
import javax.management.MalformedObjectNameException;
import javax.management.InstanceNotFoundException;
import javax.management.MBeanAttributeInfo;
import javax.management.MBeanInfo;
import java.util.Set;
import javax.management.JMException;
import java.lang.management.ManagementFactory;

import org.munin.plugin.jmx.Config;

public class Beans {

    protected ObjectName name;
    protected Set<ObjectName> mbeans;
    protected Config config;
    protected MBeanServerConnection connection;
    protected String[] filter;

    public Beans(String args[]) {
        config = getConfig(args);
        filter = new String[args.length - 1];
        this.populateBeanList(args[0]);
        for(int i=1; i<args.length; i++) {
            filter[i-1]=args[i];
        }
        java.util.Arrays.sort(filter);
    }

    protected MBeanServerConnection getConnection() {
        if (connection == null) {
            try {
                connection = BasicMBeanConnection.get(config);
            } catch (MalformedURLException e) {
                throw new IllegalStateException(
                        "Failed to get MBean Server Connection", e);
            } catch (IOException e) {
                throw new IllegalStateException(
                        "Failed to get MBean Server Connection", e);
            }
        }
        return connection;
    }

    protected void populateBeanList(String strName) {
        try {
            name = new ObjectName(strName);
        } catch (MalformedObjectNameException e) {
            throw new IllegalStateException("Failed to get provider class", e);
        }

        try {
            mbeans = getConnection().queryNames(name,null);
        } catch (IOException e) {
            throw new IllegalStateException("Failed to get provider class", e);
        }
    }

    protected void printBeans() {
        for (ObjectName bean : mbeans) {
            MBeanInfo info;
            try {
                info = connection.getMBeanInfo(bean);
            } catch (Exception e) {
                throw new IllegalStateException("Failed to get provider class", e);
            }
            MBeanAttributeInfo[] attributes = info.getAttributes();
            for (MBeanAttributeInfo attr : attributes) {
                if (filter.length == 0 || java.util.Arrays.binarySearch(filter, attr.getName()) >= 0) {
                    Object val;
                    try {
                        val = connection.getAttribute(bean,attr.getName());
                    } catch (Exception e) {
                        val = e;
                    }

                    System.out.println(bean + "\t" + attr.getName() + "\t" + val);
                }
            }
        }
    }

    private static Config getConfig(String[] args) {
        String prefix;
        if (args.length >= 2) {
            prefix = args[1];
        } else {
            prefix = null;
        }
        return new Config(prefix);
    }


    public static void main(String args[]) {
        Beans bs = new Beans(args);
        bs.printBeans();
    }
}



// vim: ts=4:et:ai
