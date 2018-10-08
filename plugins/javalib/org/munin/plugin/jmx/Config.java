package org.munin.plugin.jmx;

import java.util.HashMap;
import java.util.Map;

import javax.management.remote.JMXConnector;

public class Config {

	private static final String IP_PARAM = "ip";
	private static final String PORT_PARAM = "port";
	private static final String CATEGORY_PARAM = "category";
	private static final String USERNAME_PARAM = "username";
	private static final String PASSWORD_PARAM = "password";

	private final String ip;
	private final String port;
	private final String category;
	private final String username;
	private final String password;
	private final String prefix;

	Config(final String prefix) {
		ip = System.getenv(IP_PARAM);
		port = System.getenv(PORT_PARAM);
		String categoryEnv = System.getenv(CATEGORY_PARAM);
		username = System.getenv(USERNAME_PARAM);
		password = System.getenv(PASSWORD_PARAM);

		if (ip == null || port == null) {
			String message = "The following parameters were not configured:"
					+ (ip == null ? " ip" : "")
					+ (port == null ? " port" : "");
			throw new IllegalStateException(message);
		}
		if (categoryEnv == null) {
			category = "jvm";
		} else {
			category = categoryEnv;
		}
		if (prefix == null || prefix.length() == 0) {
			this.prefix = "jmx";
		} else {
			this.prefix = prefix;
		}
	}

	public String getIp() {
		return ip;
	}

	public String getPort() {
		return port;
	}

	public String getCategory() {
		return category;
	}

	public String getUsername() {
		return username;
	}

	public String getPassword() {
		return password;
	}

	public String getPrefix() {
		return prefix;
	}

	public boolean isDirtyConfg() {
		return System.getenv("MUNIN_CAP_DIRTYCONFIG") != null;
	}

	public Map<String, Object> getConnectionCredentials() {

		Map<String, Object> credentials = null;

		if (username == null || password == null) {
			return null;
		}

		credentials = new HashMap<String, Object>();

		credentials.put(JMXConnector.CREDENTIALS, new String[] { username,
				password });
		return credentials;
	}

}
