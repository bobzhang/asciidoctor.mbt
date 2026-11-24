// The `asciidoctor-pdf` command (see the package bobzhang/asciidoctor-pdf/cli):
// source blocks are highlighted with Rouge (`source-highlighter: rouge`);
// `cmd/asciidoctor-pdf-pygments` is the same command with Pygments too.

///|
async fn main_async() -> Unit {
  @cli.run_process()
}

///|
fn main {
  @async.run_async_main(main_async)
}
