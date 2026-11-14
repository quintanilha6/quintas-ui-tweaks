local ADDON_NAME = ...

-- Default settings (saved per account in QuintaDB)
local DEFAULTS = {
  scale = 0.5,
  hideChat = true,
  hideMenu = false,
  hideBags = false,
  hideTracker = false,
  cameraZoom = 2.6,
  autoRank = true,
}
local MIN_ZOOM, MAX_ZOOM, ZOOM_STEP = 1.0, 2.6, 0.1

local function ApplyCameraZoom(value)
  local setCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
  setCVar("cameraDistanceMaxZoomFactor", tostring(value))
end
local MIN_SCALE, MAX_SCALE, STEP = 0.3, 1.2, 0.05

local db

---------------------------------------------------------------------------
-- UI scale
---------------------------------------------------------------------------
local function ApplyScale()
  if db and not InCombatLockdown() then
    UIParent:SetScale(db.scale)
  end
end

---------------------------------------------------------------------------
-- Hide chat in combat
---------------------------------------------------------------------------
local function GetChatFrames()
  local frames = {}
  local count = NUM_CHAT_WINDOWS or 10
  for i = 1, count do
    for _, suffix in ipairs({ "", "Tab", "ButtonFrame" }) do
      local frame = _G["ChatFrame" .. i .. suffix]
      if frame then table.insert(frames, frame) end
    end
  end
  for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
                          "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
                          "QuickJoinToastButton", "FriendsMicroButton" }) do
    if _G[name] then table.insert(frames, _G[name]) end
  end
  return frames
end

local function SetChatVisible(visible)
  for _, frame in ipairs(GetChatFrames()) do
    frame:SetAlpha(visible and 1 or 0)
  end
end

-- Keep the typing box visible if you open it during combat
local function KeepEditBoxesVisible()
  local count = NUM_CHAT_WINDOWS or 10
  for i = 1, count do
    local editBox = _G["ChatFrame" .. i .. "EditBox"]
    if editBox and editBox.SetIgnoreParentAlpha then
      editBox:SetIgnoreParentAlpha(true)
    end
  end
end

local function UpdateChatVisibility()
  local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
  SetChatVisible(not (db and db.hideChat and inCombat))
end

---------------------------------------------------------------------------
-- Hide menu bar / bag bar (they fade back in when you hover over them)
---------------------------------------------------------------------------
local function AddFrames(frames, names)
  for _, name in ipairs(names) do
    if _G[name] then table.insert(frames, _G[name]) end
  end
end

local function GetMenuFrames()
  local frames = {}
  local container = _G.MicroMenuContainer or _G.MicroMenu
  if container then
    table.insert(frames, container)
  elseif MICRO_BUTTONS then
    AddFrames(frames, MICRO_BUTTONS) -- older clients: just the menu buttons, not the bags
  end
  return frames
end

local function GetBagFrames()
  local frames = {}
  if _G.BagsBar then
    table.insert(frames, _G.BagsBar)
  else
    AddFrames(frames, { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
                        "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot",
                        "KeyRingButton", "BagBarExpandToggle" })
  end
  return frames
end

-- Quest tracker: the frame name depends on the client version
local function GetTrackerFrames()
  local frames = {}
  AddFrames(frames, { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" })
  return frames
end

local hiders = {
  { key = "hideMenu", getFrames = GetMenuFrames },
  { key = "hideBags", getFrames = GetBagFrames },
  { key = "hideTracker", getFrames = GetTrackerFrames },
}

local function UpdateHider(hider)
  local frames = hider.getFrames()
  local hovering = false
  for _, frame in ipairs(frames) do
    if frame:IsVisible() and frame:IsMouseOver() then hovering = true break end
  end
  local alpha = (db and db[hider.key] and not hovering) and 0 or 1
  for _, frame in ipairs(frames) do
    frame:SetAlpha(alpha)
  end
end

local ticker
local function SetupBarHiding()
  local anyOn = false
  for _, hider in ipairs(hiders) do
    if db[hider.key] then anyOn = true end
    UpdateHider(hider)
  end
  if anyOn and not ticker then
    ticker = C_Timer.NewTicker(0.2, function()
      for _, hider in ipairs(hiders) do UpdateHider(hider) end
    end)
  elseif not anyOn and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

---------------------------------------------------------------------------
-- Auto-upgrade spell ranks on action bars
---------------------------------------------------------------------------
local GetSpellNameByID = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
local GetSpellRankText = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
local PickupSpellByID = (C_Spell and C_Spell.PickupSpell) or PickupSpell

local function RankNumber(text)
  return tonumber(text and text:match("(%d+)") or "") or 0
end

-- Highest known rank of every spell in your spellbook: name -> { id, rank }
local function GetHighestRanks()
  local best = {}
  local function consider(id, name, subText)
    if not id or not name then return end
    local rank = RankNumber(subText)
    local current = best[name]
    if not current or rank >= current.rank then
      best[name] = { id = id, rank = rank }
    end
  end

  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      if info then
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
          if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive then
            consider(item.spellID or item.actionID, item.name, item.subName)
          end
        end
      end
    end
  else
    local book = BOOKTYPE_SPELL or "spell"
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, numSpells = GetSpellTabInfo(tab)
      for i = offset + 1, offset + numSpells do
        local kind, id = GetSpellBookItemInfo(i, book)
        if kind == "SPELL" then
          local name, subText = GetSpellBookItemName(i, book)
          consider(id, name, subText)
        end
      end
    end
  end
  return best
end

local rankPending = false
local function UpgradeActionBarRanks()
  if not db or not db.autoRank then return end
  if InCombatLockdown() or GetCursorInfo() then
    rankPending = true -- try again after combat
    return
  end
  rankPending = false

  local best = GetHighestRanks()
  for slot = 1, 180 do
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" and id then
      local name = GetSpellNameByID(id)
      local top = name and best[name]
      if top and top.id ~= id and top.rank > RankNumber(GetSpellRankText(id)) then
        PickupSpellByID(top.id)
        PlaceAction(slot)
        ClearCursor() -- drops the old rank that ends up on the cursor
        print(string.format("|cff33ff99Quinta:|r upgraded %s to rank %d.", name, top.rank))
      end
    end
  end
end

local rankTimer
local function QueueRankUpgrade()
  if rankTimer then return end
  rankTimer = C_Timer.NewTimer(1, function()
    rankTimer = nil
    UpgradeActionBarRanks()
  end)
end

---------------------------------------------------------------------------
-- Settings window (/quinta)
---------------------------------------------------------------------------
local panel

local function CreatePanel()
  panel = CreateFrame("Frame", "QuintaOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  panel:SetSize(300, 340)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetClampedToScreen(true)
  panel:Hide()
  table.insert(UISpecialFrames, "QuintaOptionsFrame") -- Escape closes it

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -18)
  title:SetText("Quinta")

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Scale slider
  local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", 24, -52)

  local slider = CreateFrame("Slider", nil, panel, BackdropTemplateMixin and "BackdropTemplate")
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(230, 17)
  slider:SetPoint("TOPLEFT", 24, -72)
  slider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
  })
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetMinMaxValues(MIN_SCALE, MAX_SCALE)
  slider:SetValueStep(STEP)
  slider:SetObeyStepOnDrag(true)

  local function UpdateLabel(value)
    label:SetText(string.format("UI scale: %.2f", value))
  end

  slider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value / STEP + 0.5) * STEP
    UpdateLabel(value)
    db.scale = value
  end)
  -- Apply when you let go, so the window doesn't jump around while dragging
  slider:SetScript("OnMouseUp", function()
    if InCombatLockdown() then
      print("|cff33ff99Quinta:|r scale will apply after combat.")
    end
    ApplyScale()
  end)

  local low = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
  low:SetText(MIN_SCALE)
  local high = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
  high:SetText(MAX_SCALE)

  -- Hide chat checkbox
  local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", 20, -110)
  local checkText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  checkText:SetPoint("LEFT", check, "RIGHT", 4, 0)
  checkText:SetText("Hide chat in combat")
  check:SetScript("OnClick", function(self)
    db.hideChat = self:GetChecked() and true or false
    UpdateChatVisibility()
  end)

  -- Hide menu bar checkbox
  local menuCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  menuCheck:SetPoint("TOPLEFT", 20, -140)
  local menuText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  menuText:SetPoint("LEFT", menuCheck, "RIGHT", 4, 0)
  menuText:SetText("Hide menu bar (show on mouseover)")
  menuCheck:SetScript("OnClick", function(self)
    db.hideMenu = self:GetChecked() and true or false
    SetupBarHiding()
  end)

  -- Hide bag bar checkbox
  local bagCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  bagCheck:SetPoint("TOPLEFT", 20, -170)
  local bagText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  bagText:SetPoint("LEFT", bagCheck, "RIGHT", 4, 0)
  bagText:SetText("Hide bag bar (show on mouseover)")
  bagCheck:SetScript("OnClick", function(self)
    db.hideBags = self:GetChecked() and true or false
    SetupBarHiding()
  end)

  -- Hide quest tracker checkbox
  local trackerCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  trackerCheck:SetPoint("TOPLEFT", 20, -200)
  local trackerText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  trackerText:SetPoint("LEFT", trackerCheck, "RIGHT", 4, 0)
  trackerText:SetText("Hide quest tracker (show on mouseover)")
  trackerCheck:SetScript("OnClick", function(self)
    db.hideTracker = self:GetChecked() and true or false
    SetupBarHiding()
  end)

  -- Camera distance slider
  local zoomLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  zoomLabel:SetPoint("TOPLEFT", 24, -240)

  local zoomSlider = CreateFrame("Slider", nil, panel, BackdropTemplateMixin and "BackdropTemplate")
  zoomSlider:SetOrientation("HORIZONTAL")
  zoomSlider:SetSize(230, 17)
  zoomSlider:SetPoint("TOPLEFT", 24, -260)
  zoomSlider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
  })
  zoomSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  zoomSlider:SetMinMaxValues(MIN_ZOOM, MAX_ZOOM)
  zoomSlider:SetValueStep(ZOOM_STEP)
  zoomSlider:SetObeyStepOnDrag(true)

  local function UpdateZoomLabel(value)
    zoomLabel:SetText(string.format("Max camera distance: %.1f", value))
  end

  zoomSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value / ZOOM_STEP + 0.5) * ZOOM_STEP
    UpdateZoomLabel(value)
    db.cameraZoom = value
    ApplyCameraZoom(value)
  end)

  local zoomLow = zoomSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  zoomLow:SetPoint("TOPLEFT", zoomSlider, "BOTTOMLEFT", 0, -2)
  zoomLow:SetText(MIN_ZOOM)
  local zoomHigh = zoomSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  zoomHigh:SetPoint("TOPRIGHT", zoomSlider, "BOTTOMRIGHT", 0, -2)
  zoomHigh:SetText(MAX_ZOOM)

  -- Auto-upgrade spell ranks checkbox
  local rankCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  rankCheck:SetPoint("TOPLEFT", 20, -298)
  local rankText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rankText:SetPoint("LEFT", rankCheck, "RIGHT", 4, 0)
  rankText:SetText("Auto-upgrade spell ranks on bars")
  rankCheck:SetScript("OnClick", function(self)
    db.autoRank = self:GetChecked() and true or false
    if db.autoRank then UpgradeActionBarRanks() end
  end)

  panel:SetScript("OnShow", function()
    rankCheck:SetChecked(db.autoRank)
    zoomSlider:SetValue(db.cameraZoom)
    UpdateZoomLabel(db.cameraZoom)
    slider:SetValue(db.scale)
    UpdateLabel(db.scale)
    check:SetChecked(db.hideChat)
    menuCheck:SetChecked(db.hideMenu)
    bagCheck:SetChecked(db.hideBags)
    trackerCheck:SetChecked(db.hideTracker)
  end)
end

SLASH_QUINTA1 = "/quinta"
SlashCmdList.QUINTA = function()
  if not panel then CreatePanel() end
  panel:SetShown(not panel:IsShown())
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat
f:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat
-- Learning spells (event names differ between game versions)
for _, e in ipairs({ "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(self, event, arg1)
  if event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "SPELLS_CHANGED" then
    if db then QueueRankUpgrade() end
    return
  end

  if event == "ADDON_LOADED" then
    if arg1 == ADDON_NAME then
      QuintaDB = QuintaDB or {}
      db = QuintaDB
      for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
      end
    end
    return
  end

  if not db then return end

  if event == "PLAYER_REGEN_DISABLED" then
    if db.hideChat then SetChatVisible(false) end
    return
  elseif event == "PLAYER_REGEN_ENABLED" then
    SetChatVisible(true)
    if rankPending then QueueRankUpgrade() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    KeepEditBoxesVisible()
    UpdateChatVisibility()
    SetupBarHiding()
    ApplyCameraZoom(db.cameraZoom)
    QueueRankUpgrade()
  end

  ApplyScale()
end)
