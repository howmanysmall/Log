--!native
--!optimize 2
--!strict

type TLogMessage = (() -> (string, any?)) | string | {[any]: any}

export type LogItem = {
	ClassName: "LogItem",
	AtMostEvery: (self: LogItem, Time: number, TimeUnit: number) -> LogItem,
	Every: (self: LogItem, RunCount: number) -> LogItem,
	Throw: (self: LogItem) -> LogItem,

	Assert: <T, Arguments...>(self: LogItem, Condition: T, Arguments...) -> (T, Arguments...),
	Log: (self: LogItem, LogMessage: TLogMessage, CustomData: any?) -> (),
	Wrap: (self: LogItem) -> (LogMessage: TLogMessage, CustomData: any?) -> (),
}

export type Log = {
	Debug: (LogMessage: TLogMessage, CustomData: any?) -> (),
	Error: (LogMessage: TLogMessage, CustomData: any?) -> (),
	Fatal: (LogMessage: TLogMessage, CustomData: any?) -> (),
	Info: (LogMessage: TLogMessage, CustomData: any?) -> (),
	Trace: (LogMessage: TLogMessage, CustomData: any?) -> (),
	Warning: (LogMessage: TLogMessage, CustomData: any?) -> (),

	ErrorThrow: (LogMessage: TLogMessage, CustomData: any?) -> never,
	FatalThrow: (LogMessage: TLogMessage, CustomData: any?) -> never,

	At: (self: Log, Level: number) -> LogItem,
	AtDebug: (self: Log) -> LogItem,
	AtError: (self: Log) -> LogItem,
	AtFatal: (self: Log) -> LogItem,
	AtInfo: (self: Log) -> LogItem,
	AtTrace: (self: Log) -> LogItem,
	AtWarning: (self: Log) -> LogItem,

	Assert: <T, Arguments...>(self: Log, Condition: T, Arguments...) -> (T, Arguments...),
	Destroy: (self: Log) -> (),
}

return false
