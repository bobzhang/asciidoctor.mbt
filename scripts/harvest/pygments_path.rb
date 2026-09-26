# frozen_string_literal: true
# Makes pygments.rb run the Python Pygments found in $ORACLE_PYGMENTS_PATH (the
# release bobzhang/pygments ports, installed by scripts/harvest.mbtx) instead of
# the copy it vendors. Loaded by the harvester and, with -r, by the Ruby CLI in
# scripts/corpus.mbtx.
if (path = ENV['ORACLE_PYGMENTS_PATH'])
  require 'pygments'
  Pygments.start path
end
