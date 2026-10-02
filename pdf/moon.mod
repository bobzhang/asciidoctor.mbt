name = "bobzhang/asciidoctor-pdf"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/bobzhang/asciidoctor.mbt"

license = "MIT"

keywords = [ "asciidoc", "asciidoctor", "asciidoctor-pdf", "pdf" ]

description = "PDF backend for asciidoctor.mbt: a port of Asciidoctor PDF 2.3.27 with its themes and fonts bundled"

import {
  "bobzhang/asciidoctor@0.3.3",
  "bobzhang/prawn@0.1.0",
  "bobzhang/pygments@0.1.1",
  "moonbitlang/pagelayout@0.7.0",
  "moonbitlang/pdflite@0.3.1",
  "moonbitlang/async@0.22.4",
  "moonbit-community/yaml@0.0.7",
}

preferred_target = "native"
