package gg.isme.tv;

/** Conservative safety policy for the existing accumulating disk cache.
 * It is not a rolling cache; reserve enough room for the entire selected file.
 */
final class StorageBudget {
    static final long MIB = 1024L * 1024L;
    static final long MIN_RESERVE = 256 * MIB;
    static final long MAX_RESERVE = 1024 * MIB;
    static final long WRITE_HEADROOM = 64 * MIB;

    static long reserve(long totalBytes) {
        return Math.max(MIN_RESERVE, Math.min(MAX_RESERVE, totalBytes / 20));
    }

    static long available(long usableBytes, long totalBytes) {
        if (usableBytes <= 0 || totalBytes <= 0) return 0;
        return Math.max(0, usableBytes - reserve(totalBytes) - WRITE_HEADROOM);
    }

    static boolean canStart(long usableBytes, long totalBytes) {
        return available(usableBytes, totalBytes) >= WRITE_HEADROOM;
    }

    static boolean fits(long fileBytes, long usableBytes, long totalBytes) {
        return fileBytes > 0 && fileBytes <= available(usableBytes, totalBytes);
    }

    static boolean shouldStop(long usableBytes, long totalBytes) {
        return available(usableBytes, totalBytes) == 0;
    }
}
