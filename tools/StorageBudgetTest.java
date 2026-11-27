package gg.isme.tv;

public final class StorageBudgetTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        long m = StorageBudget.MIB;
        long small = 8 * 1024 * m, large = 128 * 1024 * m;
        check(StorageBudget.reserve(1024*m)==256*m,"minimum reserve");
        check(StorageBudget.reserve(large)==1024*m,"maximum reserve");
        check(!StorageBudget.canStart(0,small),"unknown free space");
        check(!StorageBudget.canStart(400*m,small),"low storage");
        check(StorageBudget.canStart(1024*m,small),"adequate startup");
        check(!StorageBudget.fits(2500*m,1500*m,small),"reject oversized file on TV");
        check(StorageBudget.fits(700*m,1500*m,small),"accept smaller file");
        check(!StorageBudget.fits(0,1500*m,small),"invalid size");
        check(StorageBudget.shouldStop(300*m,small),"reserve protection");
        check(!StorageBudget.shouldStop(1500*m,small),"healthy storage");
        System.out.println("StorageBudgetTest passed");
    }
}
