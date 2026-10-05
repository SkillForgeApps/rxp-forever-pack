"""Draw RestedXP's world-map icons on an overlay frame instead of as WorldMapFrame data-provider pins.

Why (30 Sep 2026, Gaz: "the gamepad UI is still crashing out"; then "I need RXP to keep drawing on the world map"):
taint.log at level 11 (11:07-11:13, Auctionator off) shows the whole failure starts on the WORLD MAP:
  * HereBeDragons-Pins-2.0.lua registers a MapCanvasDataProvider on the WorldMapFrame and makes each RXP icon a
    Blizzard PIN (AcquirePin("HereBeDragonsPinsTemplate") -> OnAcquired -> UseFrameLevelType / SetPosition ...). Every
    map open and every refresh runs those insecure functions inside Blizzard's map code (RefreshAllDataProviders,
    OnHide's secureexecuterange, CalculatePinNudging, ExecuteOnAllPins ...), and Blizzard then reads the tainted pin
    fields (owningMap, pinFrameLevelIndex, insetIndex, nudge*, EnumerateActive, HereBeDragonsPinsTemplate ...).
  * When the map is closed with the controller (B -> SmartNavigation:AttemptClose -> WorldMapFrameCloseButton:MouseUp
    -> WorldMapFrame:Hide) that chain is tainted, so SmartNavigation:SetActiveFrame / SetLastButtonForPanelInfo write
    tainted values (lastButton, currentDirections, activeInfo, first hit 11:12:40.580). Every later gamepad action
    (chat, bags, ...) reads them: FrameControlsManager.focusedFrame, InputBindingManager, SetPreferredGamepadInteractTarget
    -> "[ADDON_ACTION_FORBIDDEN] AddOn 'RXPGuides' ..." and the controller UI stops taking input until /reload.
  * The bag open at 11:07:57 carried NO RXP taint - the map is the source.
Patch: keep every icon RXP draws (same frames, same positions, same tooltips), but parent them to ONE overlay frame
inside the map canvas and place them ourselves. No data provider, no pin pool, no AcquirePin, so Blizzard's map code
never runs an RXP function and never reads an RXP-written value. The overlay is refreshed from hooksecurefunc /
HookScript hooks (they run after Blizzard's function and do not pass taint back to it):
    OnShow, OnMapChanged   -> re-place all icons for the map now showing
    OnCanvasScaleChanged   -> re-scale / re-place (icons keep their on-screen size while you zoom, like real pins)
Public API (AddWorldMapIconMap / AddWorldMapIconWorld / RemoveWorldMapIcon / RemoveAllWorldMapIcons) is unchanged.
The route LINES (map.lua) are separate Buttons in the canvas and are not touched here.
Idempotent; backs up the original next to this script. Re-run after every RXP update. Revert: copy the backup over the
installed libs\\HereBeDragons\\HereBeDragons-Pins-2.0.lua.
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
TAG = "-- RXPForever: world-map icons on an overlay, not data-provider pins (taints the gamepad UI)"

path = os.path.join(ADDONS, "RXPGuides", "libs", "HereBeDragons", "HereBeDragons-Pins-2.0.lua")
src = open(path, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
if TAG in src:
    print("HereBeDragons-Pins-2.0.lua: nothing to patch (already patched?)")
    raise SystemExit
L = src.split(nl)

start = [i for i, l in enumerate(L) if l.strip() == "worldmapPinsPool.parent = WorldMapFrame:GetCanvas()"]
end = [i for i, l in enumerate(L) if l.strip() == "WorldMapFrame:AddDataProvider(worldmapProvider)"]
if len(start) != 1 or len(end) != 1 or end[0] < start[0]:
    raise SystemExit("could not find the world map provider block (start %r, end %r)" % (start, end))
s, e = start[0], end[0]

NEW = r'''%(tag)s
-- Icons are parented to one overlay frame in the map canvas and placed here; nothing is registered with
-- WorldMapFrame (no data provider, no pin pool, no AcquirePin), so Blizzard's map code never runs or reads RXP data.
local canvas = WorldMapFrame:GetCanvas()
local overlay = CreateFrame("Frame", nil, canvas)
overlay:SetAllPoints(canvas)
overlay:SetFrameLevel(canvas:GetFrameLevel() + 100)
local placed = {}   -- icon -> { data = pin data, x = 0-1, y = 0-1 } while it is on the overlay

local function place(icon, data, x, y)
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not w or not h or w == 0 or h == 0 then return end   -- map not opened yet: OnShow re-places everything
    local base = data.baseScale or 1
    local s = base / (canvas:GetScale() or 1)               -- keep the on-screen size while the canvas is zoomed
    if s <= 0 then s = base end
    icon:SetParent(overlay)
    icon:SetScale(s)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", overlay, "TOPLEFT", x * w / s, -y * h / s)
    icon:Show()
    local p = placed[icon]
    if p then p.data, p.x, p.y = data, x, y else placed[icon] = { data = data, x = x, y = y } end
end

local function release(icon)
    icon:Hide()
    icon:SetParent(UIParent)
    icon:ClearAllPoints()
    placed[icon] = nil
end

-- provider base API (same names HereBeDragons calls internally)
function worldmapProvider:RemoveAllData()
    for icon in pairs(placed) do release(icon) end
end

function worldmapProvider:RemovePinByIcon(icon)
    if placed[icon] then release(icon) end
end

function worldmapProvider:RemovePinsByRef(ref)
    local reg = worldmapPinRegistry[ref]
    if not reg then return end
    for icon in pairs(placed) do
        if reg[icon] then release(icon) end
    end
end

function worldmapProvider:RefreshAllData(fromOnShow)
    self:RemoveAllData()

    for icon, data in pairs(worldmapPins) do
        self:HandlePin(icon, data)
    end
end

function worldmapProvider:HandlePin(icon, data)
    local uiMapID = WorldMapFrame:GetMapID()

    -- check for a valid map
    if not uiMapID then return end

    local x, y
    if uiMapID == WORLD_MAP_ID then
        -- should this pin show on the world map?
        if uiMapID ~= data.uiMapID and data.worldMapShowFlag ~= HBD_PINS_WORLDMAP_SHOW_WORLD then return end

        -- translate to the world map
        x, y = HBD:GetAzerothWorldMapCoordinatesFromWorld(data.x, data.y, data.instanceID)
    else
        -- check that it matches the instance
        if not HBD.mapData[uiMapID] or HBD.mapData[uiMapID].instance ~= data.instanceID then return end

        if uiMapID ~= data.uiMapID then
            local mapType = HBD.mapData[uiMapID].mapType
            if not data.uiMapID then
                if mapType == Enum.UIMapType.Continent and data.worldMapShowFlag >= HBD_PINS_WORLDMAP_SHOW_CONTINENT then
                    --pass
                elseif mapType ~= Enum.UIMapType.Zone and mapType ~= Enum.UIMapType.Dungeon and mapType ~= Enum.UIMapType.Micro then
                    -- fail
                    return
                end
            else
                local show = false
                local parentMapID = HBD.mapData[data.uiMapID].parent
                while parentMapID and HBD.mapData[parentMapID] do
                    if parentMapID == uiMapID then
                        local parentMapType = HBD.mapData[parentMapID].mapType
                        -- show on any parent zones if they are normal zones
                        if data.worldMapShowFlag >= HBD_PINS_WORLDMAP_SHOW_PARENT and
                            (parentMapType == Enum.UIMapType.Zone or parentMapType == Enum.UIMapType.Dungeon or parentMapType == Enum.UIMapType.Micro) then
                            show = true
                        -- show on the continent
                        elseif data.worldMapShowFlag >= HBD_PINS_WORLDMAP_SHOW_CONTINENT and
                            parentMapType == Enum.UIMapType.Continent then
                            show = true
                        end
                        break
                        -- worldmap is handled above already
                    else
                        parentMapID = HBD.mapData[parentMapID].parent
                    end
                end

                if not show then return end
            end
        end

        -- translate coordinates
        x, y = HBD:GetZoneCoordinatesFromWorld(data.x, data.y, uiMapID)
    end
    if x and y then
        place(icon, data, x, y)
    end
end

-- hooks: run after Blizzard's own function and do not pass taint back to it
local function refreshOverlay()
    worldmapProvider:RefreshAllData()
end
local function rescaleOverlay()
    for icon, p in pairs(placed) do place(icon, p.data, p.x, p.y) end
end
pcall(function()
    WorldMapFrame:HookScript("OnShow", refreshOverlay)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", refreshOverlay) end
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", rescaleOverlay) end
end)''' % {"tag": TAG}

L[s:e + 1] = NEW.split("\n")
src2 = nl.join(L)

# remember each icon's own scale (RXP's render() sets it) so place() can counter the canvas zoom
old = "    t.frameLevelType = frameLevel\n".replace("\n", nl)
new = "    t.frameLevelType = frameLevel\n    t.baseScale = icon:GetScale()   -- RXPForever overlay: the icon's own scale, before we counter-scale it\n".replace("\n", nl)
if src2.count(old) != 2:
    raise SystemExit("expected 2 'frameLevelType = frameLevel' lines (AddWorldMapIconWorld/Map), found %d" % src2.count(old))
src2 = src2.replace(old, new)

backup = os.path.join(HERE, "orig-HereBeDragons-Pins-before-overlay.lua")
if not os.path.exists(backup):
    shutil.copy2(path, backup)
open(path, "w", encoding="utf-8", newline="").write(src2)
print("HereBeDragons-Pins-2.0.lua: world-map icons now on an overlay; backup %s" % backup)
