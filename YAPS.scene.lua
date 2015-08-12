--[[ 
%% autostart
%% properties 
%% globals 
Simu_presence 
--]] 

---------------------------------------
local version = "3.5.0"; 
-- YAPS Presence Simulation by SebcBien
-- August 2015
---------------------------------------
--V3.5.0
-- Fixed launch between midnight and endtime (if endtime is after midnight)
--V3.3.2
-- renamed all variables for more readability
--V3.3.0
-- Fixed Override bug (no sleep time between lights)
--V3.2.3
-- added sunset shifting possibility (add or remove minutes to startime
-- added time stamp to push messages
-- formated messages
-- optimisation
-- cleanup
--V3.1.0
-- "complete" rewriting with unix times
-- modified end time notification impacted by random and smooth TurnOff (End_simulation_time impact)
-- exit is now exactly at End_simulation_time
-- added smooth cut off of lights at ending time (function not triggered with deactivation)
--V2.6.6
-- clean up debug messages
-- added free sms notifications
-- second fix to looping days bug
--V2.6.0 to V2.6.5 
-- Fixed bug when Random_max_TurnOff_duration = 0
-- Probably fixed End_simulation_time bug calculation when looping for days du to days are shorter now than the previous day
-- Fixed bug not turning on Lights_On_at_end_Simulation when exiting Simulation
-- added random end time + small stability changes and cleaning
-- Added array of lights to turn on after Simulation, ONLY if Simu_presence = 1 (normal ending, not ended by setting Simu_presence to 0)
-- Added the possibility to not have an always on lamp
-- Added naming of devices in the debug during Simulation
-- Added the possibility to select always on light during Simulation
--V2.2.0 to 2.5.0
-- fixed Simulation starting if restarted between End_simulation_time & midnight
-- fixed big bug Simulation restarting after end time
-- small notification and debug changes
-- Rewriting the engine
-- now relaunch automatically the next day, even if Simu_presence has not changed
-- Added Manual Stop variable
-- added list of mobiles

if (fibaro:countScenes() > 1) then 
	fibaro:debug("Scene already active! Aborting this new instance !!"); 
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
  
local Stop_hour = "00"; -- Hour when you want Simulation to stop 
local Stop_minute = "15"; -- Minute of the hour you want Simulation to stop 
-- note 1: the script will not exit while waiting the random time of the last light turned on. So end time can be longer than specified end time. (even more with var Random_max_TurnOff_duration)
-- note 2: if the global variable changes during the same wait time as above, it will exit immediately (when back home while Simulation runs)
local Sunset_offset = -20 -- number of minutes before or after sunset to activate Simulation
local Random_max_duration = 30; -- random time of light change in minutes --> here each device is on maximum 30min 
local Random_max_TurnOff_duration = 15; -- random time to add at the stop hour+stop minute so the Simulation can be more variable (0 to deactivate)
local Lights_always_on = {id["LAMPE_BUREAU"],id["LAMPE_COULOIR"]} -- IDs of lights who will always stay on during Simulation - leave empty array if none -> {}
--local Random_lights = {id["LAMPE_SDB"],id["LAMPE_HALL"],id["LAMPE_CELLIER"],id["LAMPE_CH_AMIS"]} -- IDs of lights to use in Simulation 
local Random_lights = {id["LAMPE_HALL"],id["LAMPE_CELLIER"],id["LAMPE_CH_AMIS"]} -- Reduced set for test purposes
local Activate_Push = true; -- activate push when Simulation starts and stops 
local Activate_FreeSms = false; -- activate push with Activate_FreeSms (Activate_Push must be true also) 
--local Smartphones_push = {id["PHONE_SEB"],id["PHONE_GG"]}; 
local Smartphones_push = {id["PHONE_SEB"]}; -- list of device receiving Push
local Lights_On_at_end_Simulation = 0; -- If next line is commented, no light will turn on after Simulation ends
local Lights_On_at_end_Simulation = id["LAMPE_COULOIR"]; -- ID of a light (Only One) to turn on after Simulation ends (at specified Stop_hour & Stop_minute). Comment this line to turn off this feature
local Lights_On_if_Simulation_deactivated = 0; -- If next line is commented, no light will turn on after Simulation is stopped (by putting Simu_presence to 0)
local Lights_On_if_Simulation_deactivated = id["LAMPE_HALL"]; -- ID of a light (Only One) to turn on after Simulation is stopped (Simulation_). Comment this line to turn off this feature
--------------------- USER SETTINGS END ---------------------------- 
----------------------ADVANCED SETTINGS----------------------------- 
local Show_standard_debug = true; -- Debug displayed in white 
local Show_extra_debug = false; -- Debug displayed in orange 
-------------------------------------------------------------------- 
-------------------- DO NOT CHANGE CODE BELOW ---------------------- 
--------------------------------------------------------------------
local Number_of_lights = #Random_lights; -- numbers of light devices listed above 
local Simulation = fibaro:getGlobal("Simu_presence"); --value of the global value: Simulation is on or off 
local Manual_overide = fibaro:getGlobal("overideSimuSunset"); -- if = 1 then the Simulation is forced
local Start_simulation_time = fibaro:getValue(1, "sunsetHour"); --Start Simulation when sunset
local End_simulation_time,Sunrise_unix_hour,Sunset_unix_hour,Converted_var,Midnight,End_simulation_time_with_random_max_TurnOff,Sleep_between_TurnOff;
local Is_first_launch = true;
local NotifLoop = 0;

YAPS_Engine = {}; 

function Debug(color, message) 
		fibaro:debug(string.format('<%s style="color:%s;">%s</%s>', "span", color, os.date("%a %d/%m", os.time()).." "..message, "span")); 
end 

function ExtraDebug(debugMessage) 
	if ( Show_extra_debug ) then 
		Debug( "orange", debugMessage); 
	end 
end 

function StandardDebug(debugMessage) 
	if ( Show_standard_debug ) then 
		Debug( "white", debugMessage); 
	end 
end 

function round(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

function PushMessage(sendPush) 
	if (Activate_Push) then 
		sendPush = os.date("%H:%M", os.time()).." "..sendPush -- add timestamp to push message
    	for i=1, #Smartphones_push do 
      		fibaro:call(tonumber(Smartphones_push[i]), 'sendPush', sendPush); 
      		ExtraDebug("Push message ("..sendPush..") sent to mobile: "..tonumber(Smartphones_push[i])); 
    	end 
    	if (Activate_FreeSms) then 
    		fibaro:setGlobal("Activate_FreeSms", sendPush)
			ExtraDebug("Message ("..sendPush..") sent to Activate_FreeSms"); 
    	end
	end 
end

function YAPS_Engine:UnixTimeCalc(Converted_var, hour, min)
	local time = os.time() ;
	local date = os.date("*t", time) ;
	local year = date.year ;
	local month = date.month ;
	local day = date.day ;
	unix_hour = os.time{year=year, month=month, day=day, hour=hour, min=min, sec=sec};
	ExtraDebug("converted "..Converted_var..": "..hour..":"..min.." to Unix Time: "..unix_hour..")")
	return unix_hour
end

function YAPS_Engine:ReverseUnixTimeCalc(Converted_var,hour)
	reverse_unix = os.date("%H:%M", hour)
	ExtraDebug("Reverse converted Unix Time of "..Converted_var.." : "..hour.." To: "..reverse_unix)
	return reverse_unix
end

function YAPS_Engine:EndTimeCalc() 
	local hour,min
    ExtraDebug ("Current Unix Time: "..os.time()) 
	End_simulation_time = YAPS_Engine:UnixTimeCalc("Original planed End_simulation_time", Stop_hour, Stop_minute); -- generate End_simulation_time (changes at midnight) will not change during Simulation, only when ended
	Midnight = YAPS_Engine:UnixTimeCalc("Midnight", 00, 00);
	
	Sunset_unix_hour = fibaro:getValue(1,'sunsetHour');
	hour = string.sub(Sunset_unix_hour, 1 , 2);
	min = string.sub(Sunset_unix_hour,4);
	Sunset_unix_hour = (YAPS_Engine:UnixTimeCalc("Sunset", hour, min))+Sunset_offset*60;

	-- if stop hour is between 00 and 12h then add 24 hours to End_simulation_time
	if tonumber(Stop_hour) <= 12 and (os.time() >= End_simulation_time) then
		End_simulation_time = End_simulation_time + 24*60*60 
		ExtraDebug ("stop hour <= 12, Added 24H to End_simulation_time (End_simulation_time is ending after midnignt)");
		ExtraDebug ("New End_simulation_time: "..End_simulation_time);
	end 
	
	if Random_max_TurnOff_duration ~= 0 and Number_of_lights > 1 then   -- if Simulation = 1 then slow turn off, else turn off all immediately
  		Sleep_between_TurnOff = round((math.random(Random_max_TurnOff_duration)/(Number_of_lights-1)),1);
		Sleep_between_TurnOff = math.random(Random_max_TurnOff_duration)/(Number_of_lights-1);
		ExtraDebug("Calculated sleeping between each turn off: "..Sleep_between_TurnOff.." min");
    else
    	Sleep_between_TurnOff = 0;
		ExtraDebug("No sleeping between turn off");
    end
	End_simulation_time_with_random_max_TurnOff = End_simulation_time + ((Sleep_between_TurnOff*(Number_of_lights-1))*60)
	ExtraDebug("End_simulation_time_with_random_max_TurnOff: "..End_simulation_time_with_random_max_TurnOff);	
	
	if ((os.time() < End_simulation_time) and (Sunset_unix_hour - End_simulation_time > 0) and (Is_first_launch == true)) then -- if calculation is done between midnight and End_simulation_time and sunset is wrongly calculated after endtime (at first start only)
		Sunset_unix_hour = Sunset_unix_hour - (24*60*60) + 70; -- remove 24h58m50s of sunsettime
		ExtraDebug ("launch after Midnight and before End_simulation_time, removed 24H to Sunset_unix_hour (Only at the first start)");
		ExtraDebug ("New SunsetTime: "..Sunset_unix_hour);
	end 
	Is_first_launch = false
			--[[
				and (os.time() > Midnight)
				Sunrise_unix_hour = fibaro:getValue(1,'sunriseHour')
				hour = string.sub(Sunrise_unix_hour, 1 , 2)
				min = string.sub(Sunrise_unix_hour,4)
				Sunrise_unix_hour = YAPS_Engine:UnixTimeCalc("Sunrise", hour, min)
			--]]
	-----------------------------------------------------------------------------------------------------		
	-- At first launch only, add 24h to End_simulation_time if End_simulation_time is after midnight and in the past
	--if ((wait_for_tomorrow == 0) and (End_simulation_time < os.time())) then -- if End_simulation_time + Random_max_TurnOff_duration (+5 min to avoid sunset shifting) is gone and it's the first launch of Simulation
		--End_simulation_time = End_simulation_time + 24*60*60 -- add 24h at End_simulation_time after the night is gone
		--Start_simulation_time = fibaro:getValue(1, "sunsetHour"); -- recalculate for next day (changes at midnight)
		--ExtraDebug ("wait_for_tomorrow = 0 Added 24H to End_simulation_time (first start ending after midnignt)");
		--ExtraDebug ("Recalculated Simulation StartHour (Sunset): " .. Start_simulation_time); 		
		--wait_for_tomorrow = 1	
	--end
	--	adds 24h to End_simulation_time after the end of Simulation (between sunrise and sunset)
	--if (wait_for_tomorrow == 1 and (End_simulation_time < os.time()) and ((now >= sunrise) and (now <= sunset))) then -- if it looping days and End_simulation_time is gone and we are daytime, then add 
		--End_simulation_time = End_simulation_time + 24*60*60 -- add 24h at End_simulation_time after the night is gone
		--Start_simulation_time = fibaro:getValue(1, "sunsetHour"); -- recalculate for next day
		--ExtraDebug ("wait_for_tomorrow = 1 Added One Day to End_simulation_time: " .. End_simulation_time);
		--ExtraDebug ("Recalculated Simulation StartHour (Sunset): " .. Start_simulation_time); 	
	--end 
	--ExtraDebug ("debug info: Recalculated planed End_simulation_time " ..End_simulation_time) 
end 
-- Presence Simulation actions Main loop
function YAPS_Engine:Launch() 
    PushMessage("Presence Simulation started. Will stop at: "..YAPS_Engine:ReverseUnixTimeCalc("End_simulation_time", End_simulation_time).." + rand("..Random_max_TurnOff_duration.."min) : "..YAPS_Engine:ReverseUnixTimeCalc("End_simulation_time_with_random_max_TurnOff", End_simulation_time_with_random_max_TurnOff));
    StandardDebug("Presence Simulation started. Will stop at: "..YAPS_Engine:ReverseUnixTimeCalc("End_simulation_time", End_simulation_time).." + rand("..Random_max_TurnOff_duration.."min) : "..YAPS_Engine:ReverseUnixTimeCalc("End_simulation_time_with_random_max_TurnOff", End_simulation_time_with_random_max_TurnOff));	
	if Lights_always_on[1] ~= nil then YAPS_Engine:TurnOn(Lights_always_on); end

    while ((os.time() <= End_simulation_time) and (Simulation == "1")) or ((Manual_overide == "1")) do 
		local random_light = tonumber(Random_lights[math.random(Number_of_lights)]) --choose a random light in the list 
		local lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light in the list 
		-- turn on the light if off or turn off if on 
		if tonumber(lightstatus) == 0 then fibaro:call(random_light, 'turnOn') else fibaro:call(random_light, 'turnOff') end 
		fibaro:sleep(1000); -- necessary to get back the new status, because HC2 is too fast :-) 
		lightstatus = fibaro:getValue(random_light, 'value') --get the value of the random light after his update 
		StandardDebug('light ID:'.. fibaro:getName(random_light) ..' status:'..lightstatus);
		local sleeptime = math.random(Random_max_duration*60000) --random sleep 
		StandardDebug("Entering loop of " .. round(sleeptime/60000,2) .. " minutes");
		-- Allows to exit the scene if the Simu_presence global var changes to 0 during the random  sleep
			local counterexitSimulation = 200
				while (counterexitSimulation > 0) and ((os.time() <= End_simulation_time) or Manual_overide == "1") do
					counterexitSimulation = counterexitSimulation - 1;
					test_presence_state = fibaro:getGlobal("Simu_presence");
					Simulation = tonumber(test_presence_state); --verify the global value, if the virtual device is deactivated, the loop stops. 
					--fibaro:debug("Simulation var state : " .. Simulation.." override var state : " .. Manual_overide);
					if Simulation == 0 then
						Manual_overide = fibaro:getGlobalValue("overideSimuSunset");
						if Simulation == 0 or Manual_overide == "0" then
						counterexitSimulation = 0
						end
					end
				fibaro:sleep(sleeptime/200);
				end
			ExtraDebug("Exiting loop of "..round(sleeptime/60000,2).." minutes");
		local sleeptimemin = math.abs(sleeptime/60000) 
		Simulation = fibaro:getGlobal("Simu_presence"); --verify the global value, if the virtual device is deactivated, the scene stops. 
		Manual_overide = fibaro:getGlobalValue("overideSimuSunset");
	end 
end 
	
function YAPS_Engine:EndSimulation() 
	if Lights_always_on[1] ~= nil then YAPS_Engine:TurnOff(Random_lights,Lights_always_on); end
	Debug("red","Presence Simulation deactivated");
	if (Simulation == "1") then
		Debug("yellow","Presence Simulation will restart tomorrow.");
		Debug("yellow","Sunset is around "..fibaro:getValue(1, "sunsetHour").." + Sunset Shift of "..Sunset_offset.."min = Start Time around "..YAPS_Engine:ReverseUnixTimeCalc("Sunset unix time", Sunset_unix_hour));
		PushMessage("Presence Simulation will restart tomorrow. Sunset is around "..fibaro:getValue(1, "sunsetHour").." + Sunset Shift of "..Sunset_offset.."min = Start Time around "..YAPS_Engine:ReverseUnixTimeCalc("Sunset unix time", Sunset_unix_hour));
	end
	NotifLoop = 0; -- will force main loop notifications at end of Simulation
end

function YAPS_Engine:ExitSimulation()
	PushMessage("Presence Simulation is terminated");
	Debug("red","Simu_presence = 0, Aborting Simulation scene");
	fibaro:abort(); 
end

function YAPS_Engine:TurnOff(group,group2) 
	Debug("red","TurnOff All Simulation lights!");
	local name, id2; 
	local ID_devices_group = group; 
	for i=1, #ID_devices_group do 
		Simulation = fibaro:getGlobal("Simu_presence"); --verify the global value, if Simulation presence is deactivated
		if Simulation == "0" then	Sleep_between_TurnOff = 0; end; -- if Simulation ended before End_simulation_time, then no turn off delay
		if i > 1 then -- wait Number of lights -1 (do not need to wait for the first TurnOff)
			StandardDebug("Sleeping "..Sleep_between_TurnOff.." minute(s) before next TurnOff");
			fibaro:sleep(Sleep_between_TurnOff*60000);
		end
		id2 = tonumber(ID_devices_group[i]); 
		fibaro:call(id2, "turnOff"); 
		name = fibaro:getName(id2); 
		if (name == nil or name == string.char(0)) then 
			name = "Unknown" 	
		end 
		StandardDebug("Device: "..name.." Off ");
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
	if Lights_On_at_end_Simulation ~= 0 and Simulation == "1" then
		fibaro:call(Lights_On_at_end_Simulation, "turnOn");
		name = fibaro:getName(Lights_On_at_end_Simulation); 
			if (name == nil or name == string.char(0)) then 
				name = "Unknown" 	
			end 
		Debug("red","Turned On light Lights_On_at_end_Simulation:");
		Debug("white", name);
	end
	if Lights_On_if_Simulation_deactivated ~= 0 and Simulation == "0" then
		fibaro:call(Lights_On_if_Simulation_deactivated, "turnOn");
    	name = fibaro:getName(Lights_On_if_Simulation_deactivated); 
			if (name == nil or name == string.char(0)) then 
				name = "Unknown" 	
			end 
		Debug("red","Turned On light Lights_On_if_Simulation_deactivated:");
		Debug("white", name);
	end
end 

function YAPS_Engine:TurnOn(group) 
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
	
Debug("green", "Presence Simulation | v" .. version .. " Starting up"); 
Debug( "green", "--------------------------------------------------------------------------");

------------------------ Main Loop ----------------------------------
-- first start notifications
YAPS_Engine:EndTimeCalc();
PushMessage("Scheduled presence Simulation at "..YAPS_Engine:ReverseUnixTimeCalc("Sunset unix time", Sunset_unix_hour).." (Sunset: "..fibaro:getValue(1, "sunsetHour")..")");
Debug("green","Sunset is at "..fibaro:getValue(1, "sunsetHour").." + Sunset Shift of "..Sunset_offset.."min = Start Time at "..YAPS_Engine:ReverseUnixTimeCalc("Sunset unix time", Sunset_unix_hour));
Debug("green","End of Simulation: "..YAPS_Engine:ReverseUnixTimeCalc("End Simulation", End_simulation_time).." + random of "..Random_max_TurnOff_duration.."min");
Debug("green", "Checking for actions every minute.");
Is_first_launch = true

while true do -- Infinite loop of actions checking, hours calculations, notifications
	YAPS_Engine:EndTimeCalc(); 
	-- local Sunset_unix_hour = Midnight  -- un-comment this line when testing to force a start hour (or use Sunset_offset)

	if os.time() >= Sunset_unix_hour then -- define if nighttime (sunset = 1)
		sunset = 1 
	else 
		sunset = 0 
	end 
	
	if (Simulation == "1") then 
		if sunset == 1 and (os.time() <= End_simulation_time) then 
			Debug("yellow", "It's sunset time -> Simulation ON");
			YAPS_Engine:Launch();
			YAPS_Engine:EndSimulation();
		end 
		if Manual_overide == "1" then 
			Debug("yellow", "Manual Override Activated -> Simulation ON");
			YAPS_Engine:Launch();
			YAPS_Engine:EndSimulation();
		end
		if Manual_overide == "0" and sunset == 0 and NotifLoop == 0 then 
			Debug("yellow", "Sunset is at "..fibaro:getValue(1, "sunsetHour").." + Sunset Shift of "..Sunset_offset.."min = Start Time at "..YAPS_Engine:ReverseUnixTimeCalc("Sunset unix time", Sunset_unix_hour));
			Debug("yellow", "End of Simulation: "..YAPS_Engine:ReverseUnixTimeCalc("End Simulation", End_simulation_time).." + random of "..Random_max_TurnOff_duration.."min = "..YAPS_Engine:ReverseUnixTimeCalc("End Simulation", End_simulation_time_with_random_max_TurnOff));
		end
	end

	if (Simulation == "0") then -- Condition to end Simulation 
		YAPS_Engine:ExitSimulation();
	end
	
	if NotifLoop <= 120 then --a waiting xx times the fibaro sleep below (2 hours) before resetting counter (and notifying)
    	if NotifLoop == 120 then NotifLoop = 0 end
		if NotifLoop == 0 then
		ExtraDebug("Now, checking for actions every minute. Next notify: in 2 hours");
		end
	end
		
	fibaro:sleep(1*60*1000); -- wait 1 minutes before testing again the global vars below
	Simulation = fibaro:getGlobal("Simu_presence"); 
	Manual_overide = fibaro:getGlobal("overideSimuSunset"); 
	NotifLoop = NotifLoop + 1;
end