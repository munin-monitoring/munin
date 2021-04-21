package org.munin.plugin.jmx;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Base class that provides to wrap multiple non-multigraph graph providers into
 * a single multigraph graph provider.
 */
public abstract class AbstractMultiGraphsProvider extends
		AbstractGraphsProvider {
	private String prefix = "";

	protected AbstractMultiGraphsProvider(Config config) {
		super(config);
		setPrefix(config.getPrefix());
	}

	protected abstract Map<String, AbstractGraphsProvider> getProviders();

	public String getPrefix() {
		return prefix;
	}

	public void setPrefix(String prefix) {
		this.prefix = prefix;
	}

	@Override
	public void printConfig(PrintWriter out) {
		Map<String, AbstractGraphsProvider> providers = getProviders();
		for (Map.Entry<String, AbstractGraphsProvider> entry : providers
				.entrySet()) {
			out.println("multigraph " + getPrefix() + entry.getKey());
			entry.getValue().printConfig(out);
			out.println();
		}
	}

	@Override
	public void printValues(PrintWriter out) {
		Map<String, AbstractGraphsProvider> providers = getProviders();
		for (Map.Entry<String, AbstractGraphsProvider> entry : providers
				.entrySet()) {
			StringWriter sw = new StringWriter();
			PrintWriter pw = new PrintWriter(sw);
			entry.getValue().printValues(pw);
			pw.close();
			String values = sw.toString().trim();
			if (values.length() != 0) {
				out.println("multigraph " + getPrefix() + entry.getKey());
				out.println(values);
				out.println();
			}
		}
	}

	/**
	 * Utility method that adds a specified provider to the providers
	 * <code>Map</code> multiple times: Once as a non-graphing data graph and
	 * any number of times as alias graphs.
	 *
	 * @param providers
	 *            the <code>Map</code> of providers to add to
	 * @param provider
	 *            the provider to add to the map
	 * @param dataName
	 *            the name of the non-graphing instance
	 * @param aliases
	 *            the names of the alias instances.
	 *
	 * @see #noGraph(AbstractGraphsProvider)
	 * @see #aliasFor(AbstractGraphsProvider, String)
	 */
	protected void addWithAlias(Map<String, AbstractGraphsProvider> providers,
			AbstractGraphsProvider provider, String dataName, String... aliases) {
		providers.put(dataName, noGraph(provider));
		AbstractGraphsProvider aliasProvider = aliasFor(provider, dataName);
		for (String alias : aliases) {
			providers.put(alias, aliasProvider);
		}
	}

	/**
	 * Create a provider that works exactly like the specified provider, but
	 * adds a <code>multigraph</code> attribute to the configuration,
	 * effectively turning it into a multigraph provider.
	 */
	public AbstractMultiGraphsProvider multigraph(final String name,
			final AbstractGraphsProvider provider) {
		return multigraph(name, provider, config);
	}

	public static AbstractMultiGraphsProvider multigraph(final String name,
			final AbstractGraphsProvider provider, Config config) {
		return new AbstractMultiGraphsProvider(config) {
			@Override
			protected Map<String, AbstractGraphsProvider> getProviders() {
				return Collections.singletonMap(name, provider);
			}
		};
	}

	/**
	 * Create a provider that works exactly like the specified provider, but
	 * adds <code>graph no</code> to the configuration.
	 */
	public AbstractGraphsProvider noGraph(final AbstractGraphsProvider provider) {
		return noGraph(provider, config);
	}

	public static AbstractGraphsProvider noGraph(
			final AbstractGraphsProvider provider, Config config) {
		return new AbstractGraphsProvider(config) {

			@Override
			public void printConfig(PrintWriter out) {
				provider.printConfig(out);
				out.println("graph no");
			}

			@Override
			public void printValues(PrintWriter out) {
				provider.printValues(out);
			}
		};
	}

	/**
	 * Creates an alias for the specified provider.
	 *
	 * @param provider
	 *            provider to alias
	 * @param origName
	 *            name of the original graph that will contain the data
	 * @return a new provider that aliases the specified one from the provided
	 *         name (i.e. borrows all data from that provider)
	 */
	public AbstractGraphsProvider aliasFor(
			final AbstractGraphsProvider provider, final String origName) {
		return aliasFor(provider, getPrefix() + origName, config);
	}

	private static final Pattern FIELD_CONFIG_PATTERN = Pattern.compile(
			"^([a-zA-Z0-9_]+)\\.", Pattern.MULTILINE);
	private static final Pattern GRAPH_ORDER_PATTERN = Pattern.compile(
			"^graph_order .*$", Pattern.MULTILINE | Pattern.CASE_INSENSITIVE);

	/**
	 * Creates an alias for the specified provider.
	 *
	 * @param provider
	 *            provider to alias
	 * @param origName
	 *            name of the original graph that will contain the data
	 * @param config
	 *            a Config object
	 * @return a new provider that aliases the specified one from the provided
	 *         name (i.e. borrows all data from that provider)
	 */
	public static AbstractGraphsProvider aliasFor(
			final AbstractGraphsProvider provider, final String origName,
			final Config config) {
		return new AbstractGraphsProvider(config) {

			@Override
			public void printConfig(PrintWriter out) {
				StringWriter stringWriter = new StringWriter();
				provider.printConfig(new PrintWriter(stringWriter));
				String config = stringWriter.toString();
				Set<String> fields = new LinkedHashSet<String>();
				String graphConfig = null;
				String fieldConfig = null;
				// remove existing graph_order directive
				config = GRAPH_ORDER_PATTERN.matcher(config).replaceAll("");
				Matcher matcher = FIELD_CONFIG_PATTERN.matcher(config);
				while (matcher.find()) {
					if (graphConfig == null) {
						graphConfig = config.substring(0, matcher.start())
								.replaceFirst("\n+$", "");
						fieldConfig = config.substring(matcher.start());
					}
					fields.add(matcher.group(1));
				}
				out.println(graphConfig);
				out.print("graph_order");
				for (String field : fields) {
					out.print(" " + field + "=" + origName + "." + field);
				}
				out.println();
				out.println("update no");
				out.println(fieldConfig);
			}

			@Override
			public void printValues(PrintWriter out) {
				// don't print values, as we've got "update no" set
			}
		};
	}
}
