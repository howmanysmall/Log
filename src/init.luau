--!nonstrict
--!optimize 2

-- Log
-- Stephen Leitnick
-- April 20, 2021

--[[
	IMPORTANT: Only make one logger per script/module

	Log.Level { Trace, Debug, Info, Warning, Error, Fatal }
	Log.TimeUnit { Milliseconds, Seconds, Minutes, Hours, Days, Weeks, Months, Years }

	Constructor:
		logger = Log.new()

	Log:
		Basic logging at levels:
			logger:AtTrace():Log("Hello from trace")
			logger:AtDebug():Log("Hello from debug")
			logger:AtInfo():Log("Hello from info")
			logger:AtWarning():Log("Hello from warn")
			logger:AtError():Log("Hello from error")
			logger:AtFatal():Log("Hello from fatal")
			logger:At(Log.Level.Warning):Log("Warning!")

		Log every 10 logs:
			logger:AtInfo():Every(10):Log("Log this only every 10 times")

		Log at most every 3 seconds:
			logger:AtInfo():AtMostEvery(3, Log.TimeUnit.Seconds):Log("Hello there, but not too often!")

		Wrap the Log in a function:
			local log = logger:AtDebug():Wrap()
			log("Hello")

	--------------------------------------------------------------------------------------------------------------

	LogConfig: Create a LogConfig ModuleScript anywhere in ReplicatedStorage. The configuration lets developers
	tune the lowest logging level based on various environment conditions. The LogConfig will be automatically
	required and used to set the log level.

	To set the default configuration for all environments, simply return the log level from the LogConfig:
		return "Info"

	To set a configuration that is different while in Studio:
		return {
			Studio = "Debug";
			Other = "Warning"; -- "Other" can be anything other than Studio (e.g. could be named "Default")
		}

	Fine-tune between server and client:
		return {
			Studio = {
				Server = "Info";
				Client = "Debug";
			};

			Other = "Warning";
		}

	Fine-tune based on PlaceIds:
		return {
			Studio = {
				Server = "Info";
				Client = "Debug";
			};

			Other = {
				PlaceIds = {123456, 234567}
				Server = "Severe";
				Client = "Warning";
			};
		}

	Fine-tune based on GameIds:
		return {
			Studio = {
				Server = "Info";
				Client = "Debug";
			};

			Other = {
				GameIds = {123456, 234567}
				Server = "Severe";
				Client = "Warning";
			};
		}

	Example of full-scale config with multiple environments:
		return {
			Studio = {
				Server = "Debug";
				Client = "Debug";
			};

			Dev = {
				PlaceIds = {1234567};
				Server = "Info";
				Client = "Info";
			};

			Prod = {
				PlaceIds = {2345678};
				Server = "Severe";
				Client = "Warning";
			};

			Default = "Info";
		}
--]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClassDefinition = require(script:FindFirstChild("ClassDefinition"))
local InfoLog = require(script:FindFirstChild("InfoLog"))

export type Log = ClassDefinition.Log
export type LogItem = ClassDefinition.LogItem

local IS_STUDIO = RunService:IsStudio()
local IS_SERVER = RunService:IsServer()

local AnalyticsLogLevel = Enum.AnalyticsLogLevel

local configModule = ReplicatedStorage:FindFirstChild("LogConfig", true)
	or ReplicatedStorage:FindFirstChild("log-config", true)

local UseInfoLogForInfo = false

local config = "Debug"
if configModule then
	config = require(configModule)
else
	warn("Missing LogConfig?")
end

local logLevel = nil
local timeFunc = os.clock

local _AnalyticsLogLevel = {
	Trace = 0;
	Debug = 1;
	Information = 2;
	Warning = 3;
	Error = 4;
	Fatal = 5;
}

local logLevels = {
	Trace = AnalyticsLogLevel.Trace.Value;
	Debug = AnalyticsLogLevel.Debug.Value;
	Info = AnalyticsLogLevel.Information.Value;
	Warning = AnalyticsLogLevel.Warning.Value;
	Error = AnalyticsLogLevel.Error.Value;
	Fatal = AnalyticsLogLevel.Fatal.Value;
}

local timeUnits = {
	Milliseconds = 0;
	Seconds = 1;
	Minutes = 2;
	Hours = 3;
	Days = 4;
	Weeks = 5;
	Months = 6;
	Years = 7;
}

local function ToSeconds(n, timeUnit)
	if timeUnit == timeUnits.Milliseconds then
		return n / 1_000
	elseif timeUnit == timeUnits.Seconds then
		return n
	elseif timeUnit == timeUnits.Minutes then
		return n * 60
	elseif timeUnit == timeUnits.Hours then
		return n * 3_600
	elseif timeUnit == timeUnits.Days then
		return n * 86_400
	elseif timeUnit == timeUnits.Weeks then
		return n * 604_800
	elseif timeUnit == timeUnits.Months then
		return n * 2_592_000
	elseif timeUnit == timeUnits.Years then
		return n * 31_536_000
	else
		error(`Unknown time unit {timeUnit}`, 2)
	end
end

local LogItems = (setmetatable({}, {__mode = "k"}) :: unknown) :: {[LogItem]: boolean}

local LogItem = {}
LogItem.ClassName = "LogItem"
LogItem.__index = LogItem

function LogItem.new(log, levelName, traceback, key, isDisabled: boolean, level)
	local self = setmetatable({
		_isDisabled = isDisabled;
		_level = level;

		_log = log;
		_traceback = traceback;
		_levelName = levelName;
		_modifiers = {Throw = false};
		_key = key;
	}, LogItem)

	LogItems[(self :: unknown) :: LogItem] = true
	return self
end

function LogItem:_shouldLog(stats)
	if self._modifiers.Every and not stats:_checkAndIncrementCount(self._modifiers.Every) then
		return false
	end

	if self._modifiers.AtMostEvery and not stats:_checkLastTimestamp(timeFunc(), self._modifiers.AtMostEvery) then
		return false
	end

	return true
end

function LogItem:Every(n: number)
	self._modifiers.Every = n
	return self
end

function LogItem:AtMostEvery(n: number, timeUnit: number)
	self._modifiers.AtMostEvery = ToSeconds(n, timeUnit)
	return self
end

function LogItem:Throw()
	self._modifiers.Throw = true
	return self
end

function LogItem:Log(message, customData)
	if self._isDisabled then
		return
	end

	local stats = self._log:_getLogStats(self._key)
	if not self:_shouldLog(stats) then
		return
	end

	if type(message) == "function" then
		local msg, data = message()
		message = msg
		if data ~= nil then
			customData = data
		end
	elseif type(message) == "table" then
		message = HttpService:JSONEncode(message)
	end

	stats:_setTimestamp(timeFunc())
	local logMessage = `{self._log._name}: [{self._levelName}] {message}`
	local logLevelNum = logLevels[self._levelName]

	if UseInfoLogForInfo or self._log._useInfoLog then
		if self._modifiers.Throw then
			error(logMessage .. (if customData then " " .. HttpService:JSONEncode(customData) else ""), 4)
		elseif logLevelNum == logLevels.Info then
			if customData ~= nil then
				InfoLog(logMessage, customData or "")
			else
				InfoLog(logMessage)
			end
		elseif logLevelNum < logLevels.Warning then
			if customData ~= nil then
				print(logMessage, customData or "")
			else
				print(logMessage)
			end
		else
			if customData then
				warn(logMessage, customData or "")
			else
				warn(logMessage)
			end
		end
	else
		if self._modifiers.Throw then
			error(logMessage .. (if customData then " " .. HttpService:JSONEncode(customData) else ""), 4)
		elseif logLevelNum < logLevels.Warning then
			if customData ~= nil then
				print(logMessage, customData or "")
			else
				print(logMessage)
			end
		else
			if customData ~= nil then
				warn(logMessage, customData or "")
			else
				warn(logMessage)
			end
		end
	end
end

function LogItem:Wrap()
	return function(...)
		self:Log(...)
	end
end

function LogItem:Assert(condition, ...)
	if not condition then
		self:Throw():Log(...)
	end

	return condition, ...
end

function LogItem:__tostring()
	return `LogItem<{self._log._name}>`
end

local LogStats = {}
LogStats.ClassName = "LogStats"
LogStats.__index = LogStats

function LogStats.new()
	local self = setmetatable({}, LogStats)
	self._invocationCount = 0
	self._lastTimestamp = 0
	return self
end

function LogStats:_checkAndIncrementCount(rateLimit)
	local check = self._invocationCount % rateLimit == 0
	self._invocationCount += 1
	return check
end

function LogStats:_checkLastTimestamp(now, intervalSeconds)
	return now - self._lastTimestamp >= intervalSeconds
end

function LogStats:_setTimestamp(now)
	self._lastTimestamp = now
end

--[=[
	@class Log
	@server
	Log class for logging to the AnalyticsService (e.g. PlayFab). The API
	is based off of Google's [Flogger](https://google.github.io/flogger/)
	fluent logging API.

	```lua
	local Log = require(somewhere.Log)
	local logger = Log.new()

	-- Log a simple message:
	logger:AtInfo():Log("Hello world!")

	-- Log only every 3 messages:
	for i = 1,20 do
		logger:AtInfo():Every(3):Log("Hi there!")
	end

	-- Log only every 1 second:
	for i = 1,100 do
		logger:AtInfo():AtMostEvery(3, Log.TimeUnit.Seconds):Log("Hello!")
		task.wait(0.1)
	end

	-- Wrap the above example into a function:
	local log = logger:AtInfo():AtMostEvery(3, Log.TimeUnit.Seconds):Wrap()
	for i = 1,100 do
		log("Hello!")
		task.wait(0.1)
	end

	-- Assertion:
	logger:Assert(typeof(32) == "number", "Somehow 32 is no longer a number")
	```

	------------

	### LogConfig

	A LogConfig ModuleScript is expected to exist somewhere within ReplicatedStorage
	as well. This ModuleScript defines the behavior for the logger. If not found,
	the logger will default to the Debug log level for all operations.

	For instance, this could be a script located at `ReplicatedStorage.MyGameConfig.LogConfig`. There
	just needs to be some `LogConfig`-named ModuleScript within ReplicatedStorage.

	Below are a few examples of possible LogConfig ModuleScripts:

	```lua
	-- Set "Info" as default log level for all environments:
	return "Info"
	```

	```lua
	-- To set a configuration that is different while in Studio:
	return {
		Studio = "Debug";
		Other = "Warning"; -- "Other" can be anything other than Studio (e.g. could be named "Default")
	}
	```

	```lua
	-- Fine-tune between server and client:
	return {
		Studio = {
			Server = "Info";
			Client = "Debug";
		};

		Other = "Warning";
	}
	```

	```lua
	-- Fine-tune based on PlaceIds:
	return {
		Studio = {
			Server = "Info";
			Client = "Debug";
		};

		Other = {
			PlaceIds = {123456, 234567}
			Server = "Severe";
			Client = "Warning";
		};
	}
	```

	```lua
	-- Fine-tune based on GameIds:
	return {
		Studio = {
			Server = "Info";
			Client = "Debug";
		};

		Other = {
			GameIds = {123456, 234567}
			Server = "Severe";
			Client = "Warning";
		};
	}
	```

	```lua
	-- Example of full-scale config with multiple environments:
	return {
		Studio = {
			Server = "Debug";
			Client = "Debug";
		};

		Dev = {
			PlaceIds = {1234567};
			Server = "Info";
			Client = "Info";
		};

		Prod = {
			PlaceIds = {2345678};
			Server = "Severe";
			Client = "Warning";
		};

		Default = "Info";
	}
	```
]=]
local Log = {}
Log.ClassName = "Log"
Log.__index = Log

--[=[
	@within Log
	@interface LogItem
	.Log (message: any, customData: table?) -- Log the message
	.Every (n: number) -- Log only every `n` times
	.AtMostEvery (n: number, timeUnit: TimeUnit) -- Log only every `n` `TimeUnit`
	.Throw () -- Throw an error
	.Wrap () -- Returns a function that can be called which will log out the given arguments
	.Assert (condition: boolean, args: ...) -- Assert the condition
]=]

--[=[
	@within Log
	@interface TimeUnit
	.Milliseconds number
	.Seeconds number
	.Minutes number
	.Hours number
	.Days number
	.Weeks number
	.Months number
	.Years number
]=]

--[=[
	@within Log
	@interface Level
	.Trace number
	.Debug number
	.Info number
	.Warning number
	.Error number
	.Fatal number
]=]

--[=[
	@within Log
	@prop TimeUnit TimeUnit
	@readonly
]=]

--[=[
	@within Log
	@prop Level Level
	@readonly
]=]

Log.TimeUnit = timeUnits
Log.Level = logLevels

Log.LevelNames = {}
for name, num in Log.Level do
	Log.LevelNames[num] = name
end

local function GetName(String: string)
	local NewString = string.match(String, "\"(.+)\"%]")
	if NewString and string.sub(NewString, -6) == ".story" then
		local Array = string.split(NewString, ".")
		local Length = #Array
		local StringArray = table.move(Array, Length - 1, Length, 1, table.create(2))
		String = table.concat(StringArray, ".")
	end

	return if string.sub(String, -6) == ".story"
		then String
		else string.match(String, "([^%.]-)\"%]$") or string.match(String, "([^%.]-)$")
end

--[=[
	@return Log
	Construct a new Log object.

	:::warning
	This should only be called once per script.
	:::

	@return Log
]=]
function Log.new(useInfoLog: boolean?): Log
	local name = GetName(debug.info(2, "s"))
	return Log.ForName(name, useInfoLog)
end

function Log.ForName(scriptName: string, useInfoLog: boolean?): Log
	debug.setmemorycategory(scriptName)
	local self = setmetatable({}, Log)

	self._name = scriptName
	self._stats = {}
	self._useInfoLog = not not useInfoLog

	self.Debug = self:AtDebug():Wrap()
	self.Error = self:AtError():Wrap()
	self.Fatal = self:AtFatal():Wrap()
	self.Info = self:AtInfo():Wrap()
	self.Trace = self:AtTrace():Wrap()
	self.Warning = self:AtWarning():Wrap()

	self.ErrorThrow = self:AtError():Throw():Wrap()
	self.FatalThrow = self:AtFatal():Throw():Wrap()

	return self :: any
end

function Log.SetInfoLogEnabled(enabled: boolean)
	UseInfoLogForInfo = enabled
end

function Log:SetInfoLog(useInfoLog: boolean): Log
	self._useInfoLog = useInfoLog
	return self
end

function Log:_getLogStats(key)
	local stats = self._stats[key]
	if not stats then
		stats = LogStats.new()
		self._stats[key] = stats
	end

	return stats
end

function Log:_at(level): any
	local l, f = debug.info(3, "lf")
	local traceback = debug.traceback("Log", 3)
	local key = tostring(l) .. tostring(f)

	-- if level < logLevel then
	-- 	return LogItemBlank.new(self, Log.LevelNames[level], traceback, key, level < logLevel)
	-- else
	-- 	return LogItem.new(self, Log.LevelNames[level], traceback, key)
	-- end

	return LogItem.new(self, Log.LevelNames[level], traceback, key, level < logLevel, level)
end

--[=[
	@param level LogLevel
	@return LogItem
]=]
function Log:At(level: number): LogItem
	return self:_at(level)
end

--[=[
	@return LogItem
	Get a LogItem at the Trace log level.
]=]
function Log:AtTrace(): LogItem
	return self:_at(Log.Level.Trace)
end

--[=[
	@return LogItem
	Get a LogItem at the Debug log level.
]=]
function Log:AtDebug(): LogItem
	return self:_at(Log.Level.Debug)
end

--[=[
	@return LogItem
	Get a LogItem at the Info log level.
]=]
function Log:AtInfo(): LogItem
	return self:_at(Log.Level.Info)
end

--[=[
	@return LogItem
	Get a LogItem at the Warning log level.
]=]
function Log:AtWarning(): LogItem
	return self:_at(Log.Level.Warning)
end

--[=[
	@return LogItem
	Get a LogItem at the Error log level.
]=]
function Log:AtError(): LogItem
	return self:_at(Log.Level.Error)
end

--[=[
	@return LogItem
	Get a LogItem at the Fatal log level.
]=]
function Log:AtFatal(): LogItem
	return self:_at(Log.Level.Fatal)
end

--[=[
	@param condition boolean
	@param ... any
	Asserts the condition and then logs the following
	arguments at the Error level if the condition
	fails.
]=]
function Log:Assert(condition, ...)
	if not condition then
		self.ErrorThrow(...)
	end

	return condition, ...
end

function Log:Destroy() end
function Log:__tostring()
	return `Log<{self._name}>`
end

type Level = "Trace" | "Debug" | "Info" | "Warning" | "Error" | "Fatal"
type LogConfigurationEntry = {
	Client: Level,
	Server: Level,

	GameId: number?,
	GameIds: {number}?,

	PlaceId: number?,
	PlaceIds: {number}?,
}
type LevelOrEntry = Level | LogConfigurationEntry
type LogConfiguration = {
	Default: LevelOrEntry?,
	Studio: LevelOrEntry?,
	[string]: LevelOrEntry?,
}

local function Resolve(levelOrEntry: Level | LogConfigurationEntry): Level
	if type(levelOrEntry) == "string" then
		return levelOrEntry
	end

	return if IS_SERVER then levelOrEntry.Server else levelOrEntry.Client
end
local function GetLogLevel(parseConfiguration: LogConfiguration | Level): Level
	if type(parseConfiguration) == "string" then
		return Resolve(parseConfiguration)
	end

	local castBecauseLuauSucks = parseConfiguration :: LogConfiguration

	if IS_STUDIO then
		local studioConfiguration = castBecauseLuauSucks.Studio
		if studioConfiguration then
			return Resolve(studioConfiguration :: Level)
		end
	end

	local matchedKey: string? = nil
	local matchedEntry: LevelOrEntry? = nil

	for key, value in (castBecauseLuauSucks :: unknown) :: {[string]: LevelOrEntry} do
		if key == "Studio" or key == "Default" or type(value) == "string" then
			continue
		end

		local valueCastLuauSucks = (value :: unknown) :: LogConfigurationEntry

		local hasHit = (valueCastLuauSucks.GameId and game.GameId == valueCastLuauSucks.GameId)
			or (valueCastLuauSucks.GameIds and table.find(valueCastLuauSucks.GameIds, game.GameId) ~= nil)
			or (valueCastLuauSucks.PlaceId and game.PlaceId == valueCastLuauSucks.PlaceId)
			or (valueCastLuauSucks.PlaceIds and table.find(valueCastLuauSucks.PlaceIds, game.PlaceId) ~= nil)

		if hasHit then
			if matchedEntry then
				error(`More than one LogConfig mapping matched ({matchedKey} and {key})`)
			end

			matchedEntry = valueCastLuauSucks
			matchedKey = key
		end
	end

	if matchedEntry then
		return Resolve(matchedEntry)
	end

	local default = castBecauseLuauSucks.Default
	if default then
		return Resolve(default :: LevelOrEntry)
	end

	error("No matching LogConfiguration entry and Default is not defined")
end

-- Determine log level:
do
	local function SetLogLevel(name: string): ()
		local n = string.lower(name)
		for levelName, level in Log.Level :: {[string]: number} do
			if string.lower(levelName) == n then
				-- 	if IS_STUDIO then
				local attribute = if IS_SERVER then "LogLevel" else "LogLevelClient"
				local displayName = string.upper(string.sub(n, 1, 1)) .. string.sub(n, 2)
				if tostring(Workspace:GetAttribute(attribute) or "") ~= displayName then
					Workspace:SetAttribute(attribute, displayName)
				end
				-- 	end

				logLevel = level
				for logItem in LogItems do
					logItem._isDisabled = logItem._level < logLevel
				end

				return
			end
		end

		error("Unknown log level: " .. tostring(name))
	end

	local configType = type(config)
	assert(
		configType == "table" or configType == "string",
		"LogConfig must return a table or a string; got " .. configType
	)

	SetLogLevel(GetLogLevel(config))
	-- if configType == "string" then
	-- 	SetLogLevel(config)
	-- else
	-- 	if IS_STUDIO and config.Studio then
	-- 		local studioConfigType = type(config.Studio)
	-- 		assert(
	-- 			studioConfigType == "table" or studioConfigType == "string",
	-- 			"LogConfig.Studio must be a table or a string; got " .. studioConfigType
	-- 		)

	-- 		if studioConfigType == "string" then
	-- 			-- Config for Studio:
	-- 			SetLogLevel(config.Studio)
	-- 		else
	-- 			-- Server/Client config for Studio:
	-- 			if IS_SERVER then
	-- 				local studioServerLevel = config.Studio.Server
	-- 				assert(
	-- 					type(studioServerLevel) == "string",
	-- 					"LogConfig.Studio.Server must be a string; got " .. type(studioServerLevel)
	-- 				)

	-- 				SetLogLevel(studioServerLevel)
	-- 			else
	-- 				local studioClientLevel = config.Studio.Client
	-- 				assert(
	-- 					type(studioClientLevel) == "string",
	-- 					"LogConfig.Studio.Client must be a string; got " .. type(studioClientLevel)
	-- 				)

	-- 				SetLogLevel(studioClientLevel)
	-- 			end
	-- 		end
	-- 	else
	-- 		local default = nil
	-- 		local numDefault = 0
	-- 		local set = false
	-- 		local setK = nil
	-- 		for k, specialConfig in config do
	-- 			if k == "Studio" then
	-- 				continue
	-- 			end

	-- 			if type(specialConfig) == "string" then
	-- 				default = specialConfig
	-- 				numDefault += 1
	-- 			elseif type(specialConfig) == "table" then
	-- 				-- Check if config can be used if filtered by PlaceId or GameId:
	-- 				local canUse, fallthrough = false, false
	-- 				if type(specialConfig.PlaceId) == "number" then
	-- 					canUse = specialConfig.PlaceId == game.PlaceId
	-- 				elseif type(specialConfig.PlaceIds) == "table" then
	-- 					canUse = table.find(specialConfig.PlaceIds, game.PlaceId) ~= nil
	-- 				elseif type(specialConfig.GameId) == "number" then
	-- 					canUse = specialConfig.GameId == game.GameId
	-- 				elseif type(specialConfig.GameIds) == "table" then
	-- 					canUse = table.find(specialConfig.GameIds, game.GameId) ~= nil
	-- 				else
	-- 					canUse = true
	-- 					fallthrough = true
	-- 				end

	-- 				if not fallthrough then
	-- 					assert(
	-- 						not set,
	-- 						string.format("More than one LogConfig mapping matched (%* and %*)", setK or "", k or "")
	-- 					)
	-- 				end

	-- 				if canUse then
	-- 					if IS_SERVER then
	-- 						local serverLevel = specialConfig.Server
	-- 						assert(
	-- 							type(serverLevel) == "string",
	-- 							string.format("LogConfig.%*.Server must be a string; got %*", k, type(serverLevel))
	-- 						)

	-- 						SetLogLevel(serverLevel)
	-- 						set = true
	-- 						setK = k
	-- 					else
	-- 						local clientLevel = specialConfig.Client
	-- 						assert(
	-- 							type(clientLevel) == "string",
	-- 							string.format("LogConfig.%*.Client must be a string; got %*", k, type(clientLevel))
	-- 						)

	-- 						SetLogLevel(clientLevel)
	-- 						set = true
	-- 						setK = k
	-- 					end
	-- 				end
	-- 			else
	-- 				warn(string.format("LogConfig.%* must be a table or a string; got %*", k, typeof(specialConfig)))
	-- 			end
	-- 		end

	-- 		if numDefault > 1 then
	-- 			warn("Ambiguous default logging level")
	-- 		end

	-- 		if default and not set then
	-- 			SetLogLevel(default)
	-- 		end
	-- 	end
	-- end

	assert(type(logLevel) == "number", "LogLevel failed to be determined")
	-- if IS_STUDIO then
	local attribute = if IS_SERVER then "LogLevel" else "LogLevelClient"
	Workspace:GetAttributeChangedSignal(attribute):Connect(function()
		SetLogLevel(Workspace:GetAttribute(attribute))
	end)
	-- end
end

--export type Log = typeof(Log.new())
table.freeze(Log)
return Log
