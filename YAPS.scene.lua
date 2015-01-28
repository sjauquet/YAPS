--[[ 
%% autostart
%% properties 
%% globals 
Simu_presence 
--]] 

--------------------------------
-- YAPS Presence Simulator V2.3.1
-- SebcBien
-- Janvier 2015
--------------------------------
--V2.3.1
-- small notification and debug changes
--V2.3
-- Rewriting the engine
-- now relaunch automatically the next day, even if Simu_presence has not changed
--V2.2
-- Added Manual Stop variable
-- added list of mobiles

if (fibaro:countScenes() > 1) then 
	fibaro:debug("More than one scene active, exiting!"); 
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
	PHONE_NEXUS_5		= 53,
	PHONE_NEXUS_4		= 104
	}
  
local stop_hour = "01"; -- Hour when you want simulation to stop 
local stop_minute = "10"; -- Minute of the hour you want simulation to stop 
-- note 1: the script will not exit while waiting the random time of the last light turned on. So end time can be longer than specified end time
-- note 2: if the global variable changes during the same wait time as above, it will exit immediately (when back home while simulation runs)
local rndmaxtime = 15 -- random time of light change in minutes --> here each device is on maximum 30min 
local ID_devices_lights = {id["LAMPE_SDB"],id["LAMPE_BUREAU"],id["LAMPE_HALL"],id["LAMPE_CELLIER"],id["LAMPE_CH_AMIS"]} -- IDs of lights to use in simulation 
--local ID_devices_lights = {id["LAMPE_BUREAU"],id["LAMPE_CELLIER"]} -- IDs of lights to use in simulation
local activatePush = true; -- activate push when simulation starts and stops 
--local ID_Smartphone = 53; -- ID of your smartphone 
--local ID_Smartphones = {id["PHONE_NEXUS_5"],id["PHONE_NEXUS_4"]}; 
local ID_Smartphones = {id["PHONE_NEXUS_5"]}; 
local ID_On_After_Simu = id["LAMPE_HALL"] -- Only One ID of a lamp to turn on after simulation ends (set 0 to disable)
local Manual_Stop = 1 -- 0 will not turn on the lamp "ID_On_After_Simu" at the end of the script. Replace this variable by a global value if you want to automate
--------------------- USER SETTINGS END ---------------------------- 
----------------------ADVANCED SETTINGS----------------------------- 
local showStandardDebugInfo = true; -- Debug shown in white 
local showExtraDebugInfo = true; -- Debug shown in orange 
local numbers_lights = #ID_devices_lights -- numbers of light devices listed above 
local manualOveride = fibaro:getGlobal("overideSimuSunset"); -- if = 1 then the simulation is forced
-------------------------------------------------------------------- 
----------------------------------- 
----- Do not change code below ---- 
----------------------------------- 
local simu = fibaro:getGlobal("Simu_presence"); --value of the global value: simulation is on or off 
local start_simu = fibaro:getValue(1, "sunsetHour"); --Start simulation when sunset 
local endtime 
version = "2.3" 
if (simu == "0") then 
	fibaro:debug("No need to start scene, simu = 0, Exiting") 
	fibaro:abort(); 
end

SimulatorPresenceEngine = {}; 

-- debug function 
Debug = function ( color, message ) 
		fibaro:debug(string.format('<%s style="color:%s;">%s</%s>', "span", color, message, "span")); 
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

-- function push message to mobile 
pushMessage = function (sendPush) 
	if (activatePush) then 
    for i=1, #ID_Smartphones do 
      fibaro:call(tonumber(ID_Smartphones[i]), 'sendPush', sendPush); 
      ExtraDebug("Push message ("..sendPush..") sent to mobile: "..tonumber(ID_Smartphones[i])); 
    end 
	end 
	end
-- function to calculate endtime 
function SimulatorPresenceEngine:EndTimeCalc() 
	local start = os.date("%H:%M") 
	local time = os.time() 
	local date = os.date("*t", time) 
	local year = date.year 
	local month = date.month 
	local day = date.day 
	endtime = os.time{year=year, month=month, day=day, hour=stop_hour, min=stop_minute, sec=sec} 
	start_simu = fibaro:getValue(1, "sunsetHour"); -- recalculate for next day
	--ExtraDebug ("Current OS Time" ..os.time()) 
	--ExtraDebug ("Original planed EndTime " ..endtime) 
	--[[if endtime < os.time() then 
		endtime = endtime + 24*60*60 
		ExtraDebug ("Modified Endtime +24h " ..endtime) 
	end --]]
	end 
-- function to simulate a presence 
function SimulatorPresenceEngine:Launch() 
	pushMessage("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute) 
	ExtraDebug("Lights simulation started, will stop at: "..stop_hour..":"..stop_minute ); 
	while ((os.time() <= endtime) and (simu == "1")) or ((manualOveride == "1")) do 
		-- original code: while ((os.time() <= endtime) and (simu == "1")) or ((os.time() <= endtime) and (simu == "1") and (manualOveride == "1")) do 
		if time == endtime then StandardDebug("time and endtime same value -> end") end 
		local random_light = tonumber(ID_devices_lights[math.random(numbers_lights)]) --choose a random light in the list 
		local lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light in the list 
		-- turn on the light if off or turn off if on 
		if tonumber(lightstatus) == 0 then fibaro:call(random_light, 'turnOn') else fibaro:call(random_light, 'turnOff') end 
		fibaro:sleep(1000); --necessary to get back the new status, because HC2 is too fast :-) 
		lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light after his update 
		StandardDebug('light ID:'..random_light..' status:'..lightstatus);
		local sleeptime = math.random(rndmaxtime*60000) --random sleep 
		fibaro:debug("entering loop of " .. sleeptime/60000 .. "minutes");
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
			fibaro:debug("exiting loop of " .. sleeptime/60000 .. "minutes");
		local sleeptimemin = math.abs(sleeptime/60000) 
		StandardDebug('sleeptime:'..sleeptimemin);
		simu = fibaro:getGlobal("Simu_presence"); --verify the global value, if the virtual device is deactivated, the scene stops. 
		manualOveride = fibaro:getGlobalValue("overideSimuSunset");
	end 
	end 
	
function SimulatorPresenceEngine:EndSimulation() 
	SimulatorPresenceEngine:TurnOff(ID_devices_lights); 
	Debug("red","Simulation is deactivated");
	--ExtraDebug("Tomorrow sunset: "..fibaro:getValue(1, "sunsetHour"));
	if (simu == "1") then
		Debug("grey", "Simulate Presence will Restart tomorrow at "..start_simu);
		pushMessage("Simulate Presence will Restart tomorrow at "..start_simu ..". Recheck in 5 Min");
	end
end

function SimulatorPresenceEngine:ExitSimulation()
	SimulatorPresenceEngine:TurnOff(ID_devices_lights); 
	Debug("red","Presence Simulator is Terminated");
	pushMessage("Presence Simulator is Terminated");
end

-- function to switch off devices in the list 
function SimulatorPresenceEngine:TurnOff(group) 
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
	StandardDebug("Device:" .. name .. " Off "); 
	end 
	  if (ID_On_After_Simu ~= 0 and Manual_Stop == 1) then
	  fibaro:call(ID_On_After_Simu, "turnOn"); 
	  end
	end 

-- tester startup type et si autostart ou simu = 0 ne pas push et exit

Debug("green", "Simulate Presence at Home | v" .. version ); 
Debug( "green", "----------------------------------------"); 
pushMessage("Simulate Presence will start today at "..start_simu)
ExtraDebug("Today's sunset at "..fibaro:getValue(1, "sunsetHour").." - Simulation will stop at "..stop_hour..":"..stop_minute);

while (simu=="1" or simu=="0" ) do 
	SimulatorPresenceEngine:EndTimeCalc(); 
	--local start_simu = "00:01"  -- uncomment this line when testing to force a start hour. ex: 1 min after saving the scene.
	-- define if  nighttime (sunset)
	if (os.date("%H:%M") >= start_simu) then 
		sunset = 1 
	else 
		sunset = 0 
	end 
	if sunset == 1 and (os.time() >= endtime) then 
		ExtraDebug("Simulation ended for this night.");
	end 
	if (simu == "1") then 
		if sunset == 1 and os.time() <= endtime then 
			Debug("grey", "It's sunset time -> Simulation ON");
			SimulatorPresenceEngine:Launch(); --launch the simulation. 
			SimulatorPresenceEngine:EndSimulation();
		end 

		if manualOveride == "1" then 
			Debug("grey", "Manual Override Activated -> Simulation ON");
			SimulatorPresenceEngine:Launch(); --launch the simulation. 
			SimulatorPresenceEngine:EndSimulation();
		end
			--fibaro:debug("sunset: "..sunset .. "endtime: " .. endtime .. "ostime: " .. os.time());
		if manualOveride == "0" and sunset == 0 then 
			Debug("grey", "Waiting for next Sunset -> Simulation OFF. Recheck in 5 Min"); 
		end
	end 
	-- Condition to end simulation 
	if (simu == "0") then 
		SimulatorPresenceEngine:ExitSimulation();
		Debug("red","Simu = 0, Exit from scene");
		fibaro:abort(); 
	end
	ExtraDebug("sleeping 5min before re-check");
	fibaro:sleep(5*60*1000);
	simu = fibaro:getGlobal("Simu_presence"); 
	manualOveride = fibaro:getGlobal("overideSimuSunset"); 
end 
