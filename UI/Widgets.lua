-- Small UI building blocks shared by the table, lobby and ledger windows.
local _, ns = ...

local W = {}
ns.W = W

W.MEDIA = "Interface\\AddOns\\GoblinHoldem\\Media\\"
W.FONT_TITLE = "Fonts\\MORPHEUS.TTF"
W.FONT = "Fonts\\FRIZQT__.TTF"
W.FONT_NARROW = "Fonts\\ARIALN.TTF"
W.BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

W.GOLD = { 1, 0.82, 0 }

function W.Backdrop(frame, kind)
	if not frame.SetBackdrop then
		if BackdropTemplateMixin then Mixin(frame, BackdropTemplateMixin) else return end
	end
	if kind == "dialog" then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	elseif kind == "plate" then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0.06, 0.04, 0.02, 0.88)
		frame:SetBackdropBorderColor(0.75, 0.6, 0.3, 1)
	elseif kind == "inset" then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.55)
		frame:SetBackdropBorderColor(0.5, 0.42, 0.25, 0.9)
	end
end

function W.Text(parent, size, font, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(font or W.FONT, size or 12, "")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

function W.Button(parent, text, width, height, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 100, height or 24)
	b:SetText(text)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

function W.Check(parent, label, onClick)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c.label = W.Text(c, 12)
	c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
	c.label:SetText(label)
	c.label:SetTextColor(1, 0.9, 0.7)
	if onClick then c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end) end
	return c
end

function W.Edit(parent, width, numeric)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width or 100, 20)
	e:SetAutoFocus(false)
	e:SetFontObject(ChatFontNormal)
	if numeric then e:SetNumeric(true) end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return e
end

function W.Tooltip(frame, fn)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		fn(GameTooltip)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function W.Sound(kind)
	local SK = SOUNDKIT or {}
	local ids = {
		chips = SK.LOOT_WINDOW_COIN_SOUND or 120,
		turn = SK.READY_CHECK or 8960,
		card = SK.IG_SPELLBOOK_OPEN or 829,
		win = SK.IG_QUEST_LIST_COMPLETE or 618,
		alert = SK.RAID_WARNING or 8959,
		click = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,
	}
	if ns.db and ns.db.settings.sound == false then return end
	if ids[kind] then pcall(PlaySound, ids[kind], "SFX") end
end

function W.Movable(frame, key)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if ns.db and key then
			local p, _, rp, x, y = self:GetPoint()
			ns.db.frames[key] = { p, rp, x, y }
		end
	end)
	if ns.db and key and ns.db.frames[key] then
		local s = ns.db.frames[key]
		frame:ClearAllPoints()
		frame:SetPoint(s[1], UIParent, s[2], s[3], s[4])
	end
end

--- The gold WoW dialog header plate with a title on it.
function W.Header(frame, text, width)
	local h = frame:CreateTexture(nil, "ARTWORK")
	h:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	h:SetSize(width or 360, 64)
	h:SetPoint("TOP", 0, 12)
	local t = W.Text(frame, 15, W.FONT_TITLE)
	t:SetPoint("TOP", h, "TOP", 0, -14)
	t:SetTextColor(1, 0.82, 0)
	t:SetText(text)
	frame.headerText = t
	return h, t
end

---------------------------------------------------------------------------------------------
-- Playing card
---------------------------------------------------------------------------------------------
local RANK_TEXT = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }

function W.Card(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	local function tex(layer, file)
		local t = f:CreateTexture(nil, layer)
		t:SetTexture(W.MEDIA .. file)
		return t
	end
	f.face = tex("ARTWORK", "card")
	f.face:SetAllPoints()
	f.face:SetTexCoord(0, 1, 0, 180 / 256)
	f.back = tex("ARTWORK", "cardback")
	f.back:SetAllPoints()
	f.back:SetTexCoord(0, 1, 0, 180 / 256)
	f.rank = W.Text(f, math.floor(height * 0.30), W.FONT, "OVERLAY")
	f.rank:SetShadowOffset(0, 0)
	f.rank:SetPoint("TOPLEFT", width * 0.09, -height * 0.06)
	f.pip = tex("OVERLAY", "suits")
	f.pip:SetSize(width * 0.30, width * 0.30)
	f.pip:SetPoint("TOP", f.rank, "BOTTOM", 0, -1)
	f.big = tex("OVERLAY", "suits")
	f.big:SetSize(width * 0.58, width * 0.58)
	f.big:SetPoint("CENTER", width * 0.10, -height * 0.14)
	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	f.glow:SetBlendMode("ADD")
	f.glow:SetPoint("CENTER")
	f.glow:SetSize(width * 1.9, height * 1.55)
	f.glow:SetVertexColor(1, 0.85, 0.3)
	f.glow:Hide()

	function f:SetCard(c)
		self.card = c
		if c == nil then self:Hide() return end
		self:Show()
		local faceUp = type(c) == "number"
		self.face:SetShown(faceUp)
		self.back:SetShown(not faceUp)
		self.rank:SetShown(faceUp)
		self.pip:SetShown(faceUp)
		self.big:SetShown(faceUp)
		if faceUp then
			local r, s = math.floor(c / 4), c % 4
			self.rank:SetText(RANK_TEXT[r + 1])
			if s == 1 or s == 2 then self.rank:SetTextColor(0.78, 0.08, 0.1) else self.rank:SetTextColor(0.08, 0.08, 0.1) end
			self.pip:SetTexCoord(s * 0.25, s * 0.25 + 0.25, 0, 1)
			self.big:SetTexCoord(s * 0.25, s * 0.25 + 0.25, 0, 1)
		end
	end

	function f:SetDim(dim)
		self:SetAlpha(dim and 0.45 or 1)
	end
	f:Hide()
	return f
end
