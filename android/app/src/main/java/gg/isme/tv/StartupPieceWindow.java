package gg.isme.tv;

/** Bounded deadline window within a selected file (which can start mid-piece). */
final class StartupPieceWindow {
    static final long WINDOW_BYTES = 2L * 1024 * 1024;
    static final int MAX_PIECES = 8;
    static final int DEADLINE_STEP_MS = 250;
    final int first, last;

    private StartupPieceWindow(int first, int last) {
        this.first = first;
        this.last = last;
    }

    static StartupPieceWindow at(long fileOffset, long fileSize, int pieceSize, long position) {
        if (fileOffset < 0 || fileSize <= 0 || pieceSize <= 0 || position < 0 || position >= fileSize)
            throw new IllegalArgumentException("Invalid selected file range");
        long absolute = Math.addExact(fileOffset, position);
        long end = Math.addExact(absolute, Math.min(WINDOW_BYTES, fileSize - position) - 1);
        int first = Math.toIntExact(absolute / pieceSize);
        int last = Math.toIntExact(Math.min(end / pieceSize, (long)first + MAX_PIECES - 1));
        return new StartupPieceWindow(first, last);
    }

    boolean covers(int piece) { return piece >= first && piece <= last; }
}
