// Build-time only: package Poppins and its OFL license with the app.
import 'dart:io';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final dir = Directory('${root.path}/assets/fonts');
  await dir.create(recursive: true);
  const names = ['Poppins-Regular.ttf', 'Poppins-Medium.ttf',
    'Poppins-SemiBold.ttf', 'Poppins-Bold.ttf', 'Poppins-ExtraBold.ttf', 'OFL.txt'];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    for (final name in names) {
      final target = File('${dir.path}/$name');
      if (await target.exists() && await target.length() > 1000) continue;
      final request = await client.getUrl(Uri.parse(
        'https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/$name'));
      final response = await request.close().timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) throw HttpException('Font download failed: $name (${response.statusCode})');
      final bytes = await response.expand((part) => part).toList().timeout(const Duration(seconds: 40));
      if (bytes.length < 1000 || (name.endsWith('.ttf') &&
          !(bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0))) {
        throw FormatException('Invalid font or license: $name');
      }
      final temp = File('${target.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      stdout.writeln('Prepared $name');
    }
  } finally { client.close(force: true); }
}
