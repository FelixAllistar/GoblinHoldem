-- Bot + inspection helpers loaded into each simulated client.
local ns, seed = ...
math.randomseed(seed)
local Table = ns.Table

GH_ALERTS = {}
ns.Listen("TABLE_ALERT", function(t, text, sev) GH_ALERTS[#GH_ALERTS + 1] = sev .. ": " .. text end)

function GH_Host(cfg) return assert(Table.Host(cfg)) end
function GH_T() return ns.current end

function GH_Sit(seat, amount) ns.current:RequestSeat(seat, amount) end

--- Take a random legal action if it is our turn. Returns true if we acted.
function GH_Bot(style)
	local t = ns.current
	if not t then return false end
	local mine = t:MySeat()
	if mine and t.phase == "idle" and t.engine.seats[mine].stack == 0 and t.rebuyAt ~= t.handNo then
		t.rebuyAt = t.handNo
		t:RequestChips(100000)
	end
	if t.phase ~= "playing" then return false end
	local h, seat = t.engine.hand, t:MySeat()
	if not h or not seat or h.toAct ~= seat or h.phase ~= "betting" then return false end
	if t.sentSeq == h.seq + 1 and t.sentNo == h.no then return false end -- already sent, waiting
	local L = t.engine:Legal(seat)
	local r = math.random()
	if style == "afk" then return false end
	if r < 0.10 and not L.check then t:Act("fold")
	elseif r < 0.70 then t:Act(L.check and "check" or "call")
	elseif L.canRaise then
		local amt = r > 0.98 and L.maxTo or (L.minTo + math.floor(math.random() * (L.maxTo - L.minTo) * 0.3))
		t:Act("raise", amt)
	else t:Act(L.check and "check" or "call") end
	t.sentSeq, t.sentNo = h.seq + 1, h.no
	return true
end

--- Compact state string for cross-client comparison.
function GH_State()
	local t = ns.current
	if not t then return "none" end
	local parts = { "hand=" .. t.handNo, "phase=" .. t.phase }
	for seat = 1, t.cfg.maxSeats do
		local s = t.engine.seats[seat]
		if s then parts[#parts + 1] = seat .. ":" .. s.name .. ":" .. s.stack end
	end
	return table.concat(parts, " ")
end

function GH_Total()
	local t, n = ns.current, 0
	for _, s in pairs(t.engine.seats) do n = n + s.stack end
	if t.engine:InHand() then n = n + t.engine:PotTotal() end
	local buy = 0
	for _, L in pairs(t.ledger) do buy = buy + L.buyIn - (L.out or 0) end
	return n, buy
end

function GH_Verified() return ns.current.stats.verified, ns.current.stats.failed end
function GH_MyHole()
	local c = ns.current.cur
	return c and c.myHole and ns.Cards.ListToString(c.myHole) or ""
end

function GH_Settle()
	local nets = ns.Ledger.Nets(ns.current.ledger)
	local tr = ns.Ledger.Settle(nets)
	local sum = 0
	for _, n in ipairs(nets) do sum = sum + n.net end
	return #tr, sum
end

-- Cheating dealer hooks for negative tests
function GH_CheatRolls()
	local orig = ns.Fair.RollString
	ns.Fair.RollString = function(rolls)
		for seat, v in pairs(rolls) do rolls[seat] = tostring(v) .. "7" break end
		return orig(rolls)
	end
end

function GH_CheatBoard()
	local t = ns.current
	local orig = t.DealerOnEngine
	t.DealerOnEngine = function(self, event, a)
		if event == "needBoard" and self.dealerBoard then
			local b = self.dealerBoard
			-- swap the flop's first card with a card further down the deck
			local deck = ns.Fair.Deck(self.id, self.cur.no, self.secret, self.cur.rolls)
			b[1] = deck[52]
		end
		return orig(self, event, a)
	end
end

function GH_JoinByName(dealer) ns.Table.RequestJoin(dealer) end
function GH_Practice(n) return assert(ns.Table.HostPractice(n)) end
function GH_InChannel() local t = ns.current return t and t.cfg.channel and GH_CHANNELS[t.cfg.channel] ~= nil end
