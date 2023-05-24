-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local requiredItemsShowed = false
local requiredItems = {[1] = {name = QBCore.Shared.Items["cryptostick"]["name"], image = QBCore.Shared.Items["cryptostick"]["image"]}}

-- Functions

local function DrawText3Ds(coords, text)
	SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0+0.0125, 0.017+ factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

local function SystemCrashCooldown()
	CreateThread(function()
		while Crypto.Exchange.RebootInfo.state do
			if (Crypto.Exchange.RebootInfo.percentage + 1) <= 100 then
				Crypto.Exchange.RebootInfo.percentage = Crypto.Exchange.RebootInfo.percentage + 1
				TriggerServerEvent('ls-crypto:server:Rebooting', true, Crypto.Exchange.RebootInfo.percentage)
			else
				Crypto.Exchange.RebootInfo.percentage = 0
				Crypto.Exchange.RebootInfo.state = false
				TriggerServerEvent('ls-crypto:server:Rebooting', false, 0)
			end
			Wait(1200)
		end
	end)
end

-- Events

RegisterNetEvent('ls-crypto:client:SyncReboot', function()
	Crypto.Exchange.RebootInfo.state = true
	SystemCrashCooldown()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
	TriggerServerEvent('ls-crypto:server:FetchWorth')
	TriggerServerEvent('ls-crypto:server:GetRebootState')
end)

RegisterNetEvent('ls-crypto:client:UpdateCryptoWorth', function(crypto, amount, history)
	Crypto.Worth[crypto] = amount
	if history ~= nil then
		Crypto.History[crypto] = history
	end
end)

RegisterNetEvent('ls-crypto:client:GetRebootState', function(RebootInfo)
	if RebootInfo.state then
		Crypto.Exchange.RebootInfo.state = RebootInfo.state
		Crypto.Exchange.RebootInfo.percentage = RebootInfo.percentage
		SystemCrashCooldown()
	end
end)
