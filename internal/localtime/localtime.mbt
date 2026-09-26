///|
/// Offset of the local time zone from UTC, in seconds, at `epoch` (seconds
/// since the Unix epoch). The wasm target has no time-zone database and
/// always reports UTC.
pub fn utc_offset(epoch : Int64) -> Int {
  c_utc_offset(epoch)
}

///|
#cfg(target="native")
extern "C" fn c_utc_offset(epoch : Int64) -> Int = "asciidoctor_utc_offset"

///|
#cfg(not(target="native"))
fn c_utc_offset(_epoch : Int64) -> Int {
  0
}
