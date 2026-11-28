package gg.isme.desktop;

final class DesktopPlatform {
    private DesktopPlatform() {}
    static long elapsedRealtime() { return System.nanoTime() / 1_000_000L; }
    static final class Log {
        static void d(String tag, String message) {}
        static void w(String tag, String message) { System.err.println(tag + ": " + message); }
        static void w(String tag, String message, Throwable failure) {
            System.err.println(tag + ": " + message + " (" + failure.getClass().getSimpleName() + ")");
        }
    }
}
