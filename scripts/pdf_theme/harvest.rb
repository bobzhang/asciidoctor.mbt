# frozen_string_literal: false
# Theme loader harvester (Ruby asciidoctor-pdf 2.3.27 is the oracle).
#
# Runs asciidoctor-pdf's theme loader spec (spec/theme_loader_spec.rb of the
# asciidoctor-pdf checkout) under a minimal RSpec stand-in that executes every
# example but checks nothing, and records each top-level call the examples
# make to the loader -- ThemeLoader.load_theme, ThemeLoader.load_file and
# ThemeLoader#load (with the YAML text it was given) -- with the theme files
# it read, the loaded theme (a canonical dump, see `dump`) or the fact that
# it failed, and the warnings it logged. Then records the same for every
# bundled theme, every theme fixture of the spec and the extra cases listed
# on the command line (YAML files, loaded as themes and as text).
#
# Paths are virtual in the records: the bundled themes and fonts as the
# MoonBit loader names them, the fixtures under /fixtures, temporary theme
# files under /tmp-themes, the home directory as /home.
#
# Usage: ruby harvest.rb SPEC_DIR OUT.jsonl [EXTRA.yml...]
require 'json'
require 'yaml'
require 'set'
require 'tempfile'
require 'tmpdir'
require 'asciidoctor'
require 'asciidoctor/pdf/theme_loader'

SPEC_DIR = File.realpath ARGV[0]
OUT = File.open ARGV[1], 'w'
EXTRAS = ARGV[2..]
FIXTURES = File.join SPEC_DIR, 'fixtures'
TL = Asciidoctor::PDF::ThemeLoader
TMP_DIR = Dir.mktmpdir 'themes'

VIRTUAL = [
  [TL::ThemesDir, '/asciidoctor-pdf/data/themes'],
  [TL::FontsDir, '/asciidoctor-pdf/data/fonts'],
  [FIXTURES, '/fixtures'],
  [(File.realpath TMP_DIR), '/tmp-themes'],
  [TMP_DIR, '/tmp-themes'],
  [Dir.home, '/home'],
].sort_by {|(path, _)| -path.length }

def virtual str
  VIRTUAL.each {|(real, virt)| str = str.gsub real, virt }
  str
end

def quote str
  '"' + (str.gsub(/["\\\x00-\x1f]/) {|c| c == '"' || c == '\\' ? '\\' + c : format('\u%04x', c.ord) }) + '"'
end

# The canonical form of a theme value, as pdf/theme's `Value::dump` writes it.
def dump val
  case val
  when nil then 'nil'
  when true, false, Integer then val.to_s
  when Float then 'f' + val.to_s
  when TL::HexColorValue then 'hex' + (quote val)
  when TL::TransparentColorValue then 'transparent'
  when TL::CMYKColorValue then 'cmyk[' + (val.map {|v| dump v }.join ', ') + ']'
  when String then quote virtual val
  when Symbol then ':' + val.to_s
  when Array then '[' + (val.map {|v| dump v }.join ', ') + ']'
  when Hash then '{' + (val.map {|k, v| (Symbol === k ? ':' + k.to_s : (quote k.to_s)) + ' => ' + (dump v) }.join ', ') + '}'
  else '?' + val.class.to_s
  end
end

def dump_theme theme
  theme.to_h.reject {|k, _| k == :__loaded__ }.map {|k, v| %(#{k}: #{dump v}) }.join "\n"
end

module Harvest
  @depth = 0
  @files = nil
  @texts = {}
  @count = 0
  class << self
    attr_accessor :depth, :files, :texts, :count, :example
  end

  def self.record kind, args, name: nil
    return yield if @depth > 0
    @depth += 1
    @files = {}
    logger = Asciidoctor::MemoryLogger.new
    saved = Asciidoctor::LoggerManager.logger
    Asciidoctor::LoggerManager.logger = logger
    result = error = nil
    begin
      result = yield
    rescue Exception => e # rubocop:disable Lint/RescueException
      error = e
    ensure
      @depth -= 1
      Asciidoctor::LoggerManager.logger = saved
    end
    files = @files
    @files = nil
    record = {
      'name' => name || %(#{@example} ##{@count += 1}),
      'kind' => kind,
      'args' => args,
      'files' => files.transform_keys {|k| virtual k },
      'dump' => error ? nil : (dump_theme result),
      'error' => error ? (virtual %(#{error.class}: #{error.message})) : nil,
      'warnings' => logger.messages.map {|m| virtual %(#{m[:severity]}: #{m[:message]}) },
    }
    OUT.puts record.to_json
    raise error if error
    result
  end
end

# the theme files the loader reads
class << File
  prepend(Module.new do
    def read name, *args, **opts
      content = super
      if Harvest.files && (name.to_s.end_with? '.yml') && !(name.to_s.start_with? TL::ThemesDir)
        Harvest.files[name.to_s] = virtual content.gsub(/\r\n?/, "\n")
      end
      content
    end
  end)
end

# the YAML text of the data given to ThemeLoader#load
module YAML
  class << self
    prepend(Module.new do
      def safe_load yaml, *args, **opts
        result = super
        Harvest.texts[result.object_id] = yaml if Harvest.depth == 0 && String === yaml
        result
      end
    end)
  end
end

class << TL
  prepend(Module.new do
    def load_theme theme_name = nil, theme_dir = nil
      args = [theme_name, theme_dir].map {|a| a && (virtual a) }
      Harvest.record('load_theme', args) { super }
    end

    def load_file filename, theme_data = nil, theme_dir = nil
      return super if theme_data
      args = [filename, theme_dir].map {|a| a && (virtual a) }
      Harvest.record('load_file', args) { super }
    end
  end)
end

TL.prepend(Module.new do
  def load hash, theme_data = nil
    return super if Harvest.depth > 0 || theme_data
    text = String === hash ? hash : Harvest.texts[hash.object_id]
    return super if hash && !text
    Harvest.record('load', [text || hash.to_s]) { super }
  end
end)

# A minimal stand-in for RSpec: groups and examples run in order, every
# expectation passes (only the loader's behavior is recorded); a block given
# to `expect` is run, and what it raises is swallowed.
class Matcher
  def method_missing(*) = self
  def respond_to_missing?(*) = true
end

class Expectation
  def initialize value, block
    @block = block
  end

  def to *_
    @block&.call
  rescue Exception # rubocop:disable Lint/RescueException
    nil
  end

  alias not_to to
  alias to_not to
end

class ExampleGroup
  def initialize described
    @described = described
  end

  def subject = @described
  def described_class = @described
  def fixtures_dir = FIXTURES
  def fixture_file(path, **) = (File.join FIXTURES, path)
  def home_dir = Dir.home
  def expect(value = nil, &block) = (Expectation.new value, block)

  def with_pdf_theme_file data
    @tmp_count = (@tmp_count || 0) + 1
    path = File.join TMP_DIR, %(tmp-#{Harvest.count}-#{@tmp_count}-theme.yml)
    File.write path, data
    yield path
  ensure
    File.unlink path if path && (File.exist? path)
  end

  def method_missing(*) = Matcher.new
  def respond_to_missing?(*) = true

  def describe(_title = nil, &block) = instance_eval(&block)
  alias context describe

  def it title, &block
    Harvest.example = title
    Harvest.count = 0
    instance_eval(&block)
  rescue Exception # rubocop:disable Lint/RescueException
    nil
  end
end

def describe described, &block
  ExampleGroup.new(described).instance_eval(&block)
end

spec = File.read File.join SPEC_DIR, 'theme_loader_spec.rb'
spec = spec.sub(/^require_relative .*$/, '')
eval spec, binding, File.join(SPEC_DIR, 'theme_loader_spec.rb') # rubocop:disable Security/Eval

# every bundled theme, and every theme fixture of the spec
TL::BundledThemeNames.sort.each do |name|
  Harvest.example = %(bundled #{name})
  Harvest.count = 0
  TL.load_theme name rescue nil
end
(Dir.children FIXTURES).select {|f| f.end_with? '-theme.yml' }.sort.each do |file|
  Harvest.example = %(fixture #{file})
  Harvest.count = 0
  TL.load_theme file, FIXTURES rescue nil
end

# the extra cases: each file as a theme (from its directory) and as text
EXTRAS.each do |path|
  path = File.realpath path
  dir = File.dirname path
  VIRTUAL.unshift [dir, '/extra']
  Harvest.example = %(extra #{File.basename path})
  Harvest.count = 0
  TL.load_theme (File.basename path), dir rescue nil
  begin
    text = File.read path
    data = YAML.safe_load text
    Harvest.record('load', [text], name: %(extra #{File.basename path} (text))) { TL.new.load data }
  rescue Exception # rubocop:disable Lint/RescueException
    nil
  end
  VIRTUAL.shift
end

OUT.close
