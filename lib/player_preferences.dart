import 'package:video_player/video_player.dart';
import 'app_preferences.dart';

/// Match the original cinema player's language preference and explicit Off.
List<Map<String,dynamic>> subtitleCandidates(List<Map<String,dynamic>> tracks, String language) {
  if (language == 'off') return [];
  final ordered = <Map<String,dynamic>>[];
  final seen = <int>{};
  for (final group in [
    tracks.where((t) => AppPreferences.languageAliases[t['lang']?.toString().toLowerCase()] == language),
    tracks.where((t) => AppPreferences.languageAliases[t['lang']?.toString().toLowerCase()] == 'eng'),
    tracks,
  ]) {
    for (final track in group) {
      final id = track['id'];
      if (id is int && seen.add(id)) ordered.add(track);
    }
  }
  return ordered;
}

String audioTrackLabel(VideoAudioTrack track) {
  final channels = track.channelCount;
  final codec = track.codec?.trim();
  return [
    if (track.label?.trim().isNotEmpty == true) track.label!.trim(),
    if (track.language?.trim().isNotEmpty == true && track.language != 'und') track.language!,
    if (codec?.isNotEmpty == true) codec!,
    if (channels != null && channels > 0) channels == 2 ? 'Stereo' : channels == 1 ? 'Mono' : '$channels channels',
  ].join(' / ');
}

/// Keep the player's default selection unless there is a stereo AAC track
/// in the same language. Do not invent codecs or change dubbed language.
VideoAudioTrack? compatibleAudioTrack(List<VideoAudioTrack> tracks) {
  final selected = tracks.where((t) => t.isSelected).firstOrNull;
  if (selected == null) return null;
  bool stereoAac(VideoAudioTrack t) {
    final codec = (t.codec ?? '').toLowerCase();
    return t.channelCount == 2 && (codec.contains('aac') || codec.contains('mp4a'));
  }
  if (stereoAac(selected)) return selected;
  final language = selected.language;
  if (language == null || language.isEmpty || language == 'und') return selected;
  return tracks.where((t) => t.language == language && stereoAac(t)).firstOrNull ?? selected;
}
