# frozen_string_literal: false
# Golden-fixture harvester.
#
# Loaded before an upstream test file (see scripts/harvest.mbtx). Records, for every
# top-level Asciidoctor::Document created during a test:
#   - the source text and the load options (JSON-safe subset)
#   - a canonical dump of the parsed AST (after Document#parse)
#   - the converted output (if Document#convert is called)
#   - every log message emitted while the document was active
# Records are written as JSON lines to $HARVEST_OUT.
require 'json'

HARVEST_ROOT = File.expand_path '../../.repos/asciidoctor', __dir__
$LOAD_PATH.unshift File.join(HARVEST_ROOT, 'lib')
require 'asciidoctor'
require 'asciidoctor/extensions'
require 'minitest'

module Harvest
  OUT = File.open(ENV.fetch('HARVEST_OUT'), 'w')
  COMPLIANCE_DEFAULTS = Asciidoctor::Compliance.keys.each_with_object({}) {|k, h| h[k] = Asciidoctor::Compliance.send k }
  @test = nil
  @active = []
  class << self
    attr_accessor :test, :active

    def json_safe val
      case val
      when nil, true, false, Integer, Float, String then val
      when Symbol then val.to_s
      when Array then val.map { |v| json_safe v }
      when Hash then val.each_with_object({}) { |(k, v), h| h[k.to_s] = json_safe v }
      else { '__unsupported__' => val.class.to_s }
      end
    end

    def relpath path
      path.is_a?(String) && path.start_with?(HARVEST_ROOT) ? path.sub(HARVEST_ROOT, '$ROOT') : path
    end

    def options_for opts
      opts.each_with_object({}) do |(k, v), h|
        k = k.to_s
        v = relpath v if %w(base_dir to_dir to_file docdir).include?(k)
        h[k] = json_safe v
      end
    end

    def text_of node, ivar
      node.instance_variable_get ivar
    end

    def dump_node node
      d = { 'context' => node.context.to_s }
      d['node_name'] = node.node_name if node.node_name != node.context.to_s
      d['id'] = node.id if node.id
      d['style'] = node.style if node.respond_to?(:style) && node.style
      d['level'] = node.level if node.respond_to?(:level) && node.level
      d['title'] = text_of(node, :@title) if text_of(node, :@title)
      d['numeral'] = node.numeral.to_s if node.respond_to?(:numeral) && node.numeral
      d['content_model'] = node.content_model.to_s if node.respond_to?(:content_model) && ![:compound].include?(node.content_model)
      d['subs'] = node.subs.map(&:to_s) if node.respond_to?(:subs) && !node.subs.empty?
      attrs = node.attributes.reject { |k, _| k == 'attribute_entries' }
      d['attributes'] = json_safe(attrs.to_a) unless attrs.empty? || node.context == :document
      case node
      when Asciidoctor::Document
        d['header'] = { 'doctitle' => node.header? ? text_of(node.header, :@title) : nil }
        d['attributes'] = json_safe node.attributes.reject { |k, _| k.start_with?('local', 'doc') && k.end_with?('date', 'time', 'year', 'datetime') || k == 'attribute_entries' }.sort.to_a
      when Asciidoctor::Section
        d['sectname'] = node.sectname
        d['special'] = true if node.special
        d['numbered'] = true if node.numbered
      when Asciidoctor::ListItem
        d['text'] = text_of(node, :@text)
        d['marker'] = node.marker if node.marker
      when Asciidoctor::Block
        d['lines'] = node.lines unless node.lines.empty?
      when Asciidoctor::Table
        d['rows'] = %w(head body foot).map do |s|
          node.rows[s.to_sym].map { |row| row.map { |c| dump_cell c } }
        end
        d['columns'] = node.columns.map { |c| json_safe c.attributes.to_a }
      end
      if node.is_a?(Asciidoctor::List) && node.context == :dlist
        d['items'] = node.blocks.map { |terms, desc| { 'terms' => terms.map { |t| dump_node t }, 'desc' => desc && dump_node(desc) } }
      elsif node.respond_to?(:blocks) && !node.blocks.empty?
        d['blocks'] = node.blocks.map { |b| dump_node b }
      end
      d
    end

    def dump_cell cell
      c = { 'text' => text_of(cell, :@text), 'style' => (cell.style && cell.style.to_s) }
      c['colspan'] = cell.colspan if cell.colspan
      c['rowspan'] = cell.rowspan if cell.rowspan
      c['inner'] = dump_node(cell.inner_document) if cell.inner_document
      c
    end

    def scrub val
      case val
      when String then val.dup.force_encoding('UTF-8').scrub
      when Array then val.map { |v| scrub v }
      when Hash then val.each_with_object({}) { |(k, v), h| h[scrub k] = scrub v }
      else val
      end
    end

    def emit rec
      json = begin
        JSON.generate(rec, max_nesting: false)
      rescue JSON::GeneratorError
        JSON.generate(scrub(rec).merge("scrubbed" => true), max_nesting: false)
      end
      OUT.puts json
      OUT.flush
    end
  end

  module DocumentHook
    def initialize data = nil, options = {}
      top = !options[:parent]
      rec = nil
      if top
        src = case data
              when String then data
              when Array then nil
              when nil then nil
              else (data.respond_to?(:read) ? { '__io__' => true } : data.to_s)
              end
        rec = { 'test' => Harvest.test, 'source' => src, 'options' => Harvest.options_for(options) }
        compliance = Asciidoctor::Compliance.keys.each_with_object({}) do |k, h|
          v = Asciidoctor::Compliance.send k
          h[k.to_s] = v unless v == Harvest::COMPLIANCE_DEFAULTS[k]
        end
        rec['compliance'] = compliance unless compliance.empty?
        rec['source_date_epoch'] = ENV['SOURCE_DATE_EPOCH'] unless ENV['SOURCE_DATE_EPOCH'] == '1700000000'
        rec['source_lines'] = data if Array === data
        Harvest.active.push rec
      end
      super
      if rec
        @__harvest = rec
        rec['source'] = @reader.source_lines.join("\n") if Hash === rec['source'] && @reader
      end
    ensure
      Harvest.active.delete rec if rec && !@__harvest
    end

    def parse data = nil
      r = super
      if (rec = @__harvest) && !rec['ast']
        begin
          rec['ast'] = JSON.parse(JSON.generate(Harvest.scrub(Harvest.dump_node(self)), max_nesting: false), max_nesting: false)
        rescue StandardError => e
          rec['ast_error'] = e.message
        end
      end
      r
    end

    def convert opts = {}
      out = super
      if (rec = @__harvest)
        rec['converted'] ||= []
        rec['converted'] << { 'opts' => Harvest.json_safe(opts), 'backend' => @backend, 'standalone' => !(attr? 'embedded'), 'output' => out.is_a?(String) ? out : out.to_s }
      end
      out
    end
  end
  Asciidoctor::Document.prepend DocumentHook

  def self.record_file path
    return if Harvest.active.empty? || @recording
    @recording = true
    begin
      path = path.to_path if path.respond_to? :to_path
      return unless ::String === path && ::File.file?(path)
      data = ::File.binread path
      files = (Harvest.active.last['files'] ||= {})
      files[Harvest.relpath(::File.absolute_path(path))] = [data].pack('m0')
    rescue StandardError
      nil
    ensure
      @recording = false
    end
  end

  module FileHook
    def read path, *args, &blk
      Harvest.record_file path
      super
    end

    def binread path, *args, &blk
      Harvest.record_file path
      super
    end

    def open path, *args, &blk
      Harvest.record_file path if ::String === path || path.respond_to?(:to_path)
      super
    end
  end
  ::File.singleton_class.prepend FileHook

  module LoggerHook
    def add severity, message = nil, progname = nil, &block
      unless Harvest.active.empty?
        msg = message || (block ? block.call : progname)
        text = msg.is_a?(Hash) || msg.respond_to?(:[]) && msg.respond_to?(:key?) ? { 'text' => msg[:text], 'source_location' => msg[:source_location]&.to_s } : msg.to_s
        (Harvest.active.last['messages'] ||= []) << { 'severity' => severity, 'message' => text }
      end
      super
    end
  end
  [::Logger, Asciidoctor::MemoryLogger, Asciidoctor::NullLogger].each { |c| c.prepend LoggerHook }

  module TestHook
    def before_setup
      Harvest.test = "#{self.class.name}##{name}"
      super
    end

    def after_teardown
      super
      Harvest.active.each { |rec| Harvest.emit rec }
      Harvest.active.clear
      Harvest.test = nil
    end
  end
  Minitest::Test.prepend TestHook
end
