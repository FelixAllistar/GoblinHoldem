-- Side panel: session ledger and settle-up, hand audit trail, and how the fairness works.
-- Also the dealer's request queue.
local _, ns = ...

local W = ns.W
local UI = {}
ns.LedgerUI = UI

local function T() return ns.current end

function UI:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "GoblinHoldemLedger", UIParent, W.BACKDROP_TEMPLATE)
	self.frame = f
	f:SetSize(440, 520)
	f:SetFrameStrata("HIGH")
	W.Backdrop(f, "dialog")
	W.Header(f, "Ledger", 220)
	local anchor = ns.TableUI.frame
	if anchor then f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -6, 0) else f:SetPoint("CENTER", 300, 0) end
	W.Movable(f)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -5, -5)

	self.tabs = {}
	local prev
	for _, tab in ipairs({ { "ledger", "Ledger" }, { "debts", "Debts" }, { "history", "History" }, { "audit", "Audit" }, { "help", "Fair?" } }) do
		local b = W.Button(f, tab[2], 76, 22, function() UI:Show(tab[1]) end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 18, -28) end
		prev = b
		self.tabs[tab[1]] = b
	end

	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 18, -58)
	scroll:SetPoint("BOTTOMRIGHT", -36, 18)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(380, 10)
	scroll:SetScrollChild(content)
	self.text = W.Text(content, 12, W.FONT)
	self.text:SetPoint("TOPLEFT")
	self.text:SetWidth(380)
	self.text:SetJustifyH("LEFT")
	self.text:SetSpacing(2)
	self.content = content
	self.scroll = scroll

	-- debts tab: one row per person with a "Settled" button
	self.debtRows = {}
	for i = 1, 12 do
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(396, 24)
		r:SetPoint("TOPLEFT", 22, -84 - (i - 1) * 26)
		r.text = W.Text(r, 12)
		r.text:SetPoint("LEFT")
		r.text:SetWidth(300)
		r.text:SetJustifyH("LEFT")
		r.text:SetWordWrap(false)
		r.btn = W.Button(r, "Settled", 76, 20)
		r.btn:SetPoint("RIGHT")
		r:EnableMouse(true)
		r:Hide()
		self.debtRows[i] = r
	end
	self.debtHead = W.Text(f, 12)
	self.debtHead:SetPoint("TOPLEFT", 22, -60)
	self.debtHead:SetWidth(396)
	self.debtHead:SetJustifyH("LEFT")
	self.debtHead:SetTextColor(0.8, 0.7, 0.5)
	f:Hide()
	return f
end

function UI:RefreshDebts()
	local list = {}
	for name, d in pairs(ns.db and ns.db.debts or {}) do
		if d.amount ~= 0 then list[#list + 1] = { name = name, d = d } end
	end
	table.sort(list, function(a, b) return math.abs(a.d.amount) > math.abs(b.d.amount) end)
	self.debtHead:SetText(#list == 0 and "Nobody owes anybody. Debts are added here when a gold table ends."
		or "Running totals from finished gold tables. Click Settled once the gold has changed hands.")
	for i, r in ipairs(self.debtRows) do
		local e = list[i]
		if e then
			local amt = e.d.amount
			r.text:SetText(amt > 0
				and ("|cff40ff40%s owes you %s|r"):format(e.name, ns.Money(amt, "iou"))
				or ("|cffff6060You owe %s %s|r"):format(e.name, ns.Money(-amt, "iou")))
			r.btn:SetScript("OnClick", function() ns.Ledger.ClearDebt(e.name) UI:Refresh() end)
			W.Tooltip(r, function(tt)
				tt:AddLine(e.name, 1, 0.82, 0)
				for _, it in ipairs(e.d.items) do
					tt:AddDoubleLine(date("%b %d", it.at) .. "  " .. tostring(it.note or ""), ns.Money(it.amount, "iou", true), 0.8, 0.8, 0.8, 1, 1, 1)
				end
			end)
			r:Show()
		else
			r:Hide()
		end
	end
end

function UI:HistoryText()
	local list = ns.db and ns.db.sessions or {}
	if #list == 0 then return "|cff999999No finished tables yet.|r" end
	local me = ns.Comm.Me()
	local lines = {}
	for i = #list, 1, -1 do
		local e = list[i]
		local mine
		for _, n in ipairs(e.nets or {}) do if n.name == (e.me or me) then mine = n end end
		local net = mine and mine.net or 0
		local color = net > 0 and "|cff40ff40+" or net < 0 and "|cffff6060" or "|cffcccccc"
		lines[#lines + 1] = ("|cffffd100%s|r  %s  |cff999999dealer %s, %d hands%s|r"):format(
			date("%b %d %H:%M", e.time or 0), e.name or "?", e.dealer or "?", e.hands or 0, e.final and "" or ", left early")
		lines[#lines + 1] = ("   you: %s%s|r   |cff999999%s|r"):format(color, ns.Money(net, e.mode), ns.Table.MODES[e.mode] or "")
		if i == #list then
			for _, n in ipairs(e.nets or {}) do
				lines[#lines + 1] = ("      |cff999999%s %s%s|r"):format(n.name, n.net > 0 and "+" or "", ns.Money(n.net, e.mode, true))
			end
		end
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cff999999The last 120 log lines of each table are kept in your SavedVariables in case of a dispute.|r"
	return table.concat(lines, "\n")
end

function UI:Toggle()
	self:Create()
	if self.frame:IsShown() then self.frame:Hide() else self:Show(self.tab or "ledger") end
end

function UI:Show(tab)
	self:Create()
	self.tab = tab
	for k, b in pairs(self.tabs) do if k == tab then b:LockHighlight() else b:UnlockHighlight() end end
	self.frame:Show()
	self:Refresh()
end

local function money(t, v) return ns.Money(v, t.cfg.mode) end

function UI:LedgerText(t)
	local lines = {}
	local nets = ns.Ledger.Nets(t.ledger)
	lines[#lines + 1] = ("|cffffd100%s|r - %s, %d hands"):format(t.cfg.name, ns.Table.MODES[t.cfg.mode], t.handNo)
	lines[#lines + 1] = " "
	for _, n in ipairs(nets) do
		local color = n.net > 0 and "|cff40ff40" or n.net < 0 and "|cffff6060" or "|cffcccccc"
		lines[#lines + 1] = ("%s%s|r  %s%s|r"):format(n.seated and "" or "|cff999999", n.name, color, (n.net > 0 and "+" or "") .. money(t, n.net))
		lines[#lines + 1] = ("   |cff999999in %s, now %s|r"):format(money(t, n.buyIn), money(t, n.now))
	end
	if #nets == 0 then lines[#lines + 1] = "|cff999999Nobody has bought in yet.|r" end
	lines[#lines + 1] = " "
	if t.cfg.mode == "iou" then
		lines[#lines + 1] = "|cffffd100Settle up|r (if everyone cashed out now)"
		local tr = ns.Ledger.Settle(nets)
		for _, x in ipairs(tr) do
			lines[#lines + 1] = ("%s pays %s %s"):format(x.from, x.to, money(t, x.amount))
		end
		if #tr == 0 then lines[#lines + 1] = "|cff999999Nobody owes anything.|r" end
		lines[#lines + 1] = " "
		lines[#lines + 1] = "|cff999999Pay with the trade window or the mailbox. The add-on never moves gold itself.|r"
	elseif t.cfg.mode == "bank" then
		lines[#lines + 1] = ("|cffffd100Bank: %s holds the gold|r"):format(t.dealer)
		for _, x in ipairs(ns.Ledger.BankPayouts(nets, t.dealer)) do
			lines[#lines + 1] = ("%s: paid in %s, cash-out value %s"):format(x.name, money(t, x.buyIn), money(t, x.owed))
		end
		lines[#lines + 1] = " "
		lines[#lines + 1] = "|cff999999Players trade the dealer to buy in; the dealer trades back the stack when they leave.|r"
	end
	if t.stats.failed > 0 or t.stats.voids > 0 then
		lines[#lines + 1] = " "
		lines[#lines + 1] = ("|cffff6060Warning: %d failed audits, %d voided hands this session.|r"):format(t.stats.failed, t.stats.voids)
	end
	return table.concat(lines, "\n")
end

function UI:AuditText(t)
	local lines = { ("|cffffd100%d verified|r, |cffff6060%d failed|r, %d cancelled, %d voided"):format(t.stats.verified, t.stats.failed, t.stats.aborts, t.stats.voids), " " }
	for i = #t.audits, math.max(1, #t.audits - 40), -1 do
		local a = t.audits[i]
		lines[#lines + 1] = ("%s Hand #%d  board %s%s"):format(a.ok and "|cff40ff40OK|r" or "|cffff3030FAIL|r", a.hand,
			a.board ~= "" and a.board or "-", a.me and ("  you " .. a.me) or "")
		lines[#lines + 1] = ("   |cff999999seal %s...  rolls %s|r"):format(a.commit:sub(1, 12), a.rolls or "")
		for _, issue in ipairs(a.issues or {}) do lines[#lines + 1] = "   |cffff6060" .. issue .. "|r" end
	end
	local alerts = t.alerts
	if #alerts > 0 then
		lines[#lines + 1] = " "
		lines[#lines + 1] = "|cffffd100Alerts|r"
		for i = #alerts, math.max(1, #alerts - 20), -1 do
			local a = alerts[i]
			lines[#lines + 1] = ("#%d %s%s|r"):format(a.hand or 0, a.severity == "cheat" and "|cffff4040" or "|cffffc060", a.text)
		end
	end
	return table.concat(lines, "\n")
end

local HELP = table.concat({
	"|cffffd100Who shuffles?|r Nobody alone. Each hand:",
	"1. The dealer's add-on picks a secret and posts its |cffffffffseal|r (a SHA-256 hash). The secret can't be changed after this without everyone noticing.",
	"2. Every seated player adds randomness. At |cffffffffparty/raid|r tables that's a |cffffffff/roll 1-1000000|r made by the Blizzard server, which the whole group sees. At |cffffffffanywhere|r tables each player's add-on sends a random seed over the table channel (the server stamps who sent it).",
	"3. The deck is shuffled from the secret plus everyone's randomness. The dealer couldn't know it when it sealed, and players don't know the secret, so nobody can steer or predict the cards.",
	"4. Your hole cards come to you encrypted with a key only you and the dealer's add-on know.",
	"5. After the hand the secret is revealed. Your add-on re-shuffles the deck itself and checks the seal, every roll, the board and your own cards. Any mismatch shows a red warning to the whole table, and the hand is voided.",
	" ",
	"|cffffd100What can't be checked|r",
	"The dealer's add-on knows the hole cards while a hand is running. For games with strangers, use a dealer who isn't playing (a friend, an alt, or a house bank dealer). The table shows a warning when the dealer is seated.",
	"Players sharing cards over Discord (collusion) can't be stopped by any add-on.",
	" ",
	"|cffffd100Your actions|r are sent by you and checked by every add-on against the rules, so nobody can bet chips they don't have or act out of turn.",
	" ",
	"|cffffd100Gold|r never moves automatically. Friends games settle from the ledger; house-bank games trade with the dealer. Keep it to in-game gold - buying or selling gold for real money breaks Blizzard's rules.",
}, "\n")

function UI:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	local t = T()
	local text
	local debts = self.tab == "debts"
	self.scroll:SetShown(not debts)
	self.debtHead:SetShown(debts)
	if debts then return self:RefreshDebts() end
	for _, r in ipairs(self.debtRows) do r:Hide() end
	if self.tab == "help" then text = HELP
	elseif self.tab == "history" then text = self:HistoryText()
	elseif not t then text = "|cff999999You're not at a table.|r"
	elseif self.tab == "audit" then text = self:AuditText(t)
	else text = self:LedgerText(t) end
	self.text:SetText(text)
	self.content:SetHeight(self.text:GetStringHeight() + 10)
end

ns.Listen("TABLE_UPDATE", function() UI:Refresh() end)

---------------------------------------------------------------------------------------------
-- Dealer request queue
---------------------------------------------------------------------------------------------
local R = {}
ns.RequestsUI = R

function R:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "GoblinHoldemRequests", UIParent, W.BACKDROP_TEMPLATE)
	self.frame = f
	f:SetSize(380, 260)
	f:SetPoint("CENTER", 0, 120)
	f:SetFrameStrata("DIALOG")
	W.Backdrop(f, "dialog")
	W.Header(f, "Requests", 200)
	W.Movable(f, "requests")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -5, -5)
	self.hint = W.Text(f, 11)
	self.hint:SetPoint("TOPLEFT", 20, -30)
	self.hint:SetWidth(340)
	self.hint:SetJustifyH("LEFT")
	self.hint:SetTextColor(0.8, 0.7, 0.5)
	self.rows = {}
	for i = 1, 6 do
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(340, 26)
		r:SetPoint("TOPLEFT", 20, -56 - (i - 1) * 30)
		r.text = W.Text(r, 12)
		r.text:SetPoint("LEFT")
		r.text:SetWidth(200)
		r.text:SetJustifyH("LEFT")
		r.ok = W.Button(r, "Approve", 70, 22)
		r.ok:SetPoint("RIGHT", -64, 0)
		r.no = W.Button(r, "Deny", 56, 22)
		r.no:SetPoint("RIGHT")
		self.rows[i] = r
	end
	self.none = W.Text(f, 12)
	self.none:SetPoint("CENTER")
	self.none:SetText("|cff999999No requests waiting.|r")
	f:Hide()
	return f
end

function R:Toggle()
	self:Create()
	if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() self:Refresh() end
end

function R:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	local t = T()
	local reqs = (t and t.isDealer and t.requests) or {}
	self.hint:SetText(t and t.cfg.mode == "bank"
		and "House bank: open a trade, take the gold, THEN approve. Approved chips appear between hands."
		or "Approved seats and chips appear between hands.")
	self.none:SetShown(#reqs == 0)
	for i, r in ipairs(self.rows) do
		local q = reqs[i]
		if q then
			r:Show()
			if q.kind == "join" then
				r.text:SetText(("%s wants an invite"):format(q.name))
				r.ok:SetText("Invite")
			else
				r.text:SetText(("%s: %s %s"):format(q.name, q.kind == "sit" and "sit for" or "add", ns.Money(q.amount, t.cfg.mode, true)))
				r.ok:SetText("Approve")
			end
			r.ok:SetScript("OnClick", function() t:Approve(q) R:Refresh() end)
			r.no:SetScript("OnClick", function() t:Deny(q) R:Refresh() end)
		else
			r:Hide()
		end
	end
end

ns.Listen("TABLE_UPDATE", function() R:Refresh() end)
ns.Listen("TABLE_REQUEST", function()
	R:Create()
	if not R.frame:IsShown() then R.frame:Show() end
	R:Refresh()
end)
