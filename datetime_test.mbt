///|
test "date attributes use the installed local time zone" {
  @core.set_now_epoch(() => 1700000000L)
  @core.set_utc_offset(_ => 19800)
  let doc = @asciidoctor.load("= Title")
  debug_inspect(
    [doc.attr("localdatetime"), doc.attr("docdatetime"), doc.attr("localyear")],
    content=(
      #|[
      #|  Some("2023-11-15 03:43:20 +0530"),
      #|  Some("2023-11-15 03:43:20 +0530"),
      #|  Some("2023"),
      #|]
    ),
  )
  @core.set_utc_offset(_ => -18000)
  debug_inspect(
    @asciidoctor.load("= Title").attr("localtime"),
    content=(
      #|Some("17:13:20 -0500")
    ),
  )
  // SOURCE_DATE_EPOCH pins the date and forces UTC, as in Ruby
  @core.set_source_date_epoch(Some(1700000000L))
  debug_inspect(
    @asciidoctor.load("= Title").attr("localtime"),
    content=(
      #|Some("22:13:20 UTC")
    ),
  )
  @core.set_source_date_epoch(None)
  @core.set_utc_offset(_ => 0)
  debug_inspect(
    @asciidoctor.load("= Title").attr("localtime"),
    content=(
      #|Some("22:13:20 UTC")
    ),
  )
}
