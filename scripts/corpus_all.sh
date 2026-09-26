#!/bin/sh
# Byte-for-byte comparison with Ruby Asciidoctor over every AsciiDoc corpus
# cloned into .repos/ (asciidoctor docs, asciidoctor-pdf, -diagram, -epub3,
# asciidoctorj), for the html5, docbook5 and manpage backends.
# Clone extra corpora with: git clone --depth 1 https://github.com/asciidoctor/<name> .repos/<name>
cd "$(dirname "$0")/.."
for b in html5 docbook5 manpage; do
  for d in asciidoctor/docs asciidoctor-pdf asciidoctor-diagram asciidoctor-epub3 asciidoctorj; do
    [ -d ".repos/$d" ] || continue
    printf '%-9s %-22s ' "$b" "$d"
    BACKEND=$b OUT="${TMPDIR:-/tmp}/corpus-$b-$(echo $d | tr / -)" scripts/corpus_compare.sh "$PWD/.repos/$d" | tail -1
  done
done
