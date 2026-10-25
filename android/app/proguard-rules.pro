# Taken keeps no reflection-based serialization (the JSON codecs are hand written over kotlinx-serialization's tree), so
# R8's defaults and the libraries' own consumer rules are enough.

# The widgets' callbacks (SPEC-ANDROID 10.1): Glance runs an ActionCallback by its class name and makes it with
# `getDeclaredConstructor().newInstance()` (glance-appwidget 1.2.0 RunCallbackAction). Glance's own consumer rule keeps the
# class only, and R8's full mode, AGP's default, does not keep a kept class's no-argument constructor with it ("the default
# constructor (<init>()) is not implicitly kept", https://developer.android.com/topic/performance/app-optimization/full-mode).
-keep class * implements androidx.glance.appwidget.action.ActionCallback {
    <init>();
}
