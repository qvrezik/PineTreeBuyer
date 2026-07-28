local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Pine Tree Buyer -- Made by t.me/qvrezikk",
   Icon = 0, -- Icon in Topbar. Can use Lucide Icons (string) or Roblox Image (number). 0 to use no icon (default).
   LoadingTitle = "Pine Tree Buyer",
   LoadingSubtitle = "by t.me/qvrezikk",
   ShowText = "idk", -- for mobile users to unhide Rayfield, change if you'd like
   Theme = "Amethyst", -- Check https://docs.sirius.menu/rayfield/configuration/themes

   ToggleUIKeybind = "K", -- The keybind to toggle the UI visibility (string like "K" or Enum.KeyCode)

   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false, -- Prevents Rayfield from emitting warnings when the script has a version mismatch with the interface.

   -- ScriptID = "sid_xxxxxxxxxxxx", -- Your Script ID from developer.sirius.menu — enables analytics, managed keys, and script hosting

   ConfigurationSaving = {
      Enabled = false,
      FolderName = nil, -- Create a custom folder for your hub/game
      FileName = "Big Hub"
   },

   Discord = {
      Enabled = false, -- Prompt the user to join your Discord server if their executor supports it
      Invite = "noinvitelink", -- The Discord invite code, do not include Discord.gg/. E.g. Discord.gg/ABCD would be ABCD
      RememberJoins = true -- Set this to false to make them join the Discord every time they load it up
   },

   KeySystem = true, -- Set this to true to use our key system
   KeySettings = {
      Title = "hello",
      Subtitle = "Key System",
      Note = "KEY: t.me/qvrezikk", -- Use this to tell the user how to get a key
      FileName = "Key", -- It is recommended to use something unique, as other scripts using Rayfield may overwrite your key file
      SaveKey = true, -- The user's key will be saved, but if you change the key, they will be unable to use your script
      GrabKeyFromSite = false, -- If this is true, set Key below to the RAW site you would like Rayfield to get the key from
      Key = {"t.me/qvrezikk"} -- List of keys that the system will accept, can be RAW file links (pastebin, github, etc.) or simple strings ("hello", "key22")
   }
})

local Buyer = Window:CreateTab("Main", 4483362458) -- Title, Image
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
    Callback = function()
    end,
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
            inputAmount = amount -- сохраняем в переменную
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

local Button5 = Buyer:CreateButton({
   Name = "Buy 4 cookie wheels (500 Robux)",
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
