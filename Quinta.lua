local ADDON_NAME = ...

-- Default settings (saved per account in QuintaDB)
local DEFAULTS = {
  scale = 0.5,
  hideChat = true,
  hideChatAlways = false,
  hideMenu = false,
  hideBags = false,
  hideTracker = false,
  cameraZoom = 2.6,
  autoRank = true,
  showMarkers = false,
  moveLoot = true,
  deathAlert = true,
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

local inCombat = false
local function ChatHidden()
  if not db then return false end
  return db.hideChatAlways or (db.hideChat and (inCombat or InCombatLockdown() or UnitAffectingCombat("player")))
end

local function UpdateChatVisibility()
  SetChatVisible(not ChatHidden())
end

-- The game fades chat tabs back in on mouseover: keep them hidden
local chatHooked = false
local function HookChatFading()
  if chatHooked then return end
  chatHooked = true
  for _, name in ipairs({ "FCF_FadeInChatFrame", "FCF_FadeOutChatFrame", "FCFTab_UpdateAlpha" }) do
    if _G[name] then
      hooksecurefunc(name, function()
        if ChatHidden() then SetChatVisible(false) end
      end)
    end
  end
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

-- Every action slot worth checking: a wide fixed range, plus the slot of
-- every action button that exists (covers bars like the Gamepad ones that
-- may use slots outside the usual range).
local MAX_ACTION_SLOT = 1000
local function GetActionSlots()
  local seen, slots = {}, {}
  local function add(slot)
    if type(slot) == "number" and slot > 0 and not seen[slot] then
      seen[slot] = true
      slots[#slots + 1] = slot
    end
  end
  for slot = 1, MAX_ACTION_SLOT do add(slot) end
  local frame = EnumerateFrames()
  while frame do
    if not frame:IsForbidden() then
      local slot = frame.action
      if type(slot) ~= "number" and frame.GetAttribute then
        local ok, attr = pcall(frame.GetAttribute, frame, "action")
        if ok then slot = tonumber(attr) end
      end
      add(slot)
    end
    frame = EnumerateFrames(frame)
  end
  return slots
end

local rankPending, rankPendingManual = false, false
-- manual = run from the button or /quinta ranks: ignores the auto setting
-- and reports what it did
local function UpgradeActionBarRanks(manual)
  if not db then return end
  if not manual and not db.autoRank then return end
  if InCombatLockdown() or GetCursorInfo() then
    rankPending = true -- try again after combat
    if manual then
      rankPendingManual = true
      print("|cff33ff99Quinta:|r will update spell ranks after combat.")
    end
    return
  end
  rankPending, rankPendingManual = false, false

  local best = GetHighestRanks()
  local count = 0
  for _, slot in ipairs(GetActionSlots()) do
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" and id then
      local name = GetSpellNameByID(id)
      local top = name and best[name]
      if top and top.id ~= id and top.rank > RankNumber(GetSpellRankText(id)) then
        PickupSpellByID(top.id)
        PlaceAction(slot)
        ClearCursor() -- drops the old rank that ends up on the cursor
        count = count + 1
        print(string.format("|cff33ff99Quinta:|r upgraded %s to rank %d.", name, top.rank))
      end
    end
  end

  if manual then
    if count == 0 then
      print("|cff33ff99Quinta:|r all spells on your bars are already at their highest rank.")
    else
      print(string.format("|cff33ff99Quinta:|r updated %d spell%s to the highest rank.", count, count == 1 and "" or "s"))
    end
  end
end

local rankTimer
local function QueueRankUpgrade()
  if rankTimer then return end
  rankTimer = C_Timer.NewTimer(1, function()
    rankTimer = nil
    UpgradeActionBarRanks(rankPendingManual)
  end)
end

---------------------------------------------------------------------------
-- Raid marker panel: click a mark to put it on your target (click the same
-- mark again, or X, to remove it). Drag it anywhere.
---------------------------------------------------------------------------
local MARK_SIZE = 24
local markers

local function CreateMarkers()
  markers = CreateFrame("Frame", "QuintaMarkers", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  markers:SetSize(5 * (MARK_SIZE + 2) + 6, 2 * (MARK_SIZE + 2) + 6) -- 5 on top, 4 below
  markers:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  markers:SetBackdropColor(0, 0, 0, 0.5)
  markers:SetBackdropBorderColor(0, 0, 0, 0.8)
  markers:SetMovable(true)
  markers:SetClampedToScreen(true)
  markers:EnableMouse(true)
  markers:RegisterForDrag("LeftButton")
  local function StartDrag() if not InCombatLockdown() then markers:StartMoving() end end -- not allowed in combat
  local function StopDrag()
    markers:StopMovingOrSizing()
    local point, _, relPoint, x, y = markers:GetPoint()
    db.markersPos = { point, relPoint, x, y }
  end
  markers:SetScript("OnDragStart", StartDrag)
  markers:SetScript("OnDragStop", StopDrag)

  local p = db.markersPos
  if p then markers:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else markers:SetPoint("TOP", 0, -120) end

  for i = 1, 9 do
    local mark = i <= 8 and i or 0 -- the 9th button removes the mark
    -- Setting marks is protected on this client, so each mark is a secure
    -- button that does it for us: "toggle" puts the mark on your target, or
    -- removes it if it already has that mark; "clear" removes any mark.
    local b = CreateFrame("Button", nil, markers, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "raidtarget")
    b:SetAttribute("unit", "target")
    b:SetAttribute("action", mark > 0 and "toggle" or "clear")
    if mark > 0 then b:SetAttribute("marker", mark) end
    b:SetSize(MARK_SIZE, MARK_SIZE)
    -- top row: marks 1-5; bottom row: 6-8 and X, centered under the top row
    local row, col = (i <= 5) and 0 or 1, (i <= 5) and (i - 1) or (i - 6)
    local x = 4 + col * (MARK_SIZE + 2) + row * (MARK_SIZE + 2) / 2
    b:SetPoint("TOPLEFT", x, -4 - row * (MARK_SIZE + 2))
    if mark > 0 then
      b:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mark)
    else
      b:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- dragging a mark moves the whole panel
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", StartDrag)
    b:SetScript("OnDragStop", StopDrag)
  end
end

local markersPending = false
local function UpdateMarkers()
  if not db then return end
  -- secure buttons can't be created, shown or hidden in combat: do it after
  if InCombatLockdown() then markersPending = true return end
  markersPending = false
  if db.showMarkers and not markers then CreateMarkers() end
  if not markers then return end
  if db.showMarkers then
    -- secure state driver: shows/hides with your target, even in combat
    RegisterStateDriver(markers, "visibility", "[@target,exists] show; hide")
  else
    UnregisterStateDriver(markers, "visibility")
    markers:Hide()
  end
end

---------------------------------------------------------------------------
-- Movable loot roll window (Need / Greed / Pass): Shift-drag a roll to move
-- it, or /quinta loot to show a box you can place without a roll up.
-- The rolls hang from our own anchor, so Blizzard moving them back is undone.
---------------------------------------------------------------------------
local lootAnchor, lootHooked, lootPlacing
local LOOT_DEFAULT = { "BOTTOM", "BOTTOM", 0, 280 }

local function SaveLootPos()
  local point, _, relPoint, x, y = lootAnchor:GetPoint()
  db.lootPos = { point, relPoint, x, y }
end

local function PlaceLootAnchor()
  local p = db.lootPos or LOOT_DEFAULT
  lootAnchor:ClearAllPoints()
  lootAnchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- The frame Blizzard stacks the rolls in (name depends on the client)
local function LootTarget()
  return _G.GroupLootContainer or _G.GroupLootFrame1
end

local anchoring = false
local function AnchorLoot(frame)
  if anchoring or not db or not db.moveLoot or not lootAnchor or not frame then return end
  if not db.lootPos and not lootPlacing then return end -- not moved yet: Blizzard's spot
  anchoring = true
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", lootAnchor, "BOTTOM", 0, 0) -- more rolls stack upward
  anchoring = false
end

local function StartLootDrag()
  if not db.moveLoot or not (lootPlacing or IsShiftKeyDown()) then return end
  local target = LootTarget()
  if not db.lootPos and not lootPlacing and target and target:GetBottom() then
    -- first move: start the anchor where Blizzard put the rolls
    lootAnchor:ClearAllPoints()
    lootAnchor:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", (target:GetCenter()), target:GetBottom())
    SaveLootPos()
    AnchorLoot(target)
  end
  lootAnchor:StartMoving()
end
local function StopLootDrag()
  lootAnchor:StopMovingOrSizing()
  SaveLootPos()
  AnchorLoot(LootTarget())
end

-- Let a roll frame be Shift-dragged (it moves the anchor, the rolls follow)
local function MakeRollDraggable(roll)
  if not roll or roll.quintaDrag then return end
  roll.quintaDrag = true
  roll:EnableMouse(true)
  roll:RegisterForDrag("LeftButton")
  roll:HookScript("OnDragStart", StartLootDrag)
  roll:HookScript("OnDragStop", StopLootDrag)
end

local function SetupLootMover()
  if lootHooked then return end
  local target = LootTarget()
  if not target then return end
  lootHooked = true

  lootAnchor = CreateFrame("Frame", "QuintaLootAnchor", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  lootAnchor:SetSize(250, 70)
  lootAnchor:SetMovable(true)
  lootAnchor:SetClampedToScreen(true)
  lootAnchor:RegisterForDrag("LeftButton")
  lootAnchor:SetScript("OnDragStart", StartLootDrag)
  lootAnchor:SetScript("OnDragStop", StopLootDrag)
  lootAnchor:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  lootAnchor:EnableMouse(false)
  local text = lootAnchor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("CENTER")
  text:SetText("Loot rolls appear here\nDrag me, then /quinta loot")
  lootAnchor.text = text
  lootAnchor:SetBackdropColor(0, 0, 0, 0) -- invisible until /quinta loot
  lootAnchor:SetBackdropBorderColor(0, 0, 0, 0)
  text:Hide()
  PlaceLootAnchor()

  -- Blizzard re-positions the rolls whenever it lays out the screen: put them back
  hooksecurefunc(target, "SetPoint", AnchorLoot)
  for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
    MakeRollDraggable(_G["GroupLootFrame" .. i])
  end
  if _G.GroupLootContainer_AddFrame then -- newer clients create roll frames as needed
    hooksecurefunc("GroupLootContainer_AddFrame", function(_, roll) MakeRollDraggable(roll) end)
  end
  AnchorLoot(target)
end

-- /quinta loot: show the anchor box so it can be placed without a roll up
local function ToggleLootPlacing()
  if not db.moveLoot then
    print("|cff33ff99Quinta:|r turn on \"Move loot roll window\" in /quinta first.")
    return
  end
  SetupLootMover()
  if not lootAnchor then return end
  lootPlacing = not lootPlacing
  lootAnchor:EnableMouse(lootPlacing)
  lootAnchor:SetBackdropColor(0, 0.6, 0.3, lootPlacing and 0.4 or 0)
  lootAnchor:SetBackdropBorderColor(0.2, 1, 0.6, lootPlacing and 0.9 or 0)
  lootAnchor.text:SetShown(lootPlacing)
  if lootPlacing then AnchorLoot(LootTarget()) else SaveLootPos() end
  print(lootPlacing and "|cff33ff99Quinta:|r drag the green box, then type /quinta loot again to lock it."
                     or "|cff33ff99Quinta:|r loot roll position saved.")
end

---------------------------------------------------------------------------
-- Shadow Word: Death kill alert (like a WeakAura): a big Shadow Word: Death
-- icon pops up when your target's health is at or below the spell's damage
-- (the lowest number in its tooltip, so it kills even without a crit).
-- /quinta swd shows it so you can drag it somewhere else.
--
-- In WoW Forever the target's health is secret in combat: addon code can't
-- compare it with anything. A StatusBar can, so we let it: max = health,
-- value = damage, so its fill only reaches the right end when damage >= health.
-- The bar is very long and only its last icon-width is visible (clipped), with
-- the icon riding the fill's end, so the icon shows only when it kills.
---------------------------------------------------------------------------
local GetSpellDesc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
local GetSpellIcon = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
local ALERT_SIZE = 56
local ALERT_BAR_LENGTH = 20000
local ALERT_DEFAULT = { "CENTER", "CENTER", 0, -120 }

-- Highest rank of Shadow Word: Death you know (nil if you don't have it)
local function DeathSpell()
  local best = GetHighestRanks()
  local top = best["Shadow Word: Death"] or best[GetSpellNameByID(32379) or ""]
  return top and top.id
end

-- Damage per spell ID, read from the tooltip ("inflicts 338 to 358 ..." -> 338)
local deathDamage = {}
local function DeathDamage(id)
  if deathDamage[id] == nil then
    local desc = GetSpellDesc and GetSpellDesc(id)
    local number = desc and desc:match("(%d[%d,%.]*)")
    deathDamage[id] = number and tonumber((number:gsub("%D", ""))) or nil
  end
  return deathDamage[id]
end

local alert, alertBar, alertIcon, alertPlacing
local deathSpell -- refreshed when your spells change

local function SaveAlertPos()
  local point, _, relPoint, x, y = alert:GetPoint()
  db.deathAlertPos = { point, relPoint, x, y }
end

local function CreateAlert()
  -- the part you drag (only takes the mouse while placing it)
  alert = CreateFrame("Frame", "QuintaDeathAlert", UIParent)
  alert:SetSize(ALERT_SIZE, ALERT_SIZE)
  alert:SetFrameStrata("HIGH")
  alert:SetMovable(true)
  alert:SetClampedToScreen(true)
  alert:RegisterForDrag("LeftButton")
  alert:SetScript("OnDragStart", alert.StartMoving)
  alert:SetScript("OnDragStop", function() alert:StopMovingOrSizing() SaveAlertPos() end)
  alert:EnableMouse(false)
  local p = db.deathAlertPos or ALERT_DEFAULT
  alert:SetPoint(p[1], UIParent, p[2], p[3], p[4])

  -- the window: only the end of the long bar shows through it
  local window = CreateFrame("Frame", nil, alert)
  window:SetAllPoints()
  window:SetClipsChildren(true)

  alertBar = CreateFrame("StatusBar", nil, window)
  alertBar:SetSize(ALERT_BAR_LENGTH, ALERT_SIZE)
  alertBar:SetPoint("RIGHT", window, "RIGHT")
  alertBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  alertBar:SetStatusBarColor(0, 0, 0, 0)
  alertBar:SetMinMaxValues(0, 1)
  alertBar:SetValue(0)

  -- the icon rides the end of the fill
  alertIcon = CreateFrame("Frame", nil, alertBar)
  alertIcon:SetSize(ALERT_SIZE, ALERT_SIZE)
  alertIcon:SetPoint("RIGHT", alertBar:GetStatusBarTexture(), "RIGHT")
  local border = alertIcon:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints()
  border:SetColorTexture(0.75, 0.35, 1, 1) -- shadow purple
  local icon = alertIcon:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 2, -2)
  icon:SetPoint("BOTTOMRIGHT", -2, 2)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  alertIcon.icon = icon
  local text = alertIcon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  text:SetPoint("BOTTOM", 0, 3)
  text:SetText("KILL")

  local pulse = alertIcon:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.5)
  fade:SetDuration(0.35)
  pulse:Play()

  -- hint shown while placing it
  local hint = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hint:SetPoint("TOP", alert, "BOTTOM", 0, -4)
  hint:SetText("Drag me, then /quinta swd")
  hint:Hide()
  alert.hint = hint
  alert:Hide()
end

local function SetAlertIcon()
  alertIcon.icon:SetTexture((deathSpell and GetSpellIcon(deathSpell)) or GetSpellIcon(32379)
    or "Interface\\Icons\\Spell_Shadow_DemonicFortitude")
end

-- A value addon code may use, or nil if the call failed or the value is secret
local function Plain(ok, value)
  if not ok or (issecretvalue and issecretvalue(value)) then return nil end
  return value
end

-- Cooldown: read from the game when it lets us; in combat Forever can hide it,
-- so we also time it ourselves from the moment you cast the spell.
local deathReadyAt = 0       -- GetTime() when our own timer says it's ready
local deathCooldownLength = 12 -- seconds; replaced by the real length when the game shows it

local function DeathCooldownFromGame()
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = Plain(pcall(C_Spell.GetSpellCooldown, deathSpell))
    if type(info) == "table" then
      start, duration = Plain(true, info.startTime), Plain(true, info.duration)
    end
  elseif GetSpellCooldown then
    local ok, s, d = pcall(GetSpellCooldown, deathSpell)
    start, duration = Plain(ok, s), Plain(ok, d)
  end
  return start, duration
end

local function DeathOnCooldown()
  local start, duration = DeathCooldownFromGame()
  if start and duration then
    if duration <= 1.5 then return false end -- ready (or only the global cooldown)
    deathCooldownLength = duration
    return start + duration - GetTime() > 0.1
  end
  return GetTime() < deathReadyAt -- hidden: use our own timer
end

local function OnDeathCast(spellID)
  spellID = Plain(true, spellID)
  if spellID and deathSpell and GetSpellNameByID(spellID) == GetSpellNameByID(deathSpell) then
    deathReadyAt = GetTime() + deathCooldownLength
  end
end

local function UpdateDeathAlert()
  if alertPlacing then return end
  local damage = db.deathAlert and deathSpell and DeathDamage(deathSpell)
  -- these can be secret too: only a plain "dead" or "can't attack" hides it
  local dead = Plain(pcall(UnitIsDeadOrGhost, "target"))
  local attackable = Plain(pcall(UnitCanAttack, "player", "target"))
  if not (damage and UnitExists("target")) or dead == true or attackable == false or DeathOnCooldown() then
    if alert then alert:Hide() end
    return
  end
  if not alert then CreateAlert() end
  -- the bar compares for us: full (icon visible) only when damage >= health
  local fed = pcall(function()
    alertBar:SetMinMaxValues(0, UnitHealth("target"))
    alertBar:SetValue(damage)
  end)
  if not fed then alert:Hide() return end
  SetAlertIcon()
  alert:Show()
end

-- /quinta swd: show the icon so it can be dragged, again to lock it
local function ToggleAlertPlacing()
  if not alert then CreateAlert() end
  alertPlacing = not alertPlacing
  alert:EnableMouse(alertPlacing)
  alert.hint:SetShown(alertPlacing)
  if alertPlacing then
    alertBar:SetMinMaxValues(0, 1)
    alertBar:SetValue(1) -- full: icon visible
    SetAlertIcon()
    alert:Show()
  else
    SaveAlertPos()
    alert:Hide()
    print("|cff33ff99Quinta:|r Shadow Word: Death alert position saved.")
    UpdateDeathAlert()
  end
end

local deathWatcher
local function SetupDeathAlert()
  if deathWatcher or select(2, UnitClass("player")) ~= "PRIEST" then return end
  deathSpell = DeathSpell()
  deathWatcher = CreateFrame("Frame")
  -- the cooldown length from the game's spell data, if it gives a plain number
  local ok, ms = pcall(GetSpellBaseCooldown or function() end, deathSpell or 32379)
  ms = Plain(ok, ms)
  if type(ms) == "number" and ms > 1500 then deathCooldownLength = ms / 1000 end
  deathWatcher:RegisterEvent("SPELLS_CHANGED")
  pcall(deathWatcher.RegisterUnitEvent, deathWatcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
  deathWatcher:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      OnDeathCast(spellID)
      return
    end
    deathSpell = DeathSpell() -- new rank or more spell power
    wipe(deathDamage)
  end)
  -- check 10 times a second, like a WeakAura does
  local elapsed = 0
  deathWatcher:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    UpdateDeathAlert()
  end)
end

---------------------------------------------------------------------------
-- Settings window (/quinta)
---------------------------------------------------------------------------
local panel

local function CreatePanel()
  panel = CreateFrame("Frame", "QuintaOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  panel:SetSize(300, 490)
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

  -- Hide chat in combat checkbox (greyed out while chat is always hidden)
  local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", 20, -140)
  local checkText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  checkText:SetPoint("LEFT", check, "RIGHT", 4, 0)
  checkText:SetText("Hide chat in combat")
  check:SetScript("OnClick", function(self)
    db.hideChat = self:GetChecked() and true or false
    UpdateChatVisibility()
  end)

  local function UpdateCombatCheck()
    if db.hideChatAlways then
      check:Disable()
      checkText:SetFontObject("GameFontDisable")
    else
      check:Enable()
      checkText:SetFontObject("GameFontHighlight")
    end
  end

  -- Hide chat always checkbox
  local alwaysCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  alwaysCheck:SetPoint("TOPLEFT", 20, -110)
  local alwaysText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  alwaysText:SetPoint("LEFT", alwaysCheck, "RIGHT", 4, 0)
  alwaysText:SetText("Hide chat")
  alwaysCheck:SetScript("OnClick", function(self)
    db.hideChatAlways = self:GetChecked() and true or false
    UpdateCombatCheck()
    UpdateChatVisibility()
  end)

  -- Hide menu bar checkbox
  local menuCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  menuCheck:SetPoint("TOPLEFT", 20, -170)
  local menuText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  menuText:SetPoint("LEFT", menuCheck, "RIGHT", 4, 0)
  menuText:SetText("Hide menu bar (show on mouseover)")
  menuCheck:SetScript("OnClick", function(self)
    db.hideMenu = self:GetChecked() and true or false
    SetupBarHiding()
  end)

  -- Hide bag bar checkbox
  local bagCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  bagCheck:SetPoint("TOPLEFT", 20, -200)
  local bagText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  bagText:SetPoint("LEFT", bagCheck, "RIGHT", 4, 0)
  bagText:SetText("Hide bag bar (show on mouseover)")
  bagCheck:SetScript("OnClick", function(self)
    db.hideBags = self:GetChecked() and true or false
    SetupBarHiding()
  end)

  -- Hide quest tracker checkbox
  local trackerCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  trackerCheck:SetPoint("TOPLEFT", 20, -230)
  local trackerText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  trackerText:SetPoint("LEFT", trackerCheck, "RIGHT", 4, 0)
  trackerText:SetText("Hide quest tracker (show on mouseover)")
  trackerCheck:SetScript("OnClick", function(self)
    db.hideTracker = self:GetChecked() and true or false
    SetupBarHiding()
  end)

  -- Camera distance slider
  local zoomLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  zoomLabel:SetPoint("TOPLEFT", 24, -270)

  local zoomSlider = CreateFrame("Slider", nil, panel, BackdropTemplateMixin and "BackdropTemplate")
  zoomSlider:SetOrientation("HORIZONTAL")
  zoomSlider:SetSize(230, 17)
  zoomSlider:SetPoint("TOPLEFT", 24, -290)
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
  rankCheck:SetPoint("TOPLEFT", 20, -328)
  local rankText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rankText:SetPoint("LEFT", rankCheck, "RIGHT", 4, 0)
  rankText:SetText("Auto-upgrade spell ranks on bars")
  rankCheck:SetScript("OnClick", function(self)
    db.autoRank = self:GetChecked() and true or false
    if db.autoRank then UpgradeActionBarRanks() end
  end)

  -- Update ranks now button (e.g. after learning spells on another computer)
  local rankButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  rankButton:SetSize(150, 22)
  rankButton:SetPoint("TOPLEFT", rankCheck, "BOTTOMLEFT", 30, -2)
  rankButton:SetText("Update ranks now")
  rankButton:SetScript("OnClick", function() UpgradeActionBarRanks(true) end)

  -- Raid marker panel checkbox
  local markCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  markCheck:SetPoint("TOPLEFT", 20, -392)
  local markText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  markText:SetPoint("LEFT", markCheck, "RIGHT", 4, 0)
  markText:SetText("Show raid marker panel")
  markCheck:SetScript("OnClick", function(self)
    db.showMarkers = self:GetChecked() and true or false
    UpdateMarkers()
  end)

  -- Movable loot roll window checkbox
  local lootCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  lootCheck:SetPoint("TOPLEFT", 20, -422)
  local lootText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lootText:SetPoint("LEFT", lootCheck, "RIGHT", 4, 0)
  lootText:SetText("Move loot roll window (Shift-drag)")
  lootCheck:SetScript("OnClick", function(self)
    db.moveLoot = self:GetChecked() and true or false
    if db.moveLoot then
      SetupLootMover()
      AnchorLoot(LootTarget())
    else
      if lootPlacing then ToggleLootPlacing() end
      print("|cff33ff99Quinta:|r /reload to put the loot roll window back in its usual spot.")
    end
  end)

  -- Shadow Word: Death alert checkbox
  local deathCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  deathCheck:SetPoint("TOPLEFT", 20, -452)
  local deathText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  deathText:SetPoint("LEFT", deathCheck, "RIGHT", 4, 0)
  deathText:SetText("Shadow Word: Death kill alert")
  deathCheck:SetScript("OnClick", function(self)
    db.deathAlert = self:GetChecked() and true or false
    UpdateDeathAlert()
  end)

  panel:SetScript("OnShow", function()
    deathCheck:SetChecked(db.deathAlert)
    lootCheck:SetChecked(db.moveLoot)
    markCheck:SetChecked(db.showMarkers)
    rankCheck:SetChecked(db.autoRank)
    zoomSlider:SetValue(db.cameraZoom)
    UpdateZoomLabel(db.cameraZoom)
    slider:SetValue(db.scale)
    UpdateLabel(db.scale)
    check:SetChecked(db.hideChat)
    alwaysCheck:SetChecked(db.hideChatAlways)
    UpdateCombatCheck()
    menuCheck:SetChecked(db.hideMenu)
    bagCheck:SetChecked(db.hideBags)
    trackerCheck:SetChecked(db.hideTracker)
  end)
end

SLASH_QUINTA1 = "/quinta"
SlashCmdList.QUINTA = function(msg)
  -- /quinta loot: place the loot roll window; /quinta loot reset: back to default
  local lootCmd = (msg or ""):lower():match("^loot%s*(%a*)")
  if (msg or ""):lower():match("^%s*swd") then ToggleAlertPlacing() return end
  if (msg or ""):lower():match("^%s*ranks?%s*$") then UpgradeActionBarRanks(true) return end
  if lootCmd then
    if lootCmd == "reset" then
      db.lootPos = nil
      if lootAnchor then PlaceLootAnchor() end
      print("|cff33ff99Quinta:|r loot roll window back to its default spot.")
    else
      ToggleLootPlacing()
    end
    return
  end
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
      db.playerBorder, db.borderNudge, db.deathGlow = nil, nil, nil -- removed features
    end
    return
  end

  if not db then return end

  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    UpdateChatVisibility()
    return
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    SetChatVisible(not db.hideChatAlways)
    if rankPending then QueueRankUpgrade() end
    if markersPending then UpdateMarkers() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    KeepEditBoxesVisible()
    HookChatFading()
    UpdateMarkers()
    if db.moveLoot then SetupLootMover() end
    UpdateChatVisibility()
    SetupBarHiding()
    ApplyCameraZoom(db.cameraZoom)
    QueueRankUpgrade()
    SetupDeathAlert()
  end

  ApplyScale()
end)
