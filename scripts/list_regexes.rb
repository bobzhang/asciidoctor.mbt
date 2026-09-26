# Dump every regexp used by Asciidoctor: named constants (resolved) and inline literals (by location).
# Usage: ruby scripts/list_regexes.rb > tests/regex/regexes.json
require 'json'
require 'ripper'
ROOT = File.expand_path '../.repos/asciidoctor', __dir__
$LOAD_PATH.unshift File.join(ROOT, 'lib')
require 'asciidoctor'
require 'asciidoctor/extensions'
out = []
seen = {}
walk = lambda do |mod, prefix|
  mod.constants.sort.each do |c|
    v = (mod.const_get c rescue next)
    name = "#{prefix}#{c}"
    if Regexp === v
      out << { 'name' => name, 'source' => v.source, 'options' => v.options }
    elsif Array === v || Hash === v
      (Array === v ? v.flatten : v.to_a.flatten).each_with_index do |e, i|
        out << { 'name' => "#{name}[#{i}]", 'source' => e.source, 'options' => e.options } if Regexp === e
      end
    elsif Module === v && v.name&.start_with?('Asciidoctor') && !seen[v]
      seen[v] = true
      walk.(v, "#{name}::")
    end
  end
end
walk.(Asciidoctor, '')
Dir[File.join(ROOT, 'lib/**/*.rb')].sort.each do |f|
  toks = Ripper.lex File.read(f)
  toks.each_with_index do |(pos, type, tok), i|
    next unless type == :on_regexp_beg
    j = i + 1; body = +''; interp = false
    while toks[j][1] != :on_regexp_end
      interp = true if toks[j][1] == :on_embexpr_beg
      body << toks[j][2]; j += 1
    end
    out << { 'name' => "#{f.sub(ROOT + '/', '')}:#{pos[0]}", 'source' => body, 'flags' => toks[j][2], 'interpolated' => interp }
  end
end
puts JSON.pretty_generate(out)
