import 'package:shared_preferences/shared_preferences.dart';

/// Single source for user-facing preference keys, defaults and choices.
class AppPreferences {
  static const autoplayKey='isme-autoplay-next', awakeKey='isme-keep-screen-awake',
    subtitleLanguageKey='isme-subtitle-language', subtitleSizeKey='isme-subtitle-size',
    regionKey='isme-provider-country', soundKey='isme-navigation-sounds',
    nativeDirectKey='isme-experimental-native-direct', fastStartupKey='isme-experimental-fast-startup',
    adaptiveBufferingKey='isme-experimental-adaptive-buffering';
  static const languages={'eng':'English','fil':'Filipino','off':'Off'};
  static const languageAliases={'en':'eng','eng':'eng','fil':'fil','tgl':'fil','tl':'fil','off':'off'};
  static String language(String? code)=>languageAliases[code?.toLowerCase()]??'eng';
  static const sizes=['Small','Medium','Large','Extra large'];
  static const regions={'PH':'Philippines','US':'United States','GB':'United Kingdom','KR':'South Korea','JP':'Japan','SG':'Singapore','AU':'Australia','CA':'Canada'};
  static bool nativeDirect(SharedPreferences p)=>p.getBool(nativeDirectKey)??true;
  static bool fastStartup(SharedPreferences p)=>p.getBool(fastStartupKey)??true;
  static bool adaptiveBuffering(SharedPreferences p)=>p.getBool(adaptiveBufferingKey)??true;
  static bool autoplay(SharedPreferences p)=>p.getBool(autoplayKey)??true;
  static bool awake(SharedPreferences p)=>p.getBool(awakeKey)??true;
  static bool sounds(SharedPreferences p)=>p.getBool(soundKey)??false;
  static String subtitles(SharedPreferences p)=>language(p.getString(subtitleLanguageKey));
  static int size(SharedPreferences p)=>(p.getInt(subtitleSizeKey)??1).clamp(0,3).toInt();
  static String region(SharedPreferences p)=>p.getString(regionKey)??'PH';
}
