module config;

import bancho.irc;
import vibe.vibe;

struct Config
{
	string username, password;
	string apiKey;
@optional:
	string server = "irc.ppy.sh";
	ushort port = 6667;
}

static immutable baseAPIUrl = "https://osu.ppy.sh/api";

__gshared BanchoBot banchoConnection;
__gshared Config configuration;