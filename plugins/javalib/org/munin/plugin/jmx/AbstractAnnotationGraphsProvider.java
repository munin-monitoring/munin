package org.munin.plugin.jmx;

import java.io.PrintStream;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.Method;
import java.util.Collection;
import java.util.Comparator;
import java.util.TreeSet;

import javax.management.MBeanServerConnection;

public abstract class AbstractAnnotationGraphsProvider extends
		AbstractGraphsProvider {

	protected MBeanServerConnection connection;

	@Override
	public void printConfig(PrintStream out) {
		printGraphConfig(out);
		printFieldsConfig(out);
	}

	private void printGraphConfig(PrintStream out) {
		Graph graph = getClass().getAnnotation(Graph.class);
		if (graph == null) {
			throw new IllegalArgumentException(getClass()
					+ " doesn't have @Graph annotation");
		}
		String graphTitle = "JVM (port " + Config.INSTANCE.getPort() + ") "
				+ graph.title();
		String graphVlabel = graph.vlabel();
		String graphInfo = graph.info();
		String graphArgs = graph.args();

		out.println("graph_title " + graphTitle);
		out.println("graph_vlabel " + graphVlabel);
		if (graphInfo != null && graphInfo.length() > 0) {
			out.println("graph_info " + graphInfo);
		}
		if (graphArgs != null && graphArgs.length() > 0) {
			out.println("graph_args " + graphArgs);
		}
		out.println("graph_category " + Config.INSTANCE.getCategory());
	}

	private void printFieldsConfig(PrintStream out) {
		for (Method method : getFieldMethods()) {
			Field field = method.getAnnotation(Field.class);
			String fieldName = getFieldName(method);
			String fieldLabel = field.label();
			if (fieldLabel.length() == 0) {
				fieldLabel = fieldName;
			}

			printFieldAttribute(out, fieldName, "label", fieldLabel);
			printFieldAttribute(out, fieldName, "info", field.info());
			printFieldAttribute(out, fieldName, "type", field.type());
			if (!Double.isNaN(field.min())) {
				printFieldAttribute(out, fieldName, "min", field.min());
			}
			printFieldAttribute(out, fieldName, "draw", field.draw());
			printFieldAttribute(out, fieldName, "colour", field.colour());
		}
	}

	private Collection<Method> getFieldMethods() {
		Method[] allMethods = getClass().getMethods();

		// ensure methods are sorted by position first, then by name
		TreeSet<Method> fieldMethods = new TreeSet<Method>(
				new Comparator<Method>() {

					public int compare(Method m1, Method m2) {
						Integer pos1 = m1.getAnnotation(Field.class).position();
						Integer pos2 = m2.getAnnotation(Field.class).position();
						int result = pos1.compareTo(pos2);
						if (result == 0) {
							result = getFieldName(m1).compareTo(
									getFieldName(m2));
						}
						return result;
					}
				});

		for (Method method : allMethods) {
			if (method.isAnnotationPresent(Field.class)) {
				fieldMethods.add(method);
			}
		}
		return fieldMethods;
	}

	private String getFieldName(Method method) {
		String fieldName = method.getAnnotation(Field.class).name();
		if (fieldName.length() == 0) {
			fieldName = method.getName().substring(0, 1).toUpperCase()
					+ method.getName().substring(1);
		}
		return fieldName;
	}

	private void printFieldAttribute(PrintStream out, String fieldName,
			String attributeName, Object value) {
		if (value != null) {
			String stringValue = String.valueOf(value);
			if (stringValue.length() > 0) {
				out.println(fieldName + "." + attributeName + " " + value);
			}
		}
	}

	@Override
	public void printValues(PrintStream out, MBeanServerConnection connection) {
		this.connection = connection;
		try {
			prepareValues();
		} catch (Exception e) {
			System.err.println("Failed to prepare values for class "
					+ getClass() + ": " + e.getMessage());
			e.printStackTrace();
		}
		for (Method method : getFieldMethods()) {
			String fieldName = getFieldName(method);
			try {
				Object value = method.invoke(this, new Object[0]);
				printFieldAttribute(out, fieldName, "value", value);
			} catch (Exception e) {
				System.err.println("Failed to get value for field " + fieldName
						+ ": " + e.getMessage());
				e.printStackTrace();
			}
		}
		this.connection = null;
	}

	public void prepareValues() throws Exception {
		// nothing
	}

	@Target(ElementType.TYPE)
	@Retention(RetentionPolicy.RUNTIME)
	public @interface Graph {
		String title();

		String vlabel();

		String info() default "";

		String args() default "";
	}

	@Target(ElementType.METHOD)
	@Retention(RetentionPolicy.RUNTIME)
	public @interface Field {
		String name() default "";

		String label() default "";

		String info() default "";

		String type() default "";

		double min() default Double.NaN;

		String draw() default "";

		String colour() default "";

		// Fields that have no explicit position are placed after those that
		// have a position. Fields with the same position value are sorted
		// alphabetically by name.
		int position() default Integer.MAX_VALUE;
	}

}
