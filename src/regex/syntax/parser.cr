module Regex::Syntax
  class AstParserBuilder
    def initialize
      @unicode = true
      @ignore_whitespace = false
      @ignore_case = false
      @multi_line = false
      @dot_matches_new_line = false
      @swap_greed = false
      @crlf = false
      @nest_limit = nil.as(Int32?)
      @octal = false
      @empty_min_range = false
    end

    def build : AstParser
      AstParser.new(
        unicode: @unicode,
        ignore_whitespace: @ignore_whitespace,
        ignore_case: @ignore_case,
        multi_line: @multi_line,
        dot_matches_new_line: @dot_matches_new_line,
        swap_greed: @swap_greed,
        crlf: @crlf,
        nest_limit: @nest_limit,
        octal: @octal,
        empty_min_range: @empty_min_range
      )
    end

    def ignore_whitespace(yes : Bool) : self
      @ignore_whitespace = yes
      self
    end

    def nest_limit(limit : Int32) : self
      @nest_limit = limit
      self
    end

    def octal(yes : Bool) : self
      @octal = yes
      self
    end

    def empty_min_range(yes : Bool) : self
      @empty_min_range = yes
      self
    end
  end

  def self.parse(pattern : String) : Hir::Hir
    Parser.new.parse(pattern)
  end

  class ParserBuilder
    def initialize
      @unicode = true
      @ignore_case = false
      @multi_line = false
      @dot_matches_new_line = false
      @swap_greed = false
      @ignore_whitespace = false
      @crlf = false
      @nest_limit = nil.as(Int32?)
      @octal = false
      @utf8 = true
      @line_terminator = '\n'.ord.to_u8
    end

    def build : Parser
      Parser.new(
        unicode: @unicode,
        ignore_case: @ignore_case,
        multi_line: @multi_line,
        dot_matches_new_line: @dot_matches_new_line,
        swap_greed: @swap_greed,
        ignore_whitespace: @ignore_whitespace,
        crlf: @crlf,
        nest_limit: @nest_limit,
        octal: @octal,
        utf8: @utf8,
        line_terminator: @line_terminator
      )
    end

    def nest_limit(limit : Int32) : self
      @nest_limit = limit
      self
    end

    def octal(yes : Bool) : self
      @octal = yes
      self
    end

    def utf8(yes : Bool) : self
      @utf8 = yes
      self
    end

    def line_terminator(byte : UInt8) : self
      @line_terminator = byte
      self
    end

    def ignore_whitespace(yes : Bool) : self
      @ignore_whitespace = yes
      self
    end

    def case_insensitive(yes : Bool) : self
      @ignore_case = yes
      self
    end

    def multi_line(yes : Bool) : self
      @multi_line = yes
      self
    end

    def dot_matches_new_line(yes : Bool) : self
      @dot_matches_new_line = yes
      self
    end

    def crlf(yes : Bool) : self
      @crlf = yes
      self
    end

    def swap_greed(yes : Bool) : self
      @swap_greed = yes
      self
    end

    def unicode(yes : Bool) : self
      @unicode = yes
      self
    end
  end

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
    @utf8 : Bool
    @line_terminator : UInt8

    def initialize(*,
                   unicode : Bool = true,
                   ignore_case : Bool = false,
                   multi_line : Bool = false,
                   dot_matches_new_line : Bool = false,
                   swap_greed : Bool = false,
                   ignore_whitespace : Bool = false,
                   crlf : Bool = false,
                   nest_limit : Int32? = nil,
                   octal : Bool = false,
                   utf8 : Bool = true,
                   line_terminator : UInt8 = '\n'.ord.to_u8)
      @unicode = unicode
      @ignore_case = ignore_case
      @multi_line = multi_line
      @dot_matches_new_line = dot_matches_new_line
      @swap_greed = swap_greed
      @ignore_whitespace = ignore_whitespace
      @crlf = crlf
      @nest_limit = nest_limit
      @octal = octal
      @utf8 = utf8
      @line_terminator = line_terminator
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

      begin
        hir = Translator.new(
          unicode: @unicode,
          utf8: @utf8,
          ignore_case: @ignore_case,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          crlf: @crlf,
          nest_limit: @nest_limit,
          line_terminator: @line_terminator
        ).translate(ast.root)

        Hir::Hir.new(hir)
      rescue ex : ParseError
        raise Hir::Error.new(map_translate_error_kind(ex), pattern, ex.span || ast.span, ex.message.to_s)
      end
    end

    private def map_translate_error_kind(ex : ParseError) : Hir::ErrorKind
      case ex.message
      when "Unicode not allowed"
        Hir::ErrorKind::UnicodeNotAllowed
      when "invalid UTF-8"
        Hir::ErrorKind::InvalidUtf8
      when "invalid line terminator"
        Hir::ErrorKind::InvalidLineTerminator
      else
        if ex.message.to_s.starts_with?("invalid Unicode property value")
          Hir::ErrorKind::UnicodePropertyValueNotFound
        elsif ex.message.to_s.starts_with?("invalid Unicode property")
          Hir::ErrorKind::UnicodePropertyNotFound
        else
          Hir::ErrorKind::UnicodePropertyNotFound
        end
      end
    end
  end
end
