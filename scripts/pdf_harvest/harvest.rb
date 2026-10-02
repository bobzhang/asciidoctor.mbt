# frozen_string_literal: false
# PDF golden harvester for asciidoctor-pdf's RSpec suite.
#
# Loaded into an RSpec run of the asciidoctor-pdf spec suite (see
# scripts/pdf_harvest.mbtx: `rspec --require scripts/pdf_harvest/harvest.rb`).
# Records every PDF conversion the specs perform: every document that reaches
# Asciidoctor::PDF::Converter#convert_document, however it got there (the
# to_pdf / to_pdf_file spec helpers, Asciidoctor.convert / convert_file, or
# Asciidoctor.load followed by Document#convert).
#
# Each conversion gets a stable id: spec file + RSpec example id (its position
# in the file, e.g. [1:2:3]) + conversion ordinal within the example. A record
# holds
#   - the input: the AsciiDoc source text, or the input file
#   - how the conversion was invoked (`via`: helper or API), the helper's
#     analyze mode, and the effective Asciidoctor options as passed to the API
#     (after the helpers' defaults: imagesdir, nofooter, attribute_overrides,
#     safe mode, standalone), JSON-safe
#   - the theme: the helper's pdf_theme overrides (and `extends`), or a dump
#     of a theme object passed directly
#   - every file read while converting (sources, includes, images, fonts,
#     themes), by placeholder path with SHA-256 and size; files the spec
#     created (temp files, spec/output) also with their content, since they
#     do not survive the run
#   - log messages emitted during the conversion
#   - the reference PDF (written to $PDF_HARVEST_PDFS/<name>.pdf, recorded by
#     SHA-256 and size), captured where Prawn renders it
#   - `skip`: why the case cannot be replayed as "input document + options"
#     (analyze: :document, a converter subclass, Ruby extensions, network,
#     the model loaded through the API and converted separately, no PDF)
#   - the RSpec status of the example
# Records are written as JSON lines to $PDF_HARVEST_OUT/<spec>.jsonl, one file
# per spec file, in run order. Machine-specific paths are replaced by
# placeholders ($SPEC_ROOT, $SPEC_TMP, $SPEC_OUT, $GEMS, $TMPDIR, $HOME).
require 'json'
require 'digest'
require 'stringio'
require 'tmpdir'
require 'logger'
require 'net/http'

module PdfHarvest
  SPEC_ROOT = File.realpath ENV.fetch('PDF_HARVEST_SPEC_ROOT')
  OUT_DIR = ENV.fetch('PDF_HARVEST_OUT')
  PDF_DIR = ENV.fetch('PDF_HARVEST_PDFS')
  GEM_DIRS = ENV.fetch('PDF_HARVEST_GEMS', '').split(':').reject(&:empty?)
  # files larger than this are recorded by hash only even when ephemeral
  MAX_INLINE = 1 << 20

  def self.path_forms path
    forms = [path]
    forms << (File.realpath path) if File.exist? path
    forms.uniq
  end

  PLACEHOLDERS = [
    *(path_forms File.join(SPEC_ROOT, 'spec', 'tmp')).map {|p| [p, '$SPEC_TMP'] },
    *(path_forms File.join(SPEC_ROOT, 'spec', 'output')).map {|p| [p, '$SPEC_OUT'] },
    *(path_forms SPEC_ROOT).map {|p| [p, '$SPEC_ROOT'] },
    *GEM_DIRS.flat_map {|d| (path_forms d).map {|p| [p, '$GEMS'] } },
    *(path_forms Dir.tmpdir).map {|p| [p, '$TMPDIR'] },
    *(path_forms Dir.home).map {|p| [p, '$HOME'] },
  ].uniq.sort_by {|(path, _)| -path.length }

  EPHEMERAL = %w($SPEC_TMP $SPEC_OUT $TMPDIR)

  @example = nil
  @records = []
  @stack = []
  @frames = []
  @outs = {}
  # files written during a conversion (the converter's temp images): not inputs
  @written = ::Set.new
  @counts = Hash.new 0
  class << self
    attr_accessor :example, :records, :stack, :frames, :counts

    def placeholder str
      PLACEHOLDERS.each {|(path, ph)| str = str.gsub path, ph }
      str
    end

    def json_safe val, depth = 0
      return { '__unsupported__' => 'deep' } if depth > 20
      case val
      when nil, true, false, Integer, String then val
      when Float then val.finite? ? val : val.to_s
      when Symbol then val.to_s
      when Array then val.map {|v| json_safe v, depth + 1 }
      when Hash then val.each_with_object({}) {|(k, v), h| h[k.to_s] = json_safe v, depth + 1 }
      when Pathname then { '__path__' => val.to_s }
      when StringIO then { '__io__' => 'StringIO' }
      when Proc, Method then { '__unsupported__' => 'Proc' }
      else
        if defined?(Asciidoctor::PDF::ThemeData) && Asciidoctor::PDF::ThemeData === val
          { '__theme__' => json_safe(val.table, depth + 1) }
        else
          { '__unsupported__' => val.class.to_s }
        end
      end
    end

    # The options as given to the Asciidoctor API, with the theme set aside
    # (recorded separately) and Ruby objects described.
    def options_for opts
      opts.each_with_object({}) do |(k, v), h|
        next if k.to_s == 'pdf_theme'
        h[k.to_s] = case k.to_s
                    when 'to_file' then (String === v || v.nil? || v == true || v == false) ? v : { '__io__' => v.class.to_s }
                    when 'extension_registry', 'extensions' then { '__unsupported__' => 'extensions' }
                    when 'converter' then { '__unsupported__' => v.class.to_s }
                    when 'logger' then { '__logger__' => v.class.to_s }
                    else json_safe v
                    end
      end
    end

    def theme_for opts, frame
      theme = opts[:pdf_theme] || opts['pdf_theme']
      return nil unless theme
      # the spec helpers turn a Hash into a theme (build_pdf_theme); the
      # frame keeps what the spec passed
      if frame && (orig = frame[:pdf_theme])
        if Hash === orig
          orig = orig.dup
          extends = orig.delete :extends
          return { 'extends' => json_safe(extends), 'overrides' => json_safe(orig) }
        end
      end
      { 'object' => json_safe(theme), 'dir' => ((defined?(Asciidoctor::PDF::ThemeData) && Asciidoctor::PDF::ThemeData === theme) ? theme.__dir__ : nil) }
    end

    def current
      @stack.last
    end

    def within rec
      return yield unless rec
      @stack.push rec
      begin
        yield
      ensure
        @stack.pop
      end
    end

    def note_file path
      return if @recording
      rec = current || @frames.last
      return unless rec
      @recording = true
      begin
        path = path.to_path if path.respond_to? :to_path
        return unless String === path
        abs = File.absolute_path path
        return unless File.file? abs
        files = (rec[:files] ||= {})
        return if (files.key? abs) || (@written.include? abs)
        data = File.binread abs
        files[abs] = { 'sha256' => (Digest::SHA256.hexdigest data)[0, 16], 'size' => data.bytesize, 'data' => data }
      rescue StandardError
        nil
      ensure
        @recording = false
      end
    end

    def note_written path
      return unless current
      path = path.to_path if path.respond_to? :to_path
      @written << (File.absolute_path path) if String === path
    end

    # reads of the harvester itself are not inputs
    def quietly
      saved = @recording
      @recording = true
      begin
        yield
      ensure
        @recording = saved
      end
    end

    def read_mode? args, kw
      mode = kw[:mode] || args[0]
      !(::String === mode && (mode.include?('w') || mode.include?('a'))) && !(::Integer === mode && (mode & (::File::WRONLY | ::File::RDWR)) != 0)
    end

    def note_network
      (rec = current) && (rec[:network] = true)
    end

    def ephemeral? placeholder_path
      EPHEMERAL.any? {|ph| placeholder_path.start_with? ph + '/' }
    end

    def files_json files
      (files || {}).sort.each_with_object({}) do |(abs, info), h|
        key = placeholder abs
        entry = { 'sha256' => info['sha256'], 'size' => info['size'] }
        if ephemeral? key
          if info['size'] <= MAX_INLINE
            entry['content_base64'] = [info['data']].pack 'm0'
          else
            entry['content_omitted'] = true
          end
        end
        h[key] = entry
      end
    end

    def safe_name str
      str.gsub(/[^A-Za-z0-9._-]+/, '.').sub(/\.+\z/, '')
    end

    def out_for spec
      @outs[spec] ||= File.open (File.join OUT_DIR, %(#{File.basename spec, '.rb'}.jsonl)), 'w'
    end

    def skip_reason rec
      return 'analyze: :document (the spec inspects the converter; no PDF is written)' if rec[:analyze] == 'document' && !rec[:pdf]
      return %(conversion raised #{rec[:error]}) if rec[:error] && !rec[:pdf]
      return 'converter subclass or custom converter' if rec[:converter_class] != 'Asciidoctor::PDF::Converter'
      return 'Ruby extensions registered' if rec[:extensions]
      return %(a syntax highlighter stubbed by the spec (#{rec[:stubbed].join ', '})) if rec[:stubbed]
      return 'network access (URI read)' if rec[:network]
      return 'model loaded through the API and converted separately' if rec[:via].start_with?('Asciidoctor.load', 'Document.new') && !rec[:via_convert]
      if (bad = (rec[:options] || {}).find {|k, v| Hash === v && v.key?('__unsupported__') })
        return %(option #{bad[0]} is a Ruby object)
      end
      return 'no PDF rendered' unless rec[:pdf]
      nil
    end

    def emit_example status
      ex = @example
      @records.each do |rec|
        spec = File.basename ex[:file]
        out = {
          'id' => rec[:id],
          'name' => rec[:name],
          'spec' => spec,
          'example' => ex[:scoped_id],
          'line' => ex[:line],
          'description' => ex[:description],
          'example_status' => status,
          'ordinal' => rec[:ordinal],
          'via' => rec[:via],
          'analyze' => rec[:analyze],
          'input' => rec[:input],
          'options' => rec[:options],
          'pdf_theme' => rec[:pdf_theme],
          'converter_class' => (rec[:converter_class] == 'Asciidoctor::PDF::Converter' ? nil : rec[:converter_class]),
          'messages' => rec[:messages],
          'error' => rec[:error],
          'renders' => rec[:renders],
          'pdf' => rec[:pdf],
          'skip' => (skip_reason rec),
          'files' => (files_json rec[:files]),
        }.reject {|_, v| v.nil? }
        json = begin
          JSON.generate out
        rescue JSON::GeneratorError
          JSON.generate scrub out
        end
        f = out_for spec
        f.puts stable_tmp_names placeholder json
        f.flush
      end
      @counts[:conversions] += @records.size
      @records = []
    end

    # Tempfile names (tmp-20261001-4242-1x2y3z.adoc) carry the date, the pid
    # and a random part; number them per record so that a harvest is
    # reproducible
    def stable_tmp_names json
      names = {}
      json = json.gsub(/\b([a-z]+)-\d{8}-\d+-[0-9a-z]+/) { names[$&] ||= %(#{$1}-#{names.size + 1}) }
      # the specs name converter subclasses and their backends after object ids
      json.scan(/AnonymousClass(\d+)/).flatten.uniq.each {|id| json = json.gsub(/"([A-Za-z_]+)#{id}"/) { %("#{$1}N") } }
      json
    end

    def scrub val
      case val
      when String then val.dup.force_encoding('UTF-8').scrub
      when Array then val.map {|v| scrub v }
      when Hash then val.each_with_object({}) {|(k, v), h| h[scrub k] = scrub v }
      else val
      end
    end

    def input_for data
      case data
      when String then { 'text' => data.dup.force_encoding('UTF-8') }
      when Array then { 'lines' => data }
      when File then { 'file' => (File.absolute_path data.path) }
      when nil then { 'text' => '' }
      else { 'io' => data.class.to_s }
      end
    end

    # A new top-level document: the record of a potential conversion.
    def new_record data, options
      frame = @frames.last
      api = frame && frame[:api]
      via = (frame && frame[:via]) || 'Document.new'
      # load_file / convert_file read the file and pass its text; the
      # replay converts the file itself
      docfile = via.end_with?('_file') && (attrs = options[:attributes]) && attrs['docfile']
      rec = {
        via: via,
        via_convert: frame && frame[:convert],
        analyze: frame && frame[:analyze],
        input: (docfile ? { 'file' => docfile } : (input_for data)),
        options: (options_for((api && api[:options]) || options)),
        pdf_theme: (theme_for options, (frame && frame[:helper])),
        files: (frame && frame[:files]&.dup) || {},
        messages: nil,
      }
      rec
    end

    def finish rec, pdf_bytes
      rec[:renders] = (rec[:renders] || 0) + 1
      name = rec[:name]
      File.binwrite (File.join PDF_DIR, %(#{name}.pdf)), pdf_bytes
      rec[:pdf] = { 'sha256' => (Digest::SHA256.hexdigest pdf_bytes), 'size' => pdf_bytes.bytesize, 'file' => %(#{name}.pdf) }
    end

    # Pygments lexers a spec replaced methods of (`class << lexer; def
    # highlight...`): what such a conversion shows is not Pygments'
    def stubbed_highlighters
      return [] unless defined?(::Pygments::Lexer)
      ::Pygments::Lexer.all.select {|l|
        # a method the spec defined (restored afterwards by aliasing the
        # original back, which is pygments.rb's again)
        (l.singleton_methods.include? :highlight) && !((l.method :highlight).source_location || [''])[0].include?('/pygments')
      }.map {|l| %(Pygments lexer #{l.name}#highlight) }
    rescue StandardError
      []
    end

    def start_conversion rec, converter, doc
      return if rec[:id]
      ex = @example
      return unless ex
      ex[:ordinal] += 1
      rec[:ordinal] = ex[:ordinal]
      rec[:id] = %(#{File.basename ex[:file], '.rb'}[#{ex[:scoped_id]}]##{ex[:ordinal]})
      rec[:name] = safe_name %(#{File.basename ex[:file], '.rb'}-#{ex[:scoped_id].tr ':', '.'}-#{ex[:ordinal]})
      rec[:converter_class] = converter.class.name || converter.class.to_s
      rec[:extensions] = true if doc.extensions? || (defined?(Asciidoctor::Extensions) && !Asciidoctor::Extensions.groups.empty?)
      if (stubbed = stubbed_highlighters).any?
        rec[:stubbed] = stubbed
      end
      @records << rec
    end
  end

  # Asciidoctor API entry points: the options exactly as the spec passed them
  module ApiHook
    def load input, options = {}
      PdfHarvest.with_api('Asciidoctor.load', options) { super }
    end

    def load_file filename, options = {}
      PdfHarvest.with_api('Asciidoctor.load_file', options) { super }
    end

    def convert input, options = {}
      PdfHarvest.with_api('Asciidoctor.convert', options, convert: true) { super }
    end

    def convert_file filename, options = {}
      PdfHarvest.with_api('Asciidoctor.convert_file', options, convert: true) { super }
    end
  end

  class << self
    # The outermost API call names the conversion; inner calls (convert →
    # load) only add to it.
    def with_api via, options, convert: false
      if (frame = @frames.last) && frame[:api]
        return yield
      end
      if frame && !frame[:api] # inside a spec helper
        frame[:api] = { options: (::Hash === options ? options : {}) }
        frame[:via] = "#{frame[:via]} > #{via}"
        frame[:convert] = convert
        begin
          return yield
        ensure
          frame[:api] = nil
        end
      end
      @frames.push({ via: via, api: { options: (::Hash === options ? options : {}) }, convert: convert, files: {} })
      begin
        yield
      ensure
        @frames.pop
      end
    end

    def with_helper via, input, opts
      frame = { via: via, helper: { pdf_theme: (opts[:pdf_theme].dup rescue nil) }, analyze: (a = opts[:analyze]).nil? ? nil : a.to_s, files: {} }
      @frames.push frame
      begin
        yield
      ensure
        @frames.pop
      end
    end
  end

  module DocumentHook
    def initialize data = nil, options = {}
      rec = (options[:parent] || PdfHarvest.current) ? nil : (PdfHarvest.new_record data, options)
      PdfHarvest.within(rec) { super }
      if rec
        rec[:input] = { 'text' => @reader.source_lines.join(?\n) } if rec[:input].key?('io') && @reader
        @__pdf_harvest = rec
      end
    end

    def parse data = nil
      PdfHarvest.within(@__pdf_harvest) { super }
    end

    def convert opts = {}
      rec = @__pdf_harvest
      begin
        PdfHarvest.within(rec) { super }
      rescue ::Exception => e
        rec[:error] ||= %(#{e.class}: #{e.message}) if rec
        raise
      end
    end

    def write output, target
      PdfHarvest.within(@__pdf_harvest) { super }
    end
  end

  module ConverterHook
    def convert_document doc
      if (rec = doc.instance_variable_get :@__pdf_harvest)
        PdfHarvest.start_conversion rec, self, doc
        @__pdf_harvest = rec
      end
      PdfHarvest.within(rec) { super }
    end

    # Prawn::Document#render: every way the PDF leaves the converter (write
    # to a file or stream, render_file, or render to a string)
    def render *args, &block
      rec = @__pdf_harvest
      return super unless rec && rec[:id]
      target = args[0]
      start = (target.respond_to?(:pos) ? target.pos : 0) rescue 0
      result = PdfHarvest.within(rec) { super }
      bytes = if target.nil?
                result
              elsif StringIO === target
                target.string.byteslice start, target.string.bytesize - start
              elsif target.respond_to?(:path) && target.respond_to?(:flush)
                target.flush
                PdfHarvest.quietly { File.binread(target.path).byteslice start.. }
              end
      PdfHarvest.finish rec, bytes.b if String === bytes
      result
    end

    # a PDF written to a file may be post-processed (optimize); the file is
    # the reference then
    def write pdf_doc, target
      result = super
      if (rec = @__pdf_harvest) && rec[:id] && ::String === target && (::File.file? target)
        PdfHarvest.finish rec, (PdfHarvest.quietly { ::File.binread target })
        rec[:renders] -= 1
      end
      result
    end
  end

  module HelperHook
    def to_pdf input, opts = {}
      PdfHarvest.with_helper('to_pdf', input, opts) { super }
    end

    def to_pdf_file input, output_filename, opts = {}
      PdfHarvest.with_helper('to_pdf_file', input, opts) { super }
    end
  end

  module FileHook
    def read path, *args, **kw, &blk
      PdfHarvest.note_file path
      super
    end

    def binread path, *args, &blk
      PdfHarvest.note_file path
      super
    end

    def open path, *args, **kw, &blk
      if ::String === path || path.respond_to?(:to_path)
        if PdfHarvest.read_mode? args, kw
          PdfHarvest.note_file path
        else
          PdfHarvest.note_written path
        end
      end
      super
    end

    def readlines path, *args, **kw, &blk
      PdfHarvest.note_file path
      super
    end
  end

  module NetHook
    def request *args, &blk
      PdfHarvest.note_network
      super
    end
  end

  module LoggerHook
    def add severity, message = nil, progname = nil, &block
      if (rec = PdfHarvest.current)
        msg = message || (block ? block.call : progname)
        entry = { 'severity' => (severity || ::Logger::Severity::UNKNOWN) }
        if msg.respond_to?(:[]) && msg.respond_to?(:key?) && !(::String === msg)
          entry['message'] = msg[:text].to_s
          entry['source_location'] = msg[:source_location].to_s if msg[:source_location]
        else
          entry['message'] = msg.to_s
        end
        (rec[:messages] ||= []) << entry
        return super severity, msg, progname if !message && block
      end
      super
    end
  end

  # The spec suite runs under Bundler, which activates every gem of the
  # Gemfile up front. The specs guard the syntax highlighter integrations
  # with `gem_available?` (a lookup in Gem.loaded_specs, which lists only
  # activated gems) when the spec file is loaded, so without Bundler the
  # Rouge and Pygments examples of source_spec.rb (and the ones that use
  # rouge elsewhere) would not even be defined. Activate the highlighters
  # the way Bundler does, at the versions scripts/pdf_harvest.mbtx pins and
  # passes as PDF_HARVEST_HIGHLIGHTERS (`name=version,...`): rouge and
  # coderay from the Gemfile, pygments.rb as asciidoctor-pdf's CI installs it
  # (PYGMENTS_VERSION '~> 2.0'); another version in the gem homes is not
  # picked up.
  def self.activate_highlighters
    ENV.fetch('PDF_HARVEST_HIGHLIGHTERS').split(',').each do |pinned|
      name, version = pinned.split '=', 2
      gem name, version
    end
    # CGI.parse for Rouge on Ruby 4.0
    require_relative 'cgi_parse'
  end

  def self.install
    activate_highlighters
    require 'asciidoctor'
    require 'asciidoctor/pdf'
    Asciidoctor.singleton_class.prepend ApiHook
    Asciidoctor::Document.prepend DocumentHook
    Asciidoctor::PDF::Converter.prepend ConverterHook
    ::File.singleton_class.prepend FileHook
    ::Net::HTTP.prepend NetHook
    [::Logger, Asciidoctor::MemoryLogger, Asciidoctor::NullLogger].each {|c| c.prepend LoggerHook }
  end
end

# the spec helpers (to_pdf, to_pdf_file) are defined later, by spec_helper.rb;
# a module prepended now still comes first
module RSpec
  module ExampleHelpers; end
end
RSpec::ExampleHelpers.prepend PdfHarvest::HelperHook

FileUtils.mkdir_p PdfHarvest::OUT_DIR
FileUtils.mkdir_p PdfHarvest::PDF_DIR
PdfHarvest.install

RSpec.configure do |config|
  config.around :each do |example|
    meta = example.metadata
    PdfHarvest.example = {
      file: meta[:file_path],
      scoped_id: meta[:scoped_id],
      line: meta[:line_number],
      description: example.full_description,
      ordinal: 0,
    }
    PdfHarvest.records = []
    PdfHarvest.frames.clear
    PdfHarvest.stack.clear
    example.run
    status = if example.exception
               'failed'
             elsif example.pending? || example.skipped?
               'pending'
             else
               'passed'
             end
    PdfHarvest.counts[:examples] += 1
    PdfHarvest.counts[status.to_sym] += 1
    PdfHarvest.emit_example status
    PdfHarvest.example = nil
  end

  config.after :suite do
    c = PdfHarvest.counts
    summary = { 'examples' => c[:examples], 'passed' => c[:passed], 'failed' => c[:failed], 'pending' => c[:pending], 'conversions' => c[:conversions] }
    File.write (File.join PdfHarvest::OUT_DIR, '.run.json'), (JSON.generate summary)
  end
end
