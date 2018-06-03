module api.user;

import config;
import vibe.data.json;
import vibe.http.client;
import std.conv;
import std.datetime;
import std.uri;
import std.string;

import api.utils;

struct EventInfo
{
	string displayHTML;
	string beatmapID;
	string beatmapSetID;
	SysTime date;
	int epicFactor;
}

struct UserInfo
{
	string userID;
	string username;
	long count300, count100, count50;
	long playcount;
	long rankedScore;
	long totalScore;
	long ppRank;
	double level;
	double ppRaw;
	double accuracy;
	int countRankSS;
	int countRankSSH;
	int countRankS;
	int countRankSH;
	int countRankA;
	char[2] country;
	int ppCountryRank;
	EventInfo[] events;
}

UserInfo queryUser(string username, int eventDays = 1, bool byID = false)
{
	Json ret;
	requestHTTP(baseAPIUrl ~ "/get_user?k=" ~ encodeComponent(configuration.apiKey) ~ "&u=" ~ encodeComponent(
			username) ~ "&event_days=" ~ eventDays.to!string ~ "&type=" ~ (byID ? "id"
			: "string"), (scope req) {  }, (scope res) { ret = res.readJson; });
	if (ret.type != Json.Type.array)
		return UserInfo.init;
	auto arr = ret.get!(Json[]);
	if (arr.length != 1)
		return UserInfo.init;
	auto obj = arr[0];
	UserInfo user;
	user.userID = obj.tryIndex("user_id");
	user.username = obj.tryIndex("username");
	user.count300 = obj.tryIndex("count300", "0").to!long;
	user.count100 = obj.tryIndex("count100", "0").to!long;
	user.count50 = obj.tryIndex("count50", "0").to!long;
	user.playcount = obj.tryIndex("playcount", "0").to!long;
	user.rankedScore = obj.tryIndex("ranked_score", "0").to!long;
	user.totalScore = obj.tryIndex("total_score", "0").to!long;
	user.ppRank = obj.tryIndex("pp_rank", "0").to!long;
	user.level = obj.tryIndex("level", "0").to!double;
	user.ppRaw = obj.tryIndex("pp_raw", "0").to!double;
	user.accuracy = obj.tryIndex("accuracy", "0").to!double;
	user.countRankSS = obj.tryIndex("count_rank_ss", "0").to!int;
	user.countRankSSH = obj.tryIndex("count_rank_ssh", "0").to!int;
	user.countRankS = obj.tryIndex("count_rank_s", "0").to!int;
	user.countRankSH = obj.tryIndex("count_rank_sh", "0").to!int;
	user.countRankA = obj.tryIndex("count_rank_a", "0").to!int;
	string country = obj.tryIndex("country", "??");
	if (country.length == 2)
		user.country = country[0 .. 2];
	user.ppCountryRank = obj.tryIndex("pp_country_rank", "0").to!int;
	if (auto events = "events" in obj)
	{
		if (events.type == Json.Type.array)
		{
			arr = events.get!(Json[]);
			user.events.reserve(arr.length);
			foreach (event; arr)
			{
				EventInfo info;
				info.displayHTML = event.tryIndex("display_html", "");
				info.beatmapID = event.tryIndex("beatmap_id", "");
				info.beatmapSetID = event.tryIndex("beatmapset_id", "");
				info.date = event.tryIndex("date", "").parseOsuDate;
				info.epicFactor = event.tryIndex("epicFactor", "0").to!int;
				user.events ~= info;
			}
		}
	}
	return user;
}
