import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:ismegg/player_preferences.dart';

void main() {
  final subtitles = <Map<String,dynamic>>[
    {'id': 0, 'lang': 'kor'},
    {'id': 1, 'lang': 'eng'},
    {'id': 2, 'lang': 'fil'},
    {'id': 3, 'lang': 'eng'},
  ];
  test('preferred subtitles first, English fallback, no duplicate IDs', () {
    expect(subtitleCandidates(subtitles, 'fil').map((t) => t['id']),
        [2, 1, 3, 0]);
    expect(subtitleCandidates(subtitles, 'missing').map((t) => t['id']),
        [1, 3, 0, 2]);
    expect(subtitleCandidates(subtitles, 'off'), isEmpty);
    expect(subtitleCandidates([], 'eng'), isEmpty);
  });
  test('recommend AAC stereo only in the selected language', () {
    const surround = VideoAudioTrack(id: 'surround', isSelected: true,
        language: 'en', codec: 'ac3', channelCount: 6);
    const dubbed = VideoAudioTrack(id: 'dub', isSelected: false,
        language: 'ko', codec: 'aac', channelCount: 2);
    const stereo = VideoAudioTrack(id: 'stereo', isSelected: false,
        language: 'en', codec: 'mp4a.40.2', channelCount: 2);
    expect(compatibleAudioTrack([surround, dubbed, stereo])?.id, 'stereo');
    expect(compatibleAudioTrack([surround, dubbed])?.id, 'surround');
    expect(compatibleAudioTrack([dubbed]), isNull);
    expect(audioTrackLabel(stereo), contains('Stereo'));
  });
}
