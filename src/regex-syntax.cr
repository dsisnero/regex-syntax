require "./regex/syntax/hir"
require "./regex/syntax/ast"
require "./regex/syntax/parser"

module Regex::Syntax
  VERSION = "0.1.0"

  # Main entry point for parsing regular expressions
  def self.parse(pattern : String, **options) : Hir::Hir
    parser = Parser.new(**options)
    parser.parse(pattern)
  end

  # Error types
  class Error < Exception
  end

  class ParseError < Error
  end
end
