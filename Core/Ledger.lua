-- Who's up, who's down, and who pays whom. Plus SavedVariables helpers for keys/audits/sessions.
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

--- ledger[name] = { buyIn, out, stack, seated } -> sorted list { name, buyIn, now, net }
function Ledger.Nets(ledger)
	local out = {}
	for name, L in pairs(ledger or {}) do
		local now = (L.seated and L.stack or 0) + (L.out or 0)
		out[#out + 1] = { name = name, buyIn = L.buyIn or 0, now = now, net = now - (L.buyIn or 0), seated = L.seated }
	end
	table.sort(out, function(a, b) if a.net ~= b.net then return a.net > b.net end return a.name < b.name end)
	return out
end

--- Fewest-ish transfers that settle everyone up (greedy: biggest loser pays biggest winner).
function Ledger.Settle(nets)
	local winners, losers = {}, {}
	for _, n in ipairs(nets) do
		if n.net > 0 then winners[#winners + 1] = { name = n.name, amt = n.net }
		elseif n.net < 0 then losers[#losers + 1] = { name = n.name, amt = -n.net } end
	end
	local function order(a, b) if a.amt ~= b.amt then return a.amt > b.amt end return a.name < b.name end
	table.sort(winners, order)
	table.sort(losers, order)
	local transfers = {}
	local i, j = 1, 1
	while i <= #losers and j <= #winners do
		local pay = math.min(losers[i].amt, winners[j].amt)
		if pay > 0 then transfers[#transfers + 1] = { from = losers[i].name, to = winners[j].name, amount = pay } end
		losers[i].amt = losers[i].amt - pay
		winners[j].amt = winners[j].amt - pay
		if losers[i].amt == 0 then i = i + 1 end
		if winners[j].amt == 0 then j = j + 1 end
	end
	return transfers
end

--- In "house bank" mode the dealer holds the gold: everyone settles with the dealer instead.
function Ledger.BankPayouts(nets, dealer)
	local out = {}
	for _, n in ipairs(nets) do
		if n.name ~= dealer then
			-- buy-ins were traded to the dealer; cashing out = the dealer trades the stack back
			out[#out + 1] = { name = n.name, owed = n.now, buyIn = n.buyIn, net = n.net }
		end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Persistence (no-ops until Init has loaded the SavedVariables into ns.db)
---------------------------------------------------------------------------------------------
function ns.SaveKey(tableId, key)
	if ns.db then ns.db.keys[tableId] = { key = key, at = time and time() or 0 } end
end

function ns.LoadKey(tableId)
	local e = ns.db and ns.db.keys[tableId]
	return e and e.key
end

function ns.SaveAudit(entry)
	if not ns.db then return end
	local list = ns.db.audit
	list[#list + 1] = entry
	while #list > 300 do table.remove(list, 1) end
end

--- Running balances with other players across sessions. Positive = they owe you.
function Ledger.AddDebt(name, amount, note)
	if not ns.db or amount == 0 then return end
	local d = ns.db.debts[name] or { amount = 0, items = {} }
	ns.db.debts[name] = d
	d.amount = d.amount + amount
	d.items[#d.items + 1] = { at = time(), amount = amount, note = note }
	while #d.items > 12 do table.remove(d.items, 1) end
end

function Ledger.ClearDebt(name)
	local d = ns.db and ns.db.debts[name]
	if not d then return end
	if d.amount ~= 0 then d.items[#d.items + 1] = { at = time(), amount = -d.amount, note = "settled" } end
	d.amount = 0
end

local function applyDebts(t, nets)
	local me = ns.Comm.Me()
	local note = t.cfg.name
	if t.cfg.mode == "iou" then
		for _, x in ipairs(Ledger.Settle(nets)) do
			if x.from == me then Ledger.AddDebt(x.to, -x.amount, note) end
			if x.to == me then Ledger.AddDebt(x.from, x.amount, note) end
		end
	elseif t.cfg.mode == "bank" then
		-- the dealer holds everyone's buy-ins; what's left to pay out is each cash-out value
		for _, n in ipairs(nets) do
			if n.name ~= t.dealer and n.now > 0 then
				if me == t.dealer then Ledger.AddDebt(n.name, -n.now, note .. " cash-out") end
				if me == n.name then Ledger.AddDebt(t.dealer, n.now, note .. " cash-out") end
			end
		end
	end
end

--- Keep a record of this table in SavedVariables. Called after every hand (crash-proof) and
--- once with final = true when the table ends, which is when debts are written.
function ns.SaveSession(t, final)
	if not ns.db or t.cfg.transport == "practice" or not next(t.ledger) then return end
	local list = ns.db.sessions
	local entry
	for _, e in ipairs(list) do if e.id == t.id then entry = e break end end
	if not entry then
		entry = { id = t.id, started = time() }
		list[#list + 1] = entry
		while #list > 40 do table.remove(list, 1) end
	end
	local nets = Ledger.Nets(t.ledger)
	entry.name, entry.dealer, entry.mode, entry.hands = t.cfg.name, t.dealer, t.cfg.mode, t.handNo
	entry.time, entry.nets, entry.stats, entry.me = time(), nets, t.stats, ns.Comm.Me()
	local log, from = {}, math.max(1, #t.log - 119)
	for i = from, #t.log do log[#log + 1] = t.log[i] end
	entry.log = log
	if final and not entry.final then
		entry.final = true
		applyDebts(t, nets)
	end
end
