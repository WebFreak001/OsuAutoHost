module room;

import config;
import core.time;
import bancho.irc;
import std.algorithm;
import std.conv;
import std.datetime;
import std.math;
import std.range;
import api.map;
import vibe.vibe;
import tinyevent;
import db;

enum ApprovalFlags
{
	graveyard = 1 << 0,
	wip = 1 << 1,
	pending = 1 << 2,
	ranked = 1 << 3,
	approved = 1 << 4,
	qualified = 1 << 5,
	loved = 1 << 6,
	all = graveyard | wip | pending | ranked | approved | qualified | loved,
}

enum GenreFlags
{
	unknown = 1 << 0,
	videoGame = 1 << 1,
	anime = 1 << 2,
	rock = 1 << 3,
	pop = 1 << 4,
	other = 1 << 5,
	novelty = 1 << 6,
	hipHop = 1 << 7,
	electronic = 1 << 8,
	all = unknown | videoGame | anime | rock | pop | other | novelty | hipHop | electronic
}

enum LanguageFlags
{
	unknown = 1 << 0,
	other = 1 << 1,
	english = 1 << 2,
	japanese = 1 << 3,
	chinese = 1 << 4,
	instrumental = 1 << 5,
	korean = 1 << 6,
	french = 1 << 7,
	german = 1 << 8,
	swedish = 1 << 9,
	spanish = 1 << 10,
	italian = 1 << 11,
	all = unknown | other | english | japanese | chinese | instrumental | korean
		| french | german | swedish | spanish | italian
}

enum ModeFlags
{
	osu = 1 << 0,
	taiko = 1 << 1,
	ctb = 1 << 2,
	mania = 1 << 3,
	all = osu | taiko | ctb | mania
}

struct AutoHostSettings
{
	string titlePrefix;
	string titleSuffix = "Auto Host Rotate";
	bool starsInTitle = true;
	bool enforceTitle = true;
	ubyte slots = 8;
	string password;
	string[] startInvite;
	/// Channel if the auto host room should manage an existing channel.
	string existingChannel;
	/// Inclusive min/max values for the recommended stars rating of a map. A max of 4 includes 4.99* maps. 0 enforces no limit.
	int minStars, maxStars;
	Duration startGameDuration = 3.minutes;
	Duration allReadyStartDuration = 15.seconds;
	Duration selectWarningTimeout = 60.seconds;
	Duration selectIdleChangeTimeout = 30.seconds;
	/// Number of maps to look back in playing history to deny. (Max 100)
	int recentlyPlayedLength = 5;

	ApprovalFlags preferredApproval = ApprovalFlags.all;
	GenreFlags preferredGenre = GenreFlags.all;
	LanguageFlags preferredLanguage = LanguageFlags.all;
	ModeFlags preferredMode = ModeFlags.all;
	string creator;

	string toString() const
	{
		string ret;
		ret = "Auto Host, " ~ minStars.to!string ~ "-";
		if (maxStars)
			ret ~= maxStars.to!string;
		ret ~= "*. Room prefers: map approval: " ~ stringifyBitflags(
				preferredApproval) ~ ", song genre: " ~ stringifyBitflags(preferredGenre) ~ ", song language: " ~ stringifyBitflags(
				preferredLanguage) ~ ", game mode: " ~ stringifyBitflags(
				preferredMode) ~ ". Room created by " ~ creator ~ ".";
		return ret;
	}

	bool inStarRange(double value)
	{
		auto stars = cast(int) floor(value);
		if (minStars && maxStars)
			return stars >= minStars && stars <= maxStars;
		else if (minStars)
			return stars >= minStars;
		else if (maxStars)
			return stars <= maxStars;
		else
			return true;
	}

	bool matchesApproval(Approval value)
	{
		if (preferredApproval == ApprovalFlags.all)
			return true;
		return !!(preferredApproval & (1 << (value - Approval.min)));
	}

	bool matchesGenre(MapGenre value)
	{
		if (preferredGenre == GenreFlags.all)
			return true;
		if (value == MapGenre.any || value == MapGenre.unspecified)
			return !!(preferredGenre & GenreFlags.unknown);
		else if (value <= MapGenre.novelty)
			return !!(preferredGenre & (1 << (value - 1)));
		else
			return !!(preferredGenre & (1 << (value - 2)));
	}

	bool matchesLanguage(MapLanguage value)
	{
		if (preferredLanguage == LanguageFlags.all)
			return true;
		return !!(preferredLanguage & (1 << (value - MapLanguage.min)));
	}

	bool matchesMode(MapMode value)
	{
		if (preferredMode == ModeFlags.all)
			return true;
		return !!(preferredMode & (1 << (value - MapMode.min)));
	}

	/// Returns a percentage how much a map violates the room rules. (0 being not at all, 1 being inacceptable)
	double evaluateMapSkip(ref MapInfo map, out string[] errors)
	{
		int penalties;
		int total;
		if (preferredMode != ModeFlags.all)
		{
			total += 8;
			if (!matchesMode(map.mode))
			{
				penalties += 8;
				errors ~= text("Please pick a ", stringifyBitflags(preferredMode), " map.");
			}
		}
		if (minStars || maxStars)
		{
			total += 6;
			if (!inStarRange(map.difficultyRating))
			{
				if (minStars && map.difficultyRating < minStars)
				{
					penalties += 6;
					errors ~= "Map difficulty out of preferred star range.";
				}
				else
				{
					penalties += 4;
					errors ~= "Map difficulty slightly out of preferred star range.";
				}
			}
		}
		if (preferredApproval != ApprovalFlags.all)
		{
			total += 3;
			if (!matchesApproval(map.approved))
			{
				penalties += 3;
				errors ~= text("This map is not ", stringifyBitflags(preferredApproval), ".");
			}
		}
		if (preferredGenre != GenreFlags.all)
		{
			total += 2;
			if (!matchesGenre(map.genre))
			{
				penalties += 2;
				errors ~= text("Map genre does not match ", stringifyBitflags(preferredGenre), ".");
			}
		}
		if (preferredLanguage != LanguageFlags.all)
		{
			total += 2;
			if (!matchesLanguage(map.language))
			{
				penalties += 2;
				errors ~= text("Map language does not match ", stringifyBitflags(preferredGenre), ".");
			}
		}
		return penalties / cast(double) total;
	}
}

string stringifyBitflags(T)(T flags)
{
	if (!flags)
		return "none";
	if (flags == T.all)
		return "all";
	string ret;
	size_t lastComma;
	size_t i = 1;
	while (i && i <= T.max)
	{
		if ((flags & i) != 0)
		{
			if (ret.length)
			{
				lastComma = ret.length;
				ret ~= ", ";
			}
			ret ~= (cast(T) i).to!string;
		}
		i *= 2;
	}
	if (lastComma)
		return ret[0 .. lastComma] ~ " or" ~ ret[lastComma + 1 .. $];
	else
		return ret;
}

void createAutoHostRoom(AutoHostSettings settings)
{
	string[] hostOrder;
	size_t setHost;

	string expectedTitle;
	{
		string prefix;
		if (settings.starsInTitle)
		{
			if (settings.minStars && settings.maxStars)
			{
				if (settings.minStars == settings.maxStars)
					prefix = text(settings.minStars, "* ");
				else
					prefix = text(settings.minStars, " - ", settings.maxStars, ".99* ");
			}
			else if (settings.minStars)
				prefix = text(settings.minStars, "*+ ");
			else if (settings.maxStars)
				prefix = text("0-", settings.maxStars, "* ");
		}
		expectedTitle = settings.titlePrefix ~ (settings.starsInTitle ? prefix : "")
			~ settings.titleSuffix;
	}

	OsuRoom room;
	if (settings.existingChannel.length)
	{
		room = banchoConnection.fromUnmanaged(settings.existingChannel);
		auto info = room.settings;
		if (info == OsuRoom.Settings.init)
		{
			room.sendMessage(
					"Could not setup auto host. Do '!mp addref "
					~ banchoConnection.username ~ "' and then try again.");
			return;
		}
		foreach (i, player; info.players)
		{
			if (player != OsuRoom.Settings.Player.init)
			{
				hostOrder ~= player.name;
				if (player.host)
					setHost = i;
			}
		}
		room.sendMessage("Assuming control over this room (Previous instance shut down)");
		room.sendMessage("Host order: " ~ hostOrder.join(", "));
		if (settings.enforceTitle && expectedTitle.length && info.name.strip != expectedTitle.strip)
			room.sendMessage("Please rename room name to: " ~ expectedTitle);
	}
	else
	{
		room = banchoConnection.createRoom(expectedTitle);
	}
	if (!settings.existingChannel.length)
	{
		foreach (user; settings.startInvite)
			room.invite(user);
		runTask({
			room.password = settings.password;
			room.size = settings.slots;
			room.mods = [Mod.FreeMod];
		});
	}
	ManagedRoom managedRoom = new ManagedRoom(room, settings, expectedTitle, hostOrder, setHost);
}

auto getNow() @property
{
	return Clock.currTime(UTC());
}

class ManagedRoom
{
	static struct StateTimer
	{
		State state;
		bool local;
		Timer timer;
	}

	State selectState;
	State waitingState;
	State ingameState;
	State emptyState;

	State currentState;
	StateTimer stateTimer;

	SysTime lastInfo;
	SysTime startingTime;
	double requiredSkips = 1;
	string[] skippers;
	Duration currentMapDuration = 5.minutes;
	bool startingGame;
	bool probablyPlaying;
	string[] skippedMapIDs;
	string expectedTitle;

	BeatmapInfo currentMapInfo;
	BeatmapInfo[] playHistory;

	string[] hostOrder, failedHostPassing;
	size_t currentHostIndex;
	size_t actualCurrentHost;

	OsuRoom room;
	AutoHostSettings settings;

	string[] newUsers;
	Timer newUserTimer;

	this(OsuRoom room, AutoHostSettings settings, string expectedTitle,
			string[] hostOrder, size_t currentHostIndex)
	{
		selectState = new SelectMapState(this);
		waitingState = new WaitingState(this);
		ingameState = new IngameState(this);
		emptyState = new EmptyState(this);

		currentState = selectState;
		currentState.enter();

		this.expectedTitle = expectedTitle;

		this.hostOrder = hostOrder;
		this.currentHostIndex = currentHostIndex;

		lastInfo = getNow();
		startingTime = getNow();

		newUserTimer = createTimer(&greetNewUsers);

		this.room = room;
		this.settings = settings;

		playHistory.reserve(100);

		room.onBeatmapPending ~= &this.onBeatmapPending;
		room.onBeatmapChanged ~= &this.onBeatmapChanged;
		room.onCountdownFinished ~= &this.onCountdownFinished;
		room.onUserHost ~= &this.onUserHost;
		room.onUserJoin ~= &this.onUserJoin;
		room.onUserLeave ~= &this.onUserLeave;
		room.onPlayersReady ~= &this.onPlayersReady;
		room.onMatchStart ~= &this.onMatchStart;
		room.onMatchEnd ~= &this.onMatchEnd;
		room.onMessage ~= &this.onMessage;

		if (settings.existingChannel.length)
			switchState(waitingState);
	}

	void greetNewUsers() nothrow @trusted
	{
		if (newUsers.length)
		{
			try
			{
				room.sendMessage(newUsers.join(
						", ")
						~ ": Welcome! This room's Game Host is automatically managed by a bot. To find out more, type !info");
				newUsers.length = 0;
			}
			catch (Exception)
			{
			}
		}
	}

	int requiredSkipUsers()
	{
		auto numUsers = room.slots[].count!(a => a != OsuRoom.Settings.Player.init) - 1;
		return cast(int) round(numUsers * requiredSkips);
	}

	bool canStillSkipMidMap()
	{
		return (getNow() - startingTime) < currentMapDuration / 2;
	}

	void pushHistory(BeatmapInfo info)
	{
		if (playHistory.length > 100)
		{
			playHistory[0 .. 99] = playHistory[1 .. 100];
			playHistory[$ - 1] = info;
		}
		else
			playHistory ~= info;
	}

	MapInfo checkMap()
	{
		try
		{
			auto map = queryMap(currentMapInfo.id);
			if (map == MapInfo.init)
				throw new Exception("Could not find beatmap.");
			currentMapDuration = map.playtime;
			string[] errors;
			auto skippiness = settings.evaluateMapSkip(map, errors);
			if (skippiness > 0)
			{
				requiredSkips = 1 - skippiness;
				room.sendMessage("Map does not fully qualify to room settings: " ~ errors.join(
						" ") ~ " Use !skip to skip this map. Skips: 0/" ~ requiredSkipUsers.to!string);
			}
			else
				requiredSkips = 1;
			return map;
		}
		catch (Exception e)
		{
			room.sendMessage("Error: Map could not be looked up. " ~ e.msg);
			requiredSkips = 0.8;
			currentMapDuration = 5.minutes;
			return MapInfo.init;
		}
	}

	string nextHost(bool deleteCurrent = false)
	{
		skippers.length = 0;
		switchState(selectState);
		if (deleteCurrent)
			hostOrder = hostOrder[0 .. currentHostIndex] ~ hostOrder[currentHostIndex + 1 .. $];
		if (hostOrder.length == 0)
		{
			// everyone left
			//room.close();
			failedHostPassing.length = 0;
			playHistory.length = 0;
			skippedMapIDs.length = 0;
			skippers.length = 0;
			switchState(emptyState);
			return null;
		}
		else
		{
			if (!deleteCurrent)
				currentHostIndex = (currentHostIndex + 1) % hostOrder.length;
			else if (currentHostIndex >= hostOrder.length)
				currentHostIndex = 0;
			auto user = hostOrder[currentHostIndex];
			try
			{
				if (!GameUser.findByUsername(user).shouldGiveHost)
				{
					room.sendMessage(
							"Not giving host to " ~ user ~ " because they currently have a bad reputation.");
					return nextHost(true);
				}
			}
			catch (Exception e)
			{
				room.sendMessage(user ~ ": Lucky you!");
			}
			try
			{
				room.playerByName(user);
				if (failedHostPassing.length)
				{
					room.sendMessage("Tried to give host to " ~ failedHostPassing.join(
							", ") ~ " but they left");
					failedHostPassing.length = 0;
				}
				room.host = user;
				actualCurrentHost = currentHostIndex;
				if (hostOrder.length == 0)
					room.sendMessage("No next hosts.");
				else if (hostOrder.length <= 2)
					room.sendMessage("Next host is " ~ hostOrder.cycle.drop(currentHostIndex + 1).front);
				else if (hostOrder.length > 2)
					room.sendMessage("Next hosts are " ~ hostOrder.cycle.drop(currentHostIndex + 1)
							.take(min(3, hostOrder.length - 1)).join(", "));
				return user;
			}
			catch (Exception)
			{
				failedHostPassing ~= user;
				return nextHost(true);
			}
		}
	}

	string currentHost() @property
	{
		if (currentHostIndex >= hostOrder.length)
			return null;
		return hostOrder[currentHostIndex];
	}

	void setStateTimer(Duration d, bool announce)
	{
		if (stateTimer.local)
			stateTimer.timer.stop();
		stateTimer.state = currentState;
		if (announce)
		{
			stateTimer.local = false;
			room.setTimer(d);
		}
		else
		{
			stateTimer.local = true;
			stateTimer.timer = setTimer(d, { this.onCountdownFinished(); });
		}
	}

	void abortStart()
	{
		if (!startingGame)
			return;
		room.abortTimer();
		startingGame = false;
	}

	void abortStateTimer()
	{
		if (stateTimer.state is null || startingGame)
			return;
		stateTimer.state = null;
		if (stateTimer.local)
			stateTimer.timer.stop();
		else
			room.abortTimer();
	}

	void startGame(Duration after)
	{
		if (startingGame)
			abortStateTimer();
		room.start(after);
		startingGame = true;
	}

	void switchState(State state)
	{
		abortStateTimer();
		stateTimer = StateTimer.init;
		currentState.leave();
		currentState = state;
		currentState.enter();
	}

	bool wasRecentlyPlayed(BeatmapInfo beatmap, int lookbehind = -1)
	{
		if (lookbehind == -1)
			lookbehind = settings.recentlyPlayedLength;
		int count = 0;
		foreach_reverse (other; playHistory)
		{
			if (other.id == beatmap.id)
				return true;
			if (count++ >= lookbehind)
				break;
		}
		return false;
	}

	//
	// ===== EVENTS =====
	//

	void onMessage(Message msg)
	{
		logDebug("Message: %s", msg);
		string text = msg.message.strip;
		if (text == "!info")
		{
			if (getNow() - lastInfo < 10.seconds)
				return;
			lastInfo = getNow();
			room.sendMessage("Don't mind me, just here to prevent AFK people and auto host, keeping lobbying as vanilla as possible. Source Code: https://github.com/WebFreak001/OsuAutoHost");
			room.sendMessage("Commands: !skip (if map doesn't fit criteria), !hostqueue, !me");
			room.sendMessage("Settings: " ~ settings.toString);
		}
		else if (text == "!me")
		{
			try
			{
				auto user = GameUser.findByUsername(msg.sender);
				room.sendMessage(
						msg.sender ~ ": You left as host " ~ user.hostLeaves.length.to!string ~ " times and got penalized for it "
						~ user.numHostLeavePenalties.to!string
						~ " times. You have joined auto host " ~ user.joins.to!string ~ " times.");
				room.sendMessage(
						msg.sender ~ ": So far " ~ user.picksGotSkipped.to!string ~ " of your map picks got skipped. You have played "
						~ user.playStarts.to!string ~ " times and finished "
						~ user.playFinishes.to!string ~ " times out of these.");
			}
			catch (Exception)
			{
				room.sendMessage(msg.sender ~ ": I don't know anything about you :(");
			}
		}
		else if (text == "!hostqueue")
		{
			string suffix;
			auto index = hostOrder.countUntil(msg.sender);
			if (index == -1)
				suffix = ". " ~ msg.sender ~ ": you are currently not eligible for host. Try rejoining.";
			else if (index != currentHostIndex)
			{
				auto waits = (cast(long) index - cast(long) currentHostIndex + hostOrder.length) % hostOrder
					.length;
				suffix = ". " ~ msg.sender ~ ": you are host after at most "
					~ waits.to!string ~ "other users. :)";
			}
			if (hostOrder.length == 0)
				room.sendMessage("No next hosts." ~ suffix);
			else if (hostOrder.length <= 2)
				room.sendMessage("Next host is " ~ hostOrder.cycle.drop(currentHostIndex + 1).front ~ suffix);
			else if (hostOrder.length > 2)
				room.sendMessage("Next hosts are " ~ hostOrder.cycle.drop(currentHostIndex + 1)
						.take(min(5, hostOrder.length - 1)).join(", ") ~ suffix);
		}
		else if (text == "!skip")
		{
			if (skippers.canFind(msg.sender))
				return;
			if (probablyPlaying && !canStillSkipMidMap)
			{
				if (getNow() - lastInfo < 10.seconds)
					return;
				lastInfo = getNow();
				room.sendMessage("Map is already too far progressed to skip it now.");
				return;
			}
			try
			{
				GameUser.findByUsername(msg.sender).voteSkip(skippers.length == 0);
			}
			catch (Exception)
			{
				room.sendMessage(msg.sender ~ ": yeah I can understand this decision.");
			}
			skippers ~= msg.sender;
			if (skippers.length >= requiredSkipUsers)
			{
				string host = currentHost;
				if (probablyPlaying)
					room.abortMatch();
				else
				{
					// TODO: maybe check if room is shortly before starting here
					switchState(selectState);
				}
				skippedMapIDs ~= currentMapInfo.id;
				try
				{
					GameUser.findByUsername(host).gotSkipped();
					room.sendMessage(host ~ ": your map got skipped, please pick another map.");
				}
				catch (Exception)
				{
					room.sendMessage(host ~ ": that's a crappy map, please pick another one.");
				}
			}
			else
				room.sendMessage("Map skip progress: " ~ .text(skippers.length, "/", requiredSkipUsers));
		}
		else if (text == "!r" || text == "!start")
		{
			room.sendMessage(
					msg.sender
					~ ": This room doesn't require any special commands, just play as usual. See !info");
		}
	}

	void onCountdownFinished()
	{
		if (stateTimer.state == currentState && !startingGame)
		{
			stateTimer = StateTimer.init;
			currentState.onStateTimerFinished();
		}
	}

	void onBeatmapChanged(BeatmapInfo beatmap)
	{
		currentState.onBeatmapChanged(beatmap);
	}

	void onBeatmapPending()
	{
		currentState.onBeatmapPending();
	}

	void onPlayersReady()
	{
		currentState.onPlayersReady();
	}

	void onMatchStart()
	{
		if (currentState != waitingState)
		{
			string user = currentHost;
			nextHost();
			room.abortMatch();
			try
			{
				GameUser.findByUsername(user).didInvalidStart();
				room.sendMessage(user ~ ": tried to start an invalid map, aborting and skipping host.");
			}
			catch (Exception)
			{
				room.sendMessage(
						user ~ ": tried to be a smartass and started anyway. Aborting and skipping host.");
			}
		}
		else if (!room.slots.length)
		{
			room.abortMatch();
			room.sendMessage("Currently having no users. Aborting match");
			nextHost();
		}
		else
		{
			try
			{
				foreach (slot; room.slots)
					if (slot.name.length)
						GameUser.findByUsername(slot.name).didStart();
			}
			catch (Exception e)
			{
				room.sendMessage("Have fun playing :)");
			}
			skippedMapIDs.length = 0;
			startingTime = getNow();
			probablyPlaying = true;
			currentState.onMatchStart();
			switchState(ingameState);
		}
	}

	void onMatchEnd()
	{
		try
		{
			foreach (slot; room.slots)
				if (slot.name.length)
					GameUser.findByUsername(slot.name).didFinish();
		}
		catch (Exception e)
		{
			room.sendMessage("Congrats for making it until the end \\o/");
		}

		startingGame = false;
		probablyPlaying = false;
		currentState.onMatchEnd();
		nextHost();

		requiredSkips = 1;
		skippers.length = 0;
	}

	void onUserHost(string user)
	{
		if (actualCurrentHost == currentHostIndex && user != currentHost)
		{
			string s = nextHost();
			if (s != user)
				room.sendMessage("Host passed elsewhere, passing where it was supposed to go next");
		}
	}

	void onUserJoin(string user, ubyte slot)
	{
		currentState.onUserJoin(user, slot);
		if (hostOrder.canFind(user))
			return;
		if (hostOrder.length)
		{
			// insert before current host
			hostOrder = hostOrder[0 .. currentHostIndex] ~ user ~ hostOrder[currentHostIndex .. $];
			currentHostIndex++;
			actualCurrentHost++;
		}
		else
		{
			hostOrder = [user]; // first join!
			nextHost();
			switchState(waitingState);
		}

		try
		{
			auto obj = GameUser.findByUsername(user);
			if (obj.joins == 0)
			{
				newUsers ~= user;
				newUserTimer.rearm(10.seconds);
			}
			obj.didJoin();
		}
		catch (Exception e)
		{
			room.sendMessage(user ~ ": I have been awaiting you.");
		}
	}

	void onUserLeave(string user)
	{
		if (user == currentHost)
		{
			if (!probablyPlaying)
				nextHost(true);
			else
			{
				try
				{
					auto obj = GameUser.findByUsername(user);
					obj.didLeaveAsHost();
					room.sendMessage(user ~ " has left as host, this is sad.");
				}
				catch (Exception e)
				{
					room.sendMessage(
							user ~ " has left as host, what a pleb. Laugh at them if they join again.");
				}
			}
		}
		newUsers = newUsers.remove!(a => a == user);
	}
}

abstract class State
{
	void enter();
	void leave();

	void onMatchEnd()
	{
	}

	void onBeatmapChanged(BeatmapInfo beatmap)
	{
	}

	void onBeatmapPending()
	{
	}

	void onStateTimerFinished()
	{
	}

	void onPlayersReady()
	{
	}

	void onMatchStart()
	{
	}

	void onUserJoin(string user, ubyte slot)
	{
	}
}

class SelectMapState : State
{
	ManagedRoom room;
	bool warningTimeout;
	this(ManagedRoom room)
	{
		this.room = room;
	}

	override void enter()
	{
		startIdleTimer();
	}

	override void leave()
	{

	}

	void startIdleTimer()
	{
		warningTimeout = true;
		room.setStateTimer(room.settings.selectWarningTimeout, false);
	}

	override void onBeatmapChanged(BeatmapInfo beatmap)
	{
		room.currentMapInfo = beatmap;
		room.abortStateTimer();
		auto info = room.checkMap();
		string title = info.artist ~ " - " ~ info.title;
		if (room.wasRecentlyPlayed(beatmap))
		{
			room.room.sendMessage(
					room.currentHost ~ ": Please pick another map! " ~ title ~ " was recently played.");
			startIdleTimer();
		}
		else if (room.skippedMapIDs.canFind(beatmap.id))
		{
			room.room.sendMessage(
					room.currentHost ~ ": Please pick another map! " ~ title ~ " was skipped.");
			startIdleTimer();
		}
		else
		{
			room.switchState(room.waitingState);
		}
	}

	override void onBeatmapPending()
	{
		warningTimeout = true;
		if (room.stateTimer.local)
		{
			room.abortStateTimer();
			room.setStateTimer(room.settings.selectWarningTimeout, false);
		}
	}

	override void onStateTimerFinished()
	{
		if (warningTimeout)
		{
			room.setStateTimer(room.settings.selectIdleChangeTimeout, true);
			warningTimeout = false;
			room.room.sendMessage(room.currentHost ~ ": please pick a map or next host will be picked!");
		}
		else
		{
			room.nextHost();
		}
	}
}

class WaitingState : State
{
	ManagedRoom room;
	this(ManagedRoom room)
	{
		this.room = room;
	}

	override void enter()
	{
		room.startGame(room.settings.startGameDuration);
	}

	override void leave()
	{
		room.abortStart();
	}

	override void onBeatmapChanged(BeatmapInfo beatmap)
	{
		room.room.sendMessage(
				"Hey this message should never have been sent! peppy ur game is broken plz fix.");
		room.switchState(room.selectState);
		room.selectState.onBeatmapChanged(beatmap);
	}

	override void onBeatmapPending()
	{
		room.switchState(room.selectState);
		room.selectState.onBeatmapPending();
	}

	override void onPlayersReady()
	{
		room.startGame(room.settings.allReadyStartDuration);
	}

	override void onMatchStart()
	{
		room.pushHistory(room.currentMapInfo);
	}
}

class IngameState : State
{
	ManagedRoom room;
	this(ManagedRoom room)
	{
		this.room = room;
	}

	override void onBeatmapChanged(BeatmapInfo beatmap)
	{
		room.room.sendMessage("How did you manage to change the beatmap in-game? :thinking:");
	}

	override void enter()
	{
		room.room.password = room.settings.password;
		room.abortStart();
		auto info = room.room.settings;
		if (room.settings.enforceTitle && room.expectedTitle.length
				&& info.name.strip != room.expectedTitle.strip)
			room.room.sendMessage("Please rename room name to: " ~ room.expectedTitle);
	}

	override void leave()
	{

	}
}

class EmptyState : State
{
	ManagedRoom room;
	this(ManagedRoom room)
	{
		this.room = room;
	}

	override void enter()
	{
	}

	override void leave()
	{
	}

	override void onUserJoin(string user, ubyte slot)
	{
		room.switchState(room.waitingState);
	}
}
