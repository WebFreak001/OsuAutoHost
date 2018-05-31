import mongoschema;

import vibe.db.mongo.collection;
import vibe.data.bson;

import std.datetime.systime;
import core.time;
import api.user;

struct GameUser
{
	string userID;
	string username;
	string[] nameHistory;
	SchemaDate[] hostLeaves;
	ulong numHostLeavePenalties;
	ulong joins;
	SchemaDate lastJoined;
	ulong startedSkipVotes;
	ulong numSkipVotes;
	ulong numHosts;
	ulong picksGotSkipped;
	SchemaDate[] startedInvalid;

	mixin MongoSchema;

	void gotSkipped()
	{
		picksGotSkipped++;
		save();
	}

	void didInvalidStart()
	{
		startedInvalid ~= SchemaDate.now;
		save();
	}

	void didJoin()
	{
		joins++;
		lastJoined = SchemaDate.now;
		save();
	}

	void didLeaveAsHost()
	{
		hostLeaves ~= SchemaDate.now;
		save();
	}

	void voteSkip(bool started)
	{
		if (started)
			startedSkipVotes++;
		numSkipVotes++;
		save();
	}

	bool shouldGiveHost()
	{
		auto now = Clock.currTime;
		if ((hostLeaves.length && (now - hostLeaves[$ - 1].toSysTime()) < 24.hours)
				|| (startedInvalid.length > 2
					&& (now - startedInvalid[$ - 2].toSysTime) < 24.hours
					&& (now - startedInvalid[$ - 1].toSysTime) < 12.hours))
		{
			numHostLeavePenalties++;
			save();
			return false;
		}
		else
		{
			numHosts++;
			save();
			return true;
		}
	}

	static GameUser findByUsername(string username)
	{
		auto user = queryUser(username);
		auto obj = GameUser.tryFindOne(["userID" : user.userID]);
		if (!obj.isNull)
		{
			if (obj.username != user.username)
			{
				obj.nameHistory ~= obj.username;
				obj.username = user.username;
				obj.save();
			}
			return obj;
		}
		GameUser ret;
		ret.userID = user.userID;
		ret.username = user.username;
		ret.save();
		return ret;
	}
}
