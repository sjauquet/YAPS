--[[ 
%% autostart
%% properties 
%% globals 
Simu_presence 
--]] 

---------------------------------
-- YAPS Presence Simulator V3.0.1
-- SebcBien
-- August 2015
---------------------------------
--V3.0.1
-- modified end time notification impacted by random and smooth TurnOff (endtime impact)
--V3.0.0
-- added smooth cut off of lights at ending time (not with deactivation)
--V2.6.6
-- clean up debug messages
-- added free sms notifications
-- second fix to looping days bug
--V2.6.0 to V2.6.5 
-- Fixed bug when rndmaxendtime = 0
-- Probably fixed endtime bug calculation when looping for days du to days are shorter now than the previous day
-- Fixed bug not turning on ID_On_After_Simu when exiting simulation
-- added random end time + small stability changes and cleaning
-- Added array of lights to turn on after simu, ONLY if Simu_presence = 1 (normal ending, not ended by setting Simu_presence to 0)
-- Added the possibility to not have an always on lamp
-- Added naming of devices in the debug during simulation
-- Added the possibility to select always on light during simulation
--V2.2.0 to 2.5.0
-- fixed simulation starting if restarted between endtime & midnight
-- fixed big bug simulator restarting after end time
-- small notification and debug changes
-- Rewriting the engine
-- now relaunch automatically the next day, even if Simu_presence has not changed
-- Added Manual Stop variable
-- added list of mobiles

if (fibaro:countScenes() > 1) then 
	fibaro:debug("Scene already active, exiting this new occurence !!"); 
	fibaro:abort(); 
end 
--------------------- USER SETTINGS --------------------------------
local id = {
	LAMPE_SDB			= 16,
	LAMPE_CH_AMIS		= 24,
	LAMPE_SALON			= 45,
	LAMPE_BUREAU		= 49,
	LAMPE_HALL			= 52,
	LAMPE_CELLIER		= 56,
	LAMPE_CH_EMILIEN	= 58,
    LAMPE_COULOIR		= 1316,
	PHONE_SEB			= 1347,
    PHONE_GG			= 1327
	}
  
local stop_hour = "01"; -- Hour when you want simulation to stop 
local stop_minute = "15"; -- Minute of the hour you want simulation to stop 
-- note 1: the script will not exit while waiting the random time of the last light turned on. So end time can be longer than specified end time. (even more with var rndmaxendtime)
-- note 2: if the global variable changes during the same wait time as above, it will exit immediately (when back home while simulation runs)
local rndmaxtime = 20; -- random time of light change in minutes --> here each device is on maximum 30min 
local rndmaxendtime = 15; -- random time to add at the stop hour+stop minute so the simulation can be more variable (0 to deactivate)
local ID_devices_lights_always_on = {id["LAMPE_BUREAU"],id["LAMPE_COULOIR"]} -- IDs of lights who will always stay on during simulation - leave empty array if none -> {}
local ID_devices_lights = {id["LAMPE_SDB"],id["LAMPE_HALL"],id["LAMPE_CELLIER"],id["LAMPE_CH_AMIS"]} -- IDs of lights to use in simulation 
--local ID_devices_lights = {id["LAMPE_HALL"],id["LAMPE_CELLIER"],id["LAMPE_CH_AMIS"]} -- Reduced set for test purposes
local activatePush = true; -- activate push when simulation starts and stops 
local FreeSms = false; -- activate push with FreeSms (activatePush must be true also) 
--local ID_Smartphones = {id["PHONE_SEB"],id["PHONE_GG"]}; 
local ID_Smartphones = {id["PHONE_SEB"]}; -- list of device receiving Push
local ID_On_After_Simu = 0; -- If next line is commented, no light will turn on after simulation ends
local ID_On_After_Simu = id["LAMPE_COULOIR"]; -- ID of a light (Only One) to turn on after simulation ends (at specified stop_hour & stop_minute). Comment this line to turn off this feature
local ID_On_When_Simu_Deactivated = 0; -- If next line is commented, no light will turn on after simulation is stopped (by putting Simu_presence to 0)
local ID_On_When_Simu_Deactivated = id["LAMPE_HALL"]; -- ID of a light (Only One) to turn on after simulation is stopped (Simu_). Comment this line to turn off this feature
--------------------- USER SETTINGS END ---------------------------- 
----------------------ADVANCED SETTINGS----------------------------- 
local showStandardDebugInfo = true; -- Debug shown in white 
local showExtraDebugInfo = true; -- Debug shown in orange 
-------------------------------------------------------------------- 
-------------------- DO NOT CHANGE CODE BELOW ---------------------- 
--------------------------------------------------------------------
local version = "3.0.1"; 
local simu = fibaro:getGlobal("Simu_presence"); --value of the global value: simulation is on or off 
local start_simu = fibaro:getValue(1, "sunsetHour"); --Start simulation when sunset
local endtime;
local wait_for_tomorrow = 1;
local NotifLoop = 0;
local numbers_lights = #ID_devices_lights; -- numbers of light devices listed above 
local manualOveride = fibaro:getGlobal("overideSimuSunset"); -- if = 1 then the simulation is forced

SimulatorPresenceEngine = {}; 

-- FONCTIONS
Debug = function ( color, message ) 
		fibaro:debug(string.format('<%s style="color:%s;">%s</%s>', "span", color, os.date("%a %d/%m", os.time()).." "..message, "span")); 
end 

ExtraDebug = function (debugMessage) 
	if ( showExtraDebugInfo ) then 
		Debug( "orange", debugMessage); 
	end 
end 

StandardDebug = function (debugMessage) 
	if ( showStandardDebugInfo ) then 
		Debug( "white", debugMessage); 
	end 
end 

round = function (num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end
-- Push message to mobile 
pushMessage = function (sendPush) 
	if (activatePush) then 
    	for i=1, #ID_Smartphones do 
      		fibaro:call(tonumber(ID_Smartphones[i]), 'sendPush', sendPush); 
      		ExtraDebug("Push message ("..sendPush..") sent to mobile: "..tonumber(ID_Smartphones[i])); 
    	end 
    	if (FreeSms) then 
    		fibaro:setGlobal("FreeSms", sendPush)
			ExtraDebug("Message ("..sendPush..") sent to FreeSms"); 
    	end
	end 
end
-- Calculate endtime 
function SimulatorPresenceEngine:EndTimeCalc() 
	local start = os.date("%H:%M") 
	local time = os.time() 
	local date = os.date("*t", time) 
	local year = date.year 
	local month = date.month 
	local day = date.day 
	endtime = os.time{year=year, month=month, day=day, hour=stop_hour, min=stop_minute, sec=sec}
	-- to calculate when it's daytime
	local currentHour = os.date("*t")
	local sunrise = tonumber(string.sub (fibaro:getValue(1,'sunriseHour'), 1 , 2) ) * 60 + tonumber(string.sub(fibaro:getValue(1,'sunriseHour'), 4) )
	local sunset = tonumber(string.sub (fibaro:getValue(1,'sunsetHour'), 1 , 2) ) * 60 + tonumber(string.sub(fibaro:getValue(1,'sunsetHour'), 4) )
	local now = currentHour.hour * 60 + currentHour.min;
	--ExtraDebug ("debug info: Sunrise : " .. sunrise .. " Sunset : "..sunset .. " Now : " ..now);
	--ExtraDebug ("debug info: Current OS Time" ..os.time()) 
	--ExtraDebug ("debug info: Original planed EndTime " ..endtime) 
	--ExtraDebug ("debug info: os.date: "..os.date("%H:%M").. " sunrisehour: "..fibaro:getValue(1, "sunriseHour"))
	if ((wait_for_tomorrow == 0) and (endtime+(5*60) < os.time())) then -- if endtime (+5 min to avoid sunset shifting) is gone and it's the first launch of simulator
		endtime = endtime + 24*60*60 -- add 24h at endtime after the night is gone
		start_simu = fibaro:getValue(1, "sunsetHour"); -- recalculate for next day
		ExtraDebug ("wait_for_tomorrow = 0 Added 24H to Endtime (first start ending after midnignt)");
		ExtraDebug ("Recalculated Simulation StartHour (Sunset): " .. start_simu); 		
		wait_for_tomorrow = 1	
	end 
	if (wait_for_tomorrow == 1 and (endtime+(5*60) < os.time()) and ((now >= sunrise) and (now <= sunset))) then -- if it looping days and endtime (+5 min to avoid sunset shifting) is gone and we are daytime
		endtime = endtime + 24*60*60 -- add 24h at endtime after the night is gone
		start_simu = fibaro:getValue(1, "sunsetHour"); -- recalculate for next day
		ExtraDebug ("wait_for_tomorrow = 1 Added One Day to Endtime: " .. endtime);
		ExtraDebug ("Recalculated Simulation StartHour (Sunset): " .. start_simu); 	
	end 
	--ExtraDebug ("debug info: Recalculated planed EndTime " ..endtime) 
end 
-- Simulate Presence Main 
function SimulatorPresenceEngine:Launch() 
	-- pushMessage("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute ) 
    pushMessage("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute.." + random of "..rndmaxendtime.." min")
	-- ExtraDebug("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute );
    StandardDebug("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute.." + random of "..rndmaxendtime.." min");	
	if ID_devices_lights_always_on[1] ~= nil then SimulatorPresenceEngine:TurnOn(ID_devices_lights_always_on); end
	--rndmaxendtime = tonumber(rndmaxendtime) + 1

    	ExtraDebug("Defined endtime : ".. endtime .. ". New endtime (with random): " .. rndmaxendtime)
    while ((os.time() <= endtime) and (simu == "1")) or ((manualOveride == "1")) do 
		local random_light = tonumber(ID_devices_lights[math.random(numbers_lights)]) --choose a random light in the list 
		local lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light in the list 
		-- turn on the light if off or turn off if on 
		if tonumber(lightstatus) == 0 then fibaro:call(random_light, 'turnOn') else fibaro:call(random_light, 'turnOff') end 
		fibaro:sleep(1000); --necessary to get back the new status, because HC2 is too fast :-) 
		lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light after his update 
		StandardDebug('light ID:'.. fibaro:getName(random_light) ..' status:'..lightstatus);
		local sleeptime = math.random(rndmaxtime*60000) --random sleep 
		StandardDebug("Entering loop of " .. round(sleeptime/60000,2) .. " minutes");
		-- This modification allows to exit the scene if the Simu_presence global var changes to 0 during the random  sleep
			local counterexitsimu = 200
				while (counterexitsimu > 0) do
					counterexitsimu = counterexitsimu - 1;
					test_presence_state = fibaro:getGlobal("Simu_presence");
					simu = tonumber(test_presence_state); --verify the global value, if the virtual device is deactivated, the scene stops. 
					--fibaro:debug("simu var state : " .. simu);
					if simu == 0 then
						counterexitsimu = 0
					end
				fibaro:sleep(sleeptime/200);
				end
			ExtraDebug("Exiting loop of "..round(sleeptime/60000,2).." minutes");
		local sleeptimemin = math.abs(sleeptime/60000) 
		--StandardDebug('sleeptime:'..sleeptimemin);
		simu = fibaro:getGlobal("Simu_presence"); --verify the global value, if the virtual device is deactivated, the scene stops. 
		manualOveride = fibaro:getGlobalValue("overideSimuSunset");
	end 
end 
	
function SimulatorPresenceEngine:EndSimulation() 
	if ID_devices_lights_always_on[1] ~= nil then SimulatorPresenceEngine:TurnOff(ID_devices_lights,ID_devices_lights_always_on); end
	Debug("red","Simulation is deactivated");
	if (simu == "1") then
		Debug("grey", "Presence Simulator will Restart tomorrow around ".. fibaro:getValue(1, "sunsetHour"));
		pushMessage("Presence Simulator will Restart tomorrow around ".. fibaro:getValue(1, "sunsetHour"));
		wait_for_tomorrow = 1 -- will make EndTimeCalc add 24h to endtime during daytime
	end
end

function SimulatorPresenceEngine:ExitSimulation()
	Debug("red","Presence Simulator is Terminated");
	pushMessage("Presence Simulator is Terminated");
end
-- Switch off devices in the list 
function SimulatorPresenceEngine:TurnOff(group,group2) 
	Debug("red","TurnOff All Simulation lights!");
	local name, id2, sleep_between_TurnOff ; 
	local ID_devices_group = group; 
	if rndmaxendtime ~= 0 and simu == "1" then   -- if simu = 1 then slow turn off, else turn off all immediately
	--if rndmaxendtime ~= 0 then
  		sleep_between_TurnOff = (math.random(rndmaxendtime)/numbers_lights)*60000;
		ExtraDebug("Calculated sleeping between each turn off: "..round(sleep_between_TurnOff/60000,2).." min");
		--endtime2 = endtime + math.random(rndmaxendtime)
    else
    	sleep_between_TurnOff = 0;
		ExtraDebug("No sleeping between turn off");
    end
	for i=1, #ID_devices_group do 
		id2 = tonumber(ID_devices_group[i]); 
		fibaro:call(id2, "turnOff"); 
		name = fibaro:getName(id2); 
		if (name == nil or name == string.char(0)) then 
			name = "Unknown" 	
		end 
		StandardDebug("Device: "..name.." Off ");
		StandardDebug("Sleeping of "..round(sleep_between_TurnOff/60000,2).." minutes before next TurnOff");
		fibaro:sleep(sleep_between_TurnOff);
	end 
	Debug("red","TurnOff All Always_On lights!");
	local ID_devices_group = group2; 
	for i=1, #ID_devices_group do 
		id2 = tonumber(ID_devices_group[i]); 
		fibaro:call(id2, "turnOff"); 
		name = fibaro:getName(id2); 
			if (name == nil or name == string.char(0)) then 
				name = "Unknown" 	
			end 
		StandardDebug("Device: "..name.." Off "); 
	end 
	if ID_On_After_Simu ~= 0 and simu == "1" then
		fibaro:call(ID_On_After_Simu, "turnOn");
		name = fibaro:getName(ID_On_After_Simu); 
			if (name == nil or name == string.char(0)) then 
				name = "Unknown" 	
			end 
		Debug("red","Turned On light ID_On_After_Simu:");
		Debug("white", name);
	end
	if ID_On_When_Simu_Deactivated ~= 0 and simu == "0" then
		fibaro:call(ID_On_When_Simu_Deactivated, "turnOn");
    	name = fibaro:getName(ID_On_When_Simu_Deactivated); 
			if (name == nil or name == string.char(0)) then 
				name = "Unknown" 	
			end 
		Debug("red","Turned On light ID_On_When_Simu_Deactivated:");
		Debug("white", name);
	end
end 
-- Switch on devices in the list 
function SimulatorPresenceEngine:TurnOn(group) 
	Debug("red","Turning On Always_On lights:");
	local name, id2; 
	local ID_devices_group = group; 
	for i=1, #ID_devices_group do 
		id2 = tonumber(ID_devices_group[i]); 
		fibaro:call(id2, "turnOn"); 
		name = fibaro:getName(id2); 
		if (name == nil or name == string.char(0)) then 
			name = "Unknown" 	
		end 
		StandardDebug("Device: "..name.." Turned On "); 
	end
	Debug("red","Now randomizing other lights...");
end 
	
Debug("green", "Presence Simulator | v" .. version ); 
Debug( "green", "--------------------------------");
if tonumber(stop_hour) <= 12 then wait_for_tomorrow = 0 end -- if stop hour is between 00 and 12h then will consider that stop hour is before midnight

------------------------ Main Loop ----------------------------------
if (simu == "0") then -- check before the while loop below... remove ?. 
	Debug("red","Not starting Simulation (Simu_presence = 0)");
	SimulatorPresenceEngine:ExitSimulation();
	fibaro:abort(); 
end

--pushMessage("Scheduled Simulation starting time: " .. start_simu);
--StandardDebug("Today's sunset is at "..fibaro:getValue(1, "sunsetHour").." - End of Simulation at "..stop_hour..":"..stop_minute);

while true do -- Infinie loop of actions checking, hours calculations, notifications
	SimulatorPresenceEngine:EndTimeCalc(); 
	-- local start_simu = "00:01"  -- un-comment this line when testing to force a start hour (only for the first loop)

	if (os.date("%H:%M") >= start_simu) then -- define if nighttime (sunset = 1)
		sunset = 1 
	else 
		sunset = 0 
	end 
	
	if (simu == "1") then 
		if sunset == 1 and (os.time() <= endtime) then 
			Debug("blue", "It's sunset time -> Simulation ON");
			SimulatorPresenceEngine:Launch();
			SimulatorPresenceEngine:EndSimulation();
		end 
		if manualOveride == "1" then 
			Debug("blue", "Manual Override Activated -> Simulation ON");
			SimulatorPresenceEngine:Launch();
			SimulatorPresenceEngine:EndSimulation();
		end
			--fibaro:debug("sunset: "..sunset .. " - endtime: " .. endtime .. " - ostime: " .. os.time());
		if manualOveride == "0" and sunset == 0 and NotifLoop == 0 then 
			Debug("yellow", "Waiting for next Sunset at "..start_simu.." - End of Simulation at "..stop_hour..":"..stop_minute);
		end
	end
	
	if sunset == 1 and (os.time() >= endtime) and (os.time() <= (endtime + (sleep_between_TurnOff*numbers_lights) +	60)) then 
		Debug("blue","Simulation ended (for this night)");
	end 

	if (simu == "0") then -- Condition to end simulation 
		SimulatorPresenceEngine:ExitSimulation();
		Debug("red","Simu_presence = 0, Terminating Simulation Scene");
		fibaro:abort(); 
	end
	
	if NotifLoop <= 120 then --a waiting xx times the fibaro sleep below (2 hours) before resetting counter (and notifying)
    	if NotifLoop == 120 then NotifLoop = 0 end
		if NotifLoop == 0 then
			ExtraDebug("Now, checking for actions every minute. Next notify: in 2 hours");
		end
	end
		
	fibaro:sleep(1*60*1000); -- wait 1 minutes before testing again the global vars below
	simu = fibaro:getGlobal("Simu_presence"); 
	manualOveride = fibaro:getGlobal("overideSimuSunset"); 
	NotifLoop = NotifLoop + 1;
end