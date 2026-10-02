// The `asciidoctor-pdf` command with Pygments: the command of
// cmd/asciidoctor-pdf, with bobzhang/pygments registered for
// `source-highlighter: pygments` (larger: it links Pygments' lexers).

///|
async fn main {
  @pygments.register()
  @cli.run_process()
}
