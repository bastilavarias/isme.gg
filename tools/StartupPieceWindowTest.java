package gg.isme.tv;

public final class StartupPieceWindowTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        int mib = 1024 * 1024;
        StartupPieceWindow aligned = StartupPieceWindow.at(0, 100L*mib, mib, 0);
        check(aligned.first == 0 && aligned.last == 1, "2 MiB window");
        StartupPieceWindow unaligned = StartupPieceWindow.at(3L*mib+512, 4L*mib, mib, 0);
        check(unaligned.first == 3 && unaligned.last == 5, "file offset inside piece");
        StartupPieceWindow tiny = StartupPieceWindow.at(100, 200, mib, 0);
        check(tiny.first == 0 && tiny.last == 0, "small file");
        StartupPieceWindow bounded = StartupPieceWindow.at(0, 100L*mib, 16*1024, 0);
        check(bounded.first == 0 && bounded.last == 7, "8 piece cap");
        StartupPieceWindow end = StartupPieceWindow.at(2L*mib, 3L*mib, mib, 3L*mib-1);
        check(end.first == 4 && end.last == 4, "EOF boundary");
        StartupPieceWindow large = StartupPieceWindow.at(5L*1024*mib, 7L*1024*mib, mib, 6L*1024*mib);
        check(large.first == 11264 && large.last == 11265, "64-bit offset");
        check(aligned.covers(1) && !aligned.covers(2), "coverage");
        try { StartupPieceWindow.at(0, 100, mib, 100); throw new AssertionError("EOF accepted"); }
        catch (IllegalArgumentException expected) {}
        System.out.println("StartupPieceWindowTest passed");
    }
}
