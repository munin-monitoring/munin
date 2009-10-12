
import java.io.*;

public class ConfReader {
    
    public void ConfReader(){}

    public static String[] GetConnectionInfo(String servicename){

        String[] connectionInfo = new String[2];
        File f;
        int i = 0;
        try{
       f = new File("/etc/munin/jmx.conf");
        StringBuilder temp = new StringBuilder();

        if (!f.exists() && f.length() < 0) {
            System.out.println("The specified file does not exist");
        } else {
            FileInputStream finp = new FileInputStream(f);
            byte b;
            do {
                b = (byte) finp.read();
                if ((char) b != '\n') {
                    temp.append((char) b);
                } else {
                    if (temp.toString().equals("SERVICE=" + servicename)) {
                        temp = new StringBuilder();

                        do {
                            b = (byte) finp.read();
                            if ((char) b != '\n') {
                                temp.append((char) b);

                            } else if (i == 2) {
                                break;
                            } else {
                                connectionInfo[i++] = temp.toString();
                                temp = new StringBuilder();

                            }
                        } while (b != -1);

                        break;
                    }
                    temp = new StringBuilder();

                }

            } while (b != -1);

            finp.close();
        connectionInfo[0] = connectionInfo[0].substring(3);
        connectionInfo[1] = connectionInfo[1].substring(5);
        }
        }catch(Exception e)
        {
            System.out.println(e);
        }
    

        return connectionInfo;
    }
}

