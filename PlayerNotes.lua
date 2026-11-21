-- PlayerNotes: rate players with an icon + short note, get reminded when you group with them again.
local ADDON = ...
local PREFIX = "|cff33ccffPlayerNotes|r: "

---------------------------------------------------------------------------
-- Ratings
---------------------------------------------------------------------------
local RATINGS = {
    [1]  = { label = "Positive", icon = "Interface\\RaidFrame\\ReadyCheck-Ready",    color = "|cff40ff40" },
    [0]  = { label = "Neutral",  icon = "Interface\\RaidFrame\\ReadyCheck-Waiting",  color = "|cffffd100" },
    [-1] = { label = "Negative", icon = "Interface\\RaidFrame\\ReadyCheck-NotReady", color = "|cffff4040" },
}
local ORDER = { 1, 0, -1 }
local MAX_NOTE = 150
local ADDON_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local function Icon(r, size)
    return "|T" .. RATINGS[r].icon .. ":" .. (size or 14) .. "|t"
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Midnight (12.x) can hand addons "secret" values in some contexts; never use them as keys.
local function IsSecret(v)
    return issecretvalue and v ~= nil and issecretvalue(v)
end

---------------------------------------------------------------------------
-- Name handling: every player is stored under a lowercase "name-realm" key
---------------------------------------------------------------------------
local function NormRealm(realm)
    if not realm or realm == "" then
        realm = GetNormalizedRealmName() or GetRealmName() or ""
    end
    return (realm:gsub("[%s%-]", ""))
end

local function MakeKey(name, realm)
    local r = NormRealm(realm)
    return strlower(name .. "-" .. r), name .. "-" .. r
end

local function UnitKey(unit)
    if not unit or IsSecret(unit) or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local name, realm = UnitName(unit)
    if not name or IsSecret(name) or IsSecret(realm) or name == UNKNOWNOBJECT or name == "" then return end
    return MakeKey(name, realm)
end

local function KeyFromText(text, server)
    if not text or IsSecret(text) then return end
    text = strtrim(text)
    if text == "" then return end
    local name, realm = text:match("^([^%-]+)%-(.+)$")
    name = name or text
    realm = realm or server
    return MakeKey(name, realm)
end

local function ColorName(display, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then
        return "|c" .. c.colorStr .. display .. "|r"
    end
    return display
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function GetEntry(key)
    return PlayerNotesDB.players[key]
end

local function SetEntry(key, display, rating, note)
    local e = PlayerNotesDB.players[key] or {}
    e.name = e.name or display
    e.rating = rating
    e.note = strtrim(note or ""):sub(1, MAX_NOTE)
    e.updated = time()
    PlayerNotesDB.players[key] = e
end

local function DeleteEntry(key)
    PlayerNotesDB.players[key] = nil
end

local function SafeVal(v)
    if IsSecret(v) then return nil end
    return v
end

-- Store/refresh level, class, race, guild, last seen. Creates a record only when
-- create is true (grouping with "track everyone" on); otherwise updates existing ones.
local function RecordUnit(unit, countGroup, create)
    local key, display = UnitKey(unit)
    if not key then return end
    local e = PlayerNotesDB.players[key]
    if not e then
        if not create then return end
        e = { name = display }
        PlayerNotesDB.players[key] = e
    end
    local lvl = SafeVal(UnitLevel(unit))
    if lvl and lvl > 0 then e.level = lvl end
    local className, classFile = UnitClass(unit)
    className, classFile = SafeVal(className), SafeVal(classFile)
    if classFile then e.className, e.classFile = className, classFile end
    local race = SafeVal(UnitRace(unit))
    if race then e.race = race end
    local guild = SafeVal(GetGuildInfo(unit))
    if guild and guild ~= "" then e.guild = guild end
    e.lastSeen = time()
    local zone = SafeVal(GetRealZoneText())
    if zone and zone ~= "" then e.lastZone = zone end
    if countGroup then e.timesGrouped = (e.timesGrouped or 0) + 1 end
end

local function InfoText(e)
    local parts = {}
    if e.level then parts[#parts + 1] = "Level " .. e.level end
    if e.race then parts[#parts + 1] = e.race end
    if e.className then parts[#parts + 1] = e.className end
    local txt = table.concat(parts, " ")
    if e.guild then txt = txt .. (txt ~= "" and " " or "") .. "<" .. e.guild .. ">" end
    return txt
end

local function SeenText(e)
    local parts = {}
    if e.timesGrouped and e.timesGrouped > 0 then
        parts[#parts + 1] = "Grouped " .. e.timesGrouped .. "x"
    end
    if e.lastSeen then
        parts[#parts + 1] = "last seen " .. date("%d %b %Y", e.lastSeen) .. (e.lastZone and (" in " .. e.lastZone) or "")
    end
    return table.concat(parts, ", ")
end

-- Dungeon history: newest first, last MAX_RUNS kept per player.
local MAX_RUNS = 15

local function AddRun(key, r)
    local e = r and PlayerNotesDB.players[key]
    if not e then return end
    e.runs = e.runs or {}
    local last = e.runs[1]
    -- same dungeon within 2 hours = same run (e.g. rated mid-run, then finished)
    if last and last.d == r.d and math.abs(last.t - r.t) < 7200 then
        last.bosses = math.max(last.bosses or 0, r.bosses or 0)
        return
    end
    table.insert(e.runs, 1, { d = r.d, t = r.t, bosses = r.bosses })
    while #e.runs > MAX_RUNS do table.remove(e.runs) end
end

local function RunLine(r)
    local txt = r.d .. " |cff888888" .. date("%d %b %Y", r.t)
    if r.bosses and r.bosses > 0 then txt = txt .. ", " .. r.bosses .. " boss" .. (r.bosses > 1 and "es" or "") end
    return txt .. "|r"
end

local function LastRunText(e)
    local r = e.runs and e.runs[1]
    if not r then return "" end
    local count = #e.runs
    return "Last run: " .. RunLine(r) .. (count > 1 and (" |cff888888(" .. count .. " runs together)|r") or "")
end

local function EntryText(e)
    if not e.rating then
        return "|cff888888No rating yet|r"
    end
    local rt = RATINGS[e.rating]
    local txt = Icon(e.rating) .. " " .. rt.color .. rt.label .. "|r"
    if e.note and e.note ~= "" then
        txt = txt .. ": |cffffffff" .. e.note .. "|r"
    end
    if e.updated then
        txt = txt .. " |cff888888(" .. date("%d %b %Y", e.updated) .. ")|r"
    end
    return txt
end

---------------------------------------------------------------------------
-- Group helpers
---------------------------------------------------------------------------
local function GetGroupMembers()
    local list = {}
    local prefix, n
    if IsInRaid() then
        prefix, n = "raid", GetNumGroupMembers()
    else
        prefix, n = "party", GetNumSubgroupMembers()
    end
    for i = 1, n do
        local unit = prefix .. i
        if not UnitIsUnit(unit, "player") then
            local key, display = UnitKey(unit)
            if key then
                local _, class = UnitClass(unit)
                list[#list + 1] = { key = key, display = display, class = class, unit = unit }
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- UI: icon picker (shared by editor + feedback window)
---------------------------------------------------------------------------
local function CreateRatingPicker(parent, size)
    local picker = { buttons = {}, value = nil }

    function picker:Set(v)
        self.value = v
        for _, b in ipairs(self.buttons) do
            local tex = b:GetNormalTexture()
            if v == nil then
                b:SetAlpha(0.6); tex:SetDesaturated(false)
            elseif b.rating == v then
                b:SetAlpha(1); tex:SetDesaturated(false)
            else
                b:SetAlpha(0.25); tex:SetDesaturated(true)
            end
        end
    end

    local prev
    for _, r in ipairs(ORDER) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(size, size)
        b:SetNormalTexture(RATINGS[r].icon)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.rating = r
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
        b:SetScript("OnClick", function()
            picker:Set(picker.value ~= r and r or nil)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(RATINGS[r].label)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        picker.buttons[#picker.buttons + 1] = b
        prev = b
    end

    function picker:SetPoint(...)
        self.buttons[1]:SetPoint(...)
    end
    function picker:Last()
        return self.buttons[#self.buttons]
    end

    picker:Set(nil)
    return picker
end

local function MakeWindow(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local t = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not f.TitleText then t:SetPoint("TOP", 0, -5) end
    t:SetText(title)
    tinsert(UISpecialFrames, name) -- Esc closes it
    f:Hide()
    return f
end

local function MakeEditBox(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(MAX_NOTE)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

local function MakeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, 22)
    b:SetText(text)
    return b
end

---------------------------------------------------------------------------
-- UI: single-player editor
---------------------------------------------------------------------------
local editor
local list -- notes list window (created further down)

local function RefreshList()
    if list and list:IsShown() then list:Refresh() end
end

local function CreateEditor()
    local f = MakeWindow("PlayerNotesEditor", 360, 205, "Player Note")

    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.nameText:SetPoint("TOP", 0, -32)

    f.infoText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.infoText:SetPoint("TOP", f.nameText, "BOTTOM", 0, -4)
    f.seenText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.seenText:SetPoint("TOP", f.infoText, "BOTTOM", 0, -2)
    f.runText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.runText:SetPoint("TOP", f.seenText, "BOTTOM", 0, -2)
    f.runText:SetWidth(320)
    f.runText:SetWordWrap(false)

    f.picker = CreateRatingPicker(f, 28)
    f.picker:SetPoint("TOP", f.runText, "BOTTOM", -32, -8)

    f.edit = MakeEditBox(f, 290)
    f.edit:SetPoint("TOP", 0, -150)

    f.save = MakeButton(f, "Save")
    f.save:SetPoint("BOTTOMRIGHT", -12, 10)
    f.delete = MakeButton(f, "Delete")
    f.delete:SetPoint("BOTTOMLEFT", 12, 10)

    local function Save()
        if f.picker.value == nil then
            Print("Pick an icon first (positive, neutral or negative).")
            return
        end
        SetEntry(f.key, f.display, f.picker.value, f.edit:GetText())
        if f.unit and UnitKey(f.unit) == f.key then RecordUnit(f.unit, false, false) end
        Print("Saved " .. f.display .. " " .. Icon(f.picker.value))
        f:Hide()
        RefreshList()
    end
    f.save:SetScript("OnClick", Save)
    f.edit:SetScript("OnEnterPressed", Save)
    f.delete:SetScript("OnClick", function()
        DeleteEntry(f.key)
        Print("Deleted note for " .. f.display)
        f:Hide()
        RefreshList()
    end)
    return f
end

local function OpenEditor(key, display, unit)
    if not key then return end
    editor = editor or CreateEditor()
    local e = GetEntry(key)
    if unit and e then RecordUnit(unit, false, false) end
    editor.key, editor.display, editor.unit = key, (e and e.name) or display, unit
    local c = e and e.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.classFile]
    if not c and unit then
        local _, cf = UnitClass(unit)
        c = cf and not IsSecret(cf) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
    end
    editor.nameText:SetText(editor.display)
    if c then editor.nameText:SetTextColor(c.r, c.g, c.b) else editor.nameText:SetTextColor(1, 0.82, 0) end
    editor.infoText:SetText(e and InfoText(e) or "")
    editor.seenText:SetText(e and SeenText(e) or "")
    editor.runText:SetText(e and LastRunText(e) or "")
    editor.picker:Set(e and e.rating)
    editor.edit:SetText(e and e.note or "")
    editor.delete:SetEnabled(e ~= nil)
    editor:Show()
end

---------------------------------------------------------------------------
-- UI: post-dungeon feedback window (one row per group member)
---------------------------------------------------------------------------
local feedback
local MAX_ROWS = 8 -- 4 party members plus room for replacements mid-run
local ROW_H = 30

local function CreateFeedback()
    local f = MakeWindow("PlayerNotesFeedback", 470, 0, "Rate your group")

    f.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(440, ROW_H)
        row:SetPoint("TOPLEFT", 15, -32 - (i - 1) * ROW_H)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT")
        row.name:SetWidth(135)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.picker = CreateRatingPicker(row, 22)
        row.picker:SetPoint("LEFT", row.name, "RIGHT", 4, 0)

        row.edit = MakeEditBox(row, 205)
        row.edit:SetPoint("LEFT", row.picker:Last(), "RIGHT", 14, 0)
        row.edit:SetScript("OnEnterPressed", row.edit.ClearFocus)

        f.rows[i] = row
    end

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 16, 16)
    f.hint:SetText("Only players with an icon selected are saved.")

    f.save = MakeButton(f, "Save")
    f.save:SetPoint("BOTTOMRIGHT", -12, 10)
    f.skip = MakeButton(f, "Skip")
    f.skip:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
    f.skip:SetScript("OnClick", function() f:Hide() end)

    f.save:SetScript("OnClick", function()
        local saved = 0
        for _, row in ipairs(f.rows) do
            if row:IsShown() and row.member and row.picker.value ~= nil then
                SetEntry(row.member.key, row.member.display, row.picker.value, row.edit:GetText())
                AddRun(row.member.key, f.run) -- newly rated players get this run too
                saved = saved + 1
            end
        end
        Print("Saved feedback for " .. saved .. " player(s).")
        f:Hide()
        RefreshList()
    end)
    return f
end

local function ShowFeedback(members, runInfo)
    if not members or #members == 0 then
        Print("No group members to rate.")
        return
    end
    feedback = feedback or CreateFeedback()
    feedback.run = runInfo
    local title = feedback.TitleText
    if title then
        title:SetText(runInfo and ("Rate your group: " .. runInfo.d) or "Rate your group")
    end
    local shown = math.min(#members, MAX_ROWS)
    for i, row in ipairs(feedback.rows) do
        local m = members[i]
        if i <= shown and m then
            local e = GetEntry(m.key)
            row.member = m
            row.name:SetText(ColorName(m.display, m.class))
            row.picker:Set(e and e.rating)
            row.edit:SetText(e and e.note or "")
            row:Show()
        else
            row.member = nil
            row:Hide()
        end
    end
    feedback:SetHeight(32 + shown * ROW_H + 44)
    feedback:Show()
end

---------------------------------------------------------------------------
-- UI: list of all notes (searchable, click a row to edit)
---------------------------------------------------------------------------
local LIST_ROWS = 14
local LIST_ROW_H = 22
local FILTERS = { "All", "Rated", "Positive", "Neutral", "Negative", "Not rated" }
local COLS = { -- header, width
    { "",             18 },
    { "Name",         120 },
    { "Lvl",          26 },
    { "Class",        66 },
    { "Guild",        100 },
    { "Note",         140 },
    { "Last dungeon", 115 },
    { "Last seen",    62 },
}

local function PassesFilter(e, filter)
    if filter == "Rated" then return e.rating ~= nil end
    if filter == "Positive" then return e.rating == 1 end
    if filter == "Neutral" then return e.rating == 0 end
    if filter == "Negative" then return e.rating == -1 end
    if filter == "Not rated" then return e.rating == nil end
    return true
end

local function CreateList()
    local f = MakeWindow("PlayerNotesList", 760, 470, "PlayerNotes")
    f.filter = 1

    f.search = MakeEditBox(f, 220)
    f.search:SetPoint("TOPLEFT", 22, -34)
    f.search:SetScript("OnEnterPressed", f.search.ClearFocus)
    f.search:SetScript("OnTextChanged", function() f:Refresh() end)

    f.searchHint = f.search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.searchHint:SetPoint("LEFT", 4, 0)
    f.searchHint:SetText("Search name, guild, dungeon, note...")

    f.filterBtn = MakeButton(f, "Show: All", 130)
    f.filterBtn:SetPoint("LEFT", f.search, "RIGHT", 12, 0)
    f.filterBtn:SetScript("OnClick", function()
        f.filter = f.filter % #FILTERS + 1
        f.filterBtn:SetText("Show: " .. FILTERS[f.filter])
        f:Refresh()
    end)

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.count:SetPoint("TOPRIGHT", -20, -38)

    -- column headers
    local x = 18
    for _, col in ipairs(COLS) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", x, -62)
        h:SetWidth(col[2])
        h:SetJustifyH("LEFT")
        h:SetText(col[1])
        x = x + col[2] + 6
    end

    f.scroll = CreateFrame("ScrollFrame", "PlayerNotesListScroll", f, "FauxScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 12, -78)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 44)
    f.scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, LIST_ROW_H, function() f:Refresh() end)
    end)

    f.rows = {}
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(715, LIST_ROW_H)
        row:SetPoint("TOPLEFT", 16, -78 - (i - 1) * LIST_ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)

        row.cells = {}
        local cx = 2 + COLS[1][2] + 6
        for c = 2, #COLS do
            local fs = row:CreateFontString(nil, "OVERLAY", c == 2 and "GameFontHighlight" or "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(COLS[c][2])
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cells[c] = fs
            cx = cx + COLS[c][2] + 6
        end

        row:SetScript("OnClick", function(self)
            if self.key then OpenEditor(self.key, self.display) end
        end)
        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(ColorName(self.display, e.classFile))
            local info = InfoText(e)
            if info ~= "" then GameTooltip:AddLine(info, 1, 1, 1) end
            GameTooltip:AddLine(EntryText(e), 1, 1, 1, true)
            local seen = SeenText(e)
            if seen ~= "" then GameTooltip:AddLine(seen, 0.6, 0.6, 0.6, true) end
            if e.runs and #e.runs > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Dungeons together (" .. #e.runs .. "):", 1, 0.82, 0)
                for i = 1, math.min(#e.runs, 8) do
                    GameTooltip:AddLine("  " .. RunLine(e.runs[i]), 1, 1, 1)
                end
                if #e.runs > 8 then GameTooltip:AddLine("  ...and " .. (#e.runs - 8) .. " more", 0.6, 0.6, 0.6) end
            end
            GameTooltip:AddLine("Click to rate or edit", 0.4, 0.8, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        f.rows[i] = row
    end

    f.rate = MakeButton(f, "Rate my group", 120)
    f.rate:SetPoint("BOTTOMLEFT", 12, 10)
    f.rate:SetScript("OnClick", function() SlashCmdList.PLAYERNOTES("feedback") end)

    f.add = MakeButton(f, "Note on target", 120)
    f.add:SetPoint("BOTTOMRIGHT", -12, 10)
    f.add:SetScript("OnClick", function()
        local key, display = UnitKey("target")
        if key and not UnitIsUnit("target", "player") then
            OpenEditor(key, display, "target")
        else
            Print("Target a player first, or right-click their name.")
        end
    end)

    function f:Refresh()
        local q = strlower(strtrim(self.search:GetText() or ""))
        self.searchHint:SetShown(q == "" and not self.search:HasFocus())
        local filter = FILTERS[self.filter]
        local data, total = {}, 0
        for k, e in pairs(PlayerNotesDB.players) do
            total = total + 1
            if PassesFilter(e, filter) then
                local dungeons = ""
                if e.runs then
                    for _, r in ipairs(e.runs) do dungeons = dungeons .. " " .. r.d end
                end
                local hay = strlower(k .. " " .. (e.note or "") .. " " .. (e.guild or "") .. " " .. (e.className or "") .. " " .. (e.race or "") .. dungeons)
                if q == "" or hay:find(q, 1, true) then
                    data[#data + 1] = { key = k, e = e, t = math.max(e.lastSeen or 0, e.updated or 0) }
                end
            end
        end
        table.sort(data, function(a, b) return a.t > b.t end)
        self.count:SetText(#data .. " of " .. total .. " player(s)")

        FauxScrollFrame_Update(self.scroll, #data, LIST_ROWS, LIST_ROW_H)
        local offset = FauxScrollFrame_GetOffset(self.scroll)
        for i, row in ipairs(self.rows) do
            local d = data[i + offset]
            if d then
                local e = d.e
                row.key, row.entry, row.display = d.key, e, e.name or d.key
                if e.rating then
                    row.icon:SetTexture(RATINGS[e.rating].icon)
                    row.icon:Show()
                else
                    row.icon:Hide()
                end
                row.cells[2]:SetText(ColorName(row.display, e.classFile))
                row.cells[3]:SetText(e.level or "?")
                row.cells[4]:SetText(e.className or "")
                row.cells[5]:SetText(e.guild and ("<" .. e.guild .. ">") or "")
                row.cells[6]:SetText(e.note or "")
                row.cells[7]:SetText(e.runs and e.runs[1] and e.runs[1].d or "")
                row.cells[8]:SetText(e.lastSeen and date("%d %b %y", e.lastSeen) or (e.updated and date("%d %b %y", e.updated)) or "")
                row:Show()
            else
                row.key, row.entry, row.display = nil, nil, nil
                row:Hide()
            end
        end
    end

    f.search:SetScript("OnEditFocusGained", function() f.searchHint:Hide() end)
    f.search:SetScript("OnEditFocusLost", function() f:Refresh() end)
    f:SetScript("OnShow", function() f:Refresh() end)
    return f
end

local function ToggleList()
    list = list or CreateList()
    list:SetShown(not list:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button (drag it around the minimap edge)
---------------------------------------------------------------------------
local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(PlayerNotesDB.settings.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 6
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function SetupMinimapButton()
    if not Minimap then return end
    local b = CreateFrame("Button", "PlayerNotesMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ADDON_ICON)
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            SlashCmdList.PLAYERNOTES("feedback")
        else
            ToggleList()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            PlayerNotesDB.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("PlayerNotes")
        GameTooltip:AddLine("Left-click: your notes", 1, 1, 1)
        GameTooltip:AddLine("Right-click: rate your group", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    minimapButton = b
    PlaceMinimapButton()
    b:SetShown(not PlayerNotesDB.settings.hideMinimap)
end

-- Entry in the minimap's addon drop-down, if the client has one.
function PlayerNotes_OnCompartmentClick(_, button)
    if button == "RightButton" then
        SlashCmdList.PLAYERNOTES("feedback")
    else
        ToggleList()
    end
end

---------------------------------------------------------------------------
-- Reminders when grouping with a known player
---------------------------------------------------------------------------
local reminded = {}
local checkPending = false

local function CheckGroup()
    checkPending = false
    if not IsInGroup() then
        wipe(reminded)
        return
    end
    local negative = false
    local track = PlayerNotesDB.settings.trackAll
    for _, m in ipairs(GetGroupMembers()) do
        local e = GetEntry(m.key)
        local first = not reminded[m.key]
        reminded[m.key] = true
        if e and e.rating and first then
            local msg = Icon(e.rating, 16) .. " " .. ColorName(m.display, m.class) .. " — "
                .. ((e.note and e.note ~= "") and e.note or RATINGS[e.rating].label)
            local lastR = e.runs and e.runs[1]
            Print("You've grouped with this player before: " .. msg
                .. (lastR and (" |cff888888(last run: " .. lastR.d .. ", " .. date("%d %b", lastR.t) .. ")|r") or ""))
            if PlayerNotesDB.settings.raidWarning and RaidNotice_AddMessage and RaidWarningFrame then
                RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
            end
            if e.rating == -1 then negative = true end
        end
        -- first time in this group counts as one "grouped with"; later updates just refresh info
        RecordUnit(m.unit, first, first and track)
    end
    RefreshList()
    if negative and SOUNDKIT then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

local function ScheduleCheck()
    if checkPending then return end
    checkPending = true
    C_Timer.After(1.5, CheckGroup) -- roster names often show "Unknown" for a moment
end

---------------------------------------------------------------------------
-- Dungeon completion -> feedback prompt
---------------------------------------------------------------------------
-- WoW Forever has no Mythic+ and no "dungeon complete" screen, so a run counts as
-- finished when you leave the dungeon (alive) or the group breaks up while you're
-- inside — as long as a boss died or you spent 10+ minutes in there.
local lastMembers, lastRun
local pendingFeedback = false
local run = { inside = false, instanceID = nil, name = nil, enteredAt = 0, bossKilled = false, bosses = 0, members = {}, order = {} }

local function ResetRun(instanceID, name)
    run.instanceID = instanceID
    run.name = name
    run.enteredAt = GetTime()
    run.bossKilled = false
    run.bosses = 0
    run.members, run.order = {}, {}
end

local lastKillAt = 0
local function CountBossKill()
    if not run.inside then return end
    if GetTime() - lastKillAt < 5 then return end
    lastKillAt = GetTime()
    run.bossKilled = true
    run.bosses = run.bosses + 1
end

local function FinishRun(members)
    lastMembers = members
    lastRun = { d = run.name or GetRealZoneText() or "Unknown dungeon", t = time(), bosses = run.bosses }
    for _, m in ipairs(members) do AddRun(m.key, lastRun) end
    RefreshList()
end

local function SnapshotMembers()
    for _, m in ipairs(GetGroupMembers()) do
        if not run.members[m.key] then
            run.members[m.key] = m
            run.order[#run.order + 1] = m
        end
    end
end

local function PromptFeedback()
    if InCombatLockdown() then
        pendingFeedback = true
        return
    end
    pendingFeedback = false
    if feedback and feedback:IsShown() then return end
    ShowFeedback(lastMembers, lastRun)
end

local function MaybePromptRun()
    if #run.order == 0 then return end
    if not run.bossKilled and GetTime() - run.enteredAt < 600 then return end
    FinishRun(run.order)
    ResetRun(nil)
    if PlayerNotesDB.settings.autoFeedback then
        C_Timer.After(2, PromptFeedback)
    end
end

local function UpdateInstanceState()
    local _, instanceType = IsInInstance()
    if instanceType == "party" then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if run.instanceID ~= instanceID then ResetRun(instanceID, SafeVal(name)) end
        run.inside = true
        if IsInGroup() then SnapshotMembers() end
    elseif run.inside then
        run.inside = false
        -- Released spirit after dying = you're a ghost outside, not finished.
        if not UnitIsDeadOrGhost("player") then MaybePromptRun() end
    end
end

local function OnRosterChanged()
    if run.inside then
        if IsInGroup() then
            SnapshotMembers()
        else
            MaybePromptRun() -- group disbanded while you're still inside
        end
    end
end

local function OnLFGComplete()
    if not run.name then run.name = SafeVal((GetInstanceInfo())) end
    FinishRun(GetGroupMembers())
    ResetRun(run.inside and run.instanceID or nil, run.inside and run.name or nil)
    if PlayerNotesDB.settings.autoFeedback and #lastMembers > 0 then
        C_Timer.After(4, PromptFeedback)
    end
end

---------------------------------------------------------------------------
-- Tooltip line on players you've rated
---------------------------------------------------------------------------
local function AddTooltipLine(tooltip)
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    local key = UnitKey(unit)
    local e = key and GetEntry(key)
    if not e then return end
    RecordUnit(unit, false, false) -- keep level/guild fresh
    if e.rating then
        tooltip:AddLine(EntryText(e), 1, 1, 1, true)
    end
    local seen = SeenText(e)
    if seen ~= "" then
        tooltip:AddLine("|cff33ccffPlayerNotes|r |cff888888" .. seen .. "|r", 1, 1, 1, true)
    end
    local lastRunText = LastRunText(e)
    if lastRunText ~= "" then
        tooltip:AddLine(lastRunText, 1, 1, 1, true)
    end
end

local function SetupTooltip()
    local safe = function(tt) pcall(AddTooltipLine, tt) end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, safe)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", safe)
    end
end

---------------------------------------------------------------------------
-- Right-click menu entry on players (party frames, target, chat names...)
---------------------------------------------------------------------------
local function SetupMenus()
    if not (Menu and Menu.ModifyMenu) then return end
    local function AddMenu(_, root, ctx)
        if not ctx then return end
        local key, display, unit
        if ctx.unit then key, display = UnitKey(ctx.unit); unit = key and ctx.unit end
        if not key and ctx.name then key, display = KeyFromText(ctx.name, ctx.server) end
        if not key then return end
        if key == (UnitKey("player")) then return end
        root:CreateDivider()
        root:CreateTitle("PlayerNotes")
        root:CreateButton(GetEntry(key) and "Edit player note" or "Add player note", function()
            OpenEditor(key, display, unit)
        end)
    end
    for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
                           "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND",
                           "MENU_UNIT_ENEMY_PLAYER" }) do
        pcall(Menu.ModifyMenu, tag, AddMenu)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
    Print("commands:")
    print("  /pn  — note for your target (or open your notes list)")
    print("  /pn add Name-Realm  — add or edit a note")
    print("  /pn feedback  — rate your current (or last dungeon) group")
    print("  /pn list  — open your notes list")
    print("  /pn print  — print all notes to chat")
    print("  /pn minimap  — show/hide the minimap button")
    print("  /pn delete Name-Realm  — remove a note")
    print("  /pn track  — toggle recording everyone you group with (not just rated players)")
    print("  /pn auto  — toggle the automatic post-dungeon prompt")
    print("  /pn warn  — toggle the big on-screen reminder")
end

SLASH_PLAYERNOTES1 = "/playernotes"
SLASH_PLAYERNOTES2 = "/pn"
SlashCmdList.PLAYERNOTES = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")

    if cmd == "" or cmd == "target" then
        local key, display = UnitKey("target")
        if key and not UnitIsUnit("target", "player") then
            OpenEditor(key, display, "target")
        else
            ToggleList()
        end
    elseif cmd == "help" then
        Help()
    elseif cmd == "add" or cmd == "edit" then
        local key, display
        local unit
        if rest ~= "" then key, display = KeyFromText(rest) else key, display = UnitKey("target"); unit = "target" end
        if key then OpenEditor(key, display, unit) else Print("Usage: /pn add Name-Realm (or target someone)") end
    elseif cmd == "feedback" or cmd == "fb" then
        if IsInGroup() then
            local inside = run.inside and run.name
            ShowFeedback(GetGroupMembers(), inside and { d = run.name, t = time(), bosses = run.bosses } or nil)
        else
            ShowFeedback(lastMembers, lastRun)
        end
    elseif cmd == "list" then
        ToggleList()
    elseif cmd == "print" then
        local keys = {}
        for k in pairs(PlayerNotesDB.players) do keys[#keys + 1] = k end
        table.sort(keys)
        if #keys == 0 then Print("No notes yet.") return end
        Print(#keys .. " player(s):")
        for _, k in ipairs(keys) do
            local e = PlayerNotesDB.players[k]
            local info = InfoText(e)
            print("  " .. (e.name or k) .. (info ~= "" and ("  |cffaaaaaa" .. info .. "|r") or "") .. "  " .. EntryText(e))
        end
    elseif cmd == "delete" or cmd == "del" or cmd == "remove" then
        local key = KeyFromText(rest)
        if key and GetEntry(key) then
            DeleteEntry(key)
            Print("Deleted note for " .. rest)
        else
            Print("No note found for " .. (rest ~= "" and rest or "?"))
        end
    elseif cmd == "minimap" then
        PlayerNotesDB.settings.hideMinimap = not PlayerNotesDB.settings.hideMinimap
        if minimapButton then minimapButton:SetShown(not PlayerNotesDB.settings.hideMinimap) end
        Print("Minimap button " .. (PlayerNotesDB.settings.hideMinimap and "hidden" or "shown"))
    elseif cmd == "track" then
        PlayerNotesDB.settings.trackAll = not PlayerNotesDB.settings.trackAll
        Print("Recording everyone you group with " .. (PlayerNotesDB.settings.trackAll and "ON" or "OFF (only players you rate)"))
    elseif cmd == "auto" then
        PlayerNotesDB.settings.autoFeedback = not PlayerNotesDB.settings.autoFeedback
        Print("Post-dungeon prompt " .. (PlayerNotesDB.settings.autoFeedback and "ON" or "OFF"))
    elseif cmd == "warn" then
        PlayerNotesDB.settings.raidWarning = not PlayerNotesDB.settings.raidWarning
        Print("On-screen reminder " .. (PlayerNotesDB.settings.raidWarning and "ON" or "OFF"))
    else
        Help()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        PlayerNotesDB = PlayerNotesDB or {}
        PlayerNotesDB.players = PlayerNotesDB.players or {}
        PlayerNotesDB.settings = PlayerNotesDB.settings or {}
        local s = PlayerNotesDB.settings
        if s.autoFeedback == nil then s.autoFeedback = true end
        if s.raidWarning == nil then s.raidWarning = true end
        if s.trackAll == nil then s.trackAll = true end

        SetupTooltip()
        SetupMenus()
        SetupMinimapButton()

        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("ENCOUNTER_END")
        self:RegisterEvent("BOSS_KILL")
        pcall(self.RegisterEvent, self, "LFG_COMPLETION_REWARD") -- only if Forever has a Dungeon Finder
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:UnregisterEvent("ADDON_LOADED")
        UpdateInstanceState()
    elseif event == "GROUP_ROSTER_UPDATE" then
        ScheduleCheck()
        OnRosterChanged()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ScheduleCheck()
        UpdateInstanceState()
    elseif event == "ENCOUNTER_END" then
        local success = select(5, ...)
        if not IsSecret(success) and success == 1 then CountBossKill() end
    elseif event == "BOSS_KILL" then
        CountBossKill() -- both events can fire for one kill; CountBossKill ignores the repeat
    elseif event == "LFG_COMPLETION_REWARD" then
        OnLFGComplete()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingFeedback then PromptFeedback() end
    end
end)
