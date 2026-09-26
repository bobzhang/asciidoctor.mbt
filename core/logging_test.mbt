// Ported from test/logger_test.rb.
//
// Skipped (no counterpart in the port): logger_class / resetting the logger
// to a falsy value, logdev/file/progname options of the stdlib ::Logger,
// the :logger API option, and the Logging mixin tests. The port's default
// global logger is a null logger (the CLI installs a stderr logger), so the
// "default logger writes to $stderr" tests are covered via the formatter.

///|
test "LoggerManager: allows logger instance to be changed" {
  let seen = []
  let new_logger = @core.Logger::new(m => seen.push(m.text))
  let old_logger = @core.set_logger(new_logger)
  assert_true(physical_equal(@core.logger(), new_logger))
  @core.logger().add({
    severity: Warn,
    text: "this is a call",
    source_location: None,
    include_location: None,
  })
  let restored = @core.set_logger(old_logger)
  assert_true(physical_equal(restored, new_logger))
  debug_inspect(
    seen,
    content=(
      #|["this is a call"]
    ),
  )
}

///|
test "Logger: should set level to value specified by level kwarg" {
  let seen = []
  let logger = @core.Logger::new(m => seen.push(m.text), level=Fatal)
  logger.add({
    severity: Warn,
    text: "this is a call",
    source_location: None,
    include_location: None,
  })
  assert_true(seen.is_empty())
  debug_inspect(logger.level, content="Fatal")
}

///|
test "Logger: should configure logger with level set to WARN by default" {
  debug_inspect(@core.Logger::new(_ => ()).level, content="Warn")
}

///|
test "Logger: configures default logger to use a formatter that matches traditional format" {
  let lines = []
  let logger = @core.Logger::new(m => lines.push(@core.format_log_message(m)))
  logger.add({
    severity: Warn,
    text: "this is a call",
    source_location: None,
    include_location: None,
  })
  logger.add({
    severity: Fatal,
    text: "it cannot be done",
    source_location: None,
    include_location: None,
  })
  debug_inspect(
    lines,
    content=(
      #|[
      #|  "asciidoctor: WARNING: this is a call",
      #|  "asciidoctor: FAILED: it cannot be done",
      #|]
    ),
  )
}

///|
test "Logger: NullLogger level is not nil" {
  debug_inspect(@core.Logger::null().level, content="Unknown")
}

///|
test "Logger: MemoryLogger level is not nil" {
  debug_inspect(@core.Logger::memory([]).level, content="Unknown")
}

///|
// Asciidoctor::Logger#add / NullLogger#add / MemoryLogger#max_severity
test "Logger: tracks max severity of messages added (extra)" {
  let logger = @core.Logger::null()
  debug_inspect(logger.max_severity, content="None")
  for sev in [@core.Severity::Info, Error, Warn] {
    logger.add({
      severity: sev,
      text: "msg",
      source_location: None,
      include_location: None,
    })
  }
  debug_inspect(logger.max_severity, content="Some(Error)")
  // messages below the level still count toward max severity (Ruby Logger#add)
  let warn_logger = @core.Logger::new(_ => ())
  warn_logger.add({
    severity: Info,
    text: "msg",
    source_location: None,
    include_location: None,
  })
  debug_inspect(warn_logger.max_severity, content="Some(Info)")
}

///|
test "Logging: can create an auto-formatting message with context" {
  let cursor = @core.Cursor::new(
    file="file.adoc",
    dir="/fixtures",
    path="file.adoc",
    lineno=5,
  )
  let message : @core.LogMessage = {
    severity: Warn,
    text: "Asciidoctor was here",
    source_location: Some(cursor),
    include_location: None,
  }
  inspect(message.text, content="Asciidoctor was here")
  assert_true(message.source_location is Some(c) && physical_equal(c, cursor))
  inspect(
    message.to_string(),
    content="file.adoc: line 5: Asciidoctor was here",
  )
}

///|
test "Logging: writes message prefixed with program name and source location to stderr" {
  let input =
    #|[#first]
    #|first paragraph
    #|
    #|[#first]
    #|another first paragraph
  let (_, messages) = @core.with_memory_logger(() => {
    @asciidoctor.convert(input, options=@core.Options::new(standalone=false))
  })
  inspect(
    messages.map(@core.format_log_message).join("\n"),
    content="asciidoctor: WARNING: <stdin>: line 5: id assigned to block already in use: first",
  )
}
