///|
/// Log severity (Ruby `::Logger::Severity`).
pub(all) enum Severity {
  Debug
  Info
  Warn
  Error
  Fatal
  Unknown
} derive(Eq, Debug)

///|
pub fn Severity::to_int(self : Severity) -> Int {
  match self {
    Debug => 0
    Info => 1
    Warn => 2
    Error => 3
    Fatal => 4
    Unknown => 5
  }
}

///|
/// Label used by the basic formatter (`WARN` → `WARNING`, `FATAL` → `FAILED`).
pub fn Severity::label(self : Severity) -> String {
  match self {
    Debug => "DEBUG"
    Info => "INFO"
    Warn => "WARNING"
    Error => "ERROR"
    Fatal => "FAILED"
    Unknown => "ANY"
  }
}

///|
/// A log message with optional source context (Ruby `message_with_context`).
pub(all) struct LogMessage {
  severity : Severity
  text : String
  source_location : Cursor?
  include_location : Cursor?
} derive(Debug)

///|
/// `path: line N: text` when a source location is present (Ruby `AutoFormattingMessage#inspect`).
pub fn LogMessage::to_string(self : LogMessage) -> String {
  match self.source_location {
    Some(loc) => "\{loc.line_info()}: \{self.text}"
    None => self.text
  }
}

///|
/// A logger. Messages below `level` are dropped (except by a memory logger,
/// which records everything, like Ruby's `MemoryLogger`).
pub struct Logger {
  mut level : Severity
  mut max_severity : Severity?
  priv sink : (LogMessage) -> Unit
  priv record_all : Bool
}

///|
/// Creates a logger that forwards messages at or above `level` to `sink`.
pub fn Logger::new(
  sink : (LogMessage) -> Unit,
  level? : Severity = Warn,
) -> Logger {
  { level, max_severity: None, sink, record_all: false, }
}

///|
/// A logger that discards messages but tracks the maximum severity.
pub fn Logger::null() -> Logger {
  { level: Unknown, max_severity: None, sink: _ => (), record_all: false, }
}

///|
/// A logger that records every message into `messages`.
pub fn Logger::memory(messages : Array[LogMessage]) -> Logger {
  {
    level: Debug,
    max_severity: None,
    sink: m => messages.push(m),
    record_all: true,
  }
}

///|
/// Formats a message like Ruby's `Asciidoctor::Logger::BasicFormatter`.
pub fn format_log_message(m : LogMessage) -> String {
  "asciidoctor: \{m.severity.label()}: \{m.to_string()}"
}

///|
pub fn Logger::add(self : Logger, m : LogMessage) -> Unit {
  match self.max_severity {
    Some(s) if s.to_int() >= m.severity.to_int() => ()
    _ => self.max_severity = Some(m.severity)
  }
  if self.record_all || m.severity.to_int() >= self.level.to_int() {
    (self.sink)(m)
  }
}

///|
/// Sets the minimum severity of messages forwarded to the sink.
pub fn Logger::set_level(self : Logger, level : Severity) -> Unit {
  self.level = level
}

///|
pub fn Logger::is_debug(self : Logger) -> Bool {
  self.record_all || self.level.to_int() <= 0
}

///|
pub fn Logger::is_info(self : Logger) -> Bool {
  self.record_all || self.level.to_int() <= 1
}

///|
let current_logger : Ref[Logger] = { val: Logger::null(), }

///|
/// The global logger (Ruby `LoggerManager.logger`).
pub fn logger() -> Logger {
  current_logger.val
}

///|
/// Replaces the global logger; returns the previous one.
pub fn set_logger(l : Logger) -> Logger {
  let old = current_logger.val
  current_logger.val = l
  old
}

///|
/// Runs `f` with a memory logger installed and returns the recorded messages.
pub fn[T] with_memory_logger(f : () -> T) -> (T, Array[LogMessage]) {
  let messages = []
  let old = set_logger(Logger::memory(messages))
  let r = f()
  set_logger(old) |> ignore
  (r, messages)
}

///|
fn log_msg(
  severity : Severity,
  text : String,
  source_location? : Cursor,
  include_location? : Cursor,
) -> Unit {
  logger().add({ severity, text, source_location, include_location, })
}

///|
fn log_warn(
  text : String,
  source_location? : Cursor,
  include_location? : Cursor,
) -> Unit {
  log_msg(Warn, text, source_location?, include_location?)
}

///|
fn log_error(
  text : String,
  source_location? : Cursor,
  include_location? : Cursor,
) -> Unit {
  log_msg(Error, text, source_location?, include_location?)
}

///|
fn log_info(text : String, source_location? : Cursor) -> Unit {
  log_msg(Info, text, source_location?)
}

///|
fn log_debug(text : String, source_location? : Cursor) -> Unit {
  log_msg(Debug, text, source_location?)
}

///|
/// Keys of one-time actions already performed in this process (Ruby keeps such
/// state in class variables, e.g. warning once that a gem is unavailable).
let once_keys : Map[String, Bool] = Map([])

///|
/// Returns true the first time it is called with `key` in this process.
fn once_per_process(key : String) -> Bool {
  if once_keys.contains(key) {
    false
  } else {
    once_keys[key] = true
    true
  }
}

///|
/// Snapshot of the process-wide one-time state (see `restore_process_state`).
pub fn snapshot_process_state() -> Array[String] {
  once_keys.keys().collect()
}

///|
/// Restores the process-wide one-time state. Used by drivers that rerun the
/// pipeline (e.g. `@io`) so each run observes the same state.
pub fn restore_process_state(keys : Array[String]) -> Unit {
  once_keys.clear()
  for k in keys {
    once_keys[k] = true
  }
}
