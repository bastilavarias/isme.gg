import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('movie JSON round trips and artwork falls back', () {
    final movie = Movie.fromJson({'id':'imdb:tt1234567','title':'Test','poster':'https://example.invalid/p.jpg','year':2025});
    expect(movie.art, movie.poster);
    expect(Movie.fromJson(movie.toJson()).title, 'Test');
    expect(movie.year, '2025');
  });
  test('history retains progress and removes completed movie', () async {
    SharedPreferences.setMockInitialValues({});
    final history = History(await SharedPreferences.getInstance());
    const movie = Movie(id:'test',title:'Test movie');
    await history.save(movie,const Duration(seconds:20),const Duration(seconds:100));
    expect(history.position(movie),const Duration(seconds:20));
    expect(history.movies().single.id,'test');
    await history.save(movie,const Duration(seconds:99),const Duration(seconds:100));
    expect(history.movies(),isEmpty);
  });
}
