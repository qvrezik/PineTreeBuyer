local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Anti-AFK: nudge the camera every few minutes so the server never flags us idle
task.spawn(function()
    while task.wait(240) do
        pcall(function()
            local cam = workspace.CurrentCamera
            if not cam then return end
            cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(0.5), 0)
        end)
        pcall(function()
            local char = game.Players.LocalPlayer and game.Players.LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.Velocity = hrp.Velocity + Vector3.new(0, 0.01, 0) end
        end)
    end
end)

local function parseVec3(str)
    if type(str) == "string" then
        local x, y, z = str:match("([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+)")
        return x and Vector3.new(tonumber(x), tonumber(y), tonumber(z)) or Vector3.new()
    end
    if type(str) == "table" and #str >= 3 then return Vector3.new(str[1], str[2], str[3]) end
    return Vector3.new()
end

local function cframeFromPosRot(posStr, rotStr)
    local pos = parseVec3(posStr)
    local rot = parseVec3(rotStr)
    local rad = math.rad
    return CFrame.new(pos.X, pos.Y, pos.Z) * CFrame.Angles(rad(rot.X), rad(rot.Y), rad(rot.Z))
end

local function cframeFromCFrameArray(arr)
    if type(arr) ~= "table" then return CFrame.new() end
    if #arr >= 12 then
        return CFrame.new(arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7], arr[8], arr[9], arr[10], arr[11], arr[12])
    end
    if #arr >= 3 then return CFrame.new(arr[1], arr[2], arr[3]) end
    return CFrame.new()
end

local buildOffset = nil
local Player = game:GetService("Players").LocalPlayer

local logLines = {}
local function addLog(msg)
    local line = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg)
    table.insert(logLines, line)
    print(line)
end

local function saveLog(fileName)
    local name = (fileName or "build"):match("(.+)%.[^%.]+$") or fileName or "build"
    local path = "BuildLog_" .. name .. "_" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".txt"
    local ok, err = pcall(function()
        writefile(path, table.concat(logLines, "\n"))
    end)
    if ok then
        addLog("Log saved: " .. path)
        return path
    else
        addLog("Failed to save log: " .. tostring(err))
        return nil
    end
end

local function equipAllTools()
    local p = Player
    local char = p.Character
    if not char then return end
    for _, tool in ipairs(p.Backpack:GetChildren()) do
        if tool:IsA("Tool") then pcall(function() tool.Parent = char end) end
    end
    task.wait(0.3)
end

local function unequipAllTools()
    local p = Player
    local char = p.Character
    if not char then return end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") then pcall(function() tool.Parent = p.Backpack end) end
    end
end

local function getRF(toolName, rfName)
    local p = Player
    local char = p.Character
    if not char then print("[Build] No character"); return nil end
    local t = char:FindFirstChild(toolName) or p.Backpack:FindFirstChild(toolName)
    if not t then print("[Build]", toolName, "not found"); return nil end
    return t:FindFirstChild(rfName or "RF")
end

local function getPlBlocks()
    local b = workspace:FindFirstChild("Blocks")
    if b then return b:FindFirstChild(Player.Name) end
    return nil
end

local function getBlockPivot(block)
    local primary = block.PrimaryPart
    if primary then return primary.CFrame end
    return block:GetPivot()
end

-- Only these three have a SecondaryPart in ReplicatedStorage.BuildingParts and take
-- the 7-argument form of BuildingTool.RF. MetalRod is an ordinary one-piece block
-- (Size 1,3,1) and must NOT be here, or it never gets scaled/painted.
local multiTypes = {Rope = true, Spring = true, Bar = true}

-- Wheel torque is a "level" property: the game derives the level from
-- #tostring(MotorMaxTorque / 1e6), so 1e6=1, 1e7=2, 1e8=3, 1e9=4, 1e10=5.
-- A fresh block starts at level 1, and each RF call steps one level up.
local function torqueLevel(v)
    v = tonumber(v)
    if not v or v < 1000000 then return 1 end
    return #tostring(math.floor(v / 1000000))
end

-- MValues keys in .Build files -> property names in BlockProperties (all number+)
local springPropNames = {
    Damping = "Damping",
    Stiffness = "Stiffness",
    MinLength = "Min length",
    TargetLength = "Target length",
    MaxLength = "Max length",
}

local function findNewBlock(beforeCount)
    local pf = getPlBlocks()
    if not pf then return nil end
    local after = #pf:GetChildren()
    if after > beforeCount then return pf:GetChildren()[after] end
    return nil
end

local function placeBlock(blockType, localCF, secondaryCF, rf, zone, plBlocks)
    if not rf then return nil end
    local count = Player.Data and Player.Data:FindFirstChild(blockType) and Player.Data[blockType].Value or 0
    if count <= 0 then return nil end
    local isMulti = secondaryCF ~= nil
    local worldCF = buildOffset and buildOffset * localCF or localCF
    local worldSecCF = isMulti and (buildOffset and buildOffset * secondaryCF or secondaryCF) or nil
    local beforeCount = plBlocks and #plBlocks:GetChildren() or 0
    local ok = pcall(function()
        local targetPart = zone
        local objectCF = targetPart and targetPart:IsA("BasePart") and targetPart.CFrame:ToObjectSpace(worldCF) or worldCF
        if isMulti then
            rf:InvokeServer(blockType, count, zone, objectCF, true, worldCF, worldSecCF)
        else
            rf:InvokeServer(blockType, count, zone, objectCF, true, worldCF, false)
        end
    end)
    if not ok then return nil end
    -- Grab the freshly created block immediately: InvokeServer already returned,
    -- so the server has created it. No polling, no per-block wait.
    local p = plBlocks or getPlBlocks()
    local after = p and #p:GetChildren() or 0
    if after > beforeCount then
        return p:GetChildren()[after]
    end
    return nil
end

local function parseColor(raw)
    addLog("parseColor: raw=" .. tostring(raw) .. " type=" .. type(raw))
    local r, g, b
    if type(raw) == "string" then
        r, g, b = raw:match("([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
    elseif type(raw) == "table" then
        r = raw.R or raw[1]
        g = raw.G or raw[2]
        b = raw.B or raw[3]
    end
    if not r then return nil end
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r then return nil end
    if r > 1 or g > 1 or b > 1 then
        r, g, b = r / 255, g / 255, b / 255
    end
    addLog(string.format("parseColor: -> %.3f,%.3f,%.3f", r, g, b))
    return Color3.new(r, g, b)
end

local function paintBlock(block, colorRaw)
    local rf = getRF("PaintingTool", "RF")
    if not rf then addLog("paintBlock: PaintingTool.RF not found"); return end
    local col = parseColor(colorRaw)
    if not col then addLog("paintBlock: bad color " .. tostring(colorRaw)); return end
    local ok = pcall(function() rf:InvokeServer({{block, col}}) end)
    addLog("paintBlock: " .. block.Name .. " -> " .. tostring(col) .. " ok=" .. tostring(ok))
    task.wait(0.02)
end

local unscalableTypes = {}

local function parseSize(raw)
    addLog("parseSize: raw=" .. tostring(raw) .. " type=" .. type(raw))
    local x, y, z
    if type(raw) == "string" then
        x, y, z = raw:match("([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+)")
        if not x then x, y, z = raw:match("([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)") end
    elseif type(raw) == "table" then
        x, y, z = raw[1], raw[2], raw[3]
    elseif typeof and typeof(raw) == "Vector3" then
        return raw
    end
    if x then return Vector3.new(tonumber(x), tonumber(y), tonumber(z)) end
    return nil
end

local function scaleBlock(blockType, block, sizeVal)
    if unscalableTypes[blockType] then addLog("scaleBlock: cached unscalable " .. blockType); return end
    local rf = getRF("ScalingTool", "RF")
    if not rf then addLog("scaleBlock: ScalingTool.RF not found"); return end
    local sz = parseSize(sizeVal)
    if not sz then addLog("scaleBlock: bad size " .. tostring(sizeVal)); return end
    if sz == Vector3.new(2, 2, 2) then addLog("scaleBlock: default 2,2,2 skip for " .. block.Name); return end
    local cf = getBlockPivot(block)
    addLog("scaleBlock: " .. block.Name .. " -> " .. tostring(sz) .. " pivot=" .. tostring(cf))
    local ok, err = pcall(function() rf:InvokeServer(block, sz, cf) end)
    addLog("scaleBlock: result ok=" .. tostring(ok) .. " err=" .. tostring(err))
    if not ok then addLog("scaleBlock: " .. blockType .. " error") end
end

local function setBlockProperty(block, propName)
    local rf = getRF("PropertiesTool", "SetPropertieRF")
    if not rf then addLog("setBlockProperty: PropertiesTool.SetPropertieRF not found"); return end
    addLog("setBlockProperty: " .. block.Name .. " -> " .. propName)
    local ok = pcall(function() rf:InvokeServer(propName, {block}) end)
    addLog("setBlockProperty: result ok=" .. tostring(ok))
    task.wait(0.02)
end

local function unbindBlock(block, rf)
    rf = rf or getRF("BindTool", "UnbindRF")
    if not rf then addLog("unbindBlock: no UnbindRF"); return end
    pcall(function() rf:InvokeServer({block}) end)
end

local function unbindAll()
    local rf = getRF("BindTool", "RF")
    if not rf then return end
    local pf = getPlBlocks()
    if not pf then return end
    addLog("unbindAll: clearing " .. #pf:GetChildren() .. " blocks")
    for _, block in ipairs(pf:GetChildren()) do
        unbindBlock(block)
    end
end

_G.blocksById = {}
local function applyBindData(block, bt, rf)
    if not rf then addLog("applyBindData: no BindRF"); return end
    if type(bt) ~= "table" or #bt == 0 then addLog("applyBindData: no bind data for " .. block.Name); return end
    local bindTable = {}
    local keyTable = {}
    for _, entry in ipairs(bt) do
        local targetId = entry[1]
        local actionName = entry[2]
        local keyCode = entry[3]
        addLog("applyBindData: " .. block.Name .. " entry={targetId=" .. tostring(targetId) .. ", action=" .. tostring(actionName) .. ", key=" .. tostring(keyCode) .. "}")
        local targetBlock = targetId and _G.blocksById and _G.blocksById[targetId]
        if targetBlock then
            local bindObjs = {}
            for _, c in ipairs(targetBlock:GetChildren()) do
                if string.sub(c.Name, 1, 4) == "Bind" then
                    local an = c:FindFirstChild("ActionName")
                    local act = an and an.Value or c.Name:sub(5)
                    if act == actionName then table.insert(bindObjs, c) end
                end
            end
            if #bindObjs == 0 then
                local c = targetBlock:FindFirstChild("Bind" .. actionName) or targetBlock:FindFirstChild(actionName)
                if c then bindObjs = {c} end
            end
            if #bindObjs > 0 then
                if not bindTable[actionName] then bindTable[actionName] = {} end
                for _, obj in ipairs(bindObjs) do table.insert(bindTable[actionName], obj) end
                if not keyTable[actionName] then keyTable[actionName] = keyCode or 0 end
            else
                addLog("applyBindData: no Bind objects for action " .. tostring(actionName) .. " on target " .. tostring(targetId))
            end
        else
            addLog("applyBindData: target block with ID " .. tostring(targetId) .. " not found")
        end
    end
    if next(bindTable) then
        local actionCount = 0 for _, v in pairs(bindTable) do actionCount = actionCount + #v end
        addLog("applyBindData: invoking RF with " .. actionCount .. " actions")
        local ok = pcall(function() rf:InvokeServer(bindTable, block, keyTable, false, false) end)
        addLog("applyBindData: result ok=" .. tostring(ok))
    else
        addLog("applyBindData: no bind objects found, can't bind")
    end
end

local Window = Rayfield:CreateWindow({
   Name = "Project AeroX -- Made by t.me/qvrezikk",
   Icon = 0,
   LoadingTitle = "Project AeroX",
   LoadingSubtitle = "by t.me/qvrezikk",
   ShowText = "AX",
   Theme = "Amethyst",
   ToggleUIKeybind = "K",
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   ConfigurationSaving = {
      Enabled = false,
      FolderName = nil,
      FileName = "Big Hub"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false,
   KeySettings = {
      Title = "hello",
      Subtitle = "Key System",
      Note = "KEY: t.me/qvrezikk",
      FileName = "Key",
      SaveKey = true,
      GrabKeyFromSite = false,
      Key = {"t.me/qvrezikk"}
   }
})

local Buyer = Window:CreateTab("Main", 4483362458)
local Tab2 = Window:CreateTab("Blocks", 4483362458)
local Tab3 = Window:CreateTab("Dupe", 4483362458)
local Section3 = Tab3:CreateSection("Dupe")
local Section2 = Tab2:CreateSection("Blocks")
local Section = Buyer:CreateSection("Buy")
local inputAmount = 1

local Button = Buyer:CreateButton({
    Name = "Buy pine tree x1 (80 gold)",
    Callback = function()
        local success, result = pcall(function()
            return workspace.ItemBoughtFromShop:InvokeServer("PineTree", 1)
        end)
        if success and result then
            Rayfield:Notify({
                Title = "Successfully",
                Content = "Successfully bought x1 Pine Tree",
                Duration = 3.5,
                Image = 4483362458,
            })
        else
            Rayfield:Notify({
                Title = "Failed",
                Content = "Failed, try again",
                Duration = 3.5,
                Image = 4483362458,
            })
        end
    end
})

local Button2 = Buyer:CreateButton({
    Name = "Buy pine tree x5 (400 gold)",
    Callback = function()
        local success, result = pcall(function()
            return workspace.ItemBoughtFromShop:InvokeServer("PineTree", 5)
        end)
        if success and result then
            Rayfield:Notify({
                Title = "Successfully",
                Content = "Successfully bought x5 Pine Tree",
                Duration = 3.5,
                Image = 4483362458,
            })
        else
            Rayfield:Notify({
                Title = "Failed",
                Content = "Failed, try again",
                Duration = 3.5,
                Image = 4483362458,
            })
        end
    end
})

local YouNeed = Buyer:CreateButton({
    Name = "You need: 0 gold",
    Callback = function() end,
})

local Input = Buyer:CreateInput({
    Name = "Amount of Pine Trees",
    CurrentValue = "",
    PlaceholderText = "Enter amount...",
    RemoveTextAfterFocusLost = false,
    Flag = "Input1",
    Callback = function(Text)
        local amount = tonumber(Text)
        if amount and amount > 0 then
            inputAmount = amount
            local totalPrice = amount * 80
            YouNeed:Set("You need: " .. totalPrice .. " gold")
        else
            inputAmount = 1
            YouNeed:Set("You need: 0 gold")
        end
    end,
})

local Button4 = Buyer:CreateButton({
    Name = "Buy pine tree (CUSTOM)",
    Callback = function()
        local amount = inputAmount
        if amount and amount > 0 then
            local pricePerItem = 80
            local totalPrice = amount * pricePerItem
            local success, result = pcall(function()
                return workspace.ItemBoughtFromShop:InvokeServer("PineTree", amount)
            end)
            if success and result then
                Rayfield:Notify({
                    Title = "Successfully",
                    Content = string.format("Bought x%d Pine Trees for %d gold!", amount, totalPrice),
                    Duration = 3.5,
                    Image = 4483362458,
                })
            else
                Rayfield:Notify({
                    Title = "Failed",
                    Content = "Failed, try again",
                    Duration = 3.5,
                    Image = 4483362458,
                })
            end
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Enter a valid number!",
                Duration = 3.5,
                Image = 4483362458,
            })
        end
    end,
})

local Button4 = Buyer:CreateButton({
   Name = "Buy 5 dragon harpoons (500 Robux)",
   Callback = function()
        workspace.PromptRobuxEvent:InvokeServer(1109792341, "Product")
   end,
})

local Button4 = Buyer:CreateButton({
   Name = "Buy 4 cookie wheels (250 Robux)",
   Callback = function()
        workspace.PromptRobuxEvent:InvokeServer(1126385328, "Product")
   end,
})

local Button3 = Buyer:CreateButton({
   Name = "Close UI",
   Callback = function()
   Rayfield:Destroy()
   end,
})

local Button3 = Tab2:CreateButton({
   Name = "Get Portals (experimental)",
   Callback = function()
   local rootPart = game.Players.LocalPlayer.Character.HumanoidRootPart

    rootPart.CFrame = CFrame.new(Vector3.new(435.1577715, -31.6001434, 3294.4729), rootPart.CFrame.LookVector)
    task.wait(5)

    rootPart.CFrame = CFrame.new(Vector3.new(1467.17859, -59.6000099, 3451.98779), rootPart.CFrame.LookVector)
    task.wait(5)

    rootPart.CFrame = CFrame.new(Vector3.new(1113.42468, -47.07999904, 3262.52393), rootPart.CFrame.LookVector)
    task.wait(5)

    rootPart.CFrame = CFrame.new(Vector3.new(1362.12402, -59.6000175, 3456.08716), rootPart.CFrame.LookVector)
    task.wait(5)

    rootPart.CFrame = CFrame.new(Vector3.new(1131.46521, -47.4000359, 3283.68921), rootPart.CFrame.LookVector)
    task.wait(5)

    rootPart.CFrame = CFrame.new(Vector3.new(1564.07092, -59.6000099, 3452.69385), rootPart.CFrame.LookVector)
    task.wait(5)

    rootPart.CFrame = CFrame.new(Vector3.new(1117.81592, -47.4000359, 3302.05908), rootPart.CFrame.LookVector)
   end,
})

-- Auto-Build tab
local Tab5 = Window:CreateTab("Auto-Build", 4483362458)
local Sec1 = Tab5:CreateSection("Build from File")
local SpeedSlider = Tab5:CreateSlider({Name = "Build Speed", Range = {1, 200}, Increment = 1, Suffix = "", CurrentValue = 100, Flag = "ABSpeed", Callback = function() end})
local FileBtn = Tab5:CreateButton({Name = "Files: press Refresh", Callback = function() end})

local function listBuildFiles()
    local dirs = {"AeroX/Builds/", "Butter-Builds/"}
    local all = {}
    for _, d in ipairs(dirs) do
        local ok, files = pcall(listfiles, d)
        if ok and files then
            for _, f in ipairs(files) do
                local n = f:match("[^\\/]+$")
                if n then table.insert(all, n) end
            end
        end
    end
    return all
end

local RefBtn = Tab5:CreateButton({Name = "Refresh", Callback = function()
    local files = listBuildFiles()
    if #files > 0 then
        FileBtn:Set("Files:\n" .. table.concat(files, "\n"))
    else
        FileBtn:Set("No files found")
    end
end})
local FInput = Tab5:CreateInput({Name = "Filename", CurrentValue = "", PlaceholderText = "my.build", RemoveTextAfterFocusLost = false, Flag = "ABFile", Callback = function() end})

local function tryFindFile(name)
    for _, d in ipairs({"AeroX/Builds/", "Butter-Builds/"}) do
        local ok, content = pcall(readfile, d .. name)
        if ok and content then return content end
    end
    return nil
end

local function parseBuildData(content)
    print("[Build] parseBuildData, len:", #content)
    content = content:gsub("\r\n", "\n")
    local rawBlock
    local first = content:sub(1, 100)
    print("[Build] first 100:", first:sub(1, 50))
    if first:find("%[Build%]") then
        local buildSection = content:match("%[Build%]\nBuild=(.*)")
        print("[Build] Format 3 match:", buildSection ~= nil)
        if not buildSection then return nil, "No [Build] section" end
        rawBlock = buildSection
    else
        rawBlock = content:match("%b[]") or content:match("%b{}")
        print("[Build] rawBlock (b[] or b{}):", rawBlock ~= nil, rawBlock and #rawBlock or 0)
    end
    if not rawBlock then return nil, "No JSON found" end
    rawBlock = rawBlock:match("^%s*(.-)%s*$")
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(rawBlock)
    end)
    print("[Build] JSONDecode:", ok, type(data))
    if not ok then return nil, "JSON decode: " .. tostring(data) end
    if type(data) ~= "table" then return nil, "Not a table: " .. type(data) end
    local blocksByType = {}
    local typeOrder = {}
    if type(data.Data) == "table" then
        for k, v in pairs(data.Data) do
            if type(v) == "table" then blocksByType[k] = v; table.insert(typeOrder, k) end
        end
    elseif type(data.b) == "table" then
        for k, v in pairs(data.b) do
            if type(v) == "table" then blocksByType[k] = v; table.insert(typeOrder, k) end
        end
    elseif type(data[2]) == "table" then
        if type(data[1]) == "table" then
            for _, name in ipairs(data[1]) do
                if type(data[2][name]) == "table" then
                    blocksByType[name] = data[2][name]
                    table.insert(typeOrder, name)
                end
            end
        else
            for k, v in pairs(data[2]) do
                if type(v) == "table" then blocksByType[k] = v; table.insert(typeOrder, k) end
            end
        end
    end
    if next(blocksByType) == nil then return nil, "No blocks found in file" end
    return blocksByType, typeOrder
end

local StatusBtn = Tab5:CreateButton({Name = "Status: idle", Callback = function() end})
local function setStatus(text)
    pcall(function() StatusBtn:Set("Status: " .. text) end)
end

local BuildBtn = Tab5:CreateButton({Name = "Build", Callback = function()
    logLines = {}
    addLog("=== Build started ===")
    local name = FInput.CurrentValue or ""
    if name == "" then Rayfield:Notify({Title = "Auto-Build", Content = "Enter a filename", Duration = 3}) return end
    addLog("File: " .. name)
    local content = tryFindFile(name)
    if not content then addLog("File not found"); Rayfield:Notify({Title = "Auto-Build", Content = "File not found: " .. name, Duration = 4}) return end
    local blocksByType, typeOrder = parseBuildData(content)
    if not blocksByType then addLog("Parse error: " .. tostring(typeOrder)); Rayfield:Notify({Title = "Auto-Build", Content = "Parse error: " .. tostring(typeOrder), Duration = 5}) return end
    local p = Player
    local zone = workspace:FindFirstChild(tostring(p.TeamColor) .. "Zone")
    if not zone then
        for _, c in ipairs(workspace:GetChildren()) do
            if c.Name:lower():find("zone") then zone = c; break end
        end
    end
    if not zone then zone = workspace end
    -- .Build coordinates are stored relative to the plot (zone) CFrame, not to the
    -- character. The zone also carries rotation (0/+-90 deg by team), so the full
    -- CFrame is needed, not just its position.
    if zone:IsA("BasePart") then
        buildOffset = zone.CFrame
        addLog("offset: zone " .. zone.Name .. " " .. tostring(zone.CFrame))
    else
        local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        buildOffset = hrp and CFrame.new(hrp.Position) or nil
        addLog("offset: fallback hrp " .. tostring(buildOffset))
    end
    equipAllTools()
    local buildRF = getRF("BuildingTool", "RF")
    local plBlocks = getPlBlocks()
    local placedCount = 0
    local total = 0
    for _, blocks in pairs(blocksByType) do total = total + #blocks end
    setStatus("building Phase 1/2: placing blocks")

    table.sort(typeOrder, function(a, b)
        local ma, mb = multiTypes[a], multiTypes[b]
        if ma ~= mb then return mb end
        return a < b
    end)
    _G.blocksById = {}

    local paintRF = getRF("PaintingTool", "RF")
    local propRF = getRF("PropertiesTool", "SetPropertieRF")
    local bindRF = getRF("BindTool", "RF")
    local unbindRF = getRF("BindTool", "UnbindRF")

    local paintBatch = {}
    local scaleBatch = {}
    local propBatch = {["Cast shadow"] = {}, ["Collision"] = {}, ["Anchored"] = {}}
    local transGroups = {}
    local torqueGroups = {}
    local wheelSpeedGroups = {}
    local reverseSpinBatch = {}
    local numberPropBatch = {}
    local showConstraintBatch = {}
    local crosshairsBatch = {}
    local bindBatch = {}

    -- Every number+ property takes its value as text and one call can carry all the
    -- blocks that want that same value, so they are grouped by property and value.
    local function addNumberProp(propName, value, block)
        local key = tostring(value)
        if not numberPropBatch[propName] then numberPropBatch[propName] = {} end
        if not numberPropBatch[propName][key] then numberPropBatch[propName][key] = {} end
        table.insert(numberPropBatch[propName][key], block)
    end

    -- A rope or spring anchors itself to whatever geometry exists at that moment,
    -- so placing one against a block that is still a default 2x2x2 cube leaves its
    -- endpoints in the wrong place once the cube is scaled. Ordinary blocks go down
    -- first, get scaled, and only then are the two-point blocks placed against the
    -- finished shape. wantMulti selects which of the two waves this call runs.
    local function placeWave(wantMulti)
        local wave = {}
        for _, blockType in ipairs(typeOrder or {}) do
            if (multiTypes[blockType] and true or false) == wantMulti then
                local blocks = blocksByType[blockType]
                if blocks then
                    for _, blockData in ipairs(blocks) do
                        local cf = blockData.CFrame and cframeFromCFrameArray(blockData.CFrame) or cframeFromPosRot(blockData.Position or blockData.p, blockData.Rotation or blockData.r)
                        local secondaryCF
                        if wantMulti then
                            -- Two formats in the wild: SecondaryPartPosition/Rotation
                            -- strings (drone-style) and a SecCFrame array (interesno-style).
                            local secArr = blockData.SecCFrame or blockData.sc
                            local secPos = blockData.SecondaryPartPosition or blockData.spp
                            local secRot = blockData.SecondaryPartRotation or blockData.spr
                            if type(secArr) == "table" then
                                secondaryCF = cframeFromCFrameArray(secArr)
                            elseif secPos then
                                secondaryCF = cframeFromPosRot(secPos, secRot)
                            end
                        end
                        local inst = placeBlock(blockType, cf, secondaryCF, buildRF, zone, plBlocks)
                        if inst then
                            placedCount = placedCount + 1
                            if placedCount % 50 == 0 then
                                setStatus("placing " .. placedCount .. "/" .. total)
                            end
                            -- Multi-blocks are kept too: they still need their binds
                            -- and, for Spring, their MValues.
                            table.insert(wave, {data = blockData, inst = inst, type = blockType})
                            local id = blockData.ID or blockData.id
                            if id then _G.blocksById[id] = inst end
                        end
                    end
                end
            end
        end
        return wave
    end

    -- Reads one placed block's data into the batches applied further down. Called
    -- once per wave, so the two-point blocks get the same treatment as the rest.
    local function collectEntry(entry)
        local block = entry.inst
        local blockData = entry.data
        local blockType = entry.type
        local isMulti = multiTypes[blockType]

        if not isMulti then
            local sz = blockData.Size or blockData.sz
            if sz then
                local parsedSz = parseSize(sz)
                if parsedSz and parsedSz ~= Vector3.new(2, 2, 2) then
                    table.insert(scaleBatch, {blockType = blockType, block = block, size = parsedSz})
                end
            end
        end

        -- Binds are queued, not applied here: a bind resolves its target through
        -- blocksById, and a block in wave 1 may well point at a Spring from wave 2
        -- that does not exist yet. They are all applied once both waves are down.
        local bt = blockData.BindTable or blockData.bt or blockData.bd
        if bt and type(bt) == "table" and #bt > 0 then
            table.insert(bindBatch, {block = block, bt = bt})
        end

        if not isMulti then
            local col = blockData.Color or blockData.cl
            local transparent = tonumber(blockData.Transparency) or 0
            if col and transparent < 1 then
                local c = parseColor(col)
                if c then table.insert(paintBatch, {block, c}) end
            end
            if transparent > 0 then
                local calls = math.min(4, math.ceil(transparent * 4))
                if not transGroups[calls] then transGroups[calls] = {} end
                table.insert(transGroups[calls], block)
            end
        end

        if blockData.ShowShadow == false or blockData.ss == false then
            table.insert(propBatch["Cast shadow"], block)
        end
        if blockData.CanCollide == false then
            table.insert(propBatch["Collision"], block)
        end
        if blockData.Anchored == false or blockData.a == false then
            table.insert(propBatch["Anchored"], block)
        end
        -- Wheel torque is a "level" property: group by how many steps up from the
        -- default (level 1) this block needs, so each group is clicked exactly that
        -- many times instead of a blind 4.
        local wt = blockData.WheelTorque or blockData.wt
        if not wt and type(blockData.NumberValues) == "table" then
            wt = blockData.NumberValues.WheelTorque or blockData.NumberValues.wt
        end
        if wt then
            local steps = torqueLevel(wt) - 1
            if steps > 0 then
                if not torqueGroups[steps] then torqueGroups[steps] = {} end
                table.insert(torqueGroups[steps], block)
            end
        end

        -- Wheel speed is number+, so it takes the value directly as text, and one
        -- call can carry every block that wants the same speed. Default is 50, so
        -- anything already at 50 needs no call at all.
        -- .Build files store it as NumberValues.MaxSpeed (game caps it at 50).
        local ws = blockData.WheelSpeed or blockData.ws
        if not ws and type(blockData.NumberValues) == "table" then
            ws = blockData.NumberValues.MaxSpeed or blockData.NumberValues.WheelSpeed or blockData.NumberValues.ws
        end
        if ws and tonumber(ws) ~= 50 then
            local key = tostring(ws)
            if not wheelSpeedGroups[key] then wheelSpeedGroups[key] = {} end
            table.insert(wheelSpeedGroups[key], block)
        end

        -- Reverse spin is boolean: default false, so one click only when true.
        local rs = blockData.ReverseSpin or blockData.rs
        if rs == nil and type(blockData.BoolValues) == "table" then
            rs = blockData.BoolValues.ReverseSpin
        end
        if rs == true then
            table.insert(reverseSpinBatch, block)
        end

        -- Camera crosshairs: the property is called "Crosshairs" in game but the file
        -- stores it as ShowCrosshairs. Boolean toggle, default true, so it only needs
        -- a click when the file asks for it to be off.
        local cross = blockData.ShowCrosshairs
        if cross == nil and type(blockData.BoolValues) == "table" then
            cross = blockData.BoolValues.ShowCrosshairs
        end
        if cross == false then
            table.insert(crosshairsBatch, block)
        end

        -- Spring constraint values, all number+ under MValues.
        local mv = blockData.MValues or blockData.mv
        if type(mv) == "table" then
            for mvKey, propName in pairs(springPropNames) do
                local v = mv[mvKey]
                if v ~= nil then
                    addNumberProp(propName, v, block)
                end
            end
        end

        -- Rope and Bar carry their own number+ properties. Length is the constraint's
        -- slack limit, not the distance between the endpoints -- those come from the
        -- two world CFrames at placement time, so this is independent of them.
        -- The server clamps to the Min of each property, so no validation here.
        if blockType == "Rope" or blockType == "Bar" then
            local len = blockData.Length or blockData.len
            if len == nil and type(mv) == "table" then len = mv.Length end
            if len ~= nil then addNumberProp("Length", len, block) end
        end

        -- Angle limit belongs to Bar alone (0-180).
        if blockType == "Bar" then
            local ang = blockData.AngleLimit or blockData.al
            if ang == nil and type(mv) == "table" then ang = mv.AngleLimit end
            if ang ~= nil then addNumberProp("Angle limit", ang, block) end
        end

        -- Show constraint is a boolean on all three two-point types, default true,
        -- so it only needs a click when the file asks for it to be hidden.
        -- Match rotation is deliberately absent: it only affects how the secondary
        -- part is oriented as the block is placed, and setting it afterwards is a
        -- no-op (verified in game -- nothing in the model changes).
        if multiTypes[blockType] then
            local sc = blockData.ShowConstraint
            if sc == nil and type(blockData.BoolValues) == "table" then
                sc = blockData.BoolValues.ShowConstraint
            end
            if sc == false then
                table.insert(showConstraintBatch, block)
            end
        end
    end

    -- Wave 1: ordinary blocks only, so the scaling pass below has real shapes to
    -- work with before anything anchors itself to them.
    local placed = placeWave(false)
    for _, entry in ipairs(placed) do collectEntry(entry) end

    if #scaleBatch > 0 then
        local scaleRF = getRF("ScalingTool", "RF")
        if scaleRF then
            addLog("batch scale: " .. #scaleBatch .. " blocks")
            setStatus("scaling " .. #scaleBatch .. " blocks")
            local BATCH_SIZE = 40
            for i = 1, #scaleBatch, BATCH_SIZE do
                local batchEnd = math.min(i + BATCH_SIZE - 1, #scaleBatch)
                setStatus("scaling " .. i .. "-" .. batchEnd .. "/" .. #scaleBatch)
                for j = i, batchEnd do
                    local entry = scaleBatch[j]
                    local cf = getBlockPivot(entry.block)
                    pcall(function() scaleRF:InvokeServer(entry.block, entry.size, cf) end)
                end
                if batchEnd < #scaleBatch then task.wait() end
            end
        end
    end

    -- Wave 2: Rope, Spring and Bar. The blocks they attach to are now at their
    -- real size, so the two world-space endpoints land where the file meant them to.
    -- Their batches are collected the same way and applied by the passes below.
    local placedMulti = placeWave(true)
    if #placedMulti > 0 then
        addLog("placing " .. #placedMulti .. " two-point blocks after scaling")
        setStatus("connectors: " .. #placedMulti)
        for _, entry in ipairs(placedMulti) do
            collectEntry(entry)
            table.insert(placed, entry)
        end
    end

    -- Every block from both waves is registered in blocksById by now, so a bind
    -- pointing at any of them resolves.
    if #bindBatch > 0 then
        addLog("applying binds for " .. #bindBatch .. " blocks")
        setStatus("binds x" .. #bindBatch)
        for i, item in ipairs(bindBatch) do
            unbindBlock(item.block, unbindRF)
            applyBindData(item.block, item.bt, bindRF)
            if i % 20 == 0 then task.wait() end
        end
    end

    if #paintBatch > 0 then
        addLog("batch paint: " .. #paintBatch .. " blocks")
        setStatus("painting " .. #paintBatch .. " blocks")
        if paintRF then pcall(function() paintRF:InvokeServer(paintBatch) end) end
    end

    for propName, blocks in pairs(propBatch) do
        if #blocks > 0 then
            addLog("batch property " .. propName .. ": " .. #blocks .. " blocks")
            setStatus("properties " .. propName .. " x" .. #blocks)
            if propRF then pcall(function() propRF:InvokeServer(propName, blocks) end) end
        end
    end

    for calls, blocks in pairs(transGroups) do
        addLog("batch transparency x" .. calls .. ": " .. #blocks .. " blocks")
        setStatus("transparency x" .. calls .. " for " .. #blocks .. " blocks")
        if propRF then
            for _ = 1, calls do
                pcall(function() propRF:InvokeServer("Transparency", blocks) end)
            end
        end
    end

    -- One group per target level: N steps up means exactly N calls, and the whole
    -- group is sent per call since they all need the same number of steps.
    for steps, blocks in pairs(torqueGroups) do
        addLog("batch wheel torque +" .. steps .. " levels: " .. #blocks .. " blocks")
        setStatus("wheel torque L" .. (steps + 1) .. " x" .. #blocks)
        if propRF then
            for _ = 1, steps do
                pcall(function() propRF:InvokeServer("Wheel torque", blocks) end)
            end
        end
    end

    if #reverseSpinBatch > 0 then
        addLog("batch reverse spin: " .. #reverseSpinBatch .. " blocks")
        setStatus("reverse spin x" .. #reverseSpinBatch)
        if propRF then pcall(function() propRF:InvokeServer("Reverse spin", reverseSpinBatch) end) end
    end

    if #showConstraintBatch > 0 then
        addLog("batch show constraint: " .. #showConstraintBatch .. " blocks")
        setStatus("hide constraint x" .. #showConstraintBatch)
        if propRF then pcall(function() propRF:InvokeServer("Show constraint", showConstraintBatch) end) end
    end

    if #crosshairsBatch > 0 then
        addLog("batch crosshairs: " .. #crosshairsBatch .. " blocks")
        setStatus("crosshairs x" .. #crosshairsBatch)
        if propRF then pcall(function() propRF:InvokeServer("Crosshairs", crosshairsBatch) end) end
    end

    -- Grouped by value, so all springs sharing a stiffness go in one call.
    for propName, byValue in pairs(numberPropBatch) do
        for val, blocks in pairs(byValue) do
            addLog("batch " .. propName .. " " .. val .. ": " .. #blocks .. " blocks")
            setStatus(propName .. " x" .. #blocks)
            if propRF then
                pcall(function() propRF:InvokeServer(propName, blocks, val) end)
            end
        end
    end

    -- One call per distinct speed, carrying every wheel that wants that value.
    for val, blocks in pairs(wheelSpeedGroups) do
        addLog("batch wheel speed " .. val .. ": " .. #blocks .. " blocks")
        setStatus("wheel speed " .. val .. " x" .. #blocks)
        if propRF then
            pcall(function() propRF:InvokeServer("Wheel speed", blocks, val) end)
        end
    end

    unequipAllTools()
    setStatus("done")
    addLog("=== Build finished: " .. #placed .. "/" .. total .. " blocks ===")
    local logPath = saveLog(name)
    Rayfield:Notify({Title = "Auto-Build", Content = #placed .. "/" .. total .. " blocks from " .. name .. ", log saved", Duration = 5})
end})
local LogBtn = Tab5:CreateButton({Name = "Save Log", Callback = function()
    local path = saveLog(FInput.CurrentValue or "manual")
    if path then
        Rayfield:Notify({Title = "Log", Content = "Saved: " .. path, Duration = 4})
    else
        Rayfield:Notify({Title = "Log", Content = "Failed to save", Duration = 3})
    end
end})
local Sec2 = Tab5:CreateSection("Image to Build")
local ImgInput = Tab5:CreateInput({Name = "Image URL (.bmp / .png)", CurrentValue = "", PlaceholderText = "https://catbox.moe/...bmp or ...png", RemoveTextAfterFocusLost = false, Flag = "ABImg", Callback = function() end})
local QSlider = Tab5:CreateSlider({Name = "Quality (Skip Pixels)", Range = {1, 10}, Increment = 1, Suffix = "px", CurrentValue = 4, Flag = "ABQual", Callback = function() end})
local SSlider = Tab5:CreateSlider({Name = "Size (Block Scale)", Range = {1, 5}, Increment = 0.5, Suffix = "x", CurrentValue = 1, Flag = "ABSize", Callback = function() end})
local ImgWSlider = Tab5:CreateSlider({Name = "Image Width (Blocks)", Range = {1, 80}, Increment = 1, Suffix = "bl", CurrentValue = 0, Flag = "ABImgW", Callback = function() end})
local BlocksNeededBtn = Tab5:CreateButton({Name = "Check blocks needed", Callback = function()
    local url = ImgInput.CurrentValue or ""
    if url == "" then Rayfield:Notify({Title = "Image Builder", Content = "Enter image URL first", Duration = 3}) return end
    local ok, data = pcall(function() return game:HttpGet(url) end)
    if not ok or not data then Rayfield:Notify({Title = "Image Builder", Content = "Failed to download image", Duration = 3}) return end
    local bmp, err = parseImage(data)
    if not bmp then Rayfield:Notify({Title = "Image Builder", Content = err, Duration = 5}) return end
    local q = QSlider.CurrentValue or 4
    local imgW = ImgWSlider.CurrentValue or 0
    local scale = SSlider.CurrentValue or 1
    local w, h
    if imgW and imgW > 1 then
        w = imgW
        h = math.max(1, math.round(imgW * bmp.Height / bmp.Width))
    else
        w = math.floor((bmp.Width - 1) / q) + 1
        h = math.floor((bmp.Height - 1) / q) + 1
    end
    local total = w * h
    local have = Player.Data and Player.Data:FindFirstChild("PlasticBlock") and Player.Data.PlasticBlock.Value or 0
    local okFit = total <= have
    Rayfield:Notify({
        Title = "Image Builder",
        Content = string.format("%dx%d image -> %dx%d blocks = %d plastic. You have %d. %s",
            bmp.Width, bmp.Height, w, h, total, have, okFit and "Fits!" or "NOT ENOUGH!"),
        Duration = 6,
    })
end})
local pvUpdate = nil
local PvBtn = Tab5:CreateButton({Name = "Preview Image (place in world)", Callback = function()
    if pvUpdate then pvUpdate("rebuild") end
end})
local PvHideBtn = Tab5:CreateButton({Name = "Hide Preview", Callback = function()
    if pvUpdate then pvUpdate("hide") end
end})
local PvX = Tab5:CreateSlider({Name = "Preview Offset X", Range = {-60, 60}, Increment = 0.5, Suffix = "st", CurrentValue = 0, Flag = "ABPvX", Callback = function() if pvUpdate then pvUpdate("move") end end})
local PvY = Tab5:CreateSlider({Name = "Preview Offset Y", Range = {-60, 60}, Increment = 0.5, Suffix = "st", CurrentValue = 0, Flag = "ABPvY", Callback = function() if pvUpdate then pvUpdate("move") end end})
local PvZ = Tab5:CreateSlider({Name = "Preview Offset Z", Range = {-60, 60}, Increment = 0.5, Suffix = "st", CurrentValue = 0, Flag = "ABPvZ", Callback = function() if pvUpdate then pvUpdate("move") end end})
local PvRY = Tab5:CreateSlider({Name = "Preview Rotate Y (yaw)", Range = {-180, 180}, Increment = 1, Suffix = "deg", CurrentValue = 0, Flag = "ABPvRY", Callback = function() if pvUpdate then pvUpdate("move") end end})
local PvRX = Tab5:CreateSlider({Name = "Preview Rotate X (pitch)", Range = {-180, 180}, Increment = 1, Suffix = "deg", CurrentValue = 0, Flag = "ABPvRX", Callback = function() if pvUpdate then pvUpdate("move") end end})
local PvRZ = Tab5:CreateSlider({Name = "Preview Rotate Z (roll)", Range = {-180, 180}, Increment = 1, Suffix = "deg", CurrentValue = 0, Flag = "ABPvRZ", Callback = function() if pvUpdate then pvUpdate("move") end end})
local PvFlipX = Tab5:CreateToggle({Name = "Flip Horizontal", CurrentValue = false, Flag = "ABPvFx", Callback = function() if pvUpdate then pvUpdate("rebuild") end end})
local PvFlipY = Tab5:CreateToggle({Name = "Flip Vertical", CurrentValue = false, Flag = "ABPvFy", Callback = function() if pvUpdate then pvUpdate("rebuild") end end})

-- Pure-Luau PNG decoder (deflate/inflate + unfilter + deinterlace-free)
local PNG_MAXBITS = 15

local function pngConstruct(count, symbol, lengths)
    local offs = {}
    for len = 0, PNG_MAXBITS do count[len] = 0 end
    for i = 1, #lengths do count[lengths[i]] = count[lengths[i]] + 1 end
    if count[0] == #lengths then return 0 end
    local left = 1
    for len = 1, PNG_MAXBITS do
        left = left * 2 - count[len]
        if left < 0 then return left end
    end
    offs[1] = 0
    for len = 1, PNG_MAXBITS - 1 do offs[len + 1] = offs[len] + count[len] end
    for sym = 1, #lengths do
        local l = lengths[sym]
        if l ~= 0 then
            offs[l] = offs[l] + 1
            symbol[offs[l]] = sym - 1
        end
    end
    return left
end

local function pngDecode(br, count, symbol)
    local code, first, index = 0, 0, 0
    for len = 1, PNG_MAXBITS do
        if br.bit > 7 then
            br.byte = string.byte(br.data, br.pos)
            br.pos = br.pos + 1
            br.bit = 0
        end
        code = code + (math.floor(br.byte / (2 ^ br.bit)) % 2)
        br.bit = br.bit + 1
        local c = count[len]
        if code - first < c then
            return symbol[index + (code - first) + 1]
        end
        index = index + c
        first = (first + c) * 2
        code = code * 2
    end
    return nil
end

local PNG_LEN_BASE = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local PNG_LEN_EXTRA = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local PNG_DIST_BASE = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local PNG_DIST_EXTRA = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local PNG_ORDER = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

local function pngReadBits(br, n)
    local val = 0
    for i = 0, n - 1 do
        if br.bit > 7 then
            br.byte = string.byte(br.data, br.pos)
            br.pos = br.pos + 1
            br.bit = 0
        end
        if math.floor(br.byte / (2 ^ br.bit)) % 2 == 1 then
            val = val + 2 ^ i
        end
        br.bit = br.bit + 1
    end
    return val
end

local pngFLitC, pngFLitS, pngFDistC, pngFDistS

local function pngGetFixed()
    if pngFLitC then return end
    local lit = {}
    for i = 0, 143 do lit[i + 1] = 8 end
    for i = 144, 255 do lit[i + 1] = 9 end
    for i = 256, 279 do lit[i + 1] = 7 end
    for i = 280, 287 do lit[i + 1] = 8 end
    pngFLitC, pngFLitS = {}, {}
    pngConstruct(pngFLitC, pngFLitS, lit)
    local dist = {}
    for i = 0, 29 do dist[i + 1] = 5 end
    pngFDistC, pngFDistS = {}, {}
    pngConstruct(pngFDistC, pngFDistS, dist)
end

local function pngInflate(data)
    local br = { data = data, pos = 3, bit = 8 }
    local out = {}
    local outLen = 0
    local ok = true
    local last = false
    while not last and ok do
        last = pngReadBits(br, 1) == 1
        local btype = pngReadBits(br, 2)
        if btype == 0 then
            br.bit = 8
            local len = string.byte(data, br.pos) + string.byte(data, br.pos + 1) * 256
            br.pos = br.pos + 4
            for i = 1, len do
                outLen = outLen + 1
                out[outLen] = string.byte(data, br.pos)
                br.pos = br.pos + 1
            end
        else
            local litCount, litSymbol, distCount, distSymbol
            if btype == 1 then
                pngGetFixed()
                litCount, litSymbol, distCount, distSymbol = pngFLitC, pngFLitS, pngFDistC, pngFDistS
            else
                local hlit = pngReadBits(br, 5) + 257
                local hdist = pngReadBits(br, 5) + 1
                local hclen = pngReadBits(br, 4) + 4
                local lens = {}
                for i = 0, 18 do lens[i + 1] = 0 end
                for i = 1, hclen do lens[PNG_ORDER[i] + 1] = pngReadBits(br, 3) end
                local clCount, clSymbol = {}, {}
                pngConstruct(clCount, clSymbol, lens)
                local lengths = {}
                local n = 0
                while n < hlit + hdist do
                    local sym = pngDecode(br, clCount, clSymbol)
                    if not sym then ok = false break end
                    if sym < 16 then
                        n = n + 1
                        lengths[n] = sym
                    else
                        local rep, val
                        if sym == 16 then
                            val = lengths[n]
                            rep = 3 + pngReadBits(br, 2)
                        elseif sym == 17 then
                            val = 0
                            rep = 3 + pngReadBits(br, 3)
                        else
                            val = 0
                            rep = 11 + pngReadBits(br, 7)
                        end
                        for i = 1, rep do
                            n = n + 1
                            lengths[n] = val
                        end
                    end
                end
                local litLens = {}
                for i = 1, hlit do litLens[i] = lengths[i] end
                local distLens = {}
                for i = 1, hdist do distLens[i] = lengths[hlit + i] end
                litCount, litSymbol = {}, {}
                pngConstruct(litCount, litSymbol, litLens)
                distCount, distSymbol = {}, {}
                pngConstruct(distCount, distSymbol, distLens)
            end
            if ok then
                local sym = pngDecode(br, litCount, litSymbol)
                while sym ~= 256 and ok do
                    if not sym then ok = false break end
                    if sym < 256 then
                        outLen = outLen + 1
                        out[outLen] = sym
                    else
                        local li = sym - 257
                        local len = PNG_LEN_BASE[li + 1] + pngReadBits(br, PNG_LEN_EXTRA[li + 1])
                        local dsym = pngDecode(br, distCount, distSymbol)
                        if not dsym then ok = false break end
                        local dist = PNG_DIST_BASE[dsym + 1] + pngReadBits(br, PNG_DIST_EXTRA[dsym + 1])
                        if dist > outLen then ok = false break end
                        local start = outLen - dist
                        for i = 1, len do
                            outLen = outLen + 1
                            out[outLen] = out[start + i]
                        end
                    end
                    sym = pngDecode(br, litCount, litSymbol)
                end
                if not sym then ok = false end
            end
        end
    end
    if not ok then return nil, "inflate error" end
    return out, outLen
end

local function parsePNG(data)
    if string.sub(data, 1, 8) ~= "\137PNG\r\n\26\n" then return nil, "Not a PNG" end
    local pos = 9
    local width, height, colorType, interlace
    local idat = {}
    local idatLen = 0
    local palette = {}
    local trns = {}
    local hasTrns = false
    while pos + 12 <= #data do
        local len = string.unpack(">I4", data, pos)
        local ctype = string.sub(data, pos + 4, pos + 7)
        local cdata = string.sub(data, pos + 8, pos + 7 + len)
        if ctype == "IHDR" then
            width = string.unpack(">I4", cdata, 1)
            height = string.unpack(">I4", cdata, 5)
            colorType = string.byte(cdata, 10)
            interlace = string.byte(cdata, 13)
        elseif ctype == "PLTE" then
            palette = {}
            for i = 1, len, 3 do
                table.insert(palette, { r = string.byte(cdata, i), g = string.byte(cdata, i + 1), b = string.byte(cdata, i + 2) })
            end
        elseif ctype == "tRNS" then
            hasTrns = true
            trns = {}
            for i = 1, len do trns[i] = string.byte(cdata, i) end
        elseif ctype == "IDAT" then
            table.insert(idat, cdata)
            idatLen = idatLen + len
        elseif ctype == "IEND" then
            break
        end
        pos = pos + 12 + len
    end
    if not width or not height then return nil, "No IHDR" end
    if interlace ~= 0 then return nil, "Interlaced PNG not supported" end
    if idatLen == 0 then return nil, "No IDAT" end

    local bytes, n = pngInflate(table.concat(idat))
    if not bytes then return nil, "Inflate failed" end

    local bpp
    if colorType == 0 then bpp = 1
    elseif colorType == 2 then bpp = 3
    elseif colorType == 3 then bpp = 1
    elseif colorType == 4 then bpp = 2
    elseif colorType == 6 then bpp = 4
    else return nil, "Unsupported color type " .. colorType end

    local stride = width * bpp
    if n < stride * height + height then return nil, "Image data too short" end

    local pos2 = 1
    for y = 1, height do
        local ft = bytes[pos2]
        pos2 = pos2 + 1
        local start = pos2
        if ft == 1 then
            for x = start, start + stride - 1 do
                local a = (x - bpp >= start) and bytes[x - bpp] or 0
                bytes[x] = (bytes[x] + a) % 256
            end
        elseif ft == 2 then
            if y > 1 then
                for x = start, start + stride - 1 do
                    bytes[x] = (bytes[x] + bytes[x - stride - 1]) % 256
                end
            end
        elseif ft == 3 then
            for x = start, start + stride - 1 do
                local a = (x - bpp >= start) and bytes[x - bpp] or 0
                local b = y > 1 and bytes[x - stride - 1] or 0
                bytes[x] = (bytes[x] + math.floor((a + b) / 2)) % 256
            end
        elseif ft == 4 then
            for x = start, start + stride - 1 do
                local a = (x - bpp >= start) and bytes[x - bpp] or 0
                local b = y > 1 and bytes[x - stride - 1] or 0
                local c = (x - bpp >= start and y > 1) and bytes[x - stride - 1 - bpp] or 0
                local p = a + b - c
                local pa = math.abs(p - a)
                local pb = math.abs(p - b)
                local pc = math.abs(p - c)
                local pr
                if pa <= pb and pa <= pc then pr = a
                elseif pb <= pc then pr = b
                else pr = c end
                bytes[x] = (bytes[x] + pr) % 256
            end
        end
        pos2 = pos2 + stride
    end

    -- PNG rows are stored top-down; BMP uses bottom-up. Convert to BMP layout.
    -- Pixels with alpha < 128 are skipped (nil) so transparent regions build nothing.
    local pixels = {}
    for y = 0, height - 1 do
        local srcY = height - y
        local rowStart = 1 + (srcY - 1) * (stride + 1) + 1
        local row = {}
        for x = 0, width - 1 do
            local p = rowStart + x * bpp
            if colorType == 2 then
                row[x] = Color3.fromRGB(bytes[p], bytes[p + 1], bytes[p + 2])
            elseif colorType == 6 then
                if bytes[p + 3] >= 128 then
                    row[x] = Color3.fromRGB(bytes[p], bytes[p + 1], bytes[p + 2])
                end
            elseif colorType == 3 then
                local idx = bytes[p] + 1
                if not (hasTrns and (trns[idx] or 255) < 128) then
                    local e = palette[idx]
                    row[x] = e and Color3.fromRGB(e.r, e.g, e.b) or Color3.fromRGB(255, 0, 255)
                end
            elseif colorType == 0 then
                row[x] = Color3.fromRGB(bytes[p], bytes[p], bytes[p])
            elseif colorType == 4 then
                if bytes[p + 1] >= 128 then
                    row[x] = Color3.fromRGB(bytes[p], bytes[p], bytes[p])
                end
            end
        end
        pixels[y] = row
    end
    return { Width = width, Height = height, Pixels = pixels }
end

local function parseImage(data)
    if string.sub(data, 1, 2) == "BM" then
        return parseBMP(data)
    end
    if string.sub(data, 1, 8) == "\137PNG\r\n\26\n" then
        return parsePNG(data)
    end
    return nil, "Not a BMP or PNG file. Convert image to .bmp or .png!"
end

local function parseBMP(data)
    if string.sub(data, 1, 2) ~= "BM" then return nil, "Not a BMP file. Convert image to .bmp!" end
    local pixelOffset = string.unpack("<I4", string.sub(data, 11, 14))
    local w = string.unpack("<i4", string.sub(data, 19, 22))
    local h = string.unpack("<i4", string.sub(data, 23, 26))
    local bpp = string.unpack("<I2", string.sub(data, 29, 30))
    if bpp ~= 24 and bpp ~= 32 then return nil, "Please save BMP as 24-bit or 32-bit color." end
    
    local pixels = {}
    local rowBytes = math.floor((bpp * w + 31) / 32) * 4
    for y = 0, h - 1 do
        pixels[y] = {}
        for x = 0, w - 1 do
            local idx = pixelOffset + 1 + y * rowBytes + x * (bpp / 8)
            local b, g, r = string.byte(data, idx, idx+2)
            pixels[y][x] = Color3.fromRGB(r or 255, g or 255, b or 255)
        end
    end
    return {Width = w, Height = h, Pixels = pixels}
end

-- Preview + Image Build
local pvState = { model = nil, samples = {}, cols = 0, rows = 0, scale = 1 }

local function getZonePart()
    local zone = workspace:FindFirstChild(tostring(Player.TeamColor) .. "Zone")
    if not zone then
        for _, c in ipairs(workspace:GetChildren()) do
            if c.Name:lower():find("zone") then zone = c; break end
        end
    end
    return zone
end

local function pvTransform()
    local zone = getZonePart()
    local baseCF
    if zone and zone:IsA("BasePart") then
        -- Start from the top face of the zone, inheriting its rotation so the image
        -- orientation stays consistent across teams (Really blue = -90°, New Yeller = +90°).
        -- Offsets and manual rotations are applied in the zone's local space.
        baseCF = zone.CFrame * CFrame.new(0, zone.Size.Y / 2 + 1, 0)
    else
        local fallback = (Player.Character and Player.Character:GetPivot().Position + Vector3.new(0, 10, -20))
            or Vector3.new(0, 50, 0)
        baseCF = CFrame.new(fallback)
    end
    local dx = PvX.CurrentValue or 0
    local dy = PvY.CurrentValue or 0
    local dz = PvZ.CurrentValue or 0
    return baseCF
        * CFrame.new(dx, dy, dz)
        * CFrame.Angles(math.rad(PvRX.CurrentValue or 0), math.rad(PvRY.CurrentValue or 0), math.rad(PvRZ.CurrentValue or 0))
end

local function computeSamples(bmp, q, imgW)
    local W, H = bmp.Width, bmp.Height
    local cols, rows
    if imgW and imgW > 1 then
        cols = imgW
        rows = math.max(1, math.round(imgW * H / W))
    else
        cols = math.floor((W - 1) / q) + 1
        rows = math.floor((H - 1) / q) + 1
    end
    local stepX = cols > 1 and ((W - 1) / (cols - 1)) or 0
    local stepY = rows > 1 and ((H - 1) / (rows - 1)) or 0
    local flipX = PvFlipX.CurrentValue or false
    local flipY = PvFlipY.CurrentValue or false
    local samples = {}
    for gridY = 0, rows - 1 do
        local y = H - 1 - math.floor(gridY * stepY + 0.5)
        if y < 0 then y = 0 end
        local gy = flipY and (rows - 1 - gridY) or gridY
        for gridX = 0, cols - 1 do
            local x = math.floor(gridX * stepX + 0.5)
            local color = bmp.Pixels[y] and bmp.Pixels[y][x]
            if color then
                local gx = flipX and (cols - 1 - gridX) or gridX
                table.insert(samples, { gx = gx, gy = gy, color = color })
            end
        end
    end
    return samples, cols, rows
end

local function buildPreviewModel(samples, cols, rows, scale)
    if pvState.model then pcall(function() pvState.model:Destroy() end) end
    pvState.model = nil
    local model = Instance.new("Model")
    model.Name = "ImagePreview"
    local root = Instance.new("Part")
    root.Name = "Pivot"
    root.Size = Vector3.new(1, 1, 1)
    root.Transparency = 1
    root.Anchored = true
    root.CanCollide = false
    root.Parent = model
    model.PrimaryPart = root
    local step = 2 * scale
    for _, s in ipairs(samples) do
        local p = Instance.new("Part")
        p.Size = Vector3.new(step, step, step)
        p.Anchored = true
        p.CanCollide = false
        p.Transparency = 0.55
        p.Material = Enum.Material.SmoothPlastic
        p.Color = s.color
        p.CFrame = CFrame.new(s.gx * step, s.gy * step, 0)
        p.Parent = model
    end
    model:PivotTo(pvTransform())
    model.Parent = workspace
    pvState.model = model
end

pvUpdate = function(action)
    if action == "hide" then
        if pvState.model then pcall(function() pvState.model:Destroy() end) end
        pvState.model = nil
        return
    end
    if action == "move" then
        if pvState.model then pcall(function() pvState.model:PivotTo(pvTransform()) end) end
        return
    end
    -- rebuild
    local url = ImgInput.CurrentValue or ""
    if url == "" then Rayfield:Notify({Title = "Preview", Content = "Enter image URL first", Duration = 3}) return end
    local ok, data = pcall(function() return game:HttpGet(url) end)
    if not ok or not data then Rayfield:Notify({Title = "Preview", Content = "Failed to download image", Duration = 3}) return end
    local bmp, err = parseImage(data)
    if not bmp then Rayfield:Notify({Title = "Preview", Content = err, Duration = 5}) return end
    local q = QSlider.CurrentValue or 4
    local imgW = ImgWSlider.CurrentValue or 0
    local scale = SSlider.CurrentValue or 1
    local samples, cols, rows = computeSamples(bmp, q, imgW)
    pvState.samples = samples
    pvState.cols = cols
    pvState.rows = rows
    pvState.scale = scale
    buildPreviewModel(samples, cols, rows, scale)
    Rayfield:Notify({Title = "Preview", Content = cols .. "x" .. rows .. " = " .. #samples .. " blocks shown. Move/rotate via sliders.", Duration = 4})
end

local ImgBtn = Tab5:CreateButton({Name = "Build from Image", Callback = function()
    local url = ImgInput.CurrentValue or ""
    if url == "" then Rayfield:Notify({Title = "Auto-Build", Content = "Enter .bmp/.png image URL", Duration = 3}) return end
    
    local ok, data = pcall(function() return game:HttpGet(url) end)
    if not ok or not data then Rayfield:Notify({Title = "Auto-Build", Content = "Failed to download image", Duration = 3}) return end
    
    local bmp, err = parseImage(data)
    if not bmp then Rayfield:Notify({Title = "Auto-Build", Content = err, Duration = 5}) return end
    
    local q = QSlider.CurrentValue or 4
    local imgW = ImgWSlider.CurrentValue or 0
    local scale = SSlider.CurrentValue or 1
    local samples, cols, rows = computeSamples(bmp, q, imgW)
    -- Transparent pixels are skipped by computeSamples, so cols*rows over-counts
    -- and refuses builds that actually fit.
    local totalBlocks = #samples

    local have = Player.Data and Player.Data:FindFirstChild("PlasticBlock") and Player.Data.PlasticBlock.Value or 0
    if totalBlocks > have then
        Rayfield:Notify({Title = "Image Builder", Content = "NOT ENOUGH plastic! Need " .. totalBlocks .. " blocks, you have " .. have .. ". Reduce size / raise quality.", Duration = 6})
        return
    end

    Rayfield:Notify({Title = "Image Builder", Content = "Building " .. cols .. "x" .. rows .. " ("..totalBlocks.." plastic blocks)", Duration = 4})
    
    task.spawn(function()
        local okRun, runErr = pcall(function()
        equipAllTools()
        local buildRF = getRF("BuildingTool", "RF")
        local paintEvent = getRF("PaintingTool", "RF")
        local scaleEvent = getRF("ScalingTool", "RF")
        if not buildRF then Rayfield:Notify({Title = "Image Builder", Content = "BuildingTool not found!", Duration = 3}) return end

        -- pvTransform() already yields WORLD CFrames. placeBlock multiplies by
        -- buildOffset, which a previous Auto-Build run leaves set to the zone
        -- CFrame - that would shift the whole image by a plot. Clear it.
        buildOffset = nil
        local zone = getZonePart()
        local plBlocks = getPlBlocks()

        local plastic = "PlasticBlock"
        local step = 2 * scale
        local transform = pvTransform()
        local placed = 0
        local paintPairs = {}
        local scalePairs = {}
        local expected = {}

        local function blockKey(pos)
            return string.format("%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z)
        end

        for i, s in ipairs(samples) do
            local worldCF = transform * CFrame.new(s.gx * step, s.gy * step, 0)
            local key = blockKey(worldCF.Position)
            expected[key] = s.color
            local blk = placeBlock(plastic, worldCF, nil, buildRF, zone, plBlocks)
            if blk then
                table.insert(paintPairs, {blk, s.color})
                if scale ~= 1 then table.insert(scalePairs, {blk, Vector3.new(step, step, step), getBlockPivot(blk)}) end
                placed = placed + 1
            end
            if i % 20 == 0 then task.wait(0.05) end
        end

        -- Fallback: paint any block that spawned at an expected position but wasn't captured on the spot
        task.wait(1)
        local folder = getPlBlocks()
        if folder then
            for _, blk in ipairs(folder:GetChildren()) do
                -- blocks are Models: Model has no .Position, only a pivot
                local key = blockKey(getBlockPivot(blk).Position)
                local color = expected[key]
                if color then
                    expected[key] = nil
                    local already = false
                    for _, pr in ipairs(paintPairs) do if pr[1] == blk then already = true break end end
                    if not already then
                        table.insert(paintPairs, {blk, color})
                        if scale ~= 1 then table.insert(scalePairs, {blk, Vector3.new(step, step, step), getBlockPivot(blk)}) end
                        placed = placed + 1
                    end
                end
            end
        end

        -- Paint everything in batches: one InvokeServer per 50 pairs
        if paintEvent and #paintPairs > 0 then
            for i = 1, #paintPairs, 50 do
                local batch = {}
                for j = i, math.min(i + 49, #paintPairs) do
                    batch[#batch + 1] = paintPairs[j]
                end
                pcall(function() paintEvent:InvokeServer(batch) end)
                task.wait(0.1)
            end
        end

        -- Scale afterwards (only when block scale != 1), batching 50 per wait
        if scaleEvent and #scalePairs > 0 then
            for i, s in ipairs(scalePairs) do
                pcall(function() scaleEvent:InvokeServer(s[1], s[2], s[3]) end)
                if i % 50 == 0 then task.wait(0.05) end
            end
        end
        
        unequipAllTools()
        Rayfield:Notify({Title = "Image Builder", Content = "Finished building image! Placed: " .. placed, Duration = 5})
        end)
        if not okRun then
            pcall(unequipAllTools)
            addLog("Image build error: " .. tostring(runErr))
            Rayfield:Notify({Title = "Image Builder", Content = "Error: " .. tostring(runErr), Duration = 8})
        end
    end)
end})

-- Dupe tab (LoadBoatData exploit)
local savedCFrame = nil
local currentSlot = "1"
local TargerPlayer = nil

local SetPoint = Tab3:CreateButton({
   Name = "Set Point",
   Callback = function()
       local char = Player.Character
       if char and char:FindFirstChild("HumanoidRootPart") then
           savedCFrame = char.HumanoidRootPart.CFrame
       end
   end,
})

local Input = Tab3:CreateInput({
   Name = "Slot",
   CurrentValue = "1",
   PlaceholderText = "Slot",
   RemoveTextAfterFocusLost = false,
   Flag = "Input1",
   Callback = function(Text)
       currentSlot = tostring(Text)
   end,
})

local SaveButton = Tab3:CreateButton({
   Name = "Dupe Build",
   Callback = function()
       task.spawn(function()
           local player = Player
           local char = player.Character or player.CharacterAdded:Wait()
           local hrp = char:FindFirstChild("HumanoidRootPart")
           if not hrp then return end
           if not savedCFrame then savedCFrame = hrp.CFrame end
           hrp.CFrame = CFrame.new(128.8933258, -7.1000228, 1215.9909668)
           task.wait(1)
           local slotToLoad = currentSlot
           if Rayfield and Rayfield.Flags and Rayfield.Flags["Input1"] then
               slotToLoad = tostring(Rayfield.Flags["Input1"].Value)
           end
           local slotNum = tonumber(slotToLoad:match("^%s*(.-)%s*$")) or 1
           workspace.LoadBoatData:FireServer(slotNum, 0)
           task.wait(15)
           if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
               player.Character.HumanoidRootPart.CFrame = savedCFrame
           end
       end)
   end,
})
