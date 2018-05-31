module api.map;

import config;
import vibe.data.json;
import vibe.http.client;
import std.conv;
import std.datetime;
import std.uri;
import std.string;

import api.utils;

enum Approval
{
	graveyard = -2,
	wip,
	pending,
	ranked,
	approved,
	qualified,
	loved
}

enum MapGenre
{
	any,
	unspecified,
	videoGame,
	anime,
	rock,
	pop,
	other,
	novelty = 7,
	hipHop = 9,
	electronic
}

enum MapLanguage
{
	any,
	other,
	english,
	japanese,
	chinese,
	instrumental,
	korean,
	french,
	german,
	swedish,
	spanish,
	italian
}

enum MapMode
{
	osu,
	taiko,
	ctb,
	mania
}

struct MapInfo
{
	Approval approved;
	SysTime approvedDate, lastUpdate;
	string artist;
	long setID, beatmapID;
	double bpm;
	string creator;
	double difficultyRating;
	double CS, OD, AR, HP;
	Duration hitPlaytime; // play duration without breaks
	string source;
	MapGenre genre;
	MapLanguage language;
	string title;
	Duration playtime; // play duration with breaks
	string difficultyName;
	ubyte[16] md5;
	MapMode mode;
	string[] tags;
	long numFavorites;
	long playCount;
	long passCount;
	long maxCombo;
}

MapInfo queryMap(string beatmapID)
{
	Json ret;
	requestHTTP(baseAPIUrl ~ "/get_beatmaps?k=" ~ encodeComponent(
			configuration.apiKey) ~ "&b=" ~ encodeComponent(beatmapID), (scope req) {  }, (scope res) {
		ret = res.readJson;
	});
	if (ret.type != Json.Type.array)
		return MapInfo.init;
	auto arr = ret.get!(Json[]);
	if (arr.length != 1)
		return MapInfo.init;
	auto obj = arr[0];
	MapInfo map;
	map.approved = cast(Approval) obj.tryIndex("approved", "-2").to!int;
	map.approvedDate = parseOsuDate(obj.tryIndex("approved_date", "2000-01-01 00:00:00"));
	map.lastUpdate = parseOsuDate(obj.tryIndex("approved_date", "2000-01-01 00:00:00"));
	map.artist = obj.tryIndex("artist");
	map.beatmapID = obj.tryIndex("beatmap_id", beatmapID).to!long;
	map.setID = obj.tryIndex("beatmapset_id", "0").to!long;
	map.bpm = obj.tryIndex("bpm", "0").to!double;
	map.creator = obj.tryIndex("creator");
	map.difficultyRating = obj.tryIndex("difficultyrating", "0").to!double;
	map.CS = obj.tryIndex("diff_size", "0").to!double;
	map.OD = obj.tryIndex("diff_overall", "0").to!double;
	map.AR = obj.tryIndex("diff_approach", "0").to!double;
	map.HP = obj.tryIndex("diff_drain", "0").to!double;
	map.hitPlaytime = obj.tryIndex("hit_length", "0").to!double.seconds;
	map.source = obj.tryIndex("source");
	map.genre = cast(MapGenre) obj.tryIndex("genre_id", "1").to!int;
	map.language = cast(MapLanguage) obj.tryIndex("language_id", "1").to!int;
	map.title = obj.tryIndex("title");
	map.playtime = obj.tryIndex("total_length", "0").to!double.seconds;
	map.difficultyName = obj.tryIndex("version");
	map.md5 = obj.tryIndex("file_md5", "00000000000000000000000000000000").fromMd5HexString;
	map.mode = cast(MapMode) obj.tryIndex("mode", "0").to!int;
	map.tags = obj.tryIndex("tags", "").split(' ');
	map.numFavorites = obj.tryIndex("favourite_count", "0").to!long;
	map.playCount = obj.tryIndex("playcount", "0").to!long;
	map.passCount = obj.tryIndex("passcount", "0").to!long;
	map.maxCombo = obj.tryIndex("max_combo", "0").to!long;
	return map;
}

private Duration seconds(double d)
{
	return (cast(long)(d * 1000)).msecs;
}
