package org.munin.plugin.jmx;

import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketAddress;

public class PortProbe
{
    static public void main(String[] argv)
	throws Exception
    {
	int port = -1;
	InetAddress host = null;

	switch (argv.length)
	    {
	    case 1: // assume the loopback address ("localhost")
		port = Integer.valueOf(argv[0]);
		host = InetAddress.getByName(null);
		break;
	    case 2: // host name or address was given
		port = Integer.valueOf(argv[0]);
		host = InetAddress.getByName(argv[1]);
		break;
	    default:
		System.err.println("Utilities PORT [HOST]");
		System.exit(1);
	    }

	Socket socket = new Socket();
	SocketAddress sa = new InetSocketAddress(host, port);
	try {
	    socket.connect(sa, 5*1000);
	} catch (IOException e) {
	    System.exit(1);
	} finally {
	    if (!socket.isClosed())
		socket.close();
	}
    }
}
