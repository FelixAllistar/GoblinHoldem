-- Table protocol: one dealer (the host) and any number of seated players / spectators in the
-- same party or raid. Every client runs the same Engine and applies the same messages.
--
-- Trust model, in one paragraph:
--   * Actions are sent by the player who takes them (the server stamps the sender; it can't be faked)
--     and every add-on checks them against the rules, so nobody can bet chips they don't have.
--   * The deck is sealed (committed) before the server rolls that seed it, and unsealed afterwards,
--     so the dealer cannot stack it and every add-on checks the deal (see Fair.lua).
--   * What you still have to trust: the dealer's add-on knows all hole cards during the hand. Use a
--     dealer who isn't playing for games with strangers; the UI warns when the dealer is seated.
local _, ns = ...

local Comm, Fair, Cards, Engine = ns.Comm, ns.Fair, ns.Cards, ns.Engine
local Table = {}
Table.__index = Table
ns.Table = Table

Table.ROLL_MIN, Table.ROLL_MAX = 1, 1000000
Table.ROLL_WINDOW = 15
Table.MODES = {
	iou = "Friends (IOU)",
	bank = "House bank",
	fun = "Play chips",
}

local function after(delay, fn) C_Timer.After(delay, fn) end
local function me() return Comm.Me() end

---------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------
local function newTable(id, dealer, cfg)
	local t = setmetatable({}, Table)
	t.id, t.dealer, t.cfg = id, dealer, cfg
	t.engine = Engine.New({ maxSeats = cfg.maxSeats, sb = cfg.sb, bb = cfg.bb })
	t.engine.listener = function(...) t:OnEngine(...) end
	t.isDealer = dealer == me()
	t.handNo = 0
	t.phase = "idle"
	t.ledger = {}
	t.log = {}
	t.alerts = {}
	t.audits = {}
	t.stats = { voids = 0, aborts = 0, verified = 0, failed = 0 }
	if t.isDealer then
		t.keys = {}
		t.requests = {} -- awaiting the dealer's approval
		t.pending = { sits = {}, buys = {}, leaves = {}, sitout = {} }
		t.autoDeal = true
	end
	return t
end

function Table:Log(text)
	self.log[#self.log + 1] = text
	if #self.log > 400 then table.remove(self.log, 1) end
	ns.Emit("TABLE_LOG", self, text)
end

--- severity: "info" | "warn" | "cheat"
function Table:Alert(text, severity)
	self.alerts[#self.alerts + 1] = { text = text, severity = severity or "warn", hand = self.handNo }
	self:Log((severity == "cheat" and "|cffff2020" or "|cffffa020") .. text .. "|r")
	ns.Emit("TABLE_ALERT", self, text, severity)
end

function Table:Changed() ns.Emit("TABLE_UPDATE", self) end

function Table:Name(seat)
	local s = self.engine.seats[seat]
	return s and s.name or ("seat " .. tostring(seat))
end

function Table:Fmt(amount) return ns.Money(amount, self.cfg.mode, true) end

function Table:MySeat() return self.engine:SeatOf(me()) end

---------------------------------------------------------------------------------------------
-- Snapshots: "seat,name,stack,buyIn,flags/..." describes seating between hands.
---------------------------------------------------------------------------------------------
local function encodeSnapshot(entries)
	local parts = {}
	for _, e in ipairs(entries) do
		parts[#parts + 1] = table.concat({ e.seat, e.name, e.stack, e.buyIn, e.out and "o" or "" }, ",")
	end
	return table.concat(parts, "/")
end

local function decodeSnapshot(str)
	local entries = {}
	for chunk in (str or ""):gmatch("[^/]+") do
		local seat, name, stack, buyIn, flags = chunk:match("^(%d+),([^,]+),(%d+),(%d+),(%a*)$")
		if seat then
			entries[#entries + 1] = {
				seat = tonumber(seat), name = name, stack = tonumber(stack),
				buyIn = tonumber(buyIn), out = flags:find("o") ~= nil,
			}
		end
	end
	return entries
end

function Table:ApplySnapshot(str)
	local entries = decodeSnapshot(str)
	local present = {}
	for _, e in ipairs(entries) do
		present[e.name] = true
		local L = self.ledger[e.name]
		local seat = self.engine:SeatOf(e.name)
		if L and seat and self.synced then
			local expected = self.engine.seats[seat].stack + (e.buyIn - L.buyIn)
			if expected ~= e.stack then
				self:Alert(("%s's stack is %s, but your add-on counted %s. Either you missed a message or the dealer changed it.")
					:format(e.name, self:Fmt(e.stack), self:Fmt(expected)), "warn")
			end
		end
		if not L then
			L = { buyIn = 0, out = 0, stack = 0 }
			self.ledger[e.name] = L
		end
		if e.buyIn > L.buyIn then
			self:Log(("%s buys in for %s."):format(e.name, self:Fmt(e.buyIn - L.buyIn)))
		end
		L.buyIn = e.buyIn
	end
	for _, s in pairs(self.engine.seats) do
		if not present[s.name] then
			local L = self.ledger[s.name]
			if L then
				L.out = L.out + s.stack
				L.stack = 0
				L.seated = false
			end
			self:Log(("%s leaves the table with %s."):format(s.name, self:Fmt(s.stack)))
		end
	end
	local seats = {}
	for _, e in ipairs(entries) do
		seats[e.seat] = { name = e.name, stack = e.stack, sittingOut = e.out }
		self.ledger[e.name].stack = e.stack
		self.ledger[e.name].seated = true
	end
	self.engine.seats = seats
	self.synced = true
end

function Table:CurrentEntries()
	local entries = {}
	for seat = 1, self.cfg.maxSeats do
		local s = self.engine.seats[seat]
		if s then
			local L = self.ledger[s.name]
			entries[#entries + 1] = { seat = seat, name = s.name, stack = s.stack, buyIn = L and L.buyIn or 0, out = s.sittingOut }
		end
	end
	return entries
end

---------------------------------------------------------------------------------------------
-- Hosting
---------------------------------------------------------------------------------------------
function Table.Host(cfg)
	if ns.current and ns.current.phase ~= "closed" then return nil, "you are already at a table" end
	if not Comm.GroupDist() and not cfg.allowSolo then return nil, "form a party or raid first - the table runs on your group" end
	local id = Fair.NewSecret():sub(1, 6)
	local t = newTable(id, me(), cfg)
	ns.current = t
	t:Log(("You opened %s: %s/%s no-limit, %s."):format(cfg.name, t:Fmt(cfg.sb), t:Fmt(cfg.bb), Table.MODES[cfg.mode]))
	t:Announce()
	if cfg.dealerSeated and cfg.dealerBuyIn then
		t:RequestSeat(1, cfg.dealerBuyIn)
	end
	t:Changed()
	ns.Emit("TABLE_OPENED", t)
	return t
end

--- Rebuild a dealer's table from SavedVariables after a /reload (see Init.lua).
function Table.Restore(s)
	local t = newTable(s.id, me(), s.cfg)
	t.handNo = s.handNo or 0
	t.ledger = s.ledger or {}
	t.keys = s.keys or {}
	t.myKey = s.myKey
	t.secret = s.secret
	t.stats = s.stats or t.stats
	t.autoDeal = s.autoDeal ~= false
	t.engine.button = s.button or 0
	for _, e in ipairs(s.entries or {}) do
		t.engine.seats[e.seat] = { name = e.name, stack = e.stack, sittingOut = e.out }
	end
	t.synced = true
	return t
end

function Table:Announce(target)
	local c = self.cfg
	local fields = { "TBL", self.id, c.name, c.sb, c.bb, c.minBuy, c.maxBuy, c.maxSeats, c.mode,
		c.dealerSeated and 1 or 0, c.actTimeout, self.handNo, ns.version or "dev" }
	if target then Comm.Whisper(target, unpack(fields)) else Comm.Group(unpack(fields)) end
end

--- Approved seat changes are applied between hands only.
function Table:ProposedSnapshot()
	local p = self.pending
	local entries, taken = {}, {}
	for _, e in ipairs(self:CurrentEntries()) do
		if not p.leaves[e.name] then
			local add = p.buys[e.name]
			if add then e.stack = e.stack + add e.buyIn = e.buyIn + add end
			if p.sitout[e.name] ~= nil then e.out = p.sitout[e.name] end
			entries[#entries + 1] = e
			taken[e.seat] = true
		end
	end
	for name, s in pairs(p.sits) do
		if not taken[s.seat] and not self.engine:SeatOf(name) then
			local L = self.ledger[name]
			entries[#entries + 1] = { seat = s.seat, name = name, stack = s.amount, buyIn = (L and L.buyIn or 0) + s.amount, out = false }
			taken[s.seat] = true
		end
	end
	table.sort(entries, function(a, b) return a.seat < b.seat end)
	self.pending = { sits = {}, buys = {}, leaves = {}, sitout = {} }
	return encodeSnapshot(entries)
end

function Table:PublishSeats()
	if self.engine:InHand() or self.phase == "rolling" then return end
	Comm.Group("SEATS", self.id, self.handNo, self:ProposedSnapshot())
	self:MaybeAutoDeal()
end

function Table:SeatFree(seat)
	if seat < 1 or seat > self.cfg.maxSeats or self.engine.seats[seat] then return false end
	for _, s in pairs(self.pending.sits) do if s.seat == seat then return false end end
	return true
end

function Table:HandleSitRequest(name, seat, amount, key)
	local c = self.cfg
	local function deny(reason) Comm.Whisper(name, "DENY", self.id, reason) end
	if self.phase == "closed" then return deny("table closed") end
	if self.engine:SeatOf(name) then
		self.keys[name] = key -- re-sent key after a reload
		return
	end
	if not amount or amount < c.minBuy or amount > c.maxBuy then
		return deny(("buy-in must be between %s and %s"):format(self:Fmt(c.minBuy), self:Fmt(c.maxBuy)))
	end
	if not key or #key < 16 then return deny("bad key") end
	if not self:SeatFree(seat) then
		seat = nil
		for i = 1, c.maxSeats do if self:SeatFree(i) then seat = i break end end
		if not seat then return deny("table is full") end
	end
	local req = { kind = "sit", name = name, seat = seat, amount = amount, key = key }
	if c.mode == "bank" and name ~= me() then
		self:AddRequest(req)
	else
		self:Approve(req)
	end
end

function Table:HandleBuyRequest(name, amount)
	local seat = self.engine:SeatOf(name)
	if not seat or not amount or amount <= 0 then return end
	local stack = self.engine.seats[seat].stack + (self.pending.buys[name] or 0)
	if stack + amount > self.cfg.maxBuy then
		return Comm.Whisper(name, "DENY", self.id, "that would put you over the max buy-in")
	end
	local req = { kind = "buy", name = name, amount = amount }
	if self.cfg.mode == "bank" and name ~= me() then self:AddRequest(req) else self:Approve(req) end
end

function Table:AddRequest(req)
	for i, r in ipairs(self.requests) do
		if r.name == req.name and r.kind == req.kind then table.remove(self.requests, i) break end
	end
	self.requests[#self.requests + 1] = req
	self:Log(("%s asks to %s for %s - approve it once you have the gold."):format(req.name,
		req.kind == "sit" and "sit down" or "add chips", self:Fmt(req.amount or 0)))
	ns.Emit("TABLE_REQUEST", self, req)
	self:Changed()
end

function Table:Approve(req)
	for i, r in ipairs(self.requests) do if r == req then table.remove(self.requests, i) break end end
	if req.kind == "sit" then
		if not self:SeatFree(req.seat) then
			return Comm.Whisper(req.name, "DENY", self.id, "seat was taken")
		end
		self.keys[req.name] = req.key
		self.pending.sits[req.name] = { seat = req.seat, amount = req.amount }
	elseif req.kind == "buy" then
		self.pending.buys[req.name] = (self.pending.buys[req.name] or 0) + req.amount
	elseif req.kind == "join" then
		if InviteUnit then InviteUnit(req.name) elseif C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(req.name) end
		self:Changed()
		return
	end
	self:PublishSeats()
	self:Changed()
end

function Table:Deny(req, reason)
	for i, r in ipairs(self.requests) do if r == req then table.remove(self.requests, i) break end end
	if req.kind ~= "join" then Comm.Whisper(req.name, "DENY", self.id, reason or "the dealer said no") end
	self:Changed()
end

function Table:Kick(name)
	self.pending.leaves[name] = true
	if not self.engine:InHand() then self:PublishSeats() end
	self:Changed()
end

---------------------------------------------------------------------------------------------
-- Dealer: running hands
---------------------------------------------------------------------------------------------
function Table:CanDeal()
	if not self.isDealer or self.phase ~= "idle" or self.engine:InHand() then return false end
	local n = 0
	for _, e in ipairs(self:CurrentEntries()) do
		if not e.out and e.stack > 0 and not self.pending.leaves[e.name] then n = n + 1 end
	end
	for _ in pairs(self.pending.sits) do n = n + 1 end
	return n >= 2
end

function Table:DealNext()
	if not self:CanDeal() then return false end
	local no = self.handNo + 1
	self.secret = Fair.NewSecret()
	self.dealing = { no = no }
	Comm.Group("HAND", self.id, no, Fair.Commit(self.secret), self:ProposedSnapshot())
	after(Table.ROLL_WINDOW, function()
		if self.phase == "rolling" and self.handNo == no then self:FinishRolls() end
	end)
	return true
end

function Table:FinishRolls()
	local cur = self.cur
	if not self.isDealer or self.phase ~= "rolling" or not cur or self.dealing == nil or self.dealing.no ~= cur.no then return end
	self.dealing = nil
	local rolls, players = {}, {}
	for name, seat in pairs(cur.eligible) do
		if cur.observed[name] and self.keys[name] then
			rolls[seat] = cur.observed[name]
			players[#players + 1] = seat
		elseif cur.observed[name] then
			self:Log(name .. " has no card key yet - sitting this hand out.")
		end
	end
	if #players < 2 then
		Comm.Group("ABORT", self.id, cur.no, self.secret, "not enough players rolled")
		return
	end
	table.sort(players)
	local plan = self.engine:PlanHand(players)
	local rollStr = Fair.RollString(rolls)
	local deck = Fair.Deck(self.id, cur.no, self.secret, rollStr)
	local holes, board = Cards.Layout(deck, plan.order)
	self.dealerBoard = board
	local sealed = {}
	for _, seat in ipairs(players) do
		local name = self.engine.seats[seat].name
		sealed[#sealed + 1] = seat .. ":" .. Fair.SealHole(self.keys[name], self.id, cur.no, holes[seat][1], holes[seat][2])
	end
	Comm.Group("DEAL", self.id, cur.no, rollStr, table.concat(sealed, "/"), self.engine.button)
end

function Table:DealerOnEngine(event, a)
	local h = self.engine.hand
	if not h then return end
	local no = h.no
	if event == "needBoard" then
		after(self.cfg.boardDelay or 1.0, function()
			local hh = self.engine.hand
			if not hh or hh.no ~= no or hh.phase ~= "board" then return end
			local b = self.dealerBoard
			local cards = hh.street == 1 and { b[1], b[2], b[3] } or { b[hh.street + 2] }
			Comm.Group("BOARD", self.id, no, Cards.ListToString(cards))
		end)
	elseif event == "needShowdown" or (event == "handEnd" and not a.voided) then
		after(0.5, function()
			if self.revealedNo == no then return end
			self.revealedNo = no
			Comm.Group("REVEAL", self.id, no, self.secret)
		end)
	elseif event == "turn" then
		local seat, seq = a, h.seq
		local name = self.engine.seats[seat] and self.engine.seats[seat].name
		local quick = name and (self.pending.leaves[name] or self.away and self.away[name])
		after(quick and 1 or self.cfg.actTimeout, function()
			local hh = self.engine.hand
			if hh and hh.no == no and hh.seq == seq and hh.toAct == seat and hh.phase == "betting" then
				Comm.Group("TOUT", self.id, no, seq + 1, seat)
			end
		end)
	end
end

function Table:AfterHand()
	if not self.isDealer then return end
	after(0.2, function() self:PublishSeats() end)
	self:MaybeAutoDeal()
end

--- Deal the next hand after a short pause, if auto-deal is on and two players are ready.
function Table:MaybeAutoDeal(delay)
	if not self.isDealer or not self.autoDeal or self.autoDealPending then return end
	self.autoDealPending = true
	after(delay or self.cfg.handPause or 6, function()
		self.autoDealPending = false
		if self.autoDeal and self:CanDeal() then self:DealNext() end
	end)
end

function Table:Close()
	if not self.isDealer then return end
	Comm.Group("CLOSE", self.id)
end

--- Dealer lost the hand (reload, crash): give everyone their chips back.
function Table:VoidCurrent(reason)
	if not self.isDealer then return end
	Comm.Group("VOID", self.id, self.handNo, reason or "voided by dealer", self.secret or "")
end

---------------------------------------------------------------------------------------------
-- Player actions (any seat, including a seated dealer)
---------------------------------------------------------------------------------------------
function Table:RequestSeat(seat, amount)
	self.myKey = self.myKey or Fair.NewSecret():sub(1, 32)
	ns.SaveKey(self.id, self.myKey)
	Comm.Whisper(self.dealer, "SIT", self.id, seat, amount, self.myKey)
end

function Table:RequestChips(amount)
	Comm.Whisper(self.dealer, "BUY", self.id, amount)
end

function Table:SitOut(flag)
	Comm.Group("SITOUT", self.id, flag and 1 or 0)
end

function Table:Leave()
	Comm.Group("LEAVE", self.id)
	self.leaving = true
	self:Changed()
end

function Table:Act(kind, amount)
	local h = self.engine.hand
	local seat = self:MySeat()
	if not h or not seat or h.toAct ~= seat then return false, "not your turn" end
	local legal = self.engine:Legal(seat)
	if not legal then return false, "not your turn" end
	if kind == "raise" then
		amount = math.max(legal.minTo, math.min(legal.maxTo, math.floor(amount or 0)))
		if amount >= legal.maxTo then kind = "allin" end
	end
	Comm.Group("ACT", self.id, h.no, h.seq + 1, kind, amount or 0)
	return true
end

function Table:Roll()
	local cur = self.cur
	if not cur or self.phase ~= "rolling" or cur.rolled then return end
	cur.rolled = true
	RandomRoll(Table.ROLL_MIN, Table.ROLL_MAX)
end

---------------------------------------------------------------------------------------------
-- Everyone: incoming messages
---------------------------------------------------------------------------------------------
local handlers = {}

function ns.OnMessage(sender, dist, f)
	local kind = f[1]
	if kind == "ADV" or kind == "JOIN" or kind == "ASK" then return ns.Lobby and ns.Lobby.OnMessage(sender, dist, f) end
	local h = handlers[kind]
	if not h then return end
	local t = ns.current
	if kind == "TBL" then return h(sender, f) end
	if kind == "HELLO" then
		if t and t.isDealer and t.phase ~= "closed" then
			t:Announce(sender)
			if not t.engine:InHand() and t.phase == "idle" then
				Comm.Whisper(sender, "SEATS", t.id, t.handNo, encodeSnapshot(t:CurrentEntries()))
			end
		end
		return
	end
	if not t or f[2] ~= t.id then return end
	return h(t, sender, f, dist)
end

handlers.TBL = function(sender, f)
	local t = ns.current
	if t and t.id == f[2] then
		t.cfg.name = f[3]
		return
	end
	if t and t.phase ~= "closed" and t.dealer ~= sender then return end -- already at another table
	local cfg = {
		name = f[3], sb = tonumber(f[4]), bb = tonumber(f[5]), minBuy = tonumber(f[6]), maxBuy = tonumber(f[7]),
		maxSeats = tonumber(f[8]), mode = f[9], dealerSeated = f[10] == "1", actTimeout = tonumber(f[11]) or 30,
	}
	if not (cfg.sb and cfg.bb and cfg.maxSeats and Table.MODES[cfg.mode]) then return end
	local nt = newTable(f[2], sender, cfg)
	nt.handNo = tonumber(f[12]) or 0
	nt.myKey = ns.LoadKey(nt.id)
	ns.current = nt
	nt:Log(("%s is dealing %s: %s/%s no-limit, %s."):format(sender, cfg.name, nt:Fmt(cfg.sb), nt:Fmt(cfg.bb), Table.MODES[cfg.mode]))
	if cfg.dealerSeated then
		nt:Alert("The dealer is also playing. Their add-on can see every hole card while a hand is live - only play for stakes with people you trust.", "info")
	end
	ns.Emit("TABLE_OPENED", nt)
	nt:Changed()
end

handlers.SEATS = function(t, sender, f)
	if sender ~= t.dealer then return end
	if t.engine:InHand() or t.phase == "rolling" then return end
	t.handNo = math.max(t.handNo, tonumber(f[3]) or 0)
	t:ApplySnapshot(f[4])
	if t.myKey and t:MySeat() and t.dealer ~= me() then
		-- after a reload the dealer may need our key again; cheap to resend
		if not t.keySent then t.keySent = true Comm.Whisper(t.dealer, "SIT", t.id, t:MySeat(), 0, t.myKey) end
	end
	t:Changed()
end

handlers.SIT = function(t, sender, f)
	if not t.isDealer then return end
	t:HandleSitRequest(sender, tonumber(f[3]) or 1, tonumber(f[4]), f[5])
end

handlers.BUY = function(t, sender, f)
	if not t.isDealer then return end
	t:HandleBuyRequest(sender, tonumber(f[3]))
end

handlers.DENY = function(t, sender, f)
	if sender ~= t.dealer then return end
	t:Alert("Dealer: " .. tostring(f[3]), "info")
	t:Changed()
end

handlers.SITOUT = function(t, sender, f)
	if t.isDealer and t.engine:SeatOf(sender) then
		t.pending.sitout[sender] = f[3] == "1"
		t:PublishSeats()
	end
	t:Log(sender .. (f[3] == "1" and " will sit out." or " is back."))
end

handlers.LEAVE = function(t, sender, f)
	t:Log(sender .. " is leaving the table.")
	if t.isDealer then
		if t.engine:SeatOf(sender) then t:Kick(sender) end
		for i, r in ipairs(t.requests) do if r.name == sender then table.remove(t.requests, i) break end end
		t.pending.sits[sender] = nil
	end
	t:Changed()
end

handlers.CLOSE = function(t, sender, f)
	if sender ~= t.dealer then return end
	if t.engine:InHand() then t.engine:Void() end
	t:ApplySnapshot("") -- everyone cashes out
	t.phase = "closed"
	t:Log("The table is closed. Open the ledger to settle up.")
	ns.Emit("TABLE_CLOSED", t)
	ns.SaveSession(t)
	t:Changed()
end

handlers.HAND = function(t, sender, f)
	if sender ~= t.dealer then return end
	local no = tonumber(f[3])
	if not no or no <= t.handNo then return end
	if t.engine:InHand() then -- we missed the end of the last hand somehow
		t.engine:Void()
		t.synced = false
	end
	t:ApplySnapshot(f[5])
	t.handNo = no
	t.phase = "rolling"
	local cur = { no = no, commit = f[4], eligible = {}, observed = {}, board = {}, sealed = {} }
	t.cur = cur
	for seat, s in pairs(t.engine.seats) do
		if not s.sittingOut and s.stack > 0 then cur.eligible[s.name] = seat end
	end
	t:Log(("|cffffd100Hand #%d|r - the dealer sealed the deck (%s...). Rolling for the shuffle."):format(no, f[4]:sub(1, 10)))
	local early = t.earlyRolls
	t.earlyRolls = nil
	for _, r in ipairs(early or {}) do
		if GetTime() - r.at <= 5 then t:OnSystem(r.text) end
	end
	if cur.eligible[me()] and t.myKey then
		if ns.db and ns.db.settings.autoRoll == false then
			ns.Emit("TABLE_ROLL_NEEDED", t)
		else
			-- roll only once the HAND message (with the seal) has really left our send queue
			Comm.WhenFlushed(function() t:Roll() end, 0.3 + math.random() * 0.5)
		end
	end
	t:Changed()
end

--- System chat: "<name> rolls <n> (<min>-<max>)", made and broadcast by the Blizzard server.
local rollPattern
function Table.ParseRoll(text)
	if not rollPattern then
		local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
		fmt = fmt:gsub("([%(%)%.%[%]%+%-%*%?%^%$])", "%%%1")
		fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
		rollPattern = "^" .. fmt .. "$"
	end
	local name, roll, lo, hi = text:match(rollPattern)
	if not name then return nil end
	return ns.NormName(name), tonumber(roll), tonumber(lo), tonumber(hi)
end

function Table:OnSystem(text)
	local name, roll, lo, hi = Table.ParseRoll(text)
	if not name then return end
	local cur = self.cur
	if self.phase ~= "rolling" or not cur then
		-- system chat and addon messages travel separately; keep very recent rolls in case the
		-- HAND message they belong to is still on its way
		if self.phase == "idle" then
			self.earlyRolls = self.earlyRolls or {}
			table.insert(self.earlyRolls, { text = text, at = GetTime() })
			while #self.earlyRolls > 0 and GetTime() - self.earlyRolls[1].at > 5 do table.remove(self.earlyRolls, 1) end
		end
		return
	end
	if not cur.eligible[name] then return end
	if lo ~= Table.ROLL_MIN or hi ~= Table.ROLL_MAX then
		self:Log(("%s rolled %d-%d - only 1-1000000 counts for the shuffle."):format(name, lo or 0, hi or 0))
		return
	end
	if cur.observed[name] then return end
	cur.observed[name] = roll
	self:Log(("  %s rolls |cffffffff%d|r"):format(name, roll))
	if self.isDealer and self.dealing then
		local all = true
		for n in pairs(cur.eligible) do if not cur.observed[n] then all = false break end end
		if all then after(0.3, function() self:FinishRolls() end) end
	end
	self:Changed()
end

handlers.DEAL = function(t, sender, f)
	if sender ~= t.dealer then return end
	local cur = t.cur
	local no = tonumber(f[3])
	if not cur or cur.no ~= no or t.phase ~= "rolling" then return end
	local rolls = Fair.ParseRolls(f[4])
	local players = {}
	for seat, v in pairs(rolls) do
		local s = t.engine.seats[seat]
		local name = s and s.name
		players[#players + 1] = seat
		if not name or not cur.eligible[name] then
			t:Alert(("Dealer dealt in seat %d, which wasn't eligible this hand."):format(seat), "cheat")
		elseif cur.observed[name] == nil then
			t:Alert(("You didn't see %s's roll, so you can't confirm it (dealer used %d)."):format(name, v), "warn")
		elseif cur.observed[name] ~= v then
			t:Alert(("Dealer used %d for %s, but the server rolled %d!"):format(v, name, cur.observed[name]), "cheat")
		end
	end
	for name, v in pairs(cur.observed) do
		local seat = cur.eligible[name]
		if seat and not rolls[seat] then
			t:Alert(("%s rolled %d but was left out of the shuffle."):format(name, v), "warn")
		end
	end
	table.sort(players)
	for entry in (f[5] or ""):gmatch("[^/]+") do
		local seat, code = entry:match("^(%d+):(%w+)$")
		if seat then cur.sealed[tonumber(seat)] = code end
	end
	-- the button only moves among dealt-in seats; take the dealer's previous button so that
	-- players who joined late agree on blinds and deal order
	t.engine.button = tonumber(f[6]) or t.engine.button
	local ok, err = t.engine:StartHand(no, players)
	if not ok then
		t:Alert("Could not start hand: " .. tostring(err), "warn")
		t.phase = "idle"
		return t:Changed()
	end
	cur.rolls = f[4]
	cur.dealOrder = t.engine.hand.order
	cur.mySeat = t:MySeat()
	if cur.mySeat and cur.sealed[cur.mySeat] and t.myKey then
		local c1, c2 = Fair.OpenHole(t.myKey, t.id, no, cur.sealed[cur.mySeat])
		if c1 then
			cur.myHole = { c1, c2 }
			t:Log(("You are dealt %s %s."):format(Cards.ToString(c1), Cards.ToString(c2)))
		end
	end
	t.phase = "playing"
	ns.Emit("TABLE_DEALT", t)
	t:Changed()
end

handlers.ACT = function(t, sender, f)
	local h = t.engine.hand
	local no, seq = tonumber(f[3]), tonumber(f[4])
	if not h or h.no ~= no or h.seq + 1 ~= seq then return end
	local seat = t.engine:SeatOf(sender)
	if not seat or h.toAct ~= seat then return end
	local ok, err = t.engine:Act(seat, f[5], tonumber(f[6]))
	if not ok then t:Log(("Ignored %s's %s: %s"):format(sender, tostring(f[5]), tostring(err))) end
end

handlers.TOUT = function(t, sender, f)
	if sender ~= t.dealer then return end
	local h = t.engine.hand
	local no, seq, seat = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
	if not h or h.no ~= no or h.seq + 1 ~= seq or h.toAct ~= seat then return end
	local legal = t.engine:Legal(seat)
	t:Log(t:Name(seat) .. " ran out of time.")
	t.engine:Act(seat, legal and legal.check and "check" or "fold")
end

handlers.BOARD = function(t, sender, f)
	if sender ~= t.dealer then return end
	local h = t.engine.hand
	if not h or h.no ~= tonumber(f[3]) then return end
	local cards = Cards.ListFromString(f[4])
	if not cards then return end
	local ok, err = t.engine:DealBoard(cards)
	if ok then
		for _, c in ipairs(cards) do t.cur.board[#t.cur.board + 1] = c end
	else
		t:Log("Bad board message: " .. tostring(err))
	end
end

function Table:Audit(no, secret)
	local cur = self.cur
	local rec = {
		tableId = self.id, handNo = no, commit = cur.commit, rolls = cur.rolls or "",
		dealOrder = cur.dealOrder or {}, board = cur.board, myHole = cur.myHole, mySeat = cur.mySeat,
	}
	local ok, issues, holes = Fair.Audit(rec, secret)
	local entry = {
		table = self.id, tableName = self.cfg.name, hand = no, commit = cur.commit, secret = secret,
		rolls = cur.rolls, ok = ok, issues = issues, time = time and time() or 0,
		board = Cards.ListToString(cur.board), me = cur.myHole and Cards.ListToString(cur.myHole) or nil,
	}
	self.audits[#self.audits + 1] = entry
	ns.SaveAudit(entry)
	if ok then
		self.stats.verified = self.stats.verified + 1
		self:Log(("|cff40ff40Hand #%d verified|r - deck matches the sealed commit and the server rolls."):format(no))
	else
		self.stats.failed = self.stats.failed + 1
		for _, issue in ipairs(issues) do self:Alert(("Hand #%d audit FAILED: %s"):format(no, issue), "cheat") end
	end
	return ok, holes
end

handlers.REVEAL = function(t, sender, f)
	if sender ~= t.dealer then return end
	local h = t.engine.hand
	local no = tonumber(f[3])
	if not h or h.no ~= no or not t.cur or t.cur.no ~= no or t.cur.revealed then return end
	t.cur.revealed = true
	local ok, holes = t:Audit(no, f[4])
	if h.phase == "showdown" then
		if ok then
			local live = {}
			for seat in pairs(h.inHand) do
				if not h.folded[seat] then live[seat] = holes[seat] end
			end
			t.engine:Showdown(live)
		else
			t.engine:Void()
			t:Alert("The hand was voided because the deal could not be verified.", "cheat")
		end
	elseif h.phase ~= "done" then
		t:Alert("Dealer revealed the deck before the hand was over - hand voided.", "cheat")
		t.engine:Void()
	end
	if t.cur.mySeat and t.cur.myHole and ok then
		-- nothing else to do; disputes are only needed when our own cards were wrong
	elseif t.cur.mySeat and not ok and t.cur.myHole and t.myKey then
		Comm.Group("DISPUTE", t.id, no, t.myKey)
		t.myKey = Fair.NewSecret():sub(1, 32) -- old key is now public; rotate
		ns.SaveKey(t.id, t.myKey)
		Comm.Whisper(t.dealer, "SIT", t.id, t.cur.mySeat, 0, t.myKey)
	end
	t.phase = "idle"
	t:AfterHand()
	t:Changed()
end

--- A player published their pad key so everyone can check what the dealer actually sent them.
handlers.DISPUTE = function(t, sender, f)
	local audit = t.audits[#t.audits]
	local cur = t.cur
	local no = tonumber(f[3])
	if not cur or cur.no ~= no or not audit or not audit.secret then return end
	local seat = t.engine:SeatOf(sender)
	if not seat or not cur.sealed[seat] then return end
	local c1, c2 = Fair.OpenHole(f[4], t.id, no, cur.sealed[seat])
	local deck = Fair.Deck(t.id, no, audit.secret, cur.rolls or "")
	local holes = Cards.Layout(deck, cur.dealOrder or {})
	local real = holes[seat]
	if real and (real[1] ~= c1 or real[2] ~= c2) then
		t:Alert(("Confirmed: the dealer sent %s the wrong hole cards in hand #%d."):format(sender, no), "cheat")
	else
		t:Alert(("%s disputed hand #%d, but the cards they were sent match the deck."):format(sender, no), "warn")
	end
end

handlers.ABORT = function(t, sender, f)
	if sender ~= t.dealer then return end
	local no = tonumber(f[3])
	if not t.cur or t.cur.no ~= no then return end
	if t.engine:InHand() then t.engine:Void() end
	if Fair.Commit(f[4] or "") ~= t.cur.commit then
		t:Alert("Dealer's reveal for the cancelled hand doesn't match its seal.", "cheat")
	end
	t.stats.aborts = t.stats.aborts + 1
	t:Log(("Hand #%d cancelled: %s"):format(no, tostring(f[5])))
	t.phase = "idle"
	t:AfterHand()
	t:Changed()
end

handlers.VOID = function(t, sender, f)
	if sender ~= t.dealer then return end
	local no = tonumber(f[3])
	if t.engine:InHand() and t.engine.hand.no == no then t.engine:Void() end
	t.stats.voids = t.stats.voids + 1
	t:Alert(("Dealer voided hand #%d (%s). Everyone got their chips back."):format(no or 0, tostring(f[4])), "warn")
	t.phase = "idle"
	t:AfterHand()
	t:Changed()
end

---------------------------------------------------------------------------------------------
-- Engine events -> log/UI, and dealer reactions
---------------------------------------------------------------------------------------------
local VERB = { fold = "folds", check = "checks", call = "calls", raise = "raises to", allin = "is all-in" }

function Table:OnEngine(event, a, b, c, d)
	local e = self.engine
	if event == "handStart" then
		local h = a
		self:Log(("%s has the button. Blinds: %s / %s."):format(self:Name(h.button), self:Name(h.sbSeat), self:Name(h.bbSeat)))
	elseif event == "action" then
		local seat, kind, betNow = a, b, c
		local s = e.seats[seat]
		local text = self:Name(seat) .. " " .. (VERB[kind] or kind)
		if kind == "call" or kind == "raise" then
			text = text .. " " .. self:Fmt(kind == "call" and d or betNow)
		end
		if s and s.stack == 0 and kind ~= "fold" and kind ~= "check" then text = text .. " (all-in)" end
		self:Log(text)
		ns.Emit("TABLE_ACTION", self, seat, kind)
	elseif event == "board" then
		self:Log(("*** %s *** %s"):format(a:upper(), Cards.ListToString(e.hand.board)))
	elseif event == "handEnd" then
		local r = a
		if r.voided then
			self:Log("Hand voided - stacks restored.")
		else
			if e.hand.returned then
				self:Log(("Uncalled %s returned to %s."):format(self:Fmt(e.hand.returned.amount), self:Name(e.hand.returned.seat)))
			end
			if r.showdown then
				for seat, hole in pairs(r.holes) do
					self:Log(("%s shows %s (%s)"):format(self:Name(seat), Cards.ListToString(hole), r.handNames[seat] or "?"))
				end
			end
			for _, w in ipairs(r.awards) do
				self:Log(("|cffffd100%s wins %s|r%s"):format(self:Name(w.seat), self:Fmt(w.amount), w.hand and (" with " .. w.hand) or ""))
			end
		end
		for name, L in pairs(self.ledger) do
			local seat = e:SeatOf(name)
			if seat then L.stack = e.seats[seat].stack end
		end
		ns.Emit("TABLE_HAND_END", self, r)
	end
	if self.isDealer then self:DealerOnEngine(event, a) end
	self:Changed()
end

---------------------------------------------------------------------------------------------
-- Group roster changes
---------------------------------------------------------------------------------------------
function Table:OnRoster(inGroup)
	if self.phase == "closed" then return end
	if not self.isDealer then
		if not inGroup(self.dealer) then
			if self.engine:InHand() then self.engine:Void() end
			self:ApplySnapshot("")
			self.phase = "closed"
			self:Alert("The dealer left the group. Table closed; the last hand was voided.", "warn")
			ns.SaveSession(self)
			self:Changed()
		end
		return
	end
	self.away = {}
	for _, s in pairs(self.engine.seats) do
		if s.name ~= me() and not inGroup(s.name) then
			self.away[s.name] = true
			if not self.pending.leaves[s.name] then
				self:Log(s.name .. " left the group and will be removed after this hand.")
				self:Kick(s.name)
			end
		end
	end
end
