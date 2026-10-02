# frozen_string_literal: true
# Rouge oracle for pdf/rouge (see scripts/pdf_rouge_harvest.mbtx).
#
#   ruby harvest.rb OUT.json ROUGE_CHECKOUT SPEC_DIR ASCIIDOCTOR_PDF_LIB TAG...
#
# Writes one JSON object with what the MoonBit port of Rouge 3.30 is
# generated from or checked against:
#   tokens   every token type: [qualname, shortname]
#   themes   every registered theme (and asciidoctor-pdf's default):
#            name => [[qualname, fg, bg, bold, italic, underline]...], the
#            styles the theme sets itself or inherits, colors resolved
#   unicode  code point ranges of the Unicode properties the MoonBit regex
#            engine lacks, as the running Ruby (Onigmo) defines them
#   cases    lexing cases of the lexers TAG...: [name, lexer spec, input,
#            tokens], tokens as `shortname:length` (UTF-16 code units),
#            from Rouge's demos, its visual samples (truncated at a line
#            boundary), the source blocks of asciidoctor-pdf's specs, the
#            inputs of Rouge's own lexer specs and targeted cases
#   lexers   every lexer of Rouge in its order (Lexer.all): [tag, aliases,
#            mimetypes, whether it has a detect?]
#   guesses  Lexer.guess(source:) of Rouge's demos and a few sources:
#            [name, source, tags] (none: plain text, several: ambiguous)
#   keywords the builtin tables of the ported Lua, PHP and MATLAB lexers
require 'json'
require 'rouge'

out, checkout, spec_dir, pdf_lib, *tags = ARGV

# asciidoctor-pdf's default Rouge theme
require File.join(pdf_lib, 'asciidoctor/pdf/ext/rouge/themes/asciidoctor_pdf_default')
# Ruby 4.0 has no CGI.parse (cgi-style lexer options): restore it
require_relative '../pdf_harvest/cgi_parse'

MAX_SAMPLE = 6000

tokens = []
Rouge::Token.each_token {|t| tokens << [t.qualname, t.shortname] }
tokens.sort!

# load every theme (and the modes they register) before listing them
Dir[File.join(Gem.loaded_specs['rouge'].full_gem_path, 'lib/rouge/themes/*.rb')].sort.each {|f| require f }
themes = {}
Rouge::Theme.registry.keys.sort.each do |name|
  theme = Rouge::Theme.find name
  styles = []
  Rouge::Token.each_token do |tok|
    next unless (raw = theme.styles[tok])
    style = Rouge::Theme::Style.new theme, raw
    styles << [tok.qualname, style.fg, style.bg, !!style[:bold], !!style[:italic], !!style[:underline]]
  end
  themes[name] = styles.sort_by(&:first)
end

unicode = {}
{
  'cf' => /\p{Cf}/, 'lm' => /\p{Lm}/, 'lt' => /\p{Lt}/, 'mc' => /\p{Mc}/, 'mn' => /\p{Mn}/,
  'n' => /\p{N}/, 'nl' => /\p{Nl}/, 'pc' => /\p{Pc}/, 'sm' => /\p{Sm}/, 'so' => /\p{So}/,
  'xidstart' => /\p{XID_Start}/, 'xidcontinue' => /\p{XID_Continue}/,
}.each do |name, rx|
  ranges = []
  start = nil
  (0..0x110000).each do |cp|
    inside = cp < 0x110000 && !(0xD800..0xDFFF).cover?(cp) && rx.match?([cp].pack('U'))
    if inside
      start ||= cp
    elsif start
      ranges << start << cp - 1
      start = nil
    end
  end
  unicode[name] = ranges
end

def utf16_length str
  str.encode('UTF-16LE').bytesize / 2
end

def lex_case spec, input
  lexer = Rouge::Lexer.find_fancy spec
  return nil unless lexer
  lexer.lex(input).map {|tok, val| %(#{tok.shortname}:#{utf16_length val}) }.join ' '
end

def truncate text
  return text if text.length <= MAX_SAMPLE
  cut = text.rindex(?\n, MAX_SAMPLE) || MAX_SAMPLE
  text[0, cut + 1]
end

cases = []
seen = {}
add = lambda do |name, spec, input|
  input = input.encode 'UTF-8', invalid: :replace, undef: :replace
  key = [spec, input]
  next if seen[key]
  seen[key] = true
  expected = lex_case spec, input
  cases << [name, spec, input, expected] if expected
end

gem_dir = Gem.loaded_specs['rouge'].full_gem_path
tags.each do |tag|
  klass = Rouge::Lexer.find tag or raise %(no lexer #{tag})
  demo = File.join gem_dir, 'lib/rouge/demos', klass.tag
  add.call %(#{tag}: demo), tag, (File.read demo, mode: 'r:UTF-8') if File.file? demo
  sample = File.join checkout, 'spec/visual/samples', klass.tag
  add.call %(#{tag}: visual sample), tag, (truncate File.read sample, mode: 'r:UTF-8') if File.file? sample
end

# cgi-style options given more than once: Rouge keeps every value (a list
# option takes them all, a scalar one the last)
[
  ['console?prompt=%24&prompt=%3E', %($ ls\n> echo hi\n% not a prompt\nout\n)],
  ['console?prompt=%25,%3E&prompt=%24&lang=shell', %($ ls\n% echo hi\n> x\nout\n)],
  ['php?start_inline=0&start_inline=1', %(echo "hi"; ?>\n<b>x</b>\n)],
].each do |spec, input|
  next unless tags.include? spec[/\A[^?]+/]
  add.call %(#{spec}: repeated options), spec, input
end

# targeted cases: options, nested states, Unicode
[
  ['erb?parent=json', %({"a": <%= @x %>, "b": [1, 2]}\n)],
  ['erb?parent=xml', %(<a href="<%= url %>">\n  <% if x %>y<% end %>\n</a>\n)],
  ['vue', %(<template>\n  <p :id="x">{{ msg }}</p>\n</template>\n<script>\nexport default { data() { return { msg: 'hi' } } }\n</script>\n<style scoped>\np { color: red; }\n</style>\n)],
  ['console?comments=true', %(# a comment\n$ ls -l\ntotal 0\n)],
  ['console?error=error:,fatal:&output=yaml', %($ make\nerror: no rule\nkey: value\nfatal: stop\n)],
  ['console?lang=ruby&prompt=%3E%3E', %(>> puts 1 + 2\n3\n)],
  ['yaml', %(a: &anchör x\nb: *anchör\nc: &é_1 [1, 2]\nd: *é_1\n)],
  ['d', %(auto s = q"[a[b]c]";\nauto t = q{ int x = 1; };\n/+ outer /+ inner +/ still +/\nauto u = q"EOS\nline\nEOS";\n)],
  ['csharp', %(var s = $"x {1} y {name,10:F2}";\nvar v = $@"c:\\{dir}";\n)],
  ['rust', %(/** /* nested */ */\nfn main() { let r = r#"raw "str""#; }\n)],
  ['markdown', %(```\n<?php echo 1; ?>\n```\n```\n#!/usr/bin/env python\nprint(1)\n```\n```\n# vim: ft=ruby\nputs 1\n```\n```\nplain words\n```\n)],
  ['markdown?disabledmodules=String&disabledmodules=Math', %(```php?disabledmodules=Date%2FTime\nstrlen('x'); abs(1); date('Y');\n```\n)],
].each do |spec, input|
  next unless tags.include? spec[/\A[^?]+/]
  add.call %(#{spec}: targeted), spec, input
end

# Markdown fences that guess: an ambiguous guess (PHP and HTML) takes the
# first lexer with Markdown's own options, not the fence's; a mimetype
# given twice is a list, which no lexer has, so the source decides
if tags.include? 'markdown'
  {
    'ambiguous guess' => %(```guess?disabledmodules=String\n<?php strlen('x'); ?>\n<html></html>\n```\n),
    'repeated mimetype' => %(```guess?mimetype=text/x-php&mimetype=text/plain\n<?php echo 1; ?>\n```\n),
  }.each do |what, input|
    add.call %(markdown: #{what}), 'markdown', input
  end
end

# the inputs of Rouge's own lexer specs (spec/lexers/<tag>_spec.rb:
# assert_tokens_equal with a string literal) for the ported lexers
literal = /assert_tokens_equal\s+(%q\((?:[^()\\]|\\.|\([^()]*\))*\)|'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\s*,/m
tags.each do |tag|
  file = File.join checkout, 'spec/lexers', %(#{tag}_spec.rb)
  next unless File.file? file
  n = 0
  (File.read file, mode: 'r:UTF-8').scan(literal) do |(source)|
    input = (eval source rescue nil) # a string literal of the spec file
    next unless String === input
    add.call %(#{tag}: rouge spec ##{n += 1}), tag, input
  end
end

# the source blocks of asciidoctor-pdf's specs whose language is a lexer of
# TAG... (with their cgi-style options)
#
# The source blocks of a spec file: [language, body] pairs, the body without
# the block's indentation. The first closing fence ends a block, an empty
# one too.
def source_blocks src
  blocks = []
  src.scan(/^( *)\[source,([^\]\n,]+)[^\]\n]*\]\n\1(-{4,})\n(?:(.*?)\n)??\1\3$/m) do |indent, lang, _, body|
    body = (body || '').lines.map {|l| l.start_with?(indent) ? l[indent.length..] : l.lstrip }.join
    blocks << [lang, body]
  end
  blocks
end

# checked on every run: an empty block ends at its own closing fence, and
# leaves the block next to it whole
extractor_sample = <<~'EOS'
  [source,ruby]
  ----
  ----

    [source,yaml]
    ----
    a: 1
    ----
EOS
unless (got = source_blocks extractor_sample) == [['ruby', ''], ['yaml', 'a: 1']]
  abort %(harvest.rb: the source block extractor is broken: #{got.inspect})
end

wanted = tags.map {|t| Rouge::Lexer.find(t) }.to_set
Dir[File.join(spec_dir, '*_spec.rb')].sort.each do |file|
  n = 0
  (source_blocks File.read file, mode: 'r:UTF-8').each do |lang, body|
    lexer_class = (Rouge::Lexer.lookup_fancy lang)[0] rescue nil
    next unless wanted.include? lexer_class
    next if body.include? '#{'
    add.call %(#{lang}: #{File.basename file, '.rb'} ##{n += 1}), lang, body
  end
end

lexers = Rouge::Lexer.all.map {|l| [l.tag, l.aliases, l.mimetypes, l.detectable?] }

guesses = []
guess = lambda do |name, source|
  found = begin
    l = Rouge::Lexer.guess source: source
    l == Rouge::Lexers::PlainText ? [] : [l.tag]
  rescue Rouge::Guesser::Ambiguous => e
    e.alternatives.map(&:tag)
  end
  guesses << [name, source, found]
end
Dir[File.join(gem_dir, 'lib/rouge/demos/*')].sort.each do |demo|
  guess.call %(demo #{File.basename demo}), (File.read demo, mode: 'r:UTF-8')
end
[
  ['php open tag', %(<?php echo 1; ?>\n)],
  ['hack open tag', %(<?hh echo 1;\n)],
  ['python shebang', %(#!/usr/bin/env python3\nprint(1)\n)],
  ['shell shebang', %(#!/bin/bash\necho hi\n)],
  ['vim modeline', %(x = 1\n# vim: ft=ruby\n)],
  ['emacs modeline', %(# -*- mode: python -*-\nx = 1\n)],
  ['html doctype', %(<!DOCTYPE html>\n<html></html>\n)],
  ['xml declaration', %(<?xml version="1.0"?>\n<a/>\n)],
  ['yaml directive', %(%YAML 1.2\n---\na: 1\n)],
  ['git diff', %(diff --git a/x b/x\n--- a/x\n+++ b/x\n)],
  ['postscript and diff', %(%!PS\n--- a\n+++ b\n)],
  ['plain words', %(nothing to see here\n)],
  ['empty', ''],
  ['bom and crlf', %(\uFEFF#!/usr/bin/perl\r\nprint 1;\r\n)],
].each {|name, source| guess.call name, source }

keywords = {}
if tags.include? 'lua'
  keywords['lua'] = Rouge::Lexers::Lua.builtins.map {|m, fns| [m.to_s, fns.to_a.sort] }.sort
end
if tags.include? 'php'
  keywords['php'] = Rouge::Lexers::PHP.builtins.map {|m, fns| [m.to_s, fns.to_a.sort] }.sort
end
if tags.include? 'matlab'
  keywords['matlab'] = [['', Rouge::Lexers::Matlab.builtins.to_a.sort]]
end

File.write out, (JSON.generate tokens: tokens, themes: themes, unicode: unicode, cases: cases, lexers: lexers, guesses: guesses, keywords: keywords)
