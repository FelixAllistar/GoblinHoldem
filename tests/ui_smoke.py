"""Load the whole add-on (TOC order) against a mocked frame API and drive every window through a
real hand. Catches typos, nil calls and bad arithmetic in UI code without launching the game."""
import os
import re
import sys

from lupa import luajit21 as lj

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r"""
local function noop() end
local Widget = {}
local defaults = {
  GetFrameLevel = 1, GetStringHeight = 14, GetText = "", GetChecked = false, IsShown = true,
  GetWidth = 100, GetHeight = 20, IsEnabled = true, GetNumPoints = 1,
}
Widget.__index = function(self, k)
  if defaults[k] ~= nil then local v = defaults[k] return function() return v end end
  if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
  if k == "CreateTexture" or k == "CreateFontString" then return function() return setmetatable({}, Widget) end end
  if k == "SetScript" then return function(self, ev, fn) rawset(self, "_s_" .. ev, fn) end end
  if k == "GetScript" then return function(self, ev) return rawget(self, "_s_" .. ev) end end
  if k == "Show" then return function(self) rawset(self, "_shown", true) end end
  if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
  if k == "IsShown" then return function(self) return rawget(self, "_shown") ~= false end end
  return noop
end
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({}, Widget)
  if name then _G[name] = f end
  f.editBox = setmetatable({}, Widget)
  return f
end
UIParent = CreateFrame("Frame")
GameTooltip = CreateFrame("Frame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("CHAT", m) end }
UISpecialFrames = {}
StaticPopupDialogs = {}
function StaticPopup_Show(...) end
SlashCmdList = {}
ChatFontNormal = {}
BackdropTemplateMixin = {}
function Mixin(o, m) for k, v in pairs(m) do o[k] = v end return o end
function tinsert(t, v) table.insert(t, v) end
function time() return os.time() end
function UnitClass() return "Warrior", "WARRIOR" end
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
function PlaySound() end
function GetNumGroupMembers() return 2 end
function C_Timer.NewTicker() end
function GetAddOnMetadata() return "test" end
function GetRealZoneText() return "Booty Bay" end
function GetSubZoneText() return "The Salty Sailor Tavern" end
function GetChannelName() return 0 end
function IsInGuild() return false end
NUM_CHAT_WINDOWS = 1
function ChatFrame_AddMessageEventFilter(ev, fn) GH_FILTER = fn end
"""


def main():
    L = lj.LuaRuntime(unpack_returned_tuples=True)
    with open(os.path.join(ROOT, "tests", "wowstub.lua"), encoding="utf-8") as f:
        L.execute(f.read())
    L.globals().GH_PLAYER = "Grizzle"
    L.execute(MOCK)
    ns = L.eval("{}")
    with open(os.path.join(ROOT, "GoblinHoldem.toc"), encoding="utf-8") as f:
        files = [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
    load = L.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")
    for rel in files:
        with open(os.path.join(ROOT, rel.replace("\\", "/")), encoding="utf-8") as f:
            load(f.read(), rel)("GoblinHoldem", ns)
    L.execute("unpack = unpack or table.unpack")
    script = r"""
    local ns = ...
    -- fire ADDON_LOADED through the event frame's script
    for k, v in pairs(_G) do end
    """
    # find the event frame: Init created a frame with an OnEvent script; call handlers directly instead
    L.execute(r"""
    local ns = GoblinHoldem
    GoblinHoldemDB = nil
    -- emulate ADDON_LOADED
    GoblinHoldemDB = {}
    """)
    run = L.eval(r"""function(ns)
      -- ADDON_LOADED equivalent
      GoblinHoldemDB = { settings = { autoRoll = true, hideRolls = true, sound = true, autoOpen = false }, frames = {}, keys = {}, audit = {}, sessions = {} }
      ns.db = GoblinHoldemDB
      ns.LobbyUI:Toggle()
      ns.LobbyUI:SetMode("bank")
      ns.LobbyUI:SetMode("iou")
      ns.Lobby.OnMessage("Thrall", "CHANNEL", {"ADV","abc123","Thrall's Den","500","1000","3","9","iou","1","Booty Bay","20000","200000"})
      ns.LobbyUI:Refresh()
      local t = assert(ns.Table.Host({ name = "Test", mode = "iou", sb = 500, bb = 1000, minBuy = 20000, maxBuy = 200000,
        maxSeats = 9, dealerSeated = true, dealerBuyIn = 100000, actTimeout = 30 }))
      ns.TableUI:Show()
      -- a second player sits via a (fake) whisper
      ns.Comm.Deliver("Thrall", "WHISPER", ns.Comm.Join("SIT", t.id, 3, 100000, string.rep("k", 32)))
      GH_TIME = GH_TIME + 7 GH_RunTimers()
      GH_TIME = GH_TIME + 1 GH_RunTimers()
      ns.TableUI:Refresh()
      assert(t.phase == "rolling", "expected rolling, got " .. t.phase)
      t:OnSystem("Grizzle rolls 123 (1-1000000)")
      t:OnSystem("Thrall rolls 99999 (1-1000000)")
      for i = 1, 20 do GH_TIME = GH_TIME + 0.5 GH_RunTimers() end
      assert(t.phase == "playing", "expected playing, got " .. t.phase)
      ns.TableUI:Refresh()
      ns.TableUI:RefreshButtons()
      local h = t.engine.hand
      -- whoever is to act: if it's us, use the UI; otherwise inject Thrall's action
      for step = 1, 40 do
        h = t.engine.hand
        if not h or h.phase == "done" then break end
        if h.phase == "betting" then
          if h.toAct == t:MySeat() then
            ns.TableUI:Preset(0.5)
            ns.TableUI:Preset("min")
            ns.TableUI:Do("call")
          else
            ns.Comm.Deliver("Thrall", "PARTY", ns.Comm.Join("ACT", t.id, h.no, h.seq + 1, "call", 0))
            if t.engine.hand.seq == h.seq then
              ns.Comm.Deliver("Thrall", "PARTY", ns.Comm.Join("ACT", t.id, h.no, h.seq + 1, "check", 0))
            end
          end
        end
        GH_TIME = GH_TIME + 1 GH_RunTimers()
        ns.TableUI:Refresh()
        ns.TableUI:OnUpdate(0.1)
      end
      assert(t.engine.hand.phase == "done", "hand did not finish: " .. tostring(t.engine.hand.phase))
      ns.TableUI:Refresh()
      ns.LedgerUI:Show("ledger") ns.LedgerUI:Show("audit") ns.LedgerUI:Show("help")
      ns.RequestsUI:Toggle() ns.RequestsUI:Refresh()
      SlashCmdList.GOBLINHOLDEM("help")
      SlashCmdList.GOBLINHOLDEM("")
      assert(GH_FILTER(nil, nil, "Thrall rolls 5 (1-1000000)") == true, "roll filter")
      local saved = ns.SaveHosting(t)
      assert(saved.entries[1], "hosting save")
      t:Close()
      ns.LedgerUI:Show("ledger")
      return t.stats.verified, #t.log
    end""")
    verified, nlog = run(ns)
    print(f"ui smoke: hand verified={verified}, log lines={nlog}")
    dbg = ns.debugLog
    errors = [dbg[i + 1] for i in range(len(dbg))]
    for e in errors:
        print("DEBUG ERROR:", e)
    if verified < 1 or errors:
        print("FAIL: hand not verified")
        sys.exit(1)
    print("UI SMOKE PASSED")


if __name__ == "__main__":
    main()
