package org.jlink.swingdemo;

import java.awt.HeadlessException;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.SwingUtilities;

public class SwingHello {

    private static class Wiii extends JFrame {

        public Wiii() throws HeadlessException {
            this.setSize(800, 600);
            this.setLocationRelativeTo(null);
            this.add(new JLabel("Hello World!"));
            this.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
            new Thread(new Runnable() {
                @Override
                public void run() {
                    try {
                        Thread.sleep(1000);
                        SwingUtilities.invokeLater(() -> {
                            Wiii.this.dispose();
                        });
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
            }).start();
        }

        @Override
        public void setVisible(boolean b) {
            super.setVisible(b);
            System.out.println("X98 set visible " + b);
        }

        @Override
        public void dispose() {
            super.dispose();
            System.out.println("X98 disposed");
        }

    }

    public static void main(String... args) {
        final Wiii w = new Wiii();
        SwingUtilities.invokeLater(() -> {
            w.setVisible(true);
        });
        SwingUtilities.invokeLater(() -> {
            w.repaint();
        });
        SwingUtilities.invokeLater(() -> {
            w.pack();
        });

    }
}
