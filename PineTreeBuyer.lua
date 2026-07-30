local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

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

local multiTypes = {Rope = true, Spring = true, Bar = true, MetalRod = true}

local function findNewBlock(beforeCount)
    local pf = getPlBlocks()
    if not pf then return nil end
    local after = #pf:GetChildren()
    if after > beforeCount then return pf:GetChildren()[after] end
    return nil
end

local function placeBlock(blockType, localCF, secondaryCF, rf, zone, plBlocks)
    if not rf then return false end
    local count = Player.Data and Player.Data:FindFirstChild(blockType) and Player.Data[blockType].Value or 0
    if count <= 0 then return false end
    local isMulti = secondaryCF ~= nil
    local worldCF = buildOffset and buildOffset * localCF or localCF
    local worldSecCF = isMulti and (buildOffset and buildOffset * secondaryCF or secondaryCF) or nil
    local beforeCount = plBlocks and #plBlocks:GetChildren() or 0
    local ok = pcall(function()
        if isMulti then
            rf:InvokeServer(blockType, count, zone, buildOffset or localCF, true, worldCF, worldSecCF)
        else
            rf:InvokeServer(blockType, count, zone, localCF, true, worldCF, false)
        end
    end)
    if not ok then return false end
    for _ = 1, 3 do
        local p = plBlocks or getPlBlocks()
        local after = p and #p:GetChildren() or 0
        if after > beforeCount then break end
        task.wait()
    end
    return true
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
    local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if hrp then buildOffset = CFrame.new(hrp.Position) end
    equipAllTools()
    local buildRF = getRF("BuildingTool", "RF")
    local p = Player
    local zone = workspace:FindFirstChild(tostring(p.TeamColor) .. "Zone")
    if not zone then
        for _, c in ipairs(workspace:GetChildren()) do
            if c.Name:lower():find("zone") then zone = c; break end
        end
    end
    if not zone then zone = workspace end
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
    local placed = {}
    _G.blocksById = {}
    for _, blockType in ipairs(typeOrder or {}) do
        local blocks = blocksByType[blockType]
        if blocks then
            for _, blockData in ipairs(blocks) do
                local cf = blockData.CFrame and cframeFromCFrameArray(blockData.CFrame) or cframeFromPosRot(blockData.Position or blockData.p, blockData.Rotation or blockData.r)
                local secondaryCF
                if multiTypes[blockType] then
                    local secPos = blockData.SecondaryPartPosition or blockData.spp
                    local secRot = blockData.SecondaryPartRotation or blockData.spr
                    if secPos then
                        secondaryCF = cframeFromPosRot(secPos, secRot)
                    end
                end
                local before = plBlocks and #plBlocks:GetChildren() or 0
                local ok = placeBlock(blockType, cf, secondaryCF, buildRF, zone, plBlocks)
                if ok then
                    placedCount = placedCount + 1
                    if placedCount % 50 == 0 then
                        setStatus("placing " .. placedCount .. "/" .. total)
                    end
                    if not multiTypes[blockType] then
                        local inst = findNewBlock(before)
                        if inst then
                            table.insert(placed, {data = blockData, inst = inst, type = blockType})
                            local id = blockData.ID or blockData.id
                            if id then _G.blocksById[id] = inst end
                        end
                    end
                end
            end
        end
    end

    local paintRF = getRF("PaintingTool", "RF")
    local propRF = getRF("PropertiesTool", "SetPropertieRF")
    local bindRF = getRF("BindTool", "RF")
    local unbindRF = getRF("BindTool", "UnbindRF")

    local paintBatch = {}
    local scaleBatch = {}
    local propBatch = {["Cast shadow"] = {}, ["Collision"] = {}, ["Anchored"] = {}}
    local transGroups = {}
    local wheelTorqueBatch = {}
    local wheelSpeedBatch = {}

    for _, entry in ipairs(placed) do
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

        local bt = blockData.BindTable or blockData.bt or blockData.bd
        if bt and type(bt) == "table" and #bt > 0 then
            unbindBlock(block, unbindRF)
            applyBindData(block, bt, bindRF)
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
        local hasWT = blockData.WheelTorque or blockData.wt
        if not hasWT and type(blockData.BoolValues) == "table" then
            hasWT = blockData.BoolValues.WheelTorque or blockData.BoolValues.wt
        end
        if hasWT then
            table.insert(wheelTorqueBatch, block)
        end
        local ws = blockData.WheelSpeed or blockData.ws
        if not ws and type(blockData.NumberValues) == "table" then
            ws = blockData.NumberValues.WheelSpeed or blockData.NumberValues.ws
        end
        if ws then
            table.insert(wheelSpeedBatch, {block, tostring(ws)})
        end
    end

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

    if #wheelTorqueBatch > 0 then
        addLog("batch wheel torque: " .. #wheelTorqueBatch .. " blocks")
        setStatus("wheel torque x" .. #wheelTorqueBatch)
        if propRF then
            for i = 1, 4 do
                pcall(function() propRF:InvokeServer("Wheel torque", wheelTorqueBatch) end)
            end
        end
    end

    if #wheelSpeedBatch > 0 then
        addLog("batch wheel speed: " .. #wheelSpeedBatch .. " entries")
        setStatus("wheel speed x" .. #wheelSpeedBatch)
        if propRF then
            for _, entry in ipairs(wheelSpeedBatch) do
                pcall(function() propRF:InvokeServer("Wheel speed", {entry[1]}, entry[2]) end)
            end
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
local ImgInput = Tab5:CreateInput({Name = "Image URL", CurrentValue = "", PlaceholderText = "https://catbox.moe/...png", RemoveTextAfterFocusLost = false, Flag = "ABImg", Callback = function() end})
local QSlider = Tab5:CreateSlider({Name = "Quality", Range = {1, 10}, Increment = 1, Suffix = "px", CurrentValue = 4, Flag = "ABQual", Callback = function() end})
local ImgBtn = Tab5:CreateButton({Name = "Build from Image", Callback = function()
    local url = ImgInput.CurrentValue or ""
    if url == "" then Rayfield:Notify({Title = "Auto-Build", Content = "Enter image URL", Duration = 3}) return end
    local bitmap = syn and syn.bitmap and syn.bitmap.loadImage and syn.bitmap.loadImage(url)
    if bitmap then
        local q = QSlider.CurrentValue or 4
        local w = math.floor(bitmap.Width / q)
        local h = math.floor(bitmap.Height / q)
        Rayfield:Notify({Title = "Auto-Build", Content = "Image: " .. bitmap.Width .. "x" .. bitmap.Height .. " -> " .. w .. "x" .. h .. " blocks", Duration = 4})
    else
        Rayfield:Notify({Title = "Auto-Build", Content = "syn.bitmap not available", Duration = 4})
    end
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
