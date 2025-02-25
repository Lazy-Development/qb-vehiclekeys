-----------------------
----   Variables   ----
-----------------------
local QBCore = exports['qb-core']:GetCoreObject()
local KeysList = {}

local isTakingKeys = false
local isCarjacking = false
local canCarjack = true
local AlertSend = false
local lastPickedVehicle = nil
local usingAdvanced = false
local IsHotwiring = false

VehicleClass = {
    [0] = 'compacts',
    [1] = 'sedans',
    [2] = 'suvs',
    [3] = 'coupes',
    [4] = 'muscle',
    [5] = 'sportclassics',
    [6] = 'sports',
    [7] = 'super',
    [8] = 'motorcycles',
    [9] = 'offroad',
    [10] = 'industrial',
    [11] = 'utility',
    [12] = 'vans',
    [13] = 'bicycles',
    [14] = 'boats',
    [15] = 'helicopters',
    [16] = 'planes',
    [17] = 'services',
    [18] = 'emergency',
    [19] = 'military',
    [20] = 'commercial',
    [21] = 'trains',
}

-----------------------
----   Threads     ----
-----------------------

CreateThread(function()
    while true do
        local sleep = 1000
        if LocalPlayer.state.isLoggedIn then
            sleep = 100

            local ped = PlayerPedId()
            local entering = GetVehiclePedIsTryingToEnter(ped)
            local carIsImmune = false
            if entering ~= 0 and not isBlacklistedVehicle(entering) then
                sleep = 2000
                local plate = QBCore.Functions.GetPlate(entering)

                local driver = GetPedInVehicleSeat(entering, -1)
                for _, veh in ipairs(Config.ImmuneVehicles) do
                    if GetEntityModel(entering) == joaat(veh) then
                        carIsImmune = true
                    end
                end
                -- Driven vehicle logic
                if driver ~= 0 and not IsPedAPlayer(driver) and not HasKeys(plate) and not carIsImmune then
                    if IsEntityDead(driver) then
                        if not isTakingKeys then
                            isTakingKeys = true

                            TriggerServerEvent('qb-vehiclekeys:server:setVehLockState',
                                NetworkGetNetworkIdFromEntity(entering), 1)
                            QBCore.Functions.Progressbar("steal_keys", Lang:t("progress.takekeys"), 2500, false, false,
                                {
                                    disableMovement = false,
                                    disableCarMovement = true,
                                    disableMouse = false,
                                    disableCombat = true
                                }, {}, {}, {}, function() -- Done
                                    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
                                    isTakingKeys = false
                                end, function()
                                isTakingKeys = false
                            end)
                        end
                    elseif Config.LockNPCDrivingCars then
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState',
                            NetworkGetNetworkIdFromEntity(entering), 2)
                    else
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState',
                            NetworkGetNetworkIdFromEntity(entering), 1)
                        TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)

                        --Make passengers flee
                        local pedsInVehicle = GetPedsInVehicle(entering)
                        for _, pedInVehicle in pairs(pedsInVehicle) do
                            if pedInVehicle ~= GetPedInVehicleSeat(entering, -1) then
                                MakePedFlee(pedInVehicle)
                            end
                        end
                    end
                    -- Parked car logic
                elseif driver == 0 and entering ~= lastPickedVehicle and not HasKeys(plate) and not isTakingKeys then
                    if Config.LockNPCParkedCars then
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState',
                            NetworkGetNetworkIdFromEntity(entering), 2)
                    else
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState',
                            NetworkGetNetworkIdFromEntity(entering), 1)
                    end
                end
            end

            -- Hotwiring while in vehicle, also keeps engine off for vehicles you don't own keys to
            if IsPedInAnyVehicle(ped, false) and not IsHotwiring then
                sleep = 1000
                local vehicle = GetVehiclePedIsIn(ped)
                local plate = QBCore.Functions.GetPlate(vehicle)

                if GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() and not HasKeys(plate) and
                    not isBlacklistedVehicle(vehicle) and not AreKeysJobShared(vehicle) then
                    sleep = 0
                    SetVehicleEngineOn(vehicle, false, false, true)
                end
            end

            if canCarjack then
                local playerid = PlayerId()
                local aiming, target = GetEntityPlayerIsFreeAimingAt(playerid)
                if aiming and (target ~= nil and target ~= 0) then
                    if DoesEntityExist(target) and IsPedInAnyVehicle(target, false) and not IsEntityDead(target) and
                        not IsPedAPlayer(target) then
                        local targetveh = GetVehiclePedIsIn(target)
                        for _, veh in ipairs(Config.ImmuneVehicles) do
                            if GetEntityModel(targetveh) == joaat(veh) then
                                carIsImmune = true
                            end
                        end
                        if GetPedInVehicleSeat(targetveh, -1) == target and not IsBlacklistedWeapon() then
                            local pos = GetEntityCoords(ped, true)
                            local targetpos = GetEntityCoords(target, true)
                            if #(pos - targetpos) < 5.0 and not carIsImmune then
                                CarjackVehicle(target)
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

function isBlacklistedVehicle(vehicle)
    local isBlacklisted = false
    for _, v in ipairs(Config.NoLockVehicles) do
        if GetHashKey(v) == GetEntityModel(vehicle) then
            isBlacklisted = true
            break;
        end
    end
    if Entity(vehicle).state.ignoreLocks or GetVehicleClass(vehicle) == 13 then isBlacklisted = true end
    return isBlacklisted
end

-----------------------
---- Client Events ----
-----------------------

RegisterKeyMapping('togglelocks', Lang:t("info.tlock"), 'keyboard', 'L')
RegisterCommand('togglelocks', function()
    ToggleVehicleLocks(GetVehicle())
end)

RegisterKeyMapping('engine', Lang:t("info.engine"), 'keyboard', 'G')
RegisterCommand('engine', function()
    TriggerEvent("qb-vehiclekeys:client:ToggleEngine")
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() and QBCore.Functions.GetPlayerData() ~= {} then
        GetKeys()
    end
end)

-- Handles state right when the player selects their character and location.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    GetKeys()
end)

-- Resets state on logout, in case of character change.
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    KeysList = {}
end)

RegisterNetEvent('qb-vehiclekeys:client:AddKeys', function(plate)
    KeysList[plate] = true

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped)
        local vehicleplate = QBCore.Functions.GetPlate(vehicle)

        if plate == vehicleplate then
            SetVehicleEngineOn(vehicle, false, false, false)
        end
    end
end)

RegisterNetEvent('qb-vehiclekeys:client:RemoveKeys', function(plate)
    KeysList[plate] = nil
end)

RegisterNetEvent('qb-vehiclekeys:client:ToggleEngine', function()
    local EngineOn = GetIsVehicleEngineRunning(GetVehiclePedIsIn(PlayerPedId()))
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), true)
    if HasKeys(QBCore.Functions.GetPlate(vehicle)) then
        if EngineOn then
            SetVehicleEngineOn(vehicle, false, false, true)
        else
            SetVehicleEngineOn(vehicle, true, false, true)
        end
    end
end)

RegisterNetEvent('qb-vehiclekeys:client:GiveKeys', function(id)
    local targetVehicle = GetVehicle()

    if targetVehicle then
        local targetPlate = QBCore.Functions.GetPlate(targetVehicle)
        if HasKeys(targetPlate) then
            if id and type(id) == "number" then -- Give keys to specific ID
                GiveKeys(id, targetPlate)
            else
                if IsPedSittingInVehicle(PlayerPedId(), targetVehicle) then -- Give keys to everyone in vehicle
                    local otherOccupants = GetOtherPlayersInVehicle(targetVehicle)
                    for p = 1, #otherOccupants do
                        TriggerServerEvent('qb-vehiclekeys:server:GiveVehicleKeys',
                            GetPlayerServerId(NetworkGetPlayerIndexFromPed(otherOccupants[p])), targetPlate)
                    end
                else -- Give keys to closest player
                    GiveKeys(GetPlayerServerId(QBCore.Functions.GetClosestPlayer()), targetPlate)
                end
            end
        else
            QBCore.Functions.Notify(Lang:t("notify.ydhk"), 'error')
        end
    end
end)

RegisterNetEvent('lockpicks:UseLockpick', function(isAdvanced)
    local vehicle = QBCore.Functions.GetClosestVehicle()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) and not IsHotwiring then
        local vehicleIn = GetVehiclePedIsIn(ped)
        if NeedHacking(vehicleIn) then
            return QBCore.Functions.Notify("You need to use another item to hotwire this vehicle", "error")
        end
        local plate = QBCore.Functions.GetPlate(vehicleIn)
        if GetPedInVehicleSeat(vehicleIn, -1) == PlayerPedId() and not HasKeys(plate) and
            not isBlacklistedVehicle(vehicle) and not AreKeysJobShared(vehicleIn) then
            Hotwire(vehicleIn, plate, false)
            SetVehicleEngineOn(vehicleIn, false, false, true)
        end
    else
        if vehicle == nil or vehicle == 0 then return end
        if NeedHacking(vehicle) then
            return QBCore.Functions.Notify("You need to use another item to unlock this vehicle", "error")
        end
        LockpickDoor(isAdvanced)
    end
end)

RegisterNetEvent("qb-vehiclekeys:client:useHack", function()
    local vehicle = QBCore.Functions.GetClosestVehicle()
    if vehicle == nil or vehicle == 0 then return end
    if IsPedInAnyVehicle(ped, false) and not IsHotwiring then
        local vehicleIn = GetVehiclePedIsIn(ped)
        if not NeedHacking(vehicleIn) then
            return QBCore.Functions.Notify("You need to use lockpick fool", "error")
        end
        local plate = QBCore.Functions.GetPlate(vehicleIn)
        if GetPedInVehicleSeat(vehicleIn, -1) == PlayerPedId() and not HasKeys(plate) and
            not isBlacklistedVehicle(vehicle) and not AreKeysJobShared(vehicleIn) then
            Hotwire(vehicleIn, plate, true)
            SetVehicleEngineOn(vehicleIn, false, false, true)
        end
    else
        if vehicle == nil or vehicle == 0 then return end
        if not NeedHacking(vehicle) then
            return QBCore.Functions.Notify("You need to use lockpick fool", "error")
        end
        HackDoor()
    end
    -- if not NeedHacking(vehicle) then
    --     return QBCore.Functions.Notify("You need to use lockpick fool", "error")
    -- end
    -- HackDoor()
end)


-- Backwards Compatibility ONLY -- Remove at some point --
RegisterNetEvent('vehiclekeys:client:SetOwner', function(plate)
    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
end)
-- Backwards Compatibility ONLY -- Remove at some point --

-----------------------
----   Functions   ----
-----------------------

function GiveKeys(id, plate)
    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(GetPlayerPed(GetPlayerFromServerId(id))))
    if distance < 1.5 and distance > 0.0 then
        TriggerServerEvent('qb-vehiclekeys:server:GiveVehicleKeys', id, plate)
    else
        QBCore.Functions.Notify(Lang:t("notify.nonear"), 'error')
    end
end

function GetKeys()
    QBCore.Functions.TriggerCallback('qb-vehiclekeys:server:GetVehicleKeys', function(keysList)
        KeysList = keysList
    end)
end

function HasKeys(plate)
    return KeysList[plate]
end

exports('HasKeys', HasKeys)

function loadAnimDict(dict)
    while (not HasAnimDictLoaded(dict)) do
        RequestAnimDict(dict)
        Wait(0)
    end
end

function GetVehicleInDirection(coordFromOffset, coordToOffset)
    local ped = PlayerPedId()
    local coordFrom = GetOffsetFromEntityInWorldCoords(ped, coordFromOffset.x, coordFromOffset.y, coordFromOffset.z)
    local coordTo = GetOffsetFromEntityInWorldCoords(ped, coordToOffset.x, coordToOffset.y, coordToOffset.z)

    local rayHandle = CastRayPointToPoint(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 10,
        PlayerPedId(), 0)
    local _, _, _, _, vehicle = GetShapeTestResult(rayHandle)
    return vehicle
end

-- If in vehicle returns that, otherwise tries 3 different raycasts to get the vehicle they are facing.
-- Raycasts picture: https://i.imgur.com/FRED0kV.png
function GetVehicle()
    local vehicle = GetVehiclePedIsIn(PlayerPedId())

    local RaycastOffsetTable = {
        { ['fromOffset'] = vector3(0.0, 0.0, 0.0), ['toOffset'] = vector3(0.0, 20.0, -10.0) }, -- Waist to ground 45 degree angle
        { ['fromOffset'] = vector3(0.0, 0.0, 0.7), ['toOffset'] = vector3(0.0, 10.0, -10.0) }, -- Head to ground 30 degree angle
        { ['fromOffset'] = vector3(0.0, 0.0, 0.7), ['toOffset'] = vector3(0.0, 10.0, -20.0) }, -- Head to ground 15 degree angle
    }

    local count = 0
    while vehicle == 0 and count < #RaycastOffsetTable do
        count = count + 1
        vehicle = GetVehicleInDirection(RaycastOffsetTable[count]['fromOffset'], RaycastOffsetTable[count]['toOffset'])
    end

    if not IsEntityAVehicle(vehicle) then vehicle = nil end
    return vehicle
end

function AreKeysJobShared(veh)
    local vehName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local vehPlate = GetVehicleNumberPlateText(veh)
    local jobName = QBCore.Functions.GetPlayerData().job.name
    local onDuty = QBCore.Functions.GetPlayerData().job.onduty
    for job, v in pairs(Config.SharedKeys) do
        if job == jobName then
            if Config.SharedKeys[job].requireOnduty and not onDuty then return false end
            for _, vehicle in pairs(v.vehicles) do
                if string.upper(vehicle) == vehName then
                    if not HasKeys(vehPlate) then
                        TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", vehPlate)
                    end
                    return true
                end
            end
        end
    end
    return false
end

function ToggleVehicleLocks(veh)
    if veh then
        if not isBlacklistedVehicle(veh) then
            if HasKeys(QBCore.Functions.GetPlate(veh)) or AreKeysJobShared(veh) then
                local ped = PlayerPedId()
                local vehLockStatus = GetVehicleDoorLockStatus(veh)

                loadAnimDict("anim@mp_player_intmenu@key_fob@")
                TaskPlayAnim(ped, 'anim@mp_player_intmenu@key_fob@', 'fob_click', 3.0, 3.0, -1, 49, 0, false, false,
                    false)

                TriggerServerEvent("InteractSound_SV:PlayWithinDistance", 5, "lock", 0.3)

                NetworkRequestControlOfEntity(veh)
                if vehLockStatus == 1 then
                    TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(veh), 2)
                    QBCore.Functions.Notify(Lang:t("notify.vlock"), "primary")
                else
                    TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(veh), 1)
                    QBCore.Functions.Notify(Lang:t("notify.vunlock"), "success")
                end

                SetVehicleLights(veh, 2)
                Wait(250)
                SetVehicleLights(veh, 1)
                Wait(200)
                SetVehicleLights(veh, 0)
                Wait(300)
                ClearPedTasks(ped)
            else
                QBCore.Functions.Notify(Lang:t("notify.ydhk"), 'error')
            end
        else
            TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(veh), 1)
        end
    end
end

function GetOtherPlayersInVehicle(vehicle)
    local otherPeds = {}
    for seat = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
        local pedInSeat = GetPedInVehicleSeat(vehicle, seat)
        if IsPedAPlayer(pedInSeat) and pedInSeat ~= PlayerPedId() then
            otherPeds[#otherPeds + 1] = pedInSeat
        end
    end
    return otherPeds
end

function GetPedsInVehicle(vehicle)
    local otherPeds = {}
    for seat = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
        local pedInSeat = GetPedInVehicleSeat(vehicle, seat)
        if not IsPedAPlayer(pedInSeat) and pedInSeat ~= 0 then
            otherPeds[#otherPeds + 1] = pedInSeat
        end
    end
    return otherPeds
end

function IsBlacklistedWeapon()
    local weapon = GetSelectedPedWeapon(PlayerPedId())
    if weapon ~= nil then
        for _, v in pairs(Config.NoCarjackWeapons) do
            if weapon == GetHashKey(v) then
                return true
            end
        end
    end
    return false
end

function HackDoor()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local vehicle = QBCore.Functions.GetClosestVehicle()
    if vehicle == nil or vehicle == 0 then return end
    if HasKeys(QBCore.Functions.GetPlate(vehicle)) then return end
    if #(pos - GetEntityCoords(vehicle)) > 2.5 then return end
    if GetVehicleDoorLockStatus(vehicle) <= 0 then return end
    StartHackingMinigame()
end

function LockpickDoor(isAdvanced)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local vehicle = QBCore.Functions.GetClosestVehicle()
    if vehicle == nil or vehicle == 0 then return end
    if HasKeys(QBCore.Functions.GetPlate(vehicle)) then return end
    if #(pos - GetEntityCoords(vehicle)) > 2.5 then return end
    if GetVehicleDoorLockStatus(vehicle) <= 0 then return end
    usingAdvanced = isAdvanced
    StartLockpicking()
end

function StartHackingMinigame()
    local dict = "amb@medic@standing@kneel@idle_a"
    local anim = "idle_c"
    loadAnimDict(dict)
    TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, 8.0, -1, 1, 0)
    exports['ps-ui']:Scrambler(function(success)
        StopAnimTask(PlayerPedId(), dict, anim, 1.0)
        return HackingFinishCallback(success)
    end, "numeric", 30, 0) -- Type (alphabet, numeric, alphanumeric, greek, braille, runes), Time (Seconds), Mirrored (0: Normal, 1: Normal + Mirrored 2: Mirrored only )
end

function StartLockpicking()
    local animstart = true

    CreateThread(function()
        while animstart do
            loadAnimDict("veh@break_in@0h@p_m_one@")
            TaskPlayAnim(PlayerPedId(), "veh@break_in@0h@p_m_one@", "low_force_entry_ds", 3.0, 3.0, 10000, 16, 0, false,
                false, false)
            Wait(1000)
        end
    end)
    exports['ps-ui']:Circle(function(success)
        animstart = false
        StopAnimTask(PlayerPedId(), "veh@break_in@0h@p_m_one@", "low_force_entry_ds", 1.0)
        return LockpickFinishCallback(success)
    end, 5, 20) -- NumberOfCircles, MS
end

function LockpickFinishCallback(success)
    local vehicle = QBCore.Functions.GetClosestVehicle()
    local chance = math.random()
    if success then
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        lastPickedVehicle = vehicle

        if GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', QBCore.Functions.GetPlate(vehicle))
        else

            QBCore.Functions.Notify(Lang:t("notify.vlockpick"), 'success')
            TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(vehicle), 1)
        end
    else
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        AttemptPoliceAlert("steal")
    end

    if usingAdvanced then
        if chance <= Config.RemoveLockpickAdvanced then
            TriggerServerEvent("qb-vehiclekeys:server:breakLockpick", "advancedlockpick")
        end
    else
        if chance <= Config.RemoveLockpickNormal then
            TriggerServerEvent("qb-vehiclekeys:server:breakLockpick", "lockpick")
        end
    end
end

function HackingFinishCallback(success)
    local vehicle = QBCore.Functions.GetClosestVehicle()
    if success then
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        lastPickedVehicle = vehicle
        if GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', QBCore.Functions.GetPlate(vehicle))
        else
            QBCore.Functions.Notify(Lang:t("notify.vhacked"), 'success')
            TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(vehicle), 1)
        end
    else
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        AttemptPoliceAlert("steal")
    end
end

function Hotwire(vehicle, plate, hacking)
    local hotwireTime = math.random(Config.minHotwireTime, Config.maxHotwireTime)
    local ped = PlayerPedId()
    local dict = "amb@medic@standing@kneel@idle_a"
    local anim = "idle_c"
    IsHotwiring = true
    SetVehicleAlarm(vehicle, true)
    SetVehicleAlarmTimeLeft(vehicle, hotwireTime)
    TaskPlayAnim(ped, dict, anim, 8.0, 8.0, -1, 1, 0)
    if hacking then
        local success = false
        exports['ps-ui']:Scrambler(function(scd)
            StopAnimTask(ped, dict, anim)
            success = scd
        end, "numeric", 50, 1)
        if success then
            goto sc
        else
            return QBCore.Functions.Notify(Lang:t("notify.fvlockpick"), "error")
        end
    else
        local success = false
        exports['ps-ui']:Circle(function(scd)
            StopAnimTask(ped, dict, anim)
            success = scd
        end, 15, 20) -- NumberOfCircles, MS

        if success then
            goto sc
        else
            return QBCore.Functions.Notify(Lang:t("notify.fvlockpick"), "error")
        end
    end

    ::sc::
    TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
    IsHotwiring = false

end

function CarjackVehicle(target)
    isCarjacking = true
    canCarjack = false

    loadAnimDict('mp_am_hold_up')

    local vehicle = GetVehiclePedIsUsing(target)
    local occupants = GetPedsInVehicle(vehicle)
    for p = 1, #occupants do
        local ped = occupants[p]
        CreateThread(function()
            TaskPlayAnim(ped, "mp_am_hold_up", "holdup_victim_20s", 8.0, -8.0, -1, 49, 0, false, false, false)
            PlayPain(ped, 6, 0)
        end)
        Wait(math.random(200, 500))
    end

    -- Cancel progress bar if: Ped dies during robbery, car gets too far away
    CreateThread(function()
        while isCarjacking do
            local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(target))
            if IsPedDeadOrDying(target) or distance > 7.5 then
                TriggerEvent("progressbar:client:cancel")
            end
            Wait(100)
        end
    end)

    QBCore.Functions.Progressbar("rob_keys", Lang:t("progress.acjack"), Config.CarjackingTime, false, true, {}, {}, {},
        {}, function()
            local hasWeapon, weaponHash = GetCurrentPedWeapon(PlayerPedId(), true)
            if hasWeapon and isCarjacking then

                local carjackChance
                if Config.CarjackChance[tostring(GetWeapontypeGroup(weaponHash))] then
                    carjackChance = Config.CarjackChance[tostring(GetWeapontypeGroup(weaponHash))]
                else
                    carjackChance = 0.5
                end

                if math.random() <= carjackChance then
                    local plate = QBCore.Functions.GetPlate(vehicle)

                    for p = 1, #occupants do
                        local ped = occupants[p]
                        CreateThread(function()
                            TaskLeaveVehicle(ped, vehicle, 0)
                            PlayPain(ped, 6, 0)
                            Wait(1250)
                            ClearPedTasksImmediately(ped)
                            PlayPain(ped, math.random(7, 8), 0)
                            MakePedFlee(ped)
                        end)
                    end
                    TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
                    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
                else
                    QBCore.Functions.Notify(Lang:t("notify.cjackfail"), "error")
                    MakePedFlee(target)
                    TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
                end
                isCarjacking = false
                Wait(2000)
                AttemptPoliceAlert("carjack")
                Wait(Config.DelayBetweenCarjackings)
                canCarjack = true
            end
        end, function()
        MakePedFlee(target)
        isCarjacking = false
        Wait(Config.DelayBetweenCarjackings)
        canCarjack = true
    end)
end

function AttemptPoliceAlert(type)
    if not AlertSend then
        local chance = Config.PoliceAlertChance
        if GetClockHours() >= 1 and GetClockHours() <= 6 then
            chance = Config.PoliceNightAlertChance
        end
        if math.random() <= chance then
            TriggerServerEvent('police:server:policeAlert', Lang:t("info.palert") .. type)
        end
        AlertSend = true
        SetTimeout(Config.AlertCooldown, function()
            AlertSend = false
        end)
    end
end

function MakePedFlee(ped)
    SetPedFleeAttributes(ped, 0, 0)
    TaskReactAndFleePed(ped, PlayerPedId())
end

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

-- NEW SHIT
function NeedHacking(vehicle)
    local needhacking = false
    local vehClass = VehicleClass[GetVehicleClass(vehicle)]
    local vehModel = GetEntityModel(vehicle)
    local vehName2 = GetDisplayNameFromVehicleModel(vehModel)
    local vehName = vehName2:lower()
    for i = 1, #Config.HackingVehicle["name"] do
        if vehName == Config.HackingVehicle["name"][i] then
            needhacking = true
            goto skip
        end
    end
    for i = 1, #Config.HackingVehicle['vehicle_class'] do
        if vehClass == Config.HackingVehicle['vehicle_class'][i] then
            needhacking = true
            goto skip
        end
    end
    for i = 1, #Config.HackingVehicle["brand"] do
        if QBCore.Shared.Vehicles[vehName]["brand"]:lower() == Config.HackingVehicle["brand"][i]:lower() then
            needhacking = true
            goto skip
        end
    end
    ::skip::
    return needhacking
end
