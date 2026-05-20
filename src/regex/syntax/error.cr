module Regex::Syntax
  private struct FormatterPosition
    getter line : Int32
    getter column : Int32

    def initialize(@line : Int32, @column : Int32)
    end
  end

  private struct FormatterSpan
    getter start : FormatterPosition
    getter end : FormatterPosition

    def initialize(@start : FormatterPosition, @end : FormatterPosition)
    end

    def one_line? : Bool
      start.line == end.line
    end
  end

  private class FormatterSpans
    getter multi_line : Array(FormatterSpan)

    def initialize(@pattern : String, span : AST::Span, auxiliary_span : AST::Span?)
      @multi_line = [] of FormatterSpan
      @by_line = Array(Array(FormatterSpan)).new(line_count) { [] of FormatterSpan }
      add(span)
      add(auxiliary_span) if auxiliary_span
    end

    def notate : String
      String.build do |io|
        lines.each_with_index do |line, i|
          if line_number_width.zero?
            io << "    " << line << '\n'
          else
            io << left_pad_line_number(i + 1) << ": " << line << '\n'
          end
          if notes = notate_line(i)
            io << notes << '\n'
          end
        end
      end
    end

    def multi_line_notes : Array(String)
      @multi_line.map do |span|
        "on line #{span.start.line} (column #{span.start.column}) through line #{span.end.line} (column #{span.end.column - 1})"
      end
    end

    private def add(span : AST::Span) : Nil
      converted = convert(span)
      if converted.one_line?
        idx = converted.start.line - 1
        @by_line[idx] << converted
        @by_line[idx].sort_by! { |span_item| {span_item.start.column, span_item.end.column} }
      else
        @multi_line << converted
        @multi_line.sort_by! do |span_item|
          {span_item.start.line, span_item.start.column, span_item.end.line, span_item.end.column}
        end
      end
    end

    private def convert(span : AST::Span) : FormatterSpan
      FormatterSpan.new(position_for(span.start.offset), position_for(span.end.offset))
    end

    private def position_for(offset : Int32) : FormatterPosition
      line = 1
      column = 1
      i = 0
      max = offset.clamp(0, @pattern.bytesize)
      while i < max
        if @pattern.byte_at(i) == '\n'.ord
          line += 1
          column = 1
        else
          column += 1
        end
        i += 1
      end
      FormatterPosition.new(line, column)
    end

    private def notate_line(index : Int32) : String?
      spans = @by_line[index]
      return nil if spans.empty?

      String.build do |io|
        line_number_padding.times { io << ' ' }
        pos = 1
        spans.each do |span|
          while pos < span.start.column
            io << ' '
            pos += 1
          end
          note_len = {1, span.end.column - span.start.column}.max
          note_len.times do
            io << '^'
            pos += 1
          end
        end
      end
    end

    private def lines : Array(String)
      @pattern.split('\n', remove_empty: false)
    end

    private def line_count : Int32
      lines.size.to_i
    end

    private def line_number_width : Int32
      return 0 if line_count <= 1
      line_count.to_s.size.to_i
    end

    private def left_pad_line_number(n : Int32) : String
      text = n.to_s
      "#{" " * (line_number_width - text.size)}#{text}"
    end

    private def line_number_padding : Int32
      line_number_width.zero? ? 4 : line_number_width + 2
    end
  end

  class Error < Exception
  end

  class ParseError < Error
    getter raw_message : String
    getter span : AST::Span?
    getter auxiliary_span : AST::Span?
    getter kind_key : Symbol?

    def initialize(message : String, @kind_key : Symbol? = nil, @span : AST::Span? = nil, @auxiliary_span : AST::Span? = nil)
      @raw_message = message
      super(message)
    end

    def message : String?
      @raw_message
    end
  end

  class Formatter(E)
    def initialize(@pattern : String, @err : E, @span : AST::Span, @auxiliary_span : AST::Span? = nil)
    end

    def to_s(io : IO) : Nil
      io << "regex parse error:\n"
      spans = FormatterSpans.new(@pattern, @span, @auxiliary_span)
      if @pattern.includes?('\n')
        divider = "~" * 79
        io << divider << '\n'
        io << spans.notate
        io << divider << '\n'
        spans.multi_line_notes.each do |note|
          io << note << '\n'
        end
      else
        io << spans.notate
      end
      io << "error: " << @err
    end
  end
end

module Regex::Syntax::AST
  enum ErrorKind
    CaptureLimitExceeded
    ClassEscapeInvalid
    ClassRangeInvalid
    ClassUnclosed
    DecimalEmpty
    DecimalInvalid
    EscapeHexEmpty
    EscapeHexInvalid
    EscapeHexInvalidDigit
    EscapeUnexpectedEof
    EscapeUnrecognized
    FlagDanglingNegation
    FlagDuplicate
    FlagRepeatedNegation
    FlagUnexpectedEof
    FlagUnrecognized
    GroupNameDuplicate
    GroupNameEmpty
    GroupNameInvalid
    GroupNameUnexpectedEof
    GroupUnclosed
    GroupUnopened
    NestLimitExceeded
    RepetitionCountInvalid
    RepetitionCountDecimalEmpty
    RepetitionCountUnclosed
    RepetitionMissing
    SpecialWordBoundaryUnclosed
    SpecialWordBoundaryUnrecognized
    SpecialWordOrRepetitionUnexpectedEof
    UnicodeClassInvalid
    UnsupportedBackreference
    UnsupportedLookAround
    UnsupportedGroupSyntax

    def to_s(io : IO) : Nil
      io << case self
      in .capture_limit_exceeded?                    then "exceeded the maximum number of capturing groups"
      in .class_escape_invalid?                      then "invalid escape sequence found in character class"
      in .class_range_invalid?                       then "invalid character class range, the start must be <= the end"
      in .class_unclosed?                            then "unclosed character class"
      in .decimal_empty?                             then "decimal literal empty"
      in .decimal_invalid?                           then "decimal literal invalid"
      in .escape_hex_empty?                          then "hexadecimal literal empty"
      in .escape_hex_invalid?                        then "hexadecimal literal is not a Unicode scalar value"
      in .escape_hex_invalid_digit?                  then "invalid hexadecimal digit"
      in .escape_unexpected_eof?                     then "incomplete escape sequence, reached end of pattern prematurely"
      in .escape_unrecognized?                       then "unrecognized escape sequence"
      in .flag_dangling_negation?                    then "dangling flag negation operator"
      in .flag_duplicate?                            then "duplicate flag"
      in .flag_repeated_negation?                    then "flag negation operator repeated"
      in .flag_unexpected_eof?                       then "expected flag but got end of regex"
      in .flag_unrecognized?                         then "unrecognized flag"
      in .group_name_duplicate?                      then "duplicate capture group name"
      in .group_name_empty?                          then "empty capture group name"
      in .group_name_invalid?                        then "invalid capture group character"
      in .group_name_unexpected_eof?                 then "unclosed capture group name"
      in .group_unclosed?                            then "unclosed group"
      in .group_unopened?                            then "unopened group"
      in .nest_limit_exceeded?                       then "exceed the maximum number of nested parentheses/brackets"
      in .repetition_count_invalid?                  then "invalid repetition quantifier range, the start must be <= the end"
      in .repetition_count_decimal_empty?            then "repetition quantifier expects a valid decimal"
      in .repetition_count_unclosed?                 then "unclosed counted repetition"
      in .repetition_missing?                        then "repetition operator missing expression"
      in .special_word_boundary_unclosed?            then "special word boundary assertion is either unclosed or contains an invalid character"
      in .special_word_boundary_unrecognized?        then "unrecognized special word boundary assertion, valid choices are: start, end, start-half or end-half"
      in .special_word_or_repetition_unexpected_eof? then "found either the beginning of a special word boundary or a bounded repetition on a \\b with an opening brace, but no closing brace"
      in .unicode_class_invalid?                     then "invalid Unicode character class"
      in .unsupported_backreference?                 then "backreferences are not supported"
      in .unsupported_look_around?                   then "look-around is not supported"
      in .unsupported_group_syntax?                  then "unsupported group syntax"
      end
    end
  end

  class Error < Regex::Syntax::ParseError
    getter kind : ErrorKind
    getter pattern : String

    def initialize(@kind : ErrorKind, @pattern : String, span : Span, auxiliary_span : Span? = nil, raw_message : String? = nil)
      @error_span = span
      @error_auxiliary_span = auxiliary_span
      super(raw_message || @kind.to_s, nil, @error_span, @error_auxiliary_span)
    end

    def span : Span
      @error_span
    end

    def auxiliary_span : Span?
      @error_auxiliary_span
    end

    def to_s(io : IO) : Nil
      Regex::Syntax::Formatter(ErrorKind).new(@pattern, @kind, @error_span, @error_auxiliary_span).to_s(io)
    end
  end
end

module Regex::Syntax::Hir
  enum ErrorKind
    UnicodeNotAllowed
    InvalidUtf8
    InvalidLineTerminator
    UnicodePropertyNotFound
    UnicodePropertyValueNotFound
    UnicodePerlClassNotFound
    UnicodeCaseUnavailable

    def to_s(io : IO) : Nil
      io << case self
      in .unicode_not_allowed?              then "Unicode not allowed here"
      in .invalid_utf8?                     then "pattern can match invalid UTF-8"
      in .invalid_line_terminator?          then "invalid line terminator, must be ASCII"
      in .unicode_property_not_found?       then "Unicode property not found"
      in .unicode_property_value_not_found? then "Unicode property value not found"
      in .unicode_perl_class_not_found?     then "Unicode-aware Perl class not found"
      in .unicode_case_unavailable?         then "Unicode-aware case insensitivity matching is not available"
      end
    end
  end

  class Error < Regex::Syntax::ParseError
    getter kind : ErrorKind
    getter pattern : String

    def initialize(@kind : ErrorKind, @pattern : String, span : AST::Span, raw_message : String? = nil)
      @error_span = span
      super(raw_message || @kind.to_s, nil, @error_span)
    end

    def span : AST::Span
      @error_span
    end

    def to_s(io : IO) : Nil
      Regex::Syntax::Formatter(ErrorKind).new(@pattern, @kind, @error_span).to_s(io)
    end
  end
end
