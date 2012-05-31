package org.munin.plugin.jmx;

import java.io.PrintStream;

import javax.management.MBeanServerConnection;

public abstract class AbstractGraphsProvider {
	public abstract void printConfig(PrintStream out);

	public abstract void printValues(PrintStream out,
			MBeanServerConnection connection);

	static void runGraph(final AbstractGraphsProvider provider, String[] args) {
		if (args.length == 1) {
			if (args[0].equals("config")) {
				provider.printConfig(System.out);
			} else {
				try {
					MBeanServerConnection connection = BasicMBeanConnection
							.get();
					provider.printValues(System.out, connection);
				} catch (Exception e) {
					System.out.print(e);
				}
			}
		}
	}
}
