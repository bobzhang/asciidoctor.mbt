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
#            boundary) and the source blocks of asciidoctor-pdf's specs
require 'json'
require 'rouge'

out, checkout, spec_dir, pdf_lib, *tags = ARGV

# asciidoctor-pdf's default Rouge theme
require File.join(pdf_lib, 'asciidoctor/pdf/ext/rouge/themes/asciidoctor_pdf_default')
# Ruby 4.0 has no CGI.parse (cgi-style lexer options); restore it as the cgi
# gem defines it (scripts/pdf_harvest/harvest.rb does the same)
require 'cgi'
unless CGI.respond_to? :parse
  def CGI.parse query
    params = {}
    query.split(/[&;]/).each do |pairs|
      key, value = pairs.split('=', 2).collect {|v| CGI.unescape v }
      next unless key
      params[key] ||= []
      params[key].push value if value
    end
    params.default = [].freeze
    params
  end
end

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

# the source blocks of asciidoctor-pdf's specs whose language is a lexer of
# TAG... (with their cgi-style options)
wanted = tags.map {|t| Rouge::Lexer.find(t) }.to_set
Dir[File.join(spec_dir, '*_spec.rb')].sort.each do |file|
  src = File.read file, mode: 'r:UTF-8'
  n = 0
  src.scan(/^( *)\[source,([^\]\n,]+)[^\]\n]*\]\n\1(-{4,})\n(.*?)\n\1\3$/m) do |indent, lang, _, body|
    lexer_class = (Rouge::Lexer.lookup_fancy lang)[0] rescue nil
    next unless wanted.include? lexer_class
    next if body.include? '#{'
    body = body.lines.map {|l| l.start_with?(indent) ? l[indent.length..] : l.lstrip }.join
    add.call %(#{lang}: #{File.basename file, '.rb'} ##{n += 1}), lang, body
  end
end

File.write out, (JSON.generate tokens: tokens, themes: themes, unicode: unicode, cases: cases)
