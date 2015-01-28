--[[ 
%% autostart 
%% properties 
%% globals 
Simu_presence 
--]] 
 
--------------------------------
-- YAPS Presence Simulator V2.2
-- SebcBien
-- Janvier 2015
--------------------------------
 
-- Added Manual Stop variable
-- added list of mobiles
 
if (fibaro:countScenes() > 1) then 
fibaro:debug("More than one scene active, exiting!"); 
fibaro:abort(); 
end 
 
--------------------- USER SETTINGS -------------------------------- 
local id = {
	LAMPE_SDB		= 16,
	LAMPE_CH_AMIS		= 24,
	LAMPE_SALON		= 45,
	LAMPE_BUREAU		= 49,
	LAMPE_HALL		= 52,
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
--local ID_devices_lights = {id["LAMPE_HALL"],id["LAMPE_BUREAU"],id["LAMPE_CELLIER"]} -- IDs of lights to use in simulation
local activatePush = true; -- activate push when simulation starts and stops 
local ID_Smartphone = 53; -- ID of your smartphone 
local ID_Smartphones = {id["PHONE_NEXUS_5"],id["PHONE_NEXUS_4"]}; 
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
--local start_simu = "22:28"  -- uncomment this line when testing to force a start hour 1 min after saving the scene.
local endtime 
version = "2.2" 
 
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
 
-- function to switch off devices in the list 
function SimulatorPresenceEngine:TurnOff(group) 
	Debug("red","TurnOff All lights!") 
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
 
 
-- function to calculate endtime 
function SimulatorPresenceEngine:EndTimeCalc() 
 
	local start = os.date("%H:%M") 
	local time = os.time() 
	local date = os.date("*t", time) 
	local year = date.year 
	local month = date.month 
	local day = date.day 
	endtime = os.time{year=year, month=month, day=day, hour=stop_hour, min=stop_minute, sec=sec} 
	--ExtraDebug ("CurrentTime" ..os.time()) 
	--ExtraDebug ("Original EndTime " ..endtime) 
	if endtime < os.time() then 
		endtime = endtime + 24*60*60 
	-- ExtraDebug ("Modified Endtime " ..endtime) 
	end 
	end 
 
-- function to simulate a presence 
function SimulatorPresenceEngine:Launch() 
	ExtraDebug( "Simulation will stop: "..stop_hour..":"..stop_minute ); 
	if (os.time() >= endtime) or (simu == "0") or (manualOveride == "0") then 
		ExtraDebug("Simulation stopped") 
		SimulatorPresenceEngine:TurnOff(ID_devices_lights) 
	end 
 
	pushMessage("Lights simulation started") 
	while ((os.time() <= endtime) and (simu == "1")) or ((manualOveride == "1")) do 
		-- original code: while ((os.time() <= endtime) and (simu == "1")) or ((os.time() <= endtime) and (simu == "1") and (manualOveride == "1")) do 
		if time == endtime then StandardDebug("time and endtime same value -> end") end 
		local random_light = tonumber(ID_devices_lights[math.random(numbers_lights)]) --choose a random light in the list 
		local lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light in the list 
		-- turn on the light if off or turn off if on 
		if tonumber(lightstatus) == 0 then fibaro:call(random_light, 'turnOn') else fibaro:call(random_light, 'turnOff') end 
		fibaro:sleep(1000) ; --necessary to get back the new status, because HC2 is too fast :-) 
		lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light after his update 
		StandardDebug('light ID:'..random_light..' status:'..lightstatus) 
		local sleeptime = math.random(rndmaxtime*60000) --random sleep 
		fibaro:debug("entering loop of " .. sleeptime/60000 .. "minutes")
		-- This modification allows to exit the scene if the Simu_presence global var changes to 0 during the random  sleep
			local counterexitsimu = 200
				while (counterexitsimu > 0) do
					counterexitsimu = counterexitsimu - 1;
					test_presence_state = fibaro:getGlobal("Simu_presence")
					simu = tonumber(test_presence_state); --verify the global value, if the virtual device is deactivated, the scene stops. 
					--fibaro:debug("simu var state : " .. simu)
					if simu == 0 then
						counterexitsimu = 0
					end
				fibaro:sleep(sleeptime/200) 
				end
			fibaro:debug("exiting loop of " .. sleeptime/60000 .. "minutes")
		local sleeptimemin = math.abs(sleeptime/60000) 
		StandardDebug('sleeptime:'..sleeptimemin) 
		simu = fibaro:getGlobal("Simu_presence"); --verify the global value, if the virtual device is deactivated, the scene stops. 
		manualOveride = fibaro:getGlobalValue("overideSimuSunset") 
	end 
	end 
 
 
-- Main Script beginning 
 
SimulatorPresenceEngine:EndTimeCalc(); 
 
if (simu == "1") then 
	Debug("green", "Simulate Presence at Home | v" .. version ); 
	Debug( "green", "--------------------------------------------------"); 
	ExtraDebug("Today's sunset: "..fibaro:getValue(1, "sunsetHour")) 
end 
 
if (simu == "1") then 
	Debug("grey", "Simulate Presence will start at "..start_simu) 
	pushMessage("Simulate Presence will start at "..start_simu)
end 
 
-- Main Loop 
while (simu=="1") do 
	-- Condition to start simulation 
	simu = fibaro:getGlobal("Simu_presence"); 
	manualOveride = fibaro:getGlobal("overideSimuSunset"); 
 
	if (os.date("%H:%M") >= start_simu) then 
		sunset = 1 
	else 
		sunset = 0 
	end 
 
	if ((simu == "1") and os.time() <= endtime and sunset == 1 ) or ((simu == "1") and manualOveride == "1" ) then 
		SimulatorPresenceEngine:Launch(); --launch the simulation. 
		if manualOveride == "1" and sunset == 0 then 
			Debug("grey", "Manual override activated") 
		elseif sunset == 1 then 
			Debug("grey", "It's sunset time, starting simulation") 
		end 
 
		if sunset == 0 and manualOveride == "0" then 
			Debug("grey", "Not manual override so Presence Simulation will not be activated"); 
		elseif os.time() >= endtime then 
			Debug("grey", "Time is now after:"..stop_hour..":"..stop_minute.."deactivating"); 
			SimulatorPresenceEngine:TurnOff(ID_devices_lights); 
			Debug("red","Simulation is deactivated") 
			pushMessage("Lights simulation stopped") 
		end 
	end 
end 
 
-- Condition to end simulation 
if (simu == "0") then 
	SimulatorPresenceEngine:TurnOff(ID_devices_lights); 
	Debug("red","Simulation is deactivated") 
	pushMessage("Lights simulation stopped") 
end 
Debug("red","Exit from scene") 
