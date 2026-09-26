///|
/// Records how long the processing phases (`read`, `parse`, `convert`,
/// `write`) take (Ruby `Timings`). The core is pure, so the clock is supplied
/// by the caller: a function returning the current time in seconds (ideally
/// from a monotonic clock). Pass it with `Options::new(timings=...)`; loading
/// records `read` and `parse`, converting the document records `convert`.
pub struct Timings {
  priv clock : () -> Double
  priv log : Map[String, Double]
  priv timers : Map[String, Double]
}

///|
pub fn Timings::new(clock : () -> Double) -> Timings {
  { clock, log: {}, timers: {}, }
}

///|
/// Starts the timer for `key`.
pub fn Timings::start(self : Timings, key : String) -> Unit {
  self.timers[key] = (self.clock)()
}

///|
/// Stops the timer for `key` and records the elapsed time.
pub fn Timings::record(self : Timings, key : String) -> Unit {
  match self.timers.get(key) {
    Some(started) => {
      self.timers.remove(key)
      self.log[key] = (self.clock)() - started
    }
    None => ()
  }
}

///|
/// Sets the recorded time of `key` directly.
pub fn Timings::set(self : Timings, key : String, seconds : Double) -> Unit {
  self.log[key] = seconds
}

///|
/// The sum of the times recorded for `keys`, or `None` if it is not positive.
pub fn Timings::time(self : Timings, keys : Array[String]) -> Double? {
  let mut sum = 0.0
  for key in keys {
    sum += self.log.get(key).unwrap_or(0.0)
  }
  if sum > 0.0 {
    Some(sum)
  } else {
    None
  }
}

///|
pub fn Timings::read(self : Timings) -> Double? {
  self.time(["read"])
}

///|
pub fn Timings::parse(self : Timings) -> Double? {
  self.time(["parse"])
}

///|
pub fn Timings::read_parse(self : Timings) -> Double? {
  self.time(["read", "parse"])
}

///|
pub fn Timings::convert(self : Timings) -> Double? {
  self.time(["convert"])
}

///|
pub fn Timings::read_parse_convert(self : Timings) -> Double? {
  self.time(["read", "parse", "convert"])
}

///|
pub fn Timings::write(self : Timings) -> Double? {
  self.time(["write"])
}

///|
pub fn Timings::total(self : Timings) -> Double? {
  self.time(["read", "parse", "convert", "write"])
}

///|
/// The timings report (Ruby `Timings#print_report`), one line per phase.
///
/// ```mbt check
/// test {
///   let t = @core.Timings::new(() => 0.0)
///   t.set("read", 0.00001)
///   t.set("parse", 0.00003)
///   t.set("convert", 0.00005)
///   inspect(
///     t.report(subject="doc.adoc"),
///     content=(
///       #|Input file: doc.adoc
///       #|  Time to read and parse source: 0.00004
///       #|  Time to convert document: 0.00005
///       #|  Total time (read, parse and convert): 0.00009
///       #|
///     ),
///   )
/// }
/// ```
pub fn Timings::report(self : Timings, subject? : String) -> String {
  let buf = StringBuilder()
  match subject {
    Some(s) => buf.write_string("Input file: \{s}\n")
    None => ()
  }
  buf.write_string(
    "  Time to read and parse source: \{format_seconds(self.read_parse())}\n",
  )
  buf.write_string(
    "  Time to convert document: \{format_seconds(self.convert())}\n",
  )
  buf.write_string(
    "  Total time (read, parse and convert): \{format_seconds(self.read_parse_convert())}\n",
  )
  buf.to_string()
}

///|
/// Ruby `sprintf '%05.5f', seconds.to_f`.
fn format_seconds(seconds : Double?) -> String {
  let s = seconds.unwrap_or(0.0)
  let negative = s < 0.0
  let scaled = ((if negative { -s } else { s }) * 100000.0).round().to_int64()
  let int_part = scaled / 100000L
  let frac = (scaled % 100000L).to_string()
  let frac = "0".repeat(5 - frac.length()) + frac
  "\{if negative { "-" } else { "" }}\{int_part}.\{frac}"
}
