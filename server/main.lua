-- Variables
local coin = Crypto.Coin
local LS_CORE = exports['ls-core']:GetCoreObject()
local bannedCharacters = {'%','$',';'}

-- Function
local function RefreshCrypto()
    local result = LS_CORE.Config.DATABASE(LS_CORE.Config.DATABASE_NAME, 'fetchAll', 'SELECT * FROM crypto WHERE crypto = ?', { coin })
    if result ~= nil and result[1] ~= nil then
        Crypto.Worth[coin] = result[1].worth
        if result[1].history ~= nil then
            Crypto.History[coin] = json.decode(result[1].history)
            TriggerClientEvent('ls-crypto:client:UpdateCryptoWorth', -1, coin, result[1].worth, json.decode(result[1].history))
        else
            TriggerClientEvent('ls-crypto:client:UpdateCryptoWorth', -1, coin, result[1].worth, nil)
        end
    end
end

local function ErrorHandle(error)
    for k, v in pairs(Ticker.Error_handle) do
        if string.match(error, k) then
            return v
        end
    end
    return false
end

local function GetTickerPrice() -- Touch = no help
    local ticker_promise = promise.new()
    PerformHttpRequest("https://min-api.cryptocompare.com/data/price?fsym=" .. Ticker.coin .. "&tsyms=" .. Ticker.currency .. '&api_key=' .. Ticker.Api_key, function(Error, Result, _)
        local result_obj = json.decode(Result)
        if not result_obj['Response'] then
            local this_resolve = {error =  Error, response_data = result_obj[string.upper(Ticker.currency)]}
            ticker_promise:resolve(this_resolve) --- Could resolve Error aswell for more accurate Error messages? Solved in else
        else
            local this_resolve = {error =  result_obj['Message']}
            ticker_promise:resolve(this_resolve)
        end
    end, 'GET')
    Citizen.Await(ticker_promise)
    if type(ticker_promise.value.error) ~= 'number' then
        local get_user_friendly_error = ErrorHandle(ticker_promise.value.error)
        if get_user_friendly_error then
            return get_user_friendly_error
        else
            return '\27[31m Unexpected error \27[0m' --- Raised an error which we did not expect, script should be capable of sticking with last recorded price and shutting down the sync logic
        end
    else
        return ticker_promise.value.response_data
    end
end

local function HandlePriceChance()
    local currentValue = Crypto.Worth[coin]
    local prevValue = Crypto.Worth[coin]
    local trend = math.random(0,100)
    local event = math.random(0,100)
    local chance = event - Crypto.ChanceOfCrashOrLuck

    if event > chance then
        if trend <= Crypto.ChanceOfDown then
            currentValue = currentValue - math.random(Crypto.CasualDown[1], Crypto.CasualDown[2])
        elseif trend >= Crypto.ChanceOfUp then
            currentValue = currentValue + math.random(Crypto.CasualUp[1], Crypto.CasualUp[2])
        end
    else
        if math.random(0, 1) == 1 then
            currentValue = currentValue + math.random(Crypto.Luck[1], Crypto.Luck[2])
        else
            currentValue = currentValue - math.random(Crypto.Crash[1], Crypto.Crash[2])
        end
    end

    if currentValue <= Crypto.Lower then
        currentValue = Crypto.Lower
    elseif currentValue >= Crypto.Upper then
        currentValue = Crypto.Upper
    end

    if Crypto.History[coin][4] then
        -- Shift array index 1 to 3
        for k=3,1,-1 do
            Crypto.History[coin][k] = Crypto.History[coin][k+1]
        end
        -- Assign array index 4 to the latest result
        Crypto.History[coin][4] = {PreviousWorth = prevValue, NewWorth = currentValue}
    else
        Crypto.History[coin][#Crypto.History[coin] + 1] = {PreviousWorth = prevValue, NewWorth = currentValue}
    end

    Crypto.Worth[coin] = currentValue

    local history = json.encode(Crypto.History[coin])
    local props = {
        ['worth'] = currentValue,
        ['history'] = history,
        ['crypto'] = coin
    }
    LS_CORE.Config.DATABASE( LS_CORE.Config.DATABASE_NAME, 'execute',
        'UPDATE crypto set worth = :worth, history = :history where crypto = :crypto',
        props,
        function(affectedRows)
            if affectedRows < 1 then
                print("Crypto not found, inserting new record for " .. coin)
                LS_CORE.Config.DATABASE( LS_CORE.Config.DATABASE_NAME, 'execute', 'INSERT INTO crypto (crypto, worth, history) VALUES (:crypto, :worth, :history)', props)
            end
            RefreshCrypto()
        end
    )
end

-- Events

RegisterServerEvent('ls-crypto:server:FetchWorth', function()
    for name,_ in pairs(Crypto.Worth) do
        local result = LS_CORE.Config.DATABASE(LS_CORE.Config.DATABASE_NAME, 'fetchAll', 'SELECT * FROM crypto WHERE crypto = ?', { name })
        if result[1] ~= nil then
            Crypto.Worth[name] = result[1].worth
            if result[1].history ~= nil then
                Crypto.History[name] = json.decode(result[1].history)
                TriggerClientEvent('ls-crypto:client:UpdateCryptoWorth', -1, name, result[1].worth, json.decode(result[1].history))
            else
                TriggerClientEvent('ls-crypto:client:UpdateCryptoWorth', -1, name, result[1].worth, nil)
            end
        end
    end
end)

RegisterServerEvent('ls-crypto:server:Rebooting', function(state, percentage)
    Crypto.Exchange.RebootInfo.state = state
    Crypto.Exchange.RebootInfo.percentage = percentage
end)

RegisterServerEvent('ls-crypto:server:GetRebootState', function()
    local src = source
    TriggerClientEvent('ls-crypto:client:GetRebootState', src, Crypto.Exchange.RebootInfo)
end)

RegisterServerEvent('ls-crypto:server:SyncReboot', function()
    TriggerClientEvent('ls-crypto:client:SyncReboot', -1)
end)

-- Callbacks

LS_CORE.Callback.Functions.CreateCallback('ls-crypto:server:GetCryptoData', function(source, cb, name)
    local Player = LS_CORE.Functions.GetPlayer(source)
    local CryptoData = {
        History = Crypto.History[name],
        Worth = Crypto.Worth[name],
        Portfolio = Player.Functions.GetPlayerMoney("crypto"),
        WalletId = Player.DATA.walletid,
    }

    cb(CryptoData)
end)

LS_CORE.Callback.Functions.CreateCallback('ls-crypto:server:BuyCrypto', function(source, cb, data)
    local Player = LS_CORE.Functions.GetPlayer(source)
    local total_price = math.floor(tonumber(data.Coins) * tonumber(Crypto.Worth["qbit"]))
    local cryptoAmount = Player.Functions.GetPlayerMoney("crypto") 
    
    if Player.Functions.GetPlayerMoney("bank")  >= total_price then
        local CryptoData = {
            History = Crypto.History["qbit"],
            Worth = Crypto.Worth["qbit"],
            Portfolio = cryptoAmount + tonumber(data.Coins),
            WalletId = Player.DATA.walletid,
        }
        Player.Functions.RemoveMoney('bank', total_price)
        TriggerClientEvent('qb-phone:client:AddTransaction', source, Player, data, "You have "..tonumber(data.Coins).." Qbit('s) purchased!", "Credit")
        Player.Functions.AddMoney('crypto', tonumber(data.Coins))
        cb(CryptoData)
    else
        cb(false)
    end
end)

LS_CORE.Callback.Functions.CreateCallback('ls-crypto:server:SellCrypto', function(source, cb, data)
    local Player = LS_CORE.Functions.GetPlayer(source)
    local cryptoAmount = Player.Functions.GetPlayerMoney("crypto") 

    if cryptoAmount >= tonumber(data.Coins) then
        local CryptoData = {
            History = Crypto.History["qbit"],
            Worth = Crypto.Worth["qbit"],
            Portfolio = cryptoAmount - tonumber(data.Coins),
            WalletId = Player.DATA.walletid,
        }
        Player.Functions.RemoveMoney('crypto', tonumber(data.Coins))
        local amount = math.floor(tonumber(data.Coins) * tonumber(Crypto.Worth["qbit"]))
        TriggerClientEvent('qb-phone:client:AddTransaction', source, Player, data, "You have "..tonumber(data.Coins).." Qbit('s) sold!", "Depreciation")
        Player.Functions.AddMoney('bank', amount)
        cb(CryptoData)
    else
        cb(false)
    end
end)

LS_CORE.Callback.Functions.CreateCallback('ls-crypto:server:TransferCrypto', function(source, cb, data)
    local newCoin = tostring(data.Coins)
    local newWalletId = tostring(data.WalletId)
    for _, v in pairs(bannedCharacters) do
        newCoin = string.gsub(newCoin, '%' .. v, '')
        newWalletId = string.gsub(newWalletId, '%' .. v, '')
    end
    data.WalletId = newWalletId
    data.Coins = tonumber(newCoin)
    local Player = LS_CORE.Functions.GetPlayer(source)
    local cryptoAmount = Player.Functions.GetPlayerMoney("crypto") 
    if cryptoAmount >= tonumber(data.Coins) then
        local query = '%"walletid":"' .. data.WalletId .. '"%'
        local result = LS_CORE.Config.DATABASE(LS_CORE.Config.DATABASE_NAME, 'fetchAll', 'SELECT * FROM `players` WHERE `metadata` LIKE ?', { query })
        if result[1] ~= nil then
            local CryptoData = {
                History = Crypto.History["qbit"],
                Worth = Crypto.Worth["qbit"],
                Portfolio = cryptoAmount - tonumber(data.Coins),
                WalletId = Player.DATA.walletid,
            }
            Player.Functions.RemoveMoney('crypto', tonumber(data.Coins))
            TriggerClientEvent('qb-phone:client:AddTransaction', source, Player, data, "You have "..tonumber(data.Coins).." Qbit('s) transferred!", "Depreciation")
            local Target = LS_CORE.Functions.GetIdentifier(result[1].citizenid)

            if Target ~= nil then
                Target.Functions.AddMoney('crypto', tonumber(data.Coins))
                TriggerClientEvent('qb-phone:client:AddTransaction', Target.PlayerData.source, Player, data, "There are "..tonumber(data.Coins).." Qbit('s) credited!", "Credit")
            else
                local MoneyData = json.decode(result[1].money)
                MoneyData.crypto = MoneyData.crypto + tonumber(data.Coins)
                LS_CORE.Config.DATABASE( LS_CORE.Config.DATABASE_NAME, 'execute', 'UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(MoneyData), result[1].citizenid })
            end
            cb(CryptoData)
        else
            cb("notvalid")
        end
    else
        cb("notenough")
    end
end)

-- Threads

CreateThread(function()
    while true do
        Wait(Crypto.RefreshTimer*60000)
        HandlePriceChance()
    end
end)

-- You touch = you break
if Ticker.Enabled then
    Citizen.CreateThread(function()
        local Interval = Ticker.tick_time * 60000
        if Ticker.tick_time < 2 then
            Interval = 120000
        end
        while(true) do
            local get_coin_price = GetTickerPrice()
            if type(get_coin_price) == 'number' then
                Crypto.Worth["qbit"] = get_coin_price
            else
                print('\27[31m' .. get_coin_price .. '\27[0m')
                Ticker.Enabled = false
                break
            end
            Citizen.Wait(Interval)
        end
    end)
end

RegisterCommand("givephone", function(src)
    local Player = LS_CORE.Functions.GetPlayer(src)

    print(json.encode(Player.DATA))
    --exports["ls-phone"]:GivePhoneToPlayer(src)
end)
