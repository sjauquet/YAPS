--[[ 
%% autostart
%% properties 
%% globals 
Simu_presence 
--]] 

---------------------------------
-- YAPS Presence Simulator V2.6.3
-- SebcBien
-- Avril 2015
---------------------------------
--V2.6.3
-- Added array of lights to turn on after simu, ONLY if Simu_presence = 1 (normal ending, not ended by setting Simu_presence to 0)
--V2.6.2
-- Added the possibility to not have an always on lamp
--V2.6.1
-- Added naming of devices in the debug during simulation
--V2.6.0
-- Added the possibility to select always on light during simulation
--V2.5.0
-- fixed simulation starting if restarted between endtime & midnight
--v2.4.1
-- fixed big bug simulator restarting after end time
--V2.3.1
-- small notification and debug changes
--V2.3
-- Rewriting the engine
-- now relaunch automatically the next day, even if Simu_presence has not changed
--V2.2
-- Added Manual Stop variable
-- added list of mobiles

if (fibaro:countScenes() > 1) then 
	--fibaro:debug("More than one scene active, exiting!"); 
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
    PHONE_GG			= 1327,
	}
  
local stop_hour = "01"; -- Hour when you want simulation to stop 
local stop_minute = "10"; -- Minute of the hour you want simulation to stop 
-- note 1: the script will not exit while waiting the random time of the last light turned on. So end time can be longer than specified end time
-- note 2: if the global variable changes during the same wait time as above, it will exit immediately (when back home while simulation runs)
local rndmaxtime = 20; -- random time of light change in minutes --> here each device is on maximum 30min 
local ID_devices_lights_always_on = {id["LAMPE_BUREAU"],id["LAMPE_COULOIR"]} -- IDs of lights who will always stay on during simulation - leave empty array if none -> {}
local ID_devices_lights = {id["LAMPE_SDB"],id["LAMPE_HALL"],id["LAMPE_CELLIER"],id["LAMPE_CH_AMIS"]} -- IDs of lights to use in simulation 
--local ID_devices_lights = {id["LAMPE_BUREAU"],id["LAMPE_CELLIER"]} -- Reduced set for test purposes
local activatePush = true; -- activate push when simulation starts and stops 
--local ID_Smartphones = {id["PHONE_SEB"],id["PHONE_GG"]}; 
local ID_Smartphones = {id["PHONE_SEB"]}; -- list of device receiving Push
local ID_On_After_Simu = 0; -- If next line is commented, no light will turn on after simulation ends
local ID_On_After_Simu = id["LAMPE_HALL"]; -- Only One ID of a light to turn on after simulation ends. Comment this line to turn off this feature
local ID_On_When_Simu_Deactivated = 0; -- If next line is commented, no light will turn on after simulation is stopped (by putting Simu_presence to 0)
local ID_On_When_Simu_Deactivated = id["LAMPE_HALL"]; -- Only One ID of a light to turn on after simulation is stopped. Comment this line to turn off this feature


--------------------- USER SETTINGS END ---------------------------- 
----------------------ADVANCED SETTINGS----------------------------- 
local showStandardDebugInfo = true; -- Debug shown in white 
local showExtraDebugInfo = false; -- Debug shown in orange 
local numbers_lights = #ID_devices_lights; -- numbers of light devices listed above 
local manualOveride = fibaro:getGlobal("overideSimuSunset"); -- if = 1 then the simulation is forced
-------------------------------------------------------------------- 
-------------------- DO NOT CHANGE CODE BELOW ---------------------- 
--------------------------------------------------------------------
local version = "2.6.3"; 
local simu = fibaro:getGlobal("Simu_presence"); --value of the global value: simulation is on or off 
local start_simu = fibaro:getValue(1, "sunsetHour"); --Start simulation when sunset
local endtime;
local wait_for_tomorrow = 1;
local NotifLoop = 30;

SimulatorPresenceEngine = {}; 

-- FONCTIONS
Debug = function ( color, message ) 
		--fibaro:debug(string.format('<%s style="color:%s;">%s</%s>', "span", color, message, "span")); 
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
	if ((wait_for_tomorrow == 0) and (endtime < os.time())) then -- if endtime is gone and it's the first launch of simulator
		endtime = endtime + 24*60*60 -- add 24h at endtime after the night is gone
		start_simu = fibaro:getValue(1, "sunsetHour"); -- recalculate for next day
		ExtraDebug ("Added 24H to Endtime (first start ending after midnignt)");
		ExtraDebug ("Recalculated Simulation StartHour (Sunset): " .. start_simu); 		
		wait_for_tomorrow = 1	
	end 
	if (wait_for_tomorrow == 1 and (endtime < os.time()) and ((now >= sunrise) and (now <= sunset))) then -- if it looping days and endtime is gone and we are daytime
		endtime = endtime + 24*60*60 -- add 24h at endtime after the night is gone
		start_simu = fibaro:getValue(1, "sunsetHour"); -- recalculate for next day
		ExtraDebug ("Added One Day to Endtime: " .. endtime);
		ExtraDebug ("Recalculated Simulation StartHour (Sunset): " .. start_simu); 	
	end 
	--ExtraDebug ("debug info: Recalculated planed EndTime " ..endtime) 
	end 
-- Simulate Presence Main 
function SimulatorPresenceEngine:Launch() 
	pushMessage("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute) 
	ExtraDebug("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute ); 
	if ID_devices_lights_always_on[1] ~= nil then SimulatorPresenceEngine:TurnOn(ID_devices_lights_always_on); end
	while ((os.time() <= endtime) and (simu == "1")) or ((manualOveride == "1")) do 
		-- original code: while ((os.time() <= endtime) and (simu == "1")) or ((os.time() <= endtime) and (simu == "1") and (manualOveride == "1")) do 
		if time == endtime then StandardDebug("time and endtime same value -> end") end 
		local random_light = tonumber(ID_devices_lights[math.random(numbers_lights)]) --choose a random light in the list 
		local lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light in the list 
		-- turn on the light if off or turn off if on 
		if tonumber(lightstatus) == 0 then fibaro:call(random_light, 'turnOn') else fibaro:call(random_light, 'turnOff') end 
		fibaro:sleep(1000); --necessary to get back the new status, because HC2 is too fast :-) 
		lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light after his update 
		StandardDebug('light ID:'.. fibaro:getName(random_light) ..' status:'..lightstatus);
		local sleeptime = math.random(rndmaxtime*60000) --random sleep 
		StandardDebug("entering loop of " .. round(sleeptime/60000,2) .. " minutes");
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
			StandardDebug("exiting loop of " .. round(sleeptime/60000,2) .. " minutes");
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
	Debug("red","TurnOff All lights!");
	local name, id2; 
	local ID_devices_group = group; 
	for i=1, #ID_devices_group do 
	id2 = tonumber(ID_devices_group[i]); 
	fibaro:call(id2, "turnOff"); 
	name = fibaro:getName(id2); 
	if (name == nil or name == string.char(0)) then 
		name = "Unknown" 	
	end 
	StandardDebug("Device: " .. name .. " Off "); 
	end 
	local ID_devices_group = group2; 
	for i=1, #ID_devices_group do 
	id2 = tonumber(ID_devices_group[i]); 
	fibaro:call(id2, "turnOff"); 
	name = fibaro:getName(id2); 
	if (name == nil or name == string.char(0)) then 
		name = "Unknown" 	
	end 
	StandardDebug("Device: " .. name .. " Off "); 
	end 
	  if ID_On_After_Simu ~= 0 then
	  fibaro:call(ID_On_After_Simu, "turnOn");
    	name = fibaro:getName(ID_On_After_Simu); 
			if (name == nil or name == string.char(0)) then 
				name = "Unknown" 	
			end 
      Debug("red","Manual Light Settings: Turned On light: " .. name);
	  end
	  simu = fibaro:getGlobal("Simu_presence");
	  if ID_On_When_Simu_Deactivated ~= 0 and simu == 0 then
	  fibaro:call(ID_On_When_Simu_Deactivated, "turnOn");
    	name = fibaro:getName(ID_On_When_Simu_Deactivated); 
			if (name == nil or name == string.char(0)) then 
				name = "Unknown" 	
			end 
      Debug("red","Manual Light Settings: Turned On light: " .. name);
	  end
	end 
-- Switch on devices in the list 
function SimulatorPresenceEngine:TurnOn(group) 
	Debug("red","Turning On always on lights:");
	local name, id2; 
	local ID_devices_group = group; 
	for i=1, #ID_devices_group do 
	id2 = tonumber(ID_devices_group[i]); 
	fibaro:call(id2, "turnOn"); 
	name = fibaro:getName(id2); 
	if (name == nil or name == string.char(0)) then 
		name = "Unknown" 	
	end 
	StandardDebug("Device: " .. name .. " On "); 
	end
	Debug("red","Now randomizing other lights...");
	end 
	
Debug("green", "Presence Simulator | v" .. version ); 
Debug( "green", "--------------------------------");
if tonumber(stop_hour) <= 12 then wait_for_tomorrow = 0 end -- if stop hour is between 00 and 12h then will consider that stop hour is before midnight

------------------------ Main Loop ----------------------------------
if (simu == "0") then 
	Debug("red","Not starting Simulation (Simu_presence = 0)");
	SimulatorPresenceEngine:ExitSimulation();
	fibaro:abort(); 
end

pushMessage("Scheduled Simulation starting time: " .. start_simu);
ExtraDebug("Today's sunset is at "..fibaro:getValue(1, "sunsetHour").." - End of Simulation at "..stop_hour..":"..stop_minute);

while (simu=="1" or simu=="0" ) do
	SimulatorPresenceEngine:EndTimeCalc(); 
	-- local start_simu = "00:01"  -- uncomment this line when testing to force a start hour (for the first loop)

	if (os.date("%H:%M") >= start_simu) then -- define if nighttime (sunset)
		sunset = 1 
	else 
		sunset = 0 
	end 
	
	if (simu == "1") then 
		if sunset == 1 and (os.time() <= endtime) then 
			Debug("grey", "It's sunset time -> Simulation ON");
			SimulatorPresenceEngine:Launch();
			SimulatorPresenceEngine:EndSimulation();
		end 
		if manualOveride == "1" then 
			Debug("grey", "Manual Override Activated -> Simulation ON");
			SimulatorPresenceEngine:Launch();
			SimulatorPresenceEngine:EndSimulation();
		end
			--fibaro:debug("sunset: "..sunset .. "endtime: " .. endtime .. "ostime: " .. os.time());
		if manualOveride == "0" and sunset == 0 and NotifLoop == 30 then 
			Debug("grey", "Waiting for next Sunset: " .. start_simu .. " -> Simulation OFF."); 
		end
	end 
	if sunset == 1 and (os.time() >= endtime) and (os.time() <= (endtime + 60)) then 
		Debug("grey","Simulation ended for this night.");
	end 

	if (simu == "0") then -- Condition to end simulation 
		SimulatorPresenceEngine:ExitSimulation();
		Debug("red","Simu = 0, Exit from scene");
		fibaro:abort(); 
	end
		if NotifLoop <= 30 then
    		if NotifLoop == 30 then NotifLoop = 0
			end
			if NotifLoop == 0 then ExtraDebug("Looping to check for changes every 2min")
			end
			NotifLoop = NotifLoop + 1
    	end
	fibaro:sleep(2*60*1000);
	simu = fibaro:getGlobal("Simu_presence"); 
	manualOveride = fibaro:getGlobal("overideSimuSunset"); 
end