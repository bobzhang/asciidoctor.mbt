///|
/// Seconds from a monotonic clock, for the timings report (`-t`). The wasm
/// target uses the millisecond clock of `moonbitlang/async`.
#cfg(target="native")
extern "C" fn monotonic_seconds() -> Double = "asciidoctor_cli_monotonic_seconds"

///|
#cfg(not(target="native"))
fn monotonic_seconds() -> Double {
  @async.now().to_double() / 1000.0
}
