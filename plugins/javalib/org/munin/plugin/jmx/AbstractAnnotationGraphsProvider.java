package org.munin.plugin.jmx;

import java.io.PrintWriter;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.AccessibleObject;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Collection;
import java.util.Comparator;
import java.util.TreeSet;

public abstract class AbstractAnnotationGraphsProvider extends
		AbstractGraphsProvider {

	protected AbstractAnnotationGraphsProvider(final Config config) {
		super(config);
	}

	@Override
	public void printConfig(PrintWriter out) {
		printGraphConfig(out);
		printFieldsConfig(out);
	}

	protected void printGraphConfig(PrintWriter out) {
		Graph graph = getClass().getAnnotation(Graph.class);
		if (graph == null) {
			throw new IllegalArgumentException(getClass()
					+ " doesn't have @Graph annotation");
		}
		String graphTitle = "JVM (port " + config.getPort() + ") "
				+ graph.title();
		printGraphConfig(out, graphTitle, graph.vlabel(), graph.info(), graph
				.args(), graph.update(), graph.graph());
	}

	protected void printFieldsConfig(PrintWriter out) {
		for (AccessibleObject accessible : getFieldObjects()) {
			printFieldConfig(out, accessible);
		}
	}

	protected void printFieldConfig(PrintWriter out, AccessibleObject accessible) {
		Field field = accessible.getAnnotation(Field.class);
		String fieldName = getFieldName(accessible);
		String fieldLabel = field.label();
		if (fieldLabel.length() == 0) {
			fieldLabel = fieldName;
		}

		printFieldConfig(out, fieldName, fieldLabel, field.info(),
				field.type(), field.draw(), field.colour(), field.min(), field
						.max());
	}

	private Collection<AccessibleObject> getFieldObjects() {
		// ensure methods are sorted by position first, then by name
		TreeSet<AccessibleObject> fieldObjects = new TreeSet<AccessibleObject>(
				new Comparator<AccessibleObject>() {

					public int compare(AccessibleObject m1, AccessibleObject m2) {
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

		for (Method method : getClass().getMethods()) {
			if (method.isAnnotationPresent(Field.class)) {
				fieldObjects.add(method);
			}
		}
		for (java.lang.reflect.Field field : getClass().getFields()) {
			if (field.isAnnotationPresent(Field.class)) {
				fieldObjects.add(field);
			}
		}
		return fieldObjects;
	}

	protected String getFieldName(AccessibleObject accessible) {
		String fieldName = accessible.getAnnotation(Field.class).name();
		if (fieldName.length() == 0) {
			String n;
			if (accessible instanceof Method) {
				n = ((Method) accessible).getName();
			} else if (accessible instanceof java.lang.reflect.Field) {
				n = ((java.lang.reflect.Field) accessible).getName();
			} else {
				throw new IllegalArgumentException(
						"AccessibleObject must be a field or a method: "
								+ accessible);
			}
			fieldName = n.substring(0, 1).toUpperCase() + n.substring(1);
		}
		return fieldName;
	}

	private Object getFieldValue(AccessibleObject accessible)
			throws IllegalAccessException, InvocationTargetException {
		Object value;
		if (accessible instanceof Method) {
			value = ((Method) accessible).invoke(this, new Object[0]);
		} else if (accessible instanceof java.lang.reflect.Field) {
			value = ((java.lang.reflect.Field) accessible).get(this);
		} else {
			throw new IllegalArgumentException(
					"AccessibleObject must be a field or a method: "
							+ accessible);
		}
		return value;
	}

	@Override
	public void printValues(PrintWriter out) {
		try {
			prepareValues();
		} catch (Exception e) {
			System.err.println("Failed to prepare values for class "
					+ getClass() + ": " + e.getMessage());
			e.printStackTrace();
		}
		for (AccessibleObject accessible : getFieldObjects()) {
			printFieldValue(out, accessible);
		}
	}

	protected void printFieldValue(PrintWriter out, AccessibleObject accessible) {
		String fieldName = getFieldName(accessible);
		try {
			Object value = getFieldValue(accessible);
			printFieldAttribute(out, fieldName, "value", value);
		} catch (Exception e) {
			System.err.println("Failed to get value for field " + fieldName
					+ ": " + e.getMessage());
			e.printStackTrace();
		}
	}

	protected void prepareValues() throws Exception {
		// nothing
	}

	@Target(ElementType.TYPE)
	@Retention(RetentionPolicy.RUNTIME)
	public @interface Graph {
		String title();

		String vlabel();

		String info() default "";

		String args() default "";

		boolean update() default true;

		boolean graph() default true;
	}

	@Target( { ElementType.METHOD, ElementType.FIELD })
	@Retention(RetentionPolicy.RUNTIME)
	public @interface Field {
		String name() default "";

		String label() default "";

		String info() default "";

		String type() default "";

		double min() default Double.NaN;

		double max() default Double.NaN;

		String draw() default "";

		String colour() default "";

		// Fields that have no explicit position are placed after those that
		// have a position. Fields with the same position value are sorted
		// alphabetically by name.
		int position() default Integer.MAX_VALUE;
	}

}
