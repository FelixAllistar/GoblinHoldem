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
	table.sort(winners, function(a, b) return a.amt > b.amt end)
	table.sort(losers, function(a, b) return a.amt > b.amt end)
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

function ns.SaveSession(t)
	if not ns.db or t.sessionSaved then return end
	t.sessionSaved = true
	local nets = Ledger.Nets(t.ledger)
	local list = ns.db.sessions
	list[#list + 1] = {
		id = t.id, name = t.cfg.name, dealer = t.dealer, mode = t.cfg.mode, hands = t.handNo,
		time = time and time() or 0, nets = nets, stats = t.stats,
	}
	while #list > 50 do table.remove(list, 1) end
end
