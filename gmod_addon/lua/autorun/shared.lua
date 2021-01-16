AddCSLuaFile()
resource.AddFile("materials/mute-icon.png")

if (CLIENT) then
	local drawMute = false
	local muteIcon = Material("materials/mute-icon.png")

	net.Receive("drawMute", function()
		drawMute = net.ReadBool()
	end)

	hook.Add("HUDPaint", "ttt_discord_bot_HUDPaint", function()
		if drawMute then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(muteIcon)
			surface.DrawTexturedRect(0, 0, 128, 128)
		end
	end)

	return
end

util.AddNetworkString("drawMute")
CreateConVar("discordbot_host", "localhost", FCVAR_ARCHIVE, "Sets the node server address.")
CreateConVar("discordbot_unmute_time", "0", FCVAR_ARCHIVE, "How long in seconds a mute lasts. 0 for until new round.")
CreateConVar("discordbot_enabled", "1", FCVAR_ARCHIVE, "Enable the discord bot.")
CreateConVar("discordbot_allow_player_unmutes", "1", FCVAR_ARCHIVE, "Allow players to unmute themselves with '!discord unmute'.")
CreateConVar("discordbot_port", "37405", FCVAR_ARCHIVE, "Sets the node server port.")
CreateConVar("discordbot_name", "TTT Discord Bot", FCVAR_ARCHIVE, "Sets the Plugin Prefix for helpermessages.") --The name which will be displayed in front of any Message
FILEPATH = "ttt_discord_bot.dat"
TRIES = 3
RETRY = false
ids = {}
num = 0
ids_raw = file.Read(FILEPATH, "DATA")

if (ids_raw) then
	ids = util.JSONToTable(ids_raw)
end

function saveIDs()
	file.Write(FILEPATH, util.TableToJSON(ids))
end


function timestamp() 
	return os.date("[%H:%M:%S] ")
end

function GET(req, params, cb, tries)
    if not GetConVar("discordbot_enabled"):GetBool() then
        return
    end
	httpAdress = ("http://" .. GetConVar("discordbot_host"):GetString() .. ":" .. GetConVar("discordbot_port"):GetString())
	params["num"] = num
	num = num + 1
	http.Fetch(httpAdress, function(res)
		--print(res)
		cb(util.JSONToTable(res))
	end, function(err)
		print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Request to bot failed. Is the bot running?")
		print("Err: " .. err)

		if (not tries) then
			tries = TRIES
		end

		if (tries ~= 0 and RETRY) then
			print("Retrying")
			GET(req, params, cb, tries - 1)
		end
	end, {
		req = req,
		params = util.TableToJSON(params)
	})
end

function sendClientIconInfo(ply, mute)
	if not ply then
		return
	end
	net.Start("drawMute")
	net.WriteBool(mute)
	net.Send(ply)
end

function updateIcon(ply)
    -- print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Requesting status for player " .. ply:GetName())
    if not ply then
        return
    end
	GET("state", {
		id = ids[ply:SteamID()]
	}, function(res)
		if (res) then
			--PrintTable(res)
			if (res.success) then
				sendClientIconInfo(ply, res.muted)
			end

			if (res.error) then
				print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Error on status: " .. res.error)
			end  
		end
	end)
end


function mute(ply)
	if ids[ply:SteamID()] then
		print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Requesting mute for: " .. ply:GetName())
		sendClientIconInfo(ply, true)
		GET("mute", {
			mute = true,
			id = ids[ply:SteamID()]
		}, function(res)
			if (res) then
				--PrintTable(res)
				if (res.success) then
					-- ply:PrintMessage(HUD_PRINTCENTER, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "You're muted in discord!")
					updateIcon(ply)
				end

				if (res.error) then
					ply:PrintMessage(HUD_PRINTCENTER, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Mute failed: " .. res.error)
					print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Error: " .. res.error)
				end
			end
		end)
		mute_time = tonumber(GetConVar("discordbot_unmute_time"):GetString())
		if mute_time ~= 0 then
			timer.Create("unmute " .. ply:GetName(), mute_time, 1, function ()
				unmute(ply)
			end)
		end
	end
end

function unmute(ply, reason)
    if not GetConVar("discordbot_enabled"):GetBool() then
        return
    end
	sendClientIconInfo(ply, false)
	if not reason then
		reason = "none"
	end
	if (ply) then
		if ids[ply:SteamID()] then
			print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Requesting unmute for: " .. ply:GetName())
			GET("mute", {
				mute = false,
				id = ids[ply:SteamID()],
				reason = reason
			}, function(res)
				if (res.success) then
					if (ply) then
						-- ply:PrintMessage(HUD_PRINTCENTER, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "You're no longer muted in discord!")
					end

					updateIcon(ply)
				end

				if (res.error) then
					ply:PrintMessage(HUD_PRINTCENTER, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Unmute failed: " .. res.error)
					print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Error: " .. res.error)
				end
			end)
		end
	else
		for key, ply in pairs(player.GetAll()) do
			unmute(ply, reason)
		end
	end
end

function commonRoundState()
	if gmod.GetGamemode().Name == "Trouble in Terrorist Town" or gmod.GetGamemode().Name == "TTT2 (Advanced Update)" then return ((GetRoundState() == 3) and 1 or 0) end -- Round state 3 => Game is running
	if gmod.GetGamemode().Name == "Murder" then return ((gmod.GetGamemode():GetRound() == 1) and 1 or 0) end -- Round state 1 => Game is running
	-- Round state could not be determined

	return -1
end

hook.Add("PlayerSay", "ttt_discord_bot_PlayerSay", function(ply, msg)
    if not GetConVar("discordbot_enabled"):GetBool() then
        return
    end
    -- TODO: Allow players to unmute themselves
    if (string.sub(msg, 1, 9) ~= '!discord ') then return end
    if (string.sub(msg, 10, 6) ~= 'unmute') then
        if GetConVar("discordbot_allow_player_unmutes"):GetBool() then
            unmute(ply, "Player requested unmute")
        else
			ply:PrintMessage(HUD_PRINTTALK, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "This ability is currently disabled by the host.")
        end
        return
    end
	tag = string.sub(msg, 10)
	tag_utf8 = ""

	for p, c in utf8.codes(tag) do
		tag_utf8 = string.Trim(tag_utf8 .. " " .. c)
	end
	print("[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Requesting connection for: " .. ply:GetName())
	GET("connect", {
		tag = tag_utf8
	}, function(res)
		if (res.answer == 0) then
			ply:PrintMessage(HUD_PRINTTALK, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "No guilde member with a discord tag like '" .. tag .. "' found.")
		end

		if (res.answer == 1) then
			ply:PrintMessage(HUD_PRINTTALK, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Found more than one user with a discord tag like '" .. tag .. "'. Please specify!")
		end

		if (res.tag and res.id) then
			ply:PrintMessage(HUD_PRINTTALK, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "Discord tag '" .. res.tag .. "' successfully boundet to SteamID '" .. ply:SteamID() .. "'") --lie! actually the discord id is bound! ;)
			ids[ply:SteamID()] = res.id
			saveIDs()
		end
	end)

	return ""
end)

hook.Add("PlayerInitialSpawn", "ttt_discord_bot_PlayerInitialSpawn", function(ply)
    if not GetConVar("discordbot_enabled"):GetBool() then
        return
    end
	if (ids[ply:SteamID()]) then
		ply:PrintMessage(HUD_PRINTTALK, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "You are connected with discord.")
	else
		ply:PrintMessage(HUD_PRINTTALK, "[" .. GetConVar("discordbot_name"):GetString() .. " " .. timestamp() ..  "] " .. "You are not connected with discord. Write '!discord DISCORDTAG' in the chat. E.g. '!discord marcel.js#4402'")
	end
end)

hook.Add("PlayerSpawn", "ttt_discord_bot_PlayerSpawn", function(ply)
	unmute(ply, "PlayerSpawn")
end)

hook.Add("PlayerDisconnected", "ttt_discord_bot_PlayerDisconnected", function(ply)
	unmute(ply, "PlayerDisconnected")
end)

hook.Add("ShutDown", "ttt_discord_bot_ShutDown", function()
	unmute(nil, "ShutDown")
end)

hook.Add("TTTEndRound", "ttt_discord_bot_TTTEndRound", function()
	timer.Simple(0.1, function()
		unmute(nil, "TTTEndRound")
	end)
end)

--in case of round-restart via command
hook.Add("TTTBeginRound", "ttt_discord_bot_TTTBeginRound", function()
	unmute(nil, "TTTBeginRound")
end)

hook.Add("OnEndRound", "ttt_discord_bot_OnEndRound", function()
	timer.Simple(0.1, function()
		unmute(nil, "OnEndRound")
	end)
end)

hook.Add("OnStartRound", "ttt_discord_bot_OnStartRound", function()
	unmute(nil, "OnStartRound")
end)

hook.Add("PostPlayerDeath", "ttt_discord_bot_PostPlayerDeath", function(ply)
    if not GetConVar("discordbot_enabled"):GetBool() then
        return
    end
	if (commonRoundState() == 1) then
		mute(ply)
	end
end)


timer.Create("mute_status", 1, 0, function ()
    if not GetConVar("discordbot_enabled"):GetBool() then
        return
    end
	for key, ply in pairs(player.GetAll()) do
		updateIcon(ply)
	end
end)