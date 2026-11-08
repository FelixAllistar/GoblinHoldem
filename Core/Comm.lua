-- Addon-message transport: framing, multi-part messages, a throttle-friendly send queue,
-- and local loopback so the sender processes its own group messages in send order.
--
-- Wire frame: "1<payload>" for a single message, or "M<id:2><part:1><total:1><payload>".
-- Payload fields are separated by "~" (character names can never contain it).
local _, ns = ...

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "GHoldem"
Comm.SEP = "~"
local MAX = 240
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local function b36(n) return B36:sub(n + 1, n + 1) end
local function unb36(c) local i = B36:find(c, 1, true) return i and i - 1 end

function Comm.Me()
	return ns.NormName(UnitName("player"))
end

function Comm.Join(...)
	local parts = { ... }
	for i = 1, select("#", ...) do
		local v = parts[i]
		parts[i] = v == nil and "" or tostring(v):gsub("~", "-")
	end
	return table.concat(parts, Comm.SEP)
end

function Comm.Split(payload)
	local out = {}
	for field in (payload .. Comm.SEP):gmatch("(.-)" .. Comm.SEP) do out[#out + 1] = field end
	return out
end

---------------------------------------------------------------------------------------------
-- Raw send + queue. Blizzard throttles addon messages per prefix (a burst of ~10, then about one
-- per second). We keep a token bucket a little under that and retry anything the client refuses.
---------------------------------------------------------------------------------------------
local queue = {}
local tokens, lastRefill = 10, 0
local BURST, RATE = 10, 1.2
local pumping = false

local function rawSend(text, dist, target)
	local api = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	if not api then return false end
	local ok, result = pcall(api, Comm.PREFIX, text, dist, target)
	if not ok then return false end
	if result == nil or result == true or result == 0 then return true end
	if type(result) == "table" then return true end
	return false
end

local function pump()
	local now = GetTime()
	tokens = math.min(BURST, tokens + (now - lastRefill) * RATE)
	lastRefill = now
	while #queue > 0 and tokens >= 1 do
		local m = queue[1]
		if rawSend(m.text, m.dist, m.target) then
			table.remove(queue, 1)
			tokens = tokens - 1
		else
			m.tries = (m.tries or 0) + 1
			if m.tries > 8 then table.remove(queue, 1) ns.Debug("dropped message after retries") end
			tokens = 0
			break
		end
	end
	if #queue > 0 then
		pumping = true
		C_Timer.After(0.5, pump)
	else
		pumping = false
	end
end

local msgId = 0
local function enqueue(payload, dist, target)
	if #payload + 1 <= MAX then
		queue[#queue + 1] = { text = "1" .. payload, dist = dist, target = target }
	else
		msgId = (msgId + 1) % 1296
		local id = b36(math.floor(msgId / 36)) .. b36(msgId % 36)
		local size = MAX - 4
		local total = math.ceil(#payload / size)
		assert(total <= 35, "message too large")
		for i = 1, total do
			local part = payload:sub((i - 1) * size + 1, i * size)
			queue[#queue + 1] = { text = "M" .. id .. b36(i) .. b36(total) .. part, dist = dist, target = target }
		end
	end
	if not pumping then pump() end
end

--- Run fn once everything queued so far has actually been handed to the client.
function Comm.WhenFlushed(fn, extra)
	if #queue == 0 then
		C_Timer.After(extra or 0, fn)
	else
		C_Timer.After(0.25, function() Comm.WhenFlushed(fn, extra) end)
	end
end

---------------------------------------------------------------------------------------------
-- Public send API
---------------------------------------------------------------------------------------------
function Comm.GroupDist()
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

--- Send to the whole table (the group). Processed locally right away, in order.
function Comm.Group(...)
	local payload = Comm.Join(...)
	local dist = Comm.GroupDist()
	if dist then enqueue(payload, dist) end
	Comm.Deliver(Comm.Me(), "LOCAL", payload)
end

function Comm.Whisper(target, ...)
	local payload = Comm.Join(...)
	if target == Comm.Me() then
		Comm.Deliver(target, "WHISPER", payload)
	else
		enqueue(payload, "WHISPER", target)
	end
end

--- Lobby adverts: a custom chat channel (by number) and/or the guild.
function Comm.Channel(channelNum, ...)
	enqueue(Comm.Join(...), "CHANNEL", channelNum)
end

function Comm.Guild(...)
	enqueue(Comm.Join(...), "GUILD")
end

---------------------------------------------------------------------------------------------
-- Receive
---------------------------------------------------------------------------------------------
local partial = {}

function Comm.OnAddonMessage(prefix, text, dist, sender)
	if prefix ~= Comm.PREFIX or type(text) ~= "string" then return end
	sender = ns.NormName(sender)
	-- group messages are already delivered locally by the sender's own client
	if sender == Comm.Me() and dist ~= "WHISPER" then return end
	local kind = text:sub(1, 1)
	if kind == "1" then
		Comm.Deliver(sender, dist, text:sub(2))
	elseif kind == "M" then
		local id, part, total = text:sub(2, 3), unb36(text:sub(4, 4)), unb36(text:sub(5, 5))
		if not part or not total or total < 1 then return end
		local key = sender .. ":" .. id
		local p = partial[key]
		if not p or p.total ~= total then
			p = { total = total, got = 0, parts = {}, at = GetTime() }
			partial[key] = p
		end
		if not p.parts[part] then
			p.parts[part] = text:sub(6)
			p.got = p.got + 1
		end
		if p.got == p.total then
			partial[key] = nil
			Comm.Deliver(sender, dist, table.concat(p.parts))
		end
		-- forget stale fragments
		for k, v in pairs(partial) do
			if GetTime() - v.at > 120 then partial[k] = nil end
		end
	end
end

function Comm.Deliver(sender, dist, payload)
	local fields = Comm.Split(payload)
	local ok, err = pcall(ns.OnMessage, sender, dist, fields)
	if not ok then ns.Debug("message error: " .. tostring(err)) end
end
