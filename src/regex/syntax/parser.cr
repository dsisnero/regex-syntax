module Regex::Syntax
  # Public parser entrypoint. This follows the same staged shape as Rust:
  # parse source text into AST, then translate AST into HIR.
  class Parser
    @unicode : Bool
    @ignore_case : Bool
    @multi_line : Bool
    @dot_matches_new_line : Bool
    @swap_greed : Bool
    @ignore_whitespace : Bool
    @crlf : Bool
    @nest_limit : Int32?
    @octal : Bool

    def initialize(*,
                   unicode : Bool = true,
                   ignore_case : Bool = false,
                   multi_line : Bool = false,
                   dot_matches_new_line : Bool = false,
                   swap_greed : Bool = false,
                   ignore_whitespace : Bool = false,
                   crlf : Bool = false,
                   nest_limit : Int32? = nil,
                   octal : Bool = false)
      @unicode = unicode
      @ignore_case = ignore_case
      @multi_line = multi_line
      @dot_matches_new_line = dot_matches_new_line
      @swap_greed = swap_greed
      @ignore_whitespace = ignore_whitespace
      @crlf = crlf
      @nest_limit = nest_limit
      @octal = octal
    end

    def parse(pattern : String) : Hir::Hir
      ast = AstParser.new(
        unicode: @unicode,
        ignore_whitespace: @ignore_whitespace,
        ignore_case: @ignore_case,
        multi_line: @multi_line,
        dot_matches_new_line: @dot_matches_new_line,
        swap_greed: @swap_greed,
        crlf: @crlf,
        nest_limit: @nest_limit,
        octal: @octal
      ).parse(pattern)

      hir = Translator.new(
        unicode: @unicode,
        ignore_case: @ignore_case,
        multi_line: @multi_line,
        dot_matches_new_line: @dot_matches_new_line,
        swap_greed: @swap_greed,
        ignore_whitespace: @ignore_whitespace,
        crlf: @crlf,
        nest_limit: @nest_limit
      ).translate(ast.root)

      Hir::Hir.new(hir)
    end
  end
end
