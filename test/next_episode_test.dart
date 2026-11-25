import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/next_episode.dart';

class QueueEngine extends NativeEngine {
  @override Future<List<Season>> seasons(Movie show) async=>const [Season(0,'Specials'),Season(1,'Season 1'),Season(2,'Season 2')];
  @override Future<List<Episode>> episodes(Movie show,int season) async=>switch(season){
    0=>const [Episode(number:1,title:'Special')],
    1=>const [Episode(number:1,title:'Pilot'),Episode(number:2,title:'Second')],
    2=>const [Episode(number:1,title:'New season'),Episode(number:2,title:'Future',airDate:'2099-01-01')],
    _=>const <Episode>[],
  };
}

void main(){
  test('preparation needs stable playback after a seek',(){
    final gate=NextEpisodeGate();
    bool sample(int pos,int time,{bool playing=true,bool buffering=false})=>gate.sample(
      position:Duration(seconds:pos),duration:const Duration(seconds:100),
      now:Duration(seconds:time),playing:playing,buffering:buffering);
    expect(sample(10,0),isFalse);
    expect(sample(90,2),isFalse);
    expect(sample(92,4),isFalse);
    expect(sample(94,6),isFalse);
    expect(sample(96,8),isTrue);
    expect(sample(96,10,buffering:true),isFalse);
    gate.reset();
    expect(sample(99,12),isFalse);
    expect(NextEpisodeGate.preview(const Duration(seconds:99),const Duration(seconds:100)),isTrue);
  });
  test('normal playback prepares at 70%, not before',(){
    final gate=NextEpisodeGate();
    bool sample(int pos,int time)=>gate.sample(position:Duration(seconds:pos),
      duration:const Duration(seconds:100),now:Duration(seconds:time),playing:true,buffering:false);
    expect(sample(62,0),isFalse);
    expect(sample(64,2),isFalse);
    expect(sample(66,4),isFalse);
    expect(sample(68,6),isFalse);
    expect(sample(70,8),isTrue);
  });
  test('next episodes preserve identity, artwork and season boundaries',()async{
    final engine=QueueEngine();addTearDown(engine.dispose);
    const show=Movie(id:'tmdb:tv:123',title:'Show',type:'Anime',tmdbId:123);
    final first=episodeMovie(show,1,const Episode(number:1,title:'Pilot'));
    final second=await findNextEpisode(engine,first);
    expect(second?.id,'tmdb:tv:123:s1:e2');
    expect(second?.episodeTitle,'Second');
    final nextSeason=await findNextEpisode(engine,second!);
    expect(nextSeason?.id,'tmdb:tv:123:s2:e1');
    expect(await findNextEpisode(engine,nextSeason!,now:DateTime(2026)),isNull);
    expect(await findNextEpisode(engine,episodeMovie(show,0,const Episode(number:1,title:'Special'))),isNull);
    expect(await findNextEpisode(engine,const Movie(id:'imdb:tt1234567',title:'Movie')),isNull);
  });
}
