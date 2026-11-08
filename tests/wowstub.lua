-- Minimal stand-ins for the WoW API used by the core modules, for out-of-game tests.
GH_TIME = 0
function GetTime() return GH_TIME end
function UnitName() return GH_PLAYER end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
GH_SENT = {}     -- outgoing addon messages, drained by the Python router
GH_ROLLS = {}    -- RandomRoll requests, drained by the router (the "server" answers them)
function RandomRoll(lo, hi) GH_ROLLS[#GH_ROLLS + 1] = { lo = tonumber(lo), hi = tonumber(hi) } end
GH_TIMERS = {}
C_Timer = {
	After = function(delay, fn) GH_TIMERS[#GH_TIMERS + 1] = { at = GH_TIME + delay, fn = fn } end,
}
function GH_RunTimers()
	local due, keep = {}, {}
	for _, t in ipairs(GH_TIMERS) do
		if t.at <= GH_TIME then due[#due + 1] = t else keep[#keep + 1] = t end
	end
	GH_TIMERS = keep
	table.sort(due, function(a, b) return a.at < b.at end)
	for _, t in ipairs(due) do t.fn() end
	return #due
end

-- group + addon messages
function IsInGroup() return true end
function IsInRaid() return false end
C_ChatInfo = {
	SendAddonMessage = function(prefix, text, dist, target)
		assert(#text <= 255, "addon message too long: " .. #text)
		GH_SENT[#GH_SENT + 1] = { prefix = prefix, text = text, dist = dist, target = target }
		return true
	end,
}

-- chat channels (per client); the router delivers CHANNEL messages to everyone who joined
GH_GROUPED = true
function IsInGroup() return GH_GROUPED end
GH_CHANNELS, GH_CHANNEL_IDS = {}, {}
local nextChan = 1
function JoinTemporaryChannel(name, password)
	if not GH_CHANNELS[name] then
		GH_CHANNELS[name] = nextChan
		GH_CHANNEL_IDS[nextChan] = name
		nextChan = nextChan + 1
	end
end
function GetChannelName(name) return GH_CHANNELS[name] or 0, name end
function LeaveChannelByName(name) GH_CHANNELS[name] = nil end
local rawSendAddon = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(prefix, text, dist, target)
	if dist == "CHANNEL" then
		local name = GH_CHANNEL_IDS[target]
		assert(name and GH_CHANNELS[name], "sending to a channel we are not in")
		GH_SENT[#GH_SENT + 1] = { prefix = prefix, text = text, dist = dist, target = target, chanName = name }
		return true
	end
	return rawSendAddon(prefix, text, dist, target)
end
