import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'releases/v0_2_0.dart';

typedef WhatsNewBuilder=Widget Function(SharedPreferences prefs,String version,
    bool upgraded,Future<void> Function() acknowledge);

/// Explicit version/build registration is required for every public release.
const Map<String,WhatsNewBuilder> whatsNewRegistry={
  '0.2.0+17':buildV020,
};
