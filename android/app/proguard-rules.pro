# libtorrent4j's native code resolves the generated SWIG bridge by JVM name.
# Preserve JNI upcalls, including methods with no Java callers and their types.
-keep class org.libtorrent4j.swig.** { *; }
