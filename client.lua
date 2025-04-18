local playerNames = {}
local newbiePlayers = {}
local streamedPlayers = {}
local nameThread = false
local myName = true
local namesVisible = true
local showID = false -- New variable to track ID visibility

local localPed = nil

local txd = CreateRuntimeTxd("adminsystem")
local tx = CreateRuntimeTextureFromImage(txd, "logo", "assets/logo.png")

-- Command to toggle All Nametags visibility
RegisterCommand("toggleallnames", function()
    setNamesVisible(not namesVisible)
end)

-- Command to toggle Your Nametag visibility
RegisterCommand("togglemyname", function()
    myName = not myName
end)

-- Command to toggle ID visibility
RegisterCommand("toggleid", function()
    showID = not showID
end)

AddEventHandler("esx_skin:playerRegistered", function()
    Wait(1000)
    TriggerServerEvent("requestPlayerNames")
end)

RegisterNetEvent("receivePlayerNames", function(names, newbies)
    playerNames = names
    newbiePlayers = newbies
end)

-- Detect when a player takes damage and send the damage state to the server
AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName == 'CEventNetworkEntityDamage' then
        local victim = data[1]
        local attacker = data[2]
        
        if IsEntityAPed(victim) and victim == PlayerPedId() then
            TriggerServerEvent("syncDamageState", true)
        end
    end
end)

-- Listen for damage state updates from the server
RegisterNetEvent("updateDamageState")
AddEventHandler("updateDamageState", function(serverId, isDamaged)
    if streamedPlayers[serverId] then
        streamedPlayers[serverId].isDamaged = isDamaged
        if isDamaged then
            streamedPlayers[serverId].damageTimer = GetGameTimer()
        end
    end
end)

function playerStreamer()
    while namesVisible do
        local adminPanel <const> = GetResourceState(ADMINPANEL_SCRIPT) == "started"
        streamedPlayers = {}
        localPed = PlayerPedId()

        local localCoords <const> = GetEntityCoords(localPed)
        local localId <const> = PlayerId()

        for _, player in pairs(GetActivePlayers()) do
            local playerPed <const> = GetPlayerPed(player)

            if player == localId and myName or player ~= localId then
                if DoesEntityExist(playerPed) and HasEntityClearLosToEntity(localPed, playerPed, 17) and IsEntityVisible(playerPed) then
                    local playerCoords = GetEntityCoords(playerPed)
                    if IsSphereVisible(playerCoords, 0.0099999998) then
                        local distance <const> = #(localCoords - playerCoords)

                        local serverId <const> = tonumber(GetPlayerServerId(player))
                        if serverId and distance <= STREAM_DISTANCE then
                            local adminDuty = adminPanel and exports[ADMINPANEL_SCRIPT]:isPlayerInAdminduty(serverId)

                            local isWearingMask = IsPedWearingMask(playerPed)
                            local label

                            if isWearingMask then
                                label = "Masked_"..math.random(100,1000)
                            else
                                label = (playerNames[serverId] or "")
                                if adminDuty then
                                    local adminLabel <const> = adminPanel and exports[ADMINPANEL_SCRIPT]:getPlayerAdminLabel(serverId) or 'Admin'
                                    label = GetPlayerName(player) .. ' <font color="' .. ADMIN_COLOR .. '">(' .. adminLabel .. ')</font>'
                                end
                                -- Conditionally append the ID to the label
                                if showID then
                                    label = label .. " (" .. serverId .. ")"
                                end
                            end

                            streamedPlayers[serverId] = {
                                playerId = player,
                                ped = playerPed,
                                label = label,
                                newbie = isNewbie(serverId),
                                talking = MumbleIsPlayerTalking(player) or NetworkIsPlayerTalking(player),
                                adminDuty = adminDuty,
                                isDamaged = streamedPlayers[serverId] and streamedPlayers[serverId].isDamaged or false,
                                damageTimer = streamedPlayers[serverId] and streamedPlayers[serverId].damageTimer or 0,
                            }
                        end
                    end
                end
            end
        end

        if next(streamedPlayers) and not nameThread then
            CreateThread(drawNames)
        end

        Wait(500)
    end

    streamedPlayers = {}
end
CreateThread(playerStreamer)

function drawNames()
    nameThread = true

    while next(streamedPlayers) do
        local myCoords <const> = GetEntityCoords(localPed)

        for serverId, playerData in pairs(streamedPlayers) do
            local coords <const> = getPedHeadCoords(playerData.ped)

            local dist <const> = #(coords - myCoords)
            local scale <const> = 1 - dist / STREAM_DISTANCE

            if scale > 0 then
                local newbieVisible <const> = (playerData.newbie and not playerData.adminDuty)

                -- Check if the player is damaged and set the text color to red
                local labelColor = { 255, 255, 255 }
                if playerData.isDamaged then
                    labelColor = { 255, 0, 0 }

                    -- Reset the damage flag after 3 seconds
                    if GetGameTimer() - playerData.damageTimer > 3000 then
                        playerData.isDamaged = false
                        TriggerServerEvent("syncDamageState", false) -- Notify the server to reset the damage state
                    end
                end

                DrawText3D(coords, {
                    { text = playerData.label, color = labelColor },
                    newbieVisible and {
                        text = NEWBIE_TEXT,
                        pos = { 0, -0.017 },
                        color = { 255, 150, 0 },
                        scale = 0.25,
                    } or nil,
                    playerData.talking and {
                        text = SPEAK_ICON,
                        pos = { 0, 0.025 },
                        scale = 0.4,
                    } or nil,
                }, scale, 200 * scale)

                if ADMINLOGO.visible and playerData.adminDuty then 
                    DrawMarker(
                        43,
                        coords + vector3(0, 0, 0.15),
                        vector3(0, 0, 0),
                        vector3(89.9, 180, 0),
                        vector3(scale * ADMINLOGO.size, scale * ADMINLOGO.size, 0),
                        255,
                        255,
                        255,
                        255,
                        false, --up-down anim
                        true, --face cam
                        0,
                        ADMINLOGO.rotate, --rotate
                        "adminsystem",
                        "logo",
                        false --[[drawon ents]]
                    )
                end
            end
        end

        Wait(0)
    end

    nameThread = false
end

function isNewbie(serverId)
    return (newbiePlayers[serverId] or 0) + NEWBIE_TIME > GetCloudTimeAsInt()
end

function setMyNameVisible(state)
    myName = state
end
exports("setMyNameVisible", setMyNameVisible)

function getMyNameVisible()
    return myName
end
exports("getMyNameVisible", getMyNameVisible)

function setNamesVisible(state)
    namesVisible = state
    if namesVisible then
        CreateThread(playerStreamer)
    end
end
exports("setNamesVisible", setNamesVisible)

exports("isNamesVisible", function()
    return namesVisible
end)

-- Function to detect if the player is wearing a mask
function IsPedWearingMask(ped)
    -- Masks are in clothes slot 1
    local maskIndex = GetPedDrawableVariation(ped, 1)
    return maskIndex > 0 -- Index 0 means no mask, >0 means mask is equipped
end
