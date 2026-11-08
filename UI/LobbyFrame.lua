-- Lobby: browse public tables and host your own.
local _, ns = ...

local W = ns.W
local UI = {}
ns.LobbyUI = UI

local ROWS = 7

local MODE_HELP = {
	iou = "Chips are worth gold, but nothing changes hands at the table. At the end the ledger says who pays whom. For friends who trust each other to pay up.",
	bank = "Players trade you (the dealer) gold to buy in; you approve their chips. When they leave you trade back their stack. You are the bank - and you can't sit at your own bank table.",
	fun = "Plain chips with no gold value. Just for fun.",
}

function UI:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "GoblinHoldemLobby", UIParent, W.BACKDROP_TEMPLATE)
	self.frame = f
	f:SetSize(560, 610)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	W.Backdrop(f, "dialog")
	W.Movable(f, "lobby")
	W.Header(f, "Goblin Hold'em Lobby", 300)
	tinsert(UISpecialFrames, "GoblinHoldemLobby")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -5, -5)

	-- open tables
	local title = W.Text(f, 14, W.FONT_TITLE)
	title:SetPoint("TOPLEFT", 22, -30)
	title:SetText("Open tables")
	title:SetTextColor(1, 0.82, 0)
	local refresh = W.Button(f, "Refresh", 80, 20, function() ns.Lobby.Ask() UI:Refresh() end)
	refresh:SetPoint("TOPRIGHT", -24, -28)

	local list = CreateFrame("Frame", nil, f, W.BACKDROP_TEMPLATE)
	list:SetPoint("TOPLEFT", 18, -50)
	list:SetPoint("TOPRIGHT", -18, -50)
	list:SetHeight(ROWS * 24 + 10)
	W.Backdrop(list, "inset")
	self.rows = {}
	for i = 1, ROWS do
		local r = CreateFrame("Frame", nil, list)
		r:SetSize(500, 22)
		r:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 24)
		r.text = W.Text(r, 12)
		r.text:SetPoint("LEFT", 2, 0)
		r.text:SetWidth(400)
		r.text:SetJustifyH("LEFT")
		r.text:SetWordWrap(false)
		r.join = W.Button(r, "Ask to join", 92, 20)
		r.join:SetPoint("RIGHT", list, "RIGHT", -8, 0)
		r.join:SetPoint("TOP", r, "TOP", 0, 0)
		r:EnableMouse(true)
		self.rows[i] = r
	end
	self.empty = W.Text(list, 12)
	self.empty:SetPoint("CENTER")
	self.empty:SetTextColor(0.7, 0.7, 0.7)
	self.empty:SetText("No public tables heard yet. Dealers advertise every minute or so.")

	-- join a friend directly
	local jl = W.Text(f, 12)
	jl:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -12)
	jl:SetText("Join a friend's table by name:")
	jl:SetTextColor(1, 0.9, 0.7)
	self.joinName = W.Edit(f, 130)
	self.joinName:SetPoint("LEFT", jl, "RIGHT", 12, 0)
	self.joinName:SetScript("OnEnterPressed", function(e) ns.Table.RequestJoin(e:GetText()) e:ClearFocus() end)
	local jb = W.Button(f, "Join", 60, 20, function() ns.Table.RequestJoin(UI.joinName:GetText()) end)
	jb:SetPoint("LEFT", self.joinName, "RIGHT", 6, 0)

	-- host form
	local host = W.Text(f, 14, W.FONT_TITLE)
	host:SetPoint("TOPLEFT", jl, "BOTTOMLEFT", 0, -18)
	host:SetText("Host a table")
	host:SetTextColor(1, 0.82, 0)

	local function label(text, anchor, x, y)
		local l = W.Text(f, 12)
		l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -10)
		l:SetText(text)
		l:SetTextColor(1, 0.9, 0.7)
		return l
	end

	local lName = label("Table name", host, 0, -12)
	self.name = W.Edit(f, 200)
	self.name:SetPoint("LEFT", lName, "LEFT", 110, 0)
	self.name:SetMaxLetters(28)

	local lMode = label("Game", lName, 0, -14)
	self.modeButtons = {}
	local prev
	for _, m in ipairs({ "iou", "bank", "fun" }) do
		local b = W.Button(f, ns.Table.MODES[m], 120, 22, function() UI:SetMode(m) end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", lMode, "LEFT", 104, 0) end
		prev = b
		self.modeButtons[m] = b
	end
	self.modeHelp = W.Text(f, 11)
	self.modeHelp:SetPoint("TOPLEFT", lMode, "BOTTOMLEFT", 0, -10)
	self.modeHelp:SetWidth(510)
	self.modeHelp:SetJustifyH("LEFT")
	self.modeHelp:SetTextColor(0.75, 0.75, 0.75)

	local lWhere = label("Players", lMode, 0, -46)
	self.whereButtons = {}
	local prevW
	for _, tr in ipairs({ { "channel", "Anywhere" }, { "group", "In my party/raid" } }) do
		local b = W.Button(f, tr[2], 140, 22, function() UI:SetWhere(tr[1]) end)
		if prevW then b:SetPoint("LEFT", prevW, "RIGHT", 4, 0) else b:SetPoint("LEFT", lWhere, "LEFT", 104, 0) end
		prevW = b
		self.whereButtons[tr[1]] = b
	end
	self.whereHelp = W.Text(f, 11)
	self.whereHelp:SetPoint("TOPLEFT", lWhere, "BOTTOMLEFT", 0, -10)
	self.whereHelp:SetWidth(510)
	self.whereHelp:SetJustifyH("LEFT")
	self.whereHelp:SetTextColor(0.75, 0.75, 0.75)

	local lBlinds = label("Blinds", lWhere, 0, -32)
	self.sb = W.Edit(f, 70)
	self.sb:SetPoint("LEFT", lBlinds, "LEFT", 110, 0)
	local slash = W.Text(f, 12) slash:SetPoint("LEFT", self.sb, "RIGHT", 4, 0) slash:SetText("/")
	self.bb = W.Edit(f, 70)
	self.bb:SetPoint("LEFT", slash, "RIGHT", 10, 0)
	local lBuy = W.Text(f, 12)
	lBuy:SetPoint("LEFT", self.bb, "RIGHT", 18, 0)
	lBuy:SetText("Buy-in")
	lBuy:SetTextColor(1, 0.9, 0.7)
	self.minBuy = W.Edit(f, 70)
	self.minBuy:SetPoint("LEFT", lBuy, "RIGHT", 10, 0)
	local dash = W.Text(f, 12) dash:SetPoint("LEFT", self.minBuy, "RIGHT", 4, 0) dash:SetText("to")
	self.maxBuy = W.Edit(f, 70)
	self.maxBuy:SetPoint("LEFT", dash, "RIGHT", 10, 0)

	local lSeats = label("Seats", lBlinds, 0, -14)
	self.seats = W.Edit(f, 40, true)
	self.seats:SetPoint("LEFT", lSeats, "LEFT", 110, 0)
	local lTimer = W.Text(f, 12)
	lTimer:SetPoint("LEFT", self.seats, "RIGHT", 18, 0)
	lTimer:SetText("Turn timer (sec)")
	lTimer:SetTextColor(1, 0.9, 0.7)
	self.timer = W.Edit(f, 40, true)
	self.timer:SetPoint("LEFT", lTimer, "RIGHT", 10, 0)

	self.play = W.Check(f, "I'm playing too, buy-in:", function() UI:UpdateForm() end)
	self.play:SetPoint("TOPLEFT", lSeats, "BOTTOMLEFT", -4, -10)
	self.myBuy = W.Edit(f, 70)
	self.myBuy:SetPoint("LEFT", self.play.label, "RIGHT", 10, 0)
	self.public = W.Check(f, "Advertise in the lobby (realm channel + guild)")
	self.public:SetPoint("TOPLEFT", self.play, "BOTTOMLEFT", 0, -4)
	self.approve = W.Check(f, "Approve each player who asks to join")
	self.approve:SetPoint("TOPLEFT", self.public, "BOTTOMLEFT", 0, -4)

	self.unitsHint = W.Text(f, 11)
	self.unitsHint:SetPoint("TOPLEFT", self.approve, "BOTTOMLEFT", 4, -6)
	self.unitsHint:SetTextColor(0.6, 0.6, 0.6)

	self.open = W.Button(f, "Open Table", 140, 26, function() UI:Host() end)
	self.open:SetPoint("BOTTOMRIGHT", -22, 20)
	self.practice = W.Button(f, "Practice vs bots", 140, 26, function()
		local t, err = ns.Table.HostPractice(4)
		if not t then return ns.Print(err) end
		UI.frame:Hide()
	end)
	self.practice:SetPoint("BOTTOMLEFT", 22, 20)
	W.Tooltip(self.practice, function(tt)
		tt:AddLine("Practice table", 1, 0.82, 0)
		tt:AddLine("Play solo against four goblin bots with play chips. Nothing is sent to anyone.", 1, 1, 1, true)
	end)

	-- defaults
	local d = ns.db and ns.db.hostDefaults or {}
	self.name:SetText(d.name or ((UnitName("player") or "My") .. "'s Table"))
	self.mode = d.mode or "iou"
	self.sb:SetText(d.sb or "1")
	self.bb:SetText(d.bb or "2")
	self.minBuy:SetText(d.minBuy or "40")
	self.maxBuy:SetText(d.maxBuy or "200")
	self.seats:SetText(d.seats or "9")
	self.timer:SetText(d.timer or "30")
	self.myBuy:SetText(d.myBuy or "100")
	self.play:SetChecked(d.play ~= false)
	self.public:SetChecked(d.public and true or false)
	self.approve:SetChecked(d.approve and true or false)
	self.where = d.where or "channel"
	self:SetMode(self.mode)
	self:SetWhere(self.where)

	f:Hide()
	return f
end

function UI:SetMode(m)
	self.mode = m
	for k, b in pairs(self.modeButtons) do
		if k == m then b:LockHighlight() else b:UnlockHighlight() end
	end
	self.modeHelp:SetText(MODE_HELP[m])
	self:UpdateForm()
end

local WHERE_HELP = {
	channel = "Friends can be anywhere on the realm - no party needed. The table runs on a private chat channel; invite people with the Invite button or they type /holdem join <your name>.",
	group = "Everyone at the table is in your party/raid, and the shuffle uses real server /rolls everyone sees. Best for in-person tables.",
}

function UI:SetWhere(w)
	self.where = w
	for k, b in pairs(self.whereButtons) do
		if k == w then b:LockHighlight() else b:UnlockHighlight() end
	end
	self.whereHelp:SetText(WHERE_HELP[w])
end

function UI:UpdateForm()
	if self.mode == "bank" then
		self.play:SetChecked(false)
		self.play:Disable()
	else
		self.play:Enable()
	end
	if self.play:GetChecked() then self.myBuy:Show() else self.myBuy:Hide() end
	self.unitsHint:SetText(self.mode == "fun" and "Amounts are plain chips." or "Amounts are gold: 2, 0.5, or 1g 50s all work.")
end

function UI:Host()
	local m = self.mode
	local function money(e) return ns.ParseMoney(e:GetText(), m) end
	local cfg = {
		name = (self.name:GetText() or ""):gsub("[~/,]", ""):sub(1, 28),
		mode = m, sb = money(self.sb), bb = money(self.bb),
		minBuy = money(self.minBuy), maxBuy = money(self.maxBuy),
		maxSeats = math.max(2, math.min(9, tonumber(self.seats:GetText()) or 9)),
		actTimeout = math.max(10, math.min(120, tonumber(self.timer:GetText()) or 30)),
		dealerSeated = self.play:GetChecked() and m ~= "bank",
		public = self.public:GetChecked() and true or false,
		approveJoins = self.approve:GetChecked() and true or false,
		transport = self.where or "channel",
	}
	if cfg.name == "" then cfg.name = "Goblin Hold'em" end
	if not (cfg.sb and cfg.bb and cfg.sb > 0 and cfg.bb >= cfg.sb) then return ns.Print("Blinds look wrong: small blind must be > 0 and big blind at least the small blind.") end
	if not (cfg.minBuy and cfg.maxBuy and cfg.minBuy >= cfg.bb and cfg.maxBuy >= cfg.minBuy) then return ns.Print("Buy-in range looks wrong (min must be at least the big blind, max at least min).") end
	if cfg.dealerSeated then
		cfg.dealerBuyIn = money(self.myBuy)
		if not cfg.dealerBuyIn or cfg.dealerBuyIn < cfg.minBuy or cfg.dealerBuyIn > cfg.maxBuy then
			return ns.Print("Your own buy-in has to be inside the buy-in range.")
		end
	end
	if ns.db then
		ns.db.hostDefaults = {
			name = cfg.name, mode = m, sb = self.sb:GetText(), bb = self.bb:GetText(), minBuy = self.minBuy:GetText(),
			maxBuy = self.maxBuy:GetText(), seats = self.seats:GetText(), timer = self.timer:GetText(),
			myBuy = self.myBuy:GetText(), play = self.play:GetChecked() and true or false, public = cfg.public,
			approve = cfg.approveJoins, where = cfg.transport,
		}
	end
	local t, err = ns.Table.Host(cfg)
	if not t then return ns.Print(err) end
	if cfg.public then
		ns.Lobby.EnsureChannel()
		C_Timer.After(2, function() ns.Lobby.Advertise(t) end)
	end
	self.frame:Hide()
end

function UI:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	local list = ns.Lobby.List()
	self.empty:SetShown(#list == 0)
	for i, r in ipairs(self.rows) do
		local e = list[i]
		if e then
			r:Show()
			local mode = ns.Table.MODES[e.mode] or e.mode
			r.text:SetText(("|cffffd100%s|r  %s/%s  %d/%d  |cffaaaaaa%s - %s|r%s"):format(
				e.name, ns.Money(e.sb, e.mode, true), ns.Money(e.bb, e.mode, true), e.seated, e.maxSeats,
				e.dealer, e.transport == "group" and ("in person: " .. (e.where ~= "" and e.where or "party")) or "anywhere",
				e.dealerSeated and " |cffffa040(dealer plays)|r" or ""))
			r.join:SetScript("OnClick", function() ns.Lobby.RequestJoin(e) end)
			W.Tooltip(r, function(tt)
				tt:AddLine(e.name, 1, 0.82, 0)
				tt:AddDoubleLine("Dealer", e.dealer, 0.8, 0.8, 0.8, 1, 1, 1)
				tt:AddDoubleLine("Game", mode, 0.8, 0.8, 0.8, 1, 1, 1)
				tt:AddDoubleLine("Buy-in", ns.Money(e.minBuy, e.mode, true) .. " - " .. ns.Money(e.maxBuy, e.mode, true), 0.8, 0.8, 0.8, 1, 1, 1)
				if e.where ~= "" then tt:AddDoubleLine("Where", e.where, 0.8, 0.8, 0.8, 1, 1, 1) end
				if e.dealerSeated then tt:AddLine("The dealer is also playing - their add-on sees all hole cards.", 1, 0.6, 0.2, true) end
			end)
		else
			r:Hide()
		end
	end
end

function UI:Toggle()
	self:Create()
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		ns.Lobby.Ask()
		self:Refresh()
	end
end

ns.Listen("LOBBY_UPDATE", function() UI:Refresh() end)
