module api.utils;

import std.datetime.systime;
import std.datetime.date;
import std.datetime.timezone;
import core.time;
import std.conv;
import vibe.data.json;

SysTime parseOsuDate(string datetime)
{
	if (datetime.length != "0000-00-00 00:00:00".length)
		return SysTime.init;
	return SysTime(DateTime(Date.fromISOExtString(datetime[0 .. "0000-00-00".length]),
			TimeOfDay.fromISOExtString(datetime["0000-00-00 ".length .. $])),
			new immutable SimpleTimeZone(8.hours));
}

T tryIndex(T = string)(Json json, string index, T fallback = T.init)
{
	auto obj = index in json;
	if (!obj)
		return fallback;
	return obj.opt!T(fallback);
}

ubyte[16] fromMd5HexString(string s)
{
	if (s.length != 32)
		return typeof(return).init;
	ubyte[16] ret;
	try
	{
		foreach (i; 0 .. 16)
			ret[i] = s[i * 2 .. i * 2 + 2].to!ubyte(16);
	}
	catch (Exception)
	{
		return typeof(return).init;
	}
	return ret;
}
