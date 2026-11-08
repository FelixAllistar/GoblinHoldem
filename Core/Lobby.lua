-- Public table discovery. Dealers advertise on a hidden custom chat channel (realm-wide, same
-- faction) and to their guild. Players browse the list and ask for an invite; the actual game
-- always runs inside the dealer's party/raid, where everyone can see every /roll.
local _, ns = ...

local Comm = ns.Comm
local Lobby = { tables = {} }
ns.Lobby = Lobby

Lobby.CHANNEL = "GoblinHoldem"
local EXPIRE = 150

function Lobby.ChannelNum()
	if not GetChannelName then return nil end
	local id = GetChannelName(Lobby.CHANNEL)
	if id and id > 0 then return id end
end

function Lobby.EnsureChannel()
	if Lobby.ChannelNum() then return true end
	Comm.JoinChannel(Lobby.CHANNEL)
	return Lobby.ChannelNum() ~= nil
end

local function send(...)
	local num = Lobby.ChannelNum()
	if num then Comm.Channel(num, ...) end
	if IsInGuild and IsInGuild() then Comm.Guild(...) end
end

local function where()
	local zone = GetRealZoneText and GetRealZoneText() or ""
	local sub = GetSubZoneText and GetSubZoneText() or ""
	if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
	return zone
end

function Lobby.Advertise(t)
	if not t or not t.isDealer or not t.cfg.public or t.phase == "closed" then return end
	local seated = 0
	for _ in pairs(t.engine.seats) do seated = seated + 1 end
	send("ADV", t.id, t.cfg.name, t.cfg.sb, t.cfg.bb, seated, t.cfg.maxSeats, t.cfg.mode,
		t.cfg.dealerSeated and 1 or 0, where(), t.cfg.minBuy, t.cfg.maxBuy, t.cfg.transport)
end

function Lobby.Ask()
	Lobby.EnsureChannel()
	send("ASK")
	Lobby.lastAsk = GetTime()
end

function Lobby.RequestJoin(entry)
	Lobby.wanted = Lobby.wanted or {}
	Lobby.wanted[entry.id] = true
	Comm.Whisper(entry.dealer, "JOIN", entry.id)
	ns.Print(("Asked %s for an invite to %s."):format(entry.dealer, entry.name))
end

function Lobby.Prune()
	local now = GetTime()
	for id, e in pairs(Lobby.tables) do
		if now - e.seen > EXPIRE then Lobby.tables[id] = nil end
	end
end

function Lobby.List()
	Lobby.Prune()
	local list = {}
	for _, e in pairs(Lobby.tables) do list[#list + 1] = e end
	table.sort(list, function(a, b) return a.bb > b.bb end)
	return list
end

local lastAnswer = 0
function Lobby.OnMessage(sender, dist, f)
	local kind = f[1]
	if kind == "ADV" then
		local e = {
			id = f[2], name = f[3], sb = tonumber(f[4]) or 0, bb = tonumber(f[5]) or 0,
			seated = tonumber(f[6]) or 0, maxSeats = tonumber(f[7]) or 9, mode = f[8],
			dealerSeated = f[9] == "1", where = f[10] or "", minBuy = tonumber(f[11]) or 0,
			maxBuy = tonumber(f[12]) or 0, transport = f[13] or "group", dealer = sender, seen = GetTime(), via = dist,
		}
		Lobby.tables[e.id] = e
		ns.Emit("LOBBY_UPDATE")
	elseif kind == "ASK" then
		local t = ns.current
		if t and t.isDealer and t.cfg.public and GetTime() - lastAnswer > 10 then
			lastAnswer = GetTime()
			Lobby.Advertise(t)
		end
	elseif kind == "JOIN" then
		local t = ns.current
		if t and t.isDealer and (f[2] == "" or t.id == f[2]) and t.phase ~= "closed" then
			t:HandleJoin(sender)
		end
	end
end
