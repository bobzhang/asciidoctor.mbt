# frozen_string_literal: true
# Rouge 3.30 reads cgi-style lexer options (`[source,php?start_inline=1]`,
# Lexer.lookup_fancy) with CGI.parse, which Ruby 4.0 dropped together with
# the rest of the cgi library (only cgi/escape is left). This restores it as
# the cgi gem defines it, so that those conversions behave as on the Rubies
# asciidoctor-pdf 2.3.27 supports. Loaded by scripts/pdf_harvest/harvest.rb,
# scripts/pdf_rouge/harvest.rb and, with RUBYOPT, by the oracle runs of
# scripts/pdf_compare.mbtx.
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
