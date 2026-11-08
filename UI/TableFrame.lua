-- The poker table window: felt, seats, board, pot, action bar and table log.
local _, ns = ...

local W, Cards = ns.W, ns.Cards
local UI = { lastAction = {}, shown = {}, winners = {} }
ns.TableUI = UI

local FW, FH = 900, 650
local FELT_W, FELT_H = 860, 430
local CX, CY = FELT_W / 2, FELT_H / 2
local RX, RY = 360, 178

local function T() return ns.current end
local function me() return ns.Comm.Me() end

---------------------------------------------------------------------------------------------
-- Seats
---------------------------------------------------------------------------------------------
local function classColor(name)
	if not UnitClass or not RAID_CLASS_COLORS then return 1, 0.9, 0.7 end
	local _, class = UnitClass(name)
	local c = class and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 0.9, 0.7
end

local function createSeat(felt, i)
	local s = CreateFrame("Button", nil, felt, W.BACKDROP_TEMPLATE)
	s:SetSize(132, 46)
	s:SetFrameLevel(felt:GetFrameLevel() + 5)
	W.Backdrop(s, "plate")
	s.name = W.Text(s, 12)
	s.name:SetPoint("TOP", 0, -6)
	s.name:SetWidth(124)
	s.name:SetWordWrap(false)
	s.stack = W.Text(s, 12)
	s.stack:SetPoint("TOP", s.name, "BOTTOM", 0, -3)
	s.status = W.Text(felt, 11)
	s.status:SetPoint("TOP", s, "BOTTOM", 0, -1)
	s.status:SetTextColor(0.85, 0.85, 0.75)
	s.timer = CreateFrame("StatusBar", nil, s)
	s.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	s.timer:SetStatusBarColor(1, 0.75, 0.1)
	s.timer:SetSize(122, 4)
	s.timer:SetPoint("BOTTOM", 0, 4)
	s.timer:SetMinMaxValues(0, 1)
	s.timer:Hide()
	s.cards = { W.Card(felt, 36, 50), W.Card(felt, 36, 50) }
	for _, c in ipairs(s.cards) do c:SetFrameLevel(felt:GetFrameLevel() + 4) end
	s.bet = CreateFrame("Frame", nil, felt)
	s.bet:SetSize(110, 18)
	s.bet.icon = s.bet:CreateTexture(nil, "ARTWORK")
	s.bet.icon:SetTexture(W.MEDIA .. "chip")
	s.bet.icon:SetSize(18, 18)
	s.bet.icon:SetPoint("LEFT")
	s.bet.text = W.Text(s.bet, 12)
	s.bet.text:SetPoint("LEFT", s.bet.icon, "RIGHT", 3, 0)
	s.bet.text:SetTextColor(1, 0.95, 0.75)
	s.dealer = felt:CreateTexture(nil, "OVERLAY")
	s.dealer:SetTexture(W.MEDIA .. "dealer")
	s.dealer:SetSize(24, 24)
	s:SetScript("OnClick", function() UI:OnSeatClick(i) end)
	s:SetScript("OnEnter", function(self)
		local t = T()
		local seat = t and t.engine.seats[i]
		if not seat then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(seat.name, classColor(seat.name))
		local L = t.ledger[seat.name]
		if L then
			GameTooltip:AddDoubleLine("Bought in", ns.Money(L.buyIn, t.cfg.mode), 0.8, 0.8, 0.8, 1, 1, 1)
			GameTooltip:AddDoubleLine("Session", ns.Money(seat.stack + (L.out or 0) - L.buyIn, t.cfg.mode), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if t.isDealer and seat.name ~= me() then
			GameTooltip:AddLine("Right-click: remove from table", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	s:SetScript("OnLeave", function() GameTooltip:Hide() end)
	s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	s:SetScript("OnMouseUp", function(_, button)
		local t = T()
		if button == "RightButton" and t and t.isDealer and t.engine.seats[i] and t.engine.seats[i].name ~= me() then
			t:Kick(t.engine.seats[i].name)
		end
	end)
	return s
end

function UI:PlaceSeats()
	local t = T()
	local n = t.cfg.maxSeats
	local base = t:MySeat() or 1
	for i, s in ipairs(self.seats) do
		if i > n then
			s:Hide() s.status:Hide() s.bet:Hide() s.dealer:Hide()
			for _, c in ipairs(s.cards) do c:Hide() end
		else
			local k = (i - base) % n
			local a = -math.pi / 2 - k * 2 * math.pi / n
			local x, y = CX + RX * math.cos(a), CY + RY * math.sin(a)
			s.pos = { x, y }
			s:ClearAllPoints()
			s:SetPoint("CENTER", self.felt, "BOTTOMLEFT", x, y)
			local dx, dy = CX - x, CY - y
			local len = math.sqrt(dx * dx + dy * dy)
			dx, dy = dx / len, dy / len
			local mine = (i == t:MySeat())
			local cw, ch = mine and 50 or 36, mine and 70 or 50
			local ox, oy = x + dx * 92, y + dy * (mine and 66 or 54)
			for j, c in ipairs(s.cards) do
				c:SetSize(cw, ch)
				c.rank:SetFont(W.FONT, math.floor(ch * 0.30), "")
				c.pip:SetSize(cw * 0.30, cw * 0.30)
				c.big:SetSize(cw * 0.58, cw * 0.58)
				c.glow:SetSize(cw * 1.9, ch * 1.55)
				c:ClearAllPoints()
				c:SetPoint("CENTER", self.felt, "BOTTOMLEFT", ox + (j == 1 and -(cw * 0.52) or (cw * 0.52)), oy)
			end
			s.bet:ClearAllPoints()
			s.bet:SetPoint("LEFT", self.felt, "BOTTOMLEFT", x + (CX - x) * 0.47 - 20, y + (CY - y) * 0.47)
			s.dealer:ClearAllPoints()
			s.dealer:SetPoint("CENTER", self.felt, "BOTTOMLEFT", x + (CX - x) * 0.30 + dy * 42, y + (CY - y) * 0.30 - dx * 42)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------------------------
function UI:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "GoblinHoldemTable", UIParent, W.BACKDROP_TEMPLATE)
	self.frame = f
	f:SetSize(FW, FH)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	W.Backdrop(f, "dialog")
	W.Movable(f, "table")
	W.Header(f, "Goblin Hold'em", 300)
	tinsert(UISpecialFrames, "GoblinHoldemTable")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -5, -5)

	f.subtitle = W.Text(f, 12)
	f.subtitle:SetPoint("TOP", 0, -24)
	f.subtitle:SetTextColor(0.9, 0.85, 0.7)

	local ledgerBtn = W.Button(f, "Ledger & Audit", 120, 22, function() ns.LedgerUI:Toggle() end)
	ledgerBtn:SetPoint("TOPLEFT", 18, -18)
	local lobbyBtn = W.Button(f, "Lobby", 70, 22, function() ns.LobbyUI:Toggle() end)
	lobbyBtn:SetPoint("LEFT", ledgerBtn, "RIGHT", 4, 0)

	-- felt
	local felt = CreateFrame("Frame", nil, f)
	self.felt = felt
	felt:SetSize(FELT_W, FELT_H)
	felt:SetPoint("TOP", 0, -42)
	local tex = felt:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	tex:SetTexture(W.MEDIA .. "felt")

	self.seats = {}
	for i = 1, 9 do self.seats[i] = createSeat(felt, i) end

	self.board = {}
	for i = 1, 5 do
		local c = W.Card(felt, 52, 72)
		c:SetFrameLevel(felt:GetFrameLevel() + 3)
		c:SetPoint("CENTER", felt, "BOTTOMLEFT", CX + (i - 3) * 58, CY + 22)
		self.board[i] = c
	end
	self.pot = W.Text(felt, 14, W.FONT)
	self.pot:SetPoint("CENTER", felt, "BOTTOMLEFT", CX, CY - 32)
	self.pot:SetTextColor(1, 0.9, 0.6)
	self.message = W.Text(felt, 15, W.FONT_TITLE)
	self.message:SetPoint("CENTER", felt, "BOTTOMLEFT", CX, CY - 56)
	self.message:SetWidth(440)
	self.message:SetTextColor(1, 0.82, 0)

	-- fairness seal, top-right corner of the felt
	local seal = CreateFrame("Frame", nil, felt)
	self.seal = seal
	seal:SetSize(190, 38)
	seal:SetPoint("TOPRIGHT", -4, 0)
	seal.icon = seal:CreateTexture(nil, "ARTWORK")
	seal.icon:SetTexture("Interface\\Icons\\INV_Misc_Key_03")
	seal.icon:SetSize(30, 30)
	seal.icon:SetPoint("LEFT")
	seal.line1 = W.Text(seal, 11)
	seal.line1:SetPoint("TOPLEFT", seal.icon, "TOPRIGHT", 5, -1)
	seal.line2 = W.Text(seal, 10)
	seal.line2:SetPoint("TOPLEFT", seal.line1, "BOTTOMLEFT", 0, -2)
	seal:EnableMouse(true)
	seal:SetScript("OnEnter", function(self) UI:SealTooltip(self) end)
	seal:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- warning banner, top-left corner of the felt
	self.banner = W.Text(felt, 11)
	self.banner:SetPoint("TOPLEFT", 6, -4)
	self.banner:SetWidth(200)
	self.banner:SetJustifyH("LEFT")

	self:CreateLog(f)
	self:CreateActions(f)

	f:SetScript("OnUpdate", function(_, elapsed) UI:OnUpdate(elapsed) end)
	f:Hide()
	return f
end

function UI:CreateLog(f)
	local box = CreateFrame("Frame", nil, f, W.BACKDROP_TEMPLATE)
	box:SetSize(368, 150)
	box:SetPoint("BOTTOMLEFT", 16, 16)
	W.Backdrop(box, "inset")
	local log = CreateFrame("ScrollingMessageFrame", nil, box)
	log:SetPoint("TOPLEFT", 8, -6)
	log:SetPoint("BOTTOMRIGHT", -8, 6)
	log:SetFont(W.FONT_NARROW, 12, "")
	log:SetJustifyH("LEFT")
	log:SetFading(false)
	log:SetMaxLines(400)
	log:EnableMouseWheel(true)
	log:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then self:ScrollUp() else self:ScrollDown() end
	end)
	self.log = log
end

function UI:CreateActions(f)
	local p = CreateFrame("Frame", nil, f, W.BACKDROP_TEMPLATE)
	self.actions = p
	p:SetSize(488, 150)
	p:SetPoint("BOTTOMRIGHT", -16, 16)
	W.Backdrop(p, "inset")

	p.info = W.Text(p, 13)
	p.info:SetPoint("TOPLEFT", 10, -9)
	p.info:SetPoint("TOPRIGHT", -10, -9)
	p.info:SetJustifyH("LEFT")
	p.hand = W.Text(p, 12)
	p.hand:SetPoint("TOPRIGHT", -10, -9)
	p.hand:SetTextColor(0.6, 0.9, 1)

	p.fold = W.Button(p, "Fold", 110, 30, function() UI:Do("fold") end)
	p.fold:SetPoint("TOPLEFT", 10, -30)
	p.call = W.Button(p, "Check", 150, 30, function() UI:Do("call") end)
	p.call:SetPoint("LEFT", p.fold, "RIGHT", 6, 0)
	p.raise = W.Button(p, "Raise", 190, 30, function() UI:Do("raise") end)
	p.raise:SetPoint("LEFT", p.call, "RIGHT", 6, 0)

	local slider = CreateFrame("Slider", nil, p, W.BACKDROP_TEMPLATE)
	p.slider = slider
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(330, 16)
	slider:SetPoint("TOPLEFT", 14, -70)
	if slider.SetBackdrop then
		slider:SetBackdrop({
			bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
			edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
			tile = true, tileSize = 8, edgeSize = 8,
			insets = { left = 3, right = 3, top = 6, bottom = 6 },
		})
	end
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	slider:SetMinMaxValues(0, 1)
	slider:SetValue(0)
	slider:SetScript("OnValueChanged", function(_, v, user)
		if UI.updatingSlider then return end
		UI:SetRaise(v, true)
	end)
	p.amount = W.Edit(p, 110)
	p.amount:SetPoint("LEFT", slider, "RIGHT", 14, 0)
	p.amount:SetScript("OnEnterPressed", function(self)
		local t = T()
		local v = t and ns.ParseMoney(self:GetText(), t.cfg.mode)
		if v then UI:SetRaise(v) end
		self:ClearFocus()
	end)

	local presets = { { "Min", "min" }, { "1/2 Pot", 0.5 }, { "3/4 Pot", 0.75 }, { "Pot", 1 }, { "All-in", "max" } }
	local prev
	p.presets = {}
	for _, pr in ipairs(presets) do
		local b = W.Button(p, pr[1], 72, 20, function() UI:Preset(pr[2]) end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 10, -94) end
		prev = b
		p.presets[#p.presets + 1] = b
	end

	-- seat / dealer controls (bottom row)
	p.sitout = W.Check(p, "Sit out", function(v) local t = T() if t then t:SitOut(v) end end)
	p.sitout:SetPoint("BOTTOMLEFT", 8, 6)
	p.addChips = W.Button(p, "Add chips", 80, 20, function() UI:PromptBuy(nil) end)
	p.addChips:SetPoint("BOTTOMLEFT", 84, 8)
	p.leave = W.Button(p, "Leave", 60, 20, function() StaticPopup_Show("GOBLINHOLDEM_LEAVE") end)
	p.leave:SetPoint("LEFT", p.addChips, "RIGHT", 4, 0)

	p.deal = W.Button(p, "Deal", 56, 20, function() local t = T() if t then t:DealNext() end end)
	p.deal:SetPoint("BOTTOMRIGHT", -8, 8)
	p.auto = W.Check(p, "Auto", function(v) local t = T() if t then t.autoDeal = v if v then t:MaybeAutoDeal(2) end end end)
	p.auto:SetPoint("RIGHT", p.deal, "LEFT", -40, 0)
	p.requests = W.Button(p, "Requests", 84, 20, function() ns.RequestsUI:Toggle() end)
	p.requests:SetPoint("RIGHT", p.auto, "LEFT", -4, 0)
	p.closeTable = W.Button(p, "Close", 56, 20, function() StaticPopup_Show("GOBLINHOLDEM_CLOSE") end)
	p.closeTable:SetPoint("RIGHT", p.requests, "LEFT", -4, 0)
end

---------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------
function UI:MyLegal()
	local t = T()
	if not t or t.phase ~= "playing" then return nil end
	local seat = t:MySeat()
	return seat and t.engine:Legal(seat), seat, t
end

function UI:SetRaise(v, fromSlider)
	local L, _, t = self:MyLegal()
	if not L then return end
	v = math.floor(v)
	if v < L.minTo then v = L.minTo end
	if v > L.maxTo then v = L.maxTo end
	-- snap to the small blind so the slider produces round numbers
	if fromSlider and v < L.maxTo then
		local step = t.cfg.sb
		v = math.max(L.minTo, math.floor(v / step + 0.5) * step)
	end
	self.raiseTo = v
	local p = self.actions
	self.updatingSlider = true
	p.slider:SetValue(v)
	self.updatingSlider = false
	p.amount:SetText(ns.Money(v, t.cfg.mode, true))
	self:RefreshButtons()
end

function UI:Preset(kind)
	local L, seat, t = self:MyLegal()
	if not L then return end
	if kind == "min" then return self:SetRaise(L.minTo) end
	if kind == "max" then return self:SetRaise(L.maxTo) end
	local h = t.engine.hand
	local pot = t.engine:PotTotal() + L.toCall
	self:SetRaise(h.currentBet + math.floor(pot * kind))
end

function UI:Do(kind)
	local L, seat, t = self:MyLegal()
	if not L then return end
	if kind == "call" then kind = L.check and "check" or "call" end
	local ok, err
	if kind == "raise" then
		ok, err = t:Act("raise", self.raiseTo or L.minTo)
	else
		ok, err = t:Act(kind)
	end
	if not ok then ns.Print(err) end
	W.Sound(kind == "fold" and "click" or "chips")
end

function UI:OnSeatClick(i)
	local t = T()
	if not t or t.phase == "closed" or t.engine.seats[i] then return end
	if t:MySeat() then return end
	self:PromptBuy(i)
end

StaticPopupDialogs["GOBLINHOLDEM_BUYIN"] = {
	text = "%s",
	button1 = "OK",
	button2 = "Cancel",
	hasEditBox = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(self, data)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(data and data.default or "") eb:HighlightText() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		local t = T()
		if not t or not eb then return end
		local v = ns.ParseMoney(eb:GetText(), t.cfg.mode)
		if not v or v <= 0 then return ns.Print("Couldn't read that amount.") end
		if data.seat then t:RequestSeat(data.seat, v) else t:RequestChips(v) end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		StaticPopupDialogs.GOBLINHOLDEM_BUYIN.OnAccept(parent, parent.data)
		parent:Hide()
	end,
}

StaticPopupDialogs["GOBLINHOLDEM_LEAVE"] = {
	text = "Leave the table? If a hand is running you will be folded when it's your turn.",
	button1 = "Leave", button2 = "Stay", timeout = 0, whileDead = true, hideOnEscape = true,
	OnAccept = function() local t = T() if t then t:Leave() end end,
}

StaticPopupDialogs["GOBLINHOLDEM_CLOSE"] = {
	text = "Close the table for everyone? Any hand in progress is voided and everyone cashes out.",
	button1 = "Close table", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
	OnAccept = function() local t = T() if t then t:Close() end end,
}

function UI:PromptBuy(seat)
	local t = T()
	if not t then return end
	local c = t.cfg
	local lines = {}
	if seat then
		lines[#lines + 1] = ("Buy in at %s (seat %d)"):format(c.name, seat)
	else
		lines[#lines + 1] = "Add chips (between hands)"
	end
	lines[#lines + 1] = ("Min %s, max %s."):format(ns.Money(c.minBuy, c.mode, true), ns.Money(c.maxBuy, c.mode, true))
	if c.mode == "bank" then
		lines[#lines + 1] = "|cffffd100House bank:|r trade the dealer the gold first; they approve the chips."
	elseif c.mode == "iou" then
		lines[#lines + 1] = "|cffffd100Friends game:|r nothing is traded now - you settle up from the ledger at the end."
	end
	if c.mode ~= "fun" then lines[#lines + 1] = "Amount (e.g. 50 or 12g 50s):" end
	local default = ns.Money(c.maxBuy, c.mode, true)
	StaticPopup_Show("GOBLINHOLDEM_BUYIN", table.concat(lines, "\n"), nil, { seat = seat, default = default })
end

---------------------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------------------
local STATUS = { fold = "Fold", check = "Check", call = "Call", raise = "Raise", allin = "All-in" }

function UI:Refresh()
	local t = T()
	local f = self.frame
	if not f or not f:IsShown() or not t then return end
	local e, h = t.engine, t.engine.hand
	local c = t.cfg
	f.headerText:SetText(c.name or "Goblin Hold'em")
	f.subtitle:SetText(("%s / %s No-Limit  -  %s  -  dealer: %s%s"):format(
		ns.Money(c.sb, c.mode), ns.Money(c.bb, c.mode), ns.Table.MODES[c.mode] or c.mode, t.dealer,
		t.phase == "closed" and "  |cffff5050(closed)|r" or ""))
	self:PlaceSeats()

	local live = h and h.phase ~= "done"
	local cur = t.cur
	for i = 1, c.maxSeats do
		local s, seat = self.seats[i], e.seats[i]
		s:Show()
		s.status:Show()
		if seat then
			s.name:SetText(seat.name)
			s.name:SetTextColor(classColor(seat.name))
			s.stack:SetText(ns.Money(seat.stack, c.mode))
			local inHand = h and h.inHand[i]
			local status = ""
			if t.phase == "rolling" and cur and cur.eligible[seat.name] then
				local r = cur.observed[seat.name]
				status = r and ("|cff80ff80rolled " .. r .. "|r") or "|cffaaaaaarolling...|r"
			elseif seat.sittingOut then status = "|cff999999Sitting out|r"
			elseif inHand and h.folded[i] then status = "|cff999999Folded|r"
			elseif inHand and h.allin[i] then status = "|cffff8040All-in|r"
			elseif self.lastAction[i] then status = STATUS[self.lastAction[i]] or self.lastAction[i]
			elseif seat.stack == 0 and not inHand then status = "|cff999999Busted|r"
			end
			if self.winners[i] then status = "|cffffd100Winner!|r" end
			s.status:SetText(status)
			local active = live and h.phase == "betting" and h.toAct == i
			if active then s:SetBackdropBorderColor(1, 0.85, 0.15, 1) else s:SetBackdropBorderColor(0.75, 0.6, 0.3, 1) end
			s.timer:SetShown(active and true or false)
			-- cards
			local show = self.shown[i]
			local mine = (seat.name == me()) and cur and cur.myHole and cur.no == (h and h.no)
			for j = 1, 2 do
				local card = s.cards[j]
				if show then
					card:SetCard(show[j]) card:SetDim(false)
				elseif mine and inHand then
					card:SetCard(cur.myHole[j]) card:SetDim(h.folded[i])
				elseif inHand and live and not h.folded[i] then
					card:SetCard("back") card:SetDim(false)
				else
					card:SetCard(nil)
				end
				card.glow:SetShown(self.winners[i] and show and true or false)
			end
			-- bets
			local bet = live and inHand and h.bet[i] or 0
			if bet > 0 then
				s.bet:Show()
				s.bet.text:SetText(ns.Money(bet, c.mode))
			else
				s.bet:Hide()
			end
			s.dealer:SetShown(h and h.button == i and true or false)
		else
			s.name:SetText("|cff888888Open seat|r")
			s.stack:SetText((not t:MySeat() and t.phase ~= "closed") and "|cffffd100Click to sit|r" or "")
			s.status:SetText("")
			s:SetBackdropBorderColor(0.4, 0.35, 0.25, 0.8)
			s.timer:Hide()
			s.bet:Hide()
			s.dealer:Hide()
			for _, card in ipairs(s.cards) do card:SetCard(nil) end
		end
	end

	-- board and pot
	local board = h and h.board or {}
	for i = 1, 5 do self.board[i]:SetCard(board[i]) end
	local pot = h and e:PotTotal() or 0
	self.pot:SetText(pot > 0 and ("Pot: " .. ns.Money(pot, c.mode)) or "")

	if t.phase == "rolling" and cur then
		local n, got = 0, 0
		for name in pairs(cur.eligible) do n = n + 1 if cur.observed[name] then got = got + 1 end end
		self.message:SetText(("Rolling for the shuffle  %d / %d"):format(got, n))
	elseif t.phase == "closed" then
		self.message:SetText("Table closed - see the ledger to settle up")
	elseif not h or h.phase == "done" then
		if not self.resultText then
			local seated = 0
			for _ in pairs(e.seats) do seated = seated + 1 end
			self.message:SetText(seated < 2 and "Waiting for players..." or "")
		else
			self.message:SetText(self.resultText)
		end
	else
		self.message:SetText("")
	end

	self:RefreshSeal()
	self:RefreshBanner()
	self:RefreshButtons()
end

function UI:RefreshBanner()
	local t = T()
	local parts = {}
	if t.cfg.dealerSeated then parts[#parts + 1] = "|cffffa040Dealer is playing too|r" end
	if t.stats.failed > 0 then parts[#parts + 1] = ("|cffff3030%d hand(s) FAILED audit|r"):format(t.stats.failed) end
	if t.stats.voids > 0 then parts[#parts + 1] = ("|cffffa040%d hand(s) voided|r"):format(t.stats.voids) end
	self.banner:SetText(table.concat(parts, "\n"))
end

function UI:RefreshSeal()
	local t = T()
	local seal = self.seal
	local cur = t.cur
	local last = t.audits[#t.audits]
	if t.stats.failed > 0 then
		seal.line1:SetText("|cffff3030AUDIT FAILED|r")
		seal.icon:SetVertexColor(1, 0.3, 0.3)
	elseif cur and not cur.revealed then
		seal.line1:SetText(("|cffffd100Hand #%d deck sealed|r"):format(cur.no))
		seal.icon:SetVertexColor(1, 1, 1)
	elseif last and last.ok then
		seal.line1:SetText(("|cff40ff40Hand #%d verified|r"):format(last.hand))
		seal.icon:SetVertexColor(0.6, 1, 0.6)
	else
		seal.line1:SetText("|cffccccccProvably fair deck|r")
		seal.icon:SetVertexColor(1, 1, 1)
	end
	seal.line2:SetText(("%d verified  -  %d failed"):format(t.stats.verified, t.stats.failed))
end

function UI:SealTooltip(owner)
	local t = T()
	if not t then return end
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
	GameTooltip:AddLine("Sealed deck", 1, 0.82, 0)
	GameTooltip:AddLine("Before each hand the dealer publishes a seal (a hash of a secret). Then every player /rolls 1-1000000 - those rolls come from the Blizzard server. The deck is shuffled from the secret plus all the rolls.", 1, 1, 1, true)
	GameTooltip:AddLine("When the hand ends the dealer reveals the secret and your add-on re-shuffles the deck itself and checks the seal, the rolls, the board and your own cards.", 1, 1, 1, true)
	local cur = t.cur
	if cur then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Hand", "#" .. cur.no, 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Seal", cur.commit:sub(1, 24) .. "...", 0.8, 0.8, 0.8, 1, 1, 1)
		for name, v in pairs(cur.observed) do
			GameTooltip:AddDoubleLine("  " .. name, v, 0.8, 0.8, 0.8, 0.5, 1, 0.5)
		end
	end
	GameTooltip:Show()
end

function UI:RefreshButtons()
	local t = T()
	local p = self.actions
	if not t or not p then return end
	local L, seat = self:MyLegal()
	local h = t.engine.hand
	local mySeat = t:MySeat()
	local c = t.cfg

	local acting = L ~= nil
	for _, b in ipairs({ p.fold, p.call, p.raise }) do b:SetEnabled(acting) end
	for _, b in ipairs(p.presets) do b:SetEnabled(acting and L.canRaise) end
	local canRaise = acting and L.canRaise or false
	if canRaise then p.slider:Enable() p.amount:Enable() else p.slider:Disable() p.amount:Disable() end
	p.slider:SetAlpha(canRaise and 1 or 0.4)
	p.amount:SetAlpha(canRaise and 1 or 0.4)

	if acting then
		p.call:SetText(L.check and "Check" or ("Call " .. ns.Money(L.toCall, c.mode, true)))
		if L.canRaise then
			if not self.raiseTo or self.raiseTo < L.minTo or self.raiseTo > L.maxTo or self.raiseFor ~= h.seq then
				self.raiseFor = h.seq
				self.updatingSlider = true
				p.slider:SetMinMaxValues(L.minTo, L.maxTo)
				self.updatingSlider = false
				self:SetRaise(L.minTo)
				return
			end
			p.slider:SetMinMaxValues(L.minTo, L.maxTo)
			local word = L.isBet and "Bet " or "Raise to "
			if self.raiseTo >= L.maxTo then word = "All-in " end
			p.raise:SetText(word .. ns.Money(self.raiseTo, c.mode, true))
		else
			p.raise:SetText("Raise")
			p.raise:SetEnabled(false)
		end
	else
		p.call:SetText("Check / Call")
		p.raise:SetText("Bet / Raise")
	end

	-- info line
	local info
	if t.phase == "closed" then info = "The table is closed."
	elseif acting then info = "|cffffd100Your turn.|r"
	elseif h and h.phase == "betting" and h.toAct then info = "Waiting for " .. t:Name(h.toAct) .. "..."
	elseif t.phase == "rolling" then info = "Rolling for the shuffle..."
	elseif not mySeat then info = "Spectating - click an open seat to sit down."
	else info = t.isDealer and (t.autoDeal and "Next hand starts shortly." or "Press Deal to start the next hand.") or "Waiting for the next hand..." end
	p.info:SetText(info)

	-- hand strength
	local cur = t.cur
	local text = ""
	if cur and cur.myHole and h and h.no == cur.no and h.inHand[mySeat or 0] then
		local cards = { cur.myHole[1], cur.myHole[2] }
		for _, x in ipairs(h.board) do cards[#cards + 1] = x end
		if #cards >= 5 then
			local _, _, desc = ns.Eval.Eval(cards)
			text = desc
		else
			local a, b = cur.myHole[1], cur.myHole[2]
			local ra, rb = math.floor(a / 4), math.floor(b / 4)
			if ra == rb then text = "Pocket " .. Cards.RANK_PLURAL[ra + 1]
			else
				local hi, lo = math.max(ra, rb), math.min(ra, rb)
				text = Cards.RANKS:sub(hi + 1, hi + 1) .. Cards.RANKS:sub(lo + 1, lo + 1) .. (a % 4 == b % 4 and " suited" or " offsuit")
			end
		end
	end
	p.hand:SetText(text)

	-- seat/dealer controls
	p.sitout:SetShown(mySeat ~= nil and t.phase ~= "closed")
	if mySeat then p.sitout:SetChecked(t.engine.seats[mySeat].sittingOut) end
	p.addChips:SetShown(mySeat ~= nil and t.phase ~= "closed")
	p.leave:SetShown(mySeat ~= nil and t.phase ~= "closed" and not t.leaving)
	local dealer = t.isDealer and t.phase ~= "closed"
	p.deal:SetShown(dealer)
	p.deal:SetEnabled(dealer and t:CanDeal() or false)
	p.auto:SetShown(dealer)
	if dealer then p.auto:SetChecked(t.autoDeal) end
	p.requests:SetShown(dealer)
	if dealer then p.requests:SetText(("Requests (%d)"):format(#t.requests)) end
	p.closeTable:SetShown(dealer)
end

---------------------------------------------------------------------------------------------
-- Timers and events
---------------------------------------------------------------------------------------------
local acc = 0
function UI:OnUpdate(elapsed)
	acc = acc + elapsed
	if self.dirty then
		self.dirty = false
		self:Refresh()
	end
	if acc < 0.05 then return end
	acc = 0
	local t = T()
	local h = t and t.engine.hand
	if not h or h.phase ~= "betting" or not h.toAct then return end
	local key = h.no .. ":" .. h.seq .. ":" .. h.toAct
	if key ~= self.turnKey then
		self.turnKey = key
		self.turnStart = GetTime()
		if h.toAct == t:MySeat() then
			W.Sound("turn")
			if FlashClientIcon then pcall(FlashClientIcon) end
		end
	end
	local frac = 1 - (GetTime() - self.turnStart) / (t.cfg.actTimeout or 30)
	local s = self.seats[h.toAct]
	if s then
		s.timer:SetValue(math.max(0, frac))
		if frac < 0.25 then s.timer:SetStatusBarColor(1, 0.2, 0.1) else s.timer:SetStatusBarColor(1, 0.75, 0.1) end
	end
end

function UI:MarkDirty() self.dirty = true end

function UI:Show()
	self:Create()
	self.frame:Show()
	self:ReloadLog()
	self:Refresh()
end

function UI:Toggle()
	self:Create()
	if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function UI:ReloadLog()
	local t = T()
	if not t or not self.log then return end
	self.log:Clear()
	for _, line in ipairs(t.log) do self.log:AddMessage(line) end
end

ns.Listen("TABLE_OPENED", function(t)
	UI.lastAction, UI.shown, UI.winners, UI.resultText = {}, {}, {}, nil
	local wanted = ns.Lobby and ns.Lobby.wanted and ns.Lobby.wanted[t.id]
	if t.isDealer or wanted or (ns.db and ns.db.settings.autoOpen) then
		UI:Show()
	else
		ns.Print(("%s opened a table in your group: |cffffd100%s|r. Type |cffffffff/holdem|r to watch or sit down."):format(t.dealer, t.cfg.name))
	end
	UI:ReloadLog()
end)
ns.Listen("TABLE_UPDATE", function() UI:MarkDirty() end)
ns.Listen("TABLE_LOG", function(t, text)
	if t == ns.current and UI.log then UI.log:AddMessage(text) end
end)
ns.Listen("TABLE_ALERT", function(t, text, severity)
	if severity == "cheat" then
		W.Sound("alert")
		if RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, "Goblin Hold'em: " .. text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.2, b = 0.2 })
		end
		ns.Print("|cffff3030" .. text .. "|r")
	end
end)
ns.Listen("TABLE_DEALT", function()
	UI.lastAction, UI.shown, UI.winners, UI.resultText = {}, {}, {}, nil
	W.Sound("card")
end)
ns.Listen("TABLE_ACTION", function(t, seat, kind)
	UI.lastAction[seat] = kind
end)
ns.Listen("TABLE_HAND_END", function(t, r)
	UI.lastAction = {}
	if r.voided then UI.resultText = "Hand voided" return end
	if r.showdown then
		for seat, hole in pairs(r.holes) do UI.shown[seat] = hole end
	end
	local parts, won = {}, false
	for _, a in ipairs(r.awards) do
		UI.winners[a.seat] = true
		if t.engine.seats[a.seat] and t.engine.seats[a.seat].name == me() then won = true end
		parts[#parts + 1] = ("%s wins %s%s"):format(t:Name(a.seat), ns.Money(a.amount, t.cfg.mode, true), a.hand and (" - " .. a.hand) or "")
	end
	UI.resultText = table.concat(parts, "\n")
	W.Sound(won and "win" or "chips")
end)
ns.Listen("TABLE_REQUEST", function() W.Sound("click") end)
