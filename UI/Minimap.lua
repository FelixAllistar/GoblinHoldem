-- Minimap button (left-click: open/close, right-click: settings, drag: move), the settings
-- panel, and the "it's your turn" alert, which has to work with every window closed.
local _, ns = ...

local W = ns.W
local B = {}
ns.MinimapButton = B

local function myTurn()
	local t = ns.current
	local h = t and t.engine.hand
	return h and h.phase == "betting" and h.toAct ~= nil and h.toAct == t:MySeat()
end

function B:Place()
	local angle = math.rad(ns.db and ns.db.minimapAngle or 215)
	local r = (Minimap:GetWidth() / 2) + 6
	self.button:ClearAllPoints()
	self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

function B:Create()
	if self.button or not Minimap then return end
	local b = CreateFrame("Button", "GoblinHoldemMinimapButton", Minimap)
	self.button = b
	b.dragging = false
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_04")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	b.glow = b:CreateTexture(nil, "OVERLAY")
	b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	b.glow:SetBlendMode("ADD")
	b.glow:SetSize(58, 58)
	b.glow:SetPoint("CENTER", 0, 1)
	b.glow:SetVertexColor(1, 0.85, 0.2)
	b.glow:Hide()

	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns.SettingsUI:Toggle(b) else ns.ToggleMain() end
	end)
	b:SetScript("OnDragStart", function() b.dragging = true end)
	b:SetScript("OnDragStop", function() b.dragging = false end)
	local acc = 0
	b:SetScript("OnUpdate", function(_, elapsed)
		if b.dragging then
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			B:Place()
		end
		acc = acc + elapsed
		if acc < 0.05 then return end
		acc = 0
		if myTurn() then
			b.glow:Show()
			b.glow:SetAlpha(0.45 + 0.55 * math.abs(math.sin(GetTime() * 3)))
		else
			b.glow:Hide()
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Goblin Hold'em", 1, 0.82, 0)
		local t = ns.current
		if t then
			GameTooltip:AddLine(t.cfg.name .. (t.phase == "closed" and " (closed)" or ""), 1, 1, 1)
			local seat = t:MySeat()
			if seat then
				local L = t.ledger[ns.Comm.Me()]
				GameTooltip:AddDoubleLine("Your stack", ns.Money(t.engine.seats[seat].stack, t.cfg.mode), 0.8, 0.8, 0.8, 1, 1, 1)
				if L then
					local net = t.engine.seats[seat].stack + (L.out or 0) - L.buyIn
					GameTooltip:AddDoubleLine("This session", (net > 0 and "+" or "") .. ns.Money(net, t.cfg.mode), 0.8, 0.8, 0.8, 1, 1, 1)
				end
			end
			if myTurn() then GameTooltip:AddLine("It's your turn!", 1, 0.82, 0) end
		else
			GameTooltip:AddLine("Not at a table", 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click: open / close", 0.6, 0.8, 1)
		GameTooltip:AddLine("Right-click: settings", 0.6, 0.8, 1)
		GameTooltip:AddLine("Drag: move this button", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self:Place()
end

function B:Update()
	self:Create()
	if not self.button then return end
	if ns.db and ns.db.settings.minimap == false then self.button:Hide() else self.button:Show() end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() B:Update() end)

---------------------------------------------------------------------------------------------
-- Your-turn alert
---------------------------------------------------------------------------------------------
local function anyWindowShown()
	local a, b = ns.TableUI.frame, ns.MiniUI.frame
	return (a and a:IsShown()) or (b and b:IsShown())
end

ns.Listen("TABLE_TURN", function()
	W.Sound("turn")
	if FlashClientIcon then pcall(FlashClientIcon) end
	if anyWindowShown() then return end
	if UIErrorsFrame then UIErrorsFrame:AddMessage("Goblin Hold'em: it's your turn!", 1, 0.82, 0) end
	if not ns.db or ns.db.settings.turnPopup then ns.MiniUI:Show() end
end)

ns.Listen("TABLE_TIMED_OUT", function()
	ns.Print("You ran out of time and are sitting out. Click |cffffffffI'm back|r when you're ready - you won't be dealt in (or pay blinds) until then.")
end)

---------------------------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------------------------
local S = {}
ns.SettingsUI = S

local OPTIONS = {
	{ "sound", "Sounds" },
	{ "turnPopup", "Pop up the mini HUD when it's my turn" },
	{ "mini", "Open the mini HUD instead of the full table" },
	{ "confirmAllIn", "Ask before going all-in for gold" },
	{ "autoOpen", "Open the table when one starts in my party" },
	{ "hideRolls", "Keep shuffle /rolls out of my chat" },
	{ "minimap", "Show the minimap button" },
}

function S:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "GoblinHoldemSettings", UIParent, W.BACKDROP_TEMPLATE)
	self.frame = f
	f:SetSize(330, 96 + #OPTIONS * 26 + 64)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	W.Backdrop(f, "dialog")
	W.Header(f, "Hold'em Settings", 250)
	W.Movable(f, "settings")
	tinsert(UISpecialFrames, "GoblinHoldemSettings")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -5, -5)

	self.checks = {}
	for i, opt in ipairs(OPTIONS) do
		local c = W.Check(f, opt[2], function(v)
			ns.db.settings[opt[1]] = v
			if opt[1] == "minimap" then
				B:Update()
				if not v then ns.Print("Minimap button hidden. /holdem minimap brings it back.") end
			end
		end)
		c:SetPoint("TOPLEFT", 20, -30 - (i - 1) * 26)
		self.checks[opt[1]] = c
	end

	local y = -34 - #OPTIONS * 26
	local label = W.Text(f, 12)
	label:SetPoint("TOPLEFT", 24, y - 4)
	label:SetText("Table size")
	label:SetTextColor(1, 0.9, 0.7)
	self.sizes = {}
	local prev
	for _, sz in ipairs({ { 0.8, "Small" }, { 1, "Normal" }, { 1.15, "Large" } }) do
		local b = W.Button(f, sz[2], 64, 20, function()
			ns.db.settings.scale = sz[1]
			if ns.TableUI.frame then ns.TableUI.frame:SetScale(sz[1]) end
			S:Refresh()
		end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", label, "LEFT", 84, 0) end
		prev = b
		self.sizes[sz[1]] = b
	end

	local lobby = W.Button(f, "Lobby", 90, 22, function() ns.LobbyUI:Toggle() end)
	lobby:SetPoint("BOTTOMLEFT", 20, 18)
	local debts = W.Button(f, "Debts", 90, 22, function() ns.LedgerUI:Show("debts") end)
	debts:SetPoint("LEFT", lobby, "RIGHT", 6, 0)
	local history = W.Button(f, "History", 90, 22, function() ns.LedgerUI:Show("history") end)
	history:SetPoint("LEFT", debts, "RIGHT", 6, 0)
	local keys = W.Text(f, 10)
	keys:SetPoint("BOTTOMLEFT", 22, 46)
	keys:SetTextColor(0.6, 0.6, 0.6)
	keys:SetText("Fold / Call keys: Esc > Key Bindings > AddOns > Goblin Hold'em")
	f:Hide()
	return f
end

function S:Refresh()
	if not self.frame then return end
	for key, c in pairs(self.checks) do c:SetChecked(ns.db.settings[key] and true or false) end
	for scale, b in pairs(self.sizes) do
		if math.abs((ns.db.settings.scale or 1) - scale) < 0.01 then b:LockHighlight() else b:UnlockHighlight() end
	end
end

function S:Toggle()
	self:Create()
	if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() self:Refresh() end
end
