package org.munin.plugin.jmx;

import java.io.IOException;
import java.io.PrintWriter;
import java.net.MalformedURLException;

import javax.management.MBeanServerConnection;

public abstract class AbstractGraphsProvider {
	protected final Config config;
	private MBeanServerConnection connection;

	protected AbstractGraphsProvider(final Config config) {
		if (config == null) {
			throw new IllegalArgumentException("config must not be null");
		}
		this.config = config;
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

	public abstract void printConfig(PrintWriter out);

	public abstract void printValues(PrintWriter out);

	protected void printGraphConfig(PrintWriter out, String title,
			String vlabel, String info, String args, boolean update,
			boolean graph) {
		out.println("graph_title " + title);
		out.println("graph_vlabel " + vlabel);
		if (info != null && info.length() > 0) {
			out.println("graph_info " + info);
		}
		if (args != null && args.length() > 0) {
			out.println("graph_args " + args);
		}
		out.println("graph_category " + config.getCategory());
		if (!update) {
			out.println("update no");
		}
		if (!graph) {
			out.println("graph no");
		}
	}

	protected void printFieldConfig(PrintWriter out, String name, String label,
			String info, String type, String draw, String colour, double min,
			double max) {
		printFieldAttribute(out, name, "label", label);
		printFieldAttribute(out, name, "info", info);
		printFieldAttribute(out, name, "type", type);
		if (!Double.isNaN(min)) {
			printFieldAttribute(out, name, "min", min);
		}
		if (!Double.isNaN(max)) {
			printFieldAttribute(out, name, "max", max);
		}
		printFieldAttribute(out, name, "draw", draw);
		printFieldAttribute(out, name, "colour", colour);
	}

	protected void printFieldAttribute(PrintWriter out, String fieldName,
			String attributeName, Object value) {
		if (value != null) {
			String stringValue = String.valueOf(value);
			if (stringValue.length() > 0) {
				out.println(fieldName + "." + attributeName + " " + value);
			}
		}
	}

	static void runGraph(String[] args) {
		String providerClassName = Thread.currentThread().getStackTrace()[2].getClassName();
		Class<? extends AbstractGraphsProvider> providerClass;
		try {
			providerClass = Class.forName(providerClassName).asSubclass(AbstractGraphsProvider.class);
		} catch (ClassNotFoundException e) {
			throw new IllegalStateException("Failed to get provider class", e);
		}
		Config config = getConfig(args);
		AbstractGraphsProvider provider = getProvider(providerClass, config);
		runGraph(provider, config, args);
	}

	private static AbstractGraphsProvider getProvider(
			Class<? extends AbstractGraphsProvider> providerClass, Config config) {
		try {
			return providerClass.getConstructor(Config.class).newInstance(
					config);
		} catch (NoSuchMethodException e) {
			// just try default constructor
			try {
				return providerClass.newInstance();
			} catch (Exception e1) {
				throw new IllegalArgumentException(
						"Can't instantiate provider with default constructor: "
								+ providerClass, e);
			}
		} catch (Exception e) {
			throw new IllegalArgumentException(
					"Can't instantiate provider with constructor accepting Config object: "
							+ providerClass, e);
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

	private static void runGraph(final AbstractGraphsProvider provider,
			Config config, String[] args) {
		try {
			PrintWriter out = new PrintWriter(System.out);
			if (args[0].equals("config")) {
				provider.printConfig(out);
				if (config.isDirtyConfg()) {
					provider.printValues(out);
				}
			} else {
				provider.printValues(out);
			}
			out.flush();
		} catch (Exception e) {
			e.printStackTrace(System.err);
		}
	}

	protected static String toFieldName(String name) {
		return name.replaceAll("[^A-Za-z0-9_]", "_");
	}
}
