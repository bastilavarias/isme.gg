package gg.isme.desktop;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class DesktopServerTest {
    @Test void fullRange() { assertArrayEquals(new long[]{0, 99}, DesktopServer.range(null, 100)); }
    @Test void seekAndSuffix() {
        assertArrayEquals(new long[]{10, 99}, DesktopServer.range("bytes=10-", 100));
        assertArrayEquals(new long[]{90, 99}, DesktopServer.range("bytes=-10", 100));
        assertArrayEquals(new long[]{5, 99}, DesktopServer.range("bytes=5-150", 100));
    }
    @Test void rejectsInvalidRanges() {
        for (String range : new String[]{"bytes=100-", "bytes=9-2", "bytes=-0", "bytes=0-1,4-5", "bytes=-", "bytes=99999999999999999999999-"})
            assertThrows(IllegalArgumentException.class, () -> DesktopServer.range(range, 100));
    }
}
