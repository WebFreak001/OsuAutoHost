import vibe.vibe;
import bancho.irc;
import config;
import db;
import room;
import mongoschema;

void main()
{
	auto db = connectMongoDB("mongodb://127.0.0.1").getDatabase("osuautohost");
	db["gameusers"].register!GameUser;
	db["rooms"].register!PersistentAutoHostRoom;

	configuration = readFileUTF8("config.json").parseJsonString.deserializeJson!Config;
	banchoConnection = new BanchoBot(configuration.username,
			configuration.password, configuration.server, configuration.port);
	bool running = true;
	auto botTask = runTask({
		while (running)
		{
			banchoConnection.connect();
			logDiagnostic("Got disconnected from bancho...");
			sleep(2.seconds);
		}
	});
	sleep(3.seconds);
	//dfmt off
	AutoHostSettings settings = {
		internalID: "testroom1",
		minStars: 5,
		password: "test",
		startInvite: ["WebFreak"],
		preferredGenre: GenreFlags.anime | GenreFlags.videoGame,
		preferredMode: ModeFlags.osu,
		creator: "WebFreak"
	};
	//dfmt on
	createAutoHostRoom(settings);
	botTask.join();
}
