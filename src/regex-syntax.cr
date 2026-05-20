require "set"
require "./regex/syntax/hir"
require "./regex/syntax/hir_interval"
require "./regex/syntax/rank"
require "./regex/syntax/literal"
require "./regex/syntax/utf8"
require "./regex/syntax/hir_print"
require "./regex/syntax/hir_visitor"
require "./regex/syntax/ast"
require "./regex/syntax/error"
require "./regex/syntax/ast_print"
require "./regex/syntax/ast_visitor"
require "./regex/syntax/parser"
require "./regex/syntax/translate"

module Regex::Syntax
  VERSION = "0.1.0"

  class UnicodeWordError < Error
  end

  def self.escape(text : String) : String
    String.build do |io|
      escape_into(text, io)
    end
  end

  def self.escape_into(text : String, io : IO) : Nil
    text.each_char do |char|
      io << '\\' if meta_character?(char)
      io << char
    end
  end

  def self.meta_character?(char : Char) : Bool
    case char
    when '\\', '.', '+', '*', '?', '(', ')', '|', '[', ']', '{', '}', '^', '$', '#', '&', '-', '~'
      true
    else
      false
    end
  end

  def self.escapeable_character?(char : Char) : Bool
    return true if meta_character?(char)
    return false unless char.ascii?

    case char
    when '0'..'9', 'A'..'Z', 'a'..'z', '<', '>'
      false
    else
      true
    end
  end

  def self.word_byte?(byte : UInt8) : Bool
    case byte
    when '_'.ord.to_u8, '0'.ord.to_u8..'9'.ord.to_u8, 'a'.ord.to_u8..'z'.ord.to_u8, 'A'.ord.to_u8..'Z'.ord.to_u8
      true
    else
      false
    end
  end

  def self.word_character?(char : Char) : Bool
    try_is_word_character(char)
  end

  def self.try_is_word_character(char : Char) : Bool
    codepoint = char.ord.to_u32
    ranges = Regex::Syntax::UnicodeTables::PerlWord::PERL_WORD
    !!ranges.bsearch { |range| range.end >= codepoint }.try { |range| codepoint >= range.begin }
  end

  # AST parser for regex source text.
  class AstParser
    @input : String
    @pos : Int32
    @len : Int32
    @unicode : Bool
    @ignore_whitespace : Bool
    @nest_limit : Int32?
    @octal : Bool
    @empty_min_range : Bool
    @capture_index : Int32
    @capture_names : Hash(String, AST::Span)
    @comments : Array(AST::Comment)

    # Stack for tracking flag state when entering groups
    @flag_stack : Array(Tuple(Bool, Bool, Bool, Bool, Bool, Bool))

    @initial_unicode : Bool
    @initial_ignore_whitespace : Bool
    # Current flag state
    @initial_ignore_case : Bool
    @initial_multi_line : Bool
    @initial_dot_matches_new_line : Bool
    @initial_swap_greed : Bool
    @initial_crlf : Bool
    @ignore_case : Bool
    @multi_line : Bool
    @dot_matches_new_line : Bool
    @swap_greed : Bool
    @crlf : Bool

    def initialize(*, unicode : Bool = true, ignore_whitespace : Bool = false, ignore_case : Bool = false, multi_line : Bool = false, dot_matches_new_line : Bool = false, swap_greed : Bool = false, crlf : Bool = false, nest_limit : Int32? = nil, octal : Bool = false, empty_min_range : Bool = false)
      @initial_unicode = unicode
      @initial_ignore_whitespace = ignore_whitespace
      @initial_ignore_case = ignore_case
      @initial_multi_line = multi_line
      @initial_dot_matches_new_line = dot_matches_new_line
      @initial_swap_greed = swap_greed
      @initial_crlf = crlf
      @unicode = unicode
      @ignore_whitespace = ignore_whitespace
      @ignore_case = ignore_case
      @multi_line = multi_line
      @dot_matches_new_line = dot_matches_new_line
      @swap_greed = swap_greed
      @crlf = crlf
      @nest_limit = nest_limit
      @octal = octal
      @empty_min_range = empty_min_range
      @capture_index = 0
      @capture_names = {} of String => AST::Span
      @comments = [] of AST::Comment
      @flag_stack = [] of Tuple(Bool, Bool, Bool, Bool, Bool, Bool)
      @input = ""
      @pos = 0
      @len = 0
    end

    def parse(pattern : String) : AST::Ast
      parse_with_comments(pattern).ast
    end

    def parse_with_comments(pattern : String) : AST::WithComments
      reset(pattern)

      root = parse_alternation
      check_nest_limit(root) if @nest_limit

      AST::WithComments.new(AST::Ast.new(root), @comments.dup)
    rescue ex : ParseError
      raise AST::Error.new(map_parse_error_kind(ex), pattern, ex.span || error_span, ex.auxiliary_span, ex.message.to_s)
    end

    private def reset(pattern : String) : Nil
      @input = pattern
      @pos = 0
      @len = pattern.size
      @unicode = @initial_unicode
      @ignore_whitespace = @initial_ignore_whitespace
      @ignore_case = @initial_ignore_case
      @multi_line = @initial_multi_line
      @dot_matches_new_line = @initial_dot_matches_new_line
      @swap_greed = @initial_swap_greed
      @crlf = @initial_crlf
      @capture_index = 0
      @capture_names.clear
      @comments.clear
      @flag_stack.clear
    end

    private def error_span : AST::Span
      start = @pos.clamp(0, @len)
      finish = start
      finish += 1 if finish < @len
      AST::Span.new(start, finish)
    end

    private def map_parse_error_kind(ex : ParseError) : AST::ErrorKind
      if kind_key = ex.kind_key
        return map_parse_error_key(kind_key)
      end

      case ex.message
      when "unmatched ')'"
        AST::ErrorKind::GroupUnopened
      when "decimal literal empty", "empty decimal"
        AST::ErrorKind::DecimalEmpty
      when "decimal literal invalid", "invalid decimal"
        AST::ErrorKind::DecimalInvalid
      when "repetition operator not preceded by expression"
        AST::ErrorKind::RepetitionMissing
      when "unexpected end of pattern after backslash", "unexpected end of pattern in Unicode property escape", "unexpected end of pattern in hex escape"
        AST::ErrorKind::EscapeUnexpectedEof
      when "backreferences are not supported"
        AST::ErrorKind::UnsupportedBackreference
      when "unclosed Unicode property escape"
        AST::ErrorKind::UnicodeClassInvalid
      when "special word boundary unclosed"
        AST::ErrorKind::SpecialWordBoundaryUnclosed
      when "unrecognized special word boundary assertion"
        AST::ErrorKind::SpecialWordBoundaryUnrecognized
      when "special word boundary or repetition unexpected end of pattern"
        AST::ErrorKind::SpecialWordOrRepetitionUnexpectedEof
      when "invalid hex digit in escape"
        AST::ErrorKind::EscapeHexInvalidDigit
      when "empty hex escape"
        AST::ErrorKind::EscapeHexEmpty
      when "invalid hex escape"
        AST::ErrorKind::EscapeHexInvalid
      when "invalid escape sequence", "unrecognized escape sequence"
        AST::ErrorKind::EscapeUnrecognized
      when "invalid escape sequence in character class"
        AST::ErrorKind::ClassEscapeInvalid
      when "unclosed character class"
        AST::ErrorKind::ClassUnclosed
      when "invalid character class range"
        AST::ErrorKind::ClassRangeInvalid
      when "unsupported group syntax"
        AST::ErrorKind::UnsupportedGroupSyntax
      when "look-behind groups not supported", "look-ahead groups not supported"
        AST::ErrorKind::UnsupportedLookAround
      when "unclosed group"
        AST::ErrorKind::GroupUnclosed
      when "invalid capture name"
        AST::ErrorKind::GroupNameInvalid
      when "empty capture name"
        AST::ErrorKind::GroupNameEmpty
      when "unclosed capture group name"
        AST::ErrorKind::GroupNameUnexpectedEof
      when "capture limit exceeded"
        AST::ErrorKind::CaptureLimitExceeded
      when "unclosed repetition count"
        AST::ErrorKind::RepetitionCountUnclosed
      when "invalid repetition range"
        AST::ErrorKind::RepetitionCountInvalid
      when "empty repetition count"
        AST::ErrorKind::RepetitionCountDecimalEmpty
      when "unexpected end of flags"
        AST::ErrorKind::FlagUnexpectedEof
      when "unrecognized flag"
        AST::ErrorKind::FlagUnrecognized
      else
        if ex.message.to_s.starts_with?("duplicate flag")
          AST::ErrorKind::FlagDuplicate
        elsif ex.message.to_s.starts_with?("repeated flag negation")
          AST::ErrorKind::FlagRepeatedNegation
        elsif ex.message.to_s.starts_with?("dangling flag negation")
          AST::ErrorKind::FlagDanglingNegation
        elsif ex.message.to_s.starts_with?("duplicate capture name")
          AST::ErrorKind::GroupNameDuplicate
        elsif ex.message.to_s.starts_with?("nest limit exceeded")
          AST::ErrorKind::NestLimitExceeded
        elsif ex.message.to_s.starts_with?("invalid Unicode property")
          AST::ErrorKind::UnicodeClassInvalid
        else
          AST::ErrorKind::EscapeUnrecognized
        end
      end
    end

    private def map_parse_error_key(kind_key : Symbol) : AST::ErrorKind
      case kind_key
      when :flag_duplicate         then AST::ErrorKind::FlagDuplicate
      when :flag_repeated_negation then AST::ErrorKind::FlagRepeatedNegation
      when :flag_dangling_negation then AST::ErrorKind::FlagDanglingNegation
      when :group_name_duplicate   then AST::ErrorKind::GroupNameDuplicate
      when :nest_limit_exceeded    then AST::ErrorKind::NestLimitExceeded
      else
        AST::ErrorKind::EscapeUnrecognized
      end
    end

    private def parse_alternation : AST::Node
      terms = [] of AST::Node
      terms << parse_concatenation

      while current_char == '|'
        advance # skip '|'
        terms << parse_concatenation
      end

      if terms.size == 1
        terms.first
      else
        AST::Alternation.new(AST::Span.new(0, @pos), terms)
      end
    end

    private def parse_concatenation : AST::Node
      atoms = [] of AST::Node

      while !eof? && current_char != '|' && current_char != ')'
        bump_space
        break if eof? || current_char == '|' || current_char == ')'

        atom = parse_atom
        unless atom.is_a?(AST::Empty)
          atoms << atom
        end
      end

      case atoms.size
      when 0
        AST::Empty.new(AST::Span.new(@pos, @pos))
      when 1
        atoms.first
      else
        AST::Concat.new(AST::Span.new(0, @pos), atoms)
      end
    end

    private def parse_atom : AST::Node
      node = parse_primary
      while repetition_operator_start?
        if node.is_a?(AST::SetFlags)
          raise ParseError.new("repetition operator not preceded by expression", nil, AST::Span.new(@pos, @pos))
        end
        node = parse_repetition(node)
      end
      node
    end

    private def repetition_operator_start? : Bool
      return false if eof?

      case current_char
      when '*', '+', '?', '{'
        true
      else
        false
      end
    end

    private def parse_primary : AST::Node
      return AST::Empty.new(AST::Span.new(@pos, @pos)) if eof?

      case current_char
      when '.'
        parse_dot
      when '^'
        parse_assertion_start
      when '$'
        parse_assertion_end
      when '\\'
        parse_escape
      when '['
        parse_class_bracketed
      when '('
        parse_group
      when ')'
        raise ParseError.new("unmatched ')'")
      when '*', '+', '?', '{'
        raise ParseError.new("repetition operator not preceded by expression", nil, AST::Span.new(@pos, @pos))
      when '|'
        AST::Empty.new(AST::Span.new(@pos, @pos))
      else
        parse_literal
      end
    end

    private def parse_dot : AST::Node
      start = @pos
      advance
      AST::Dot.new(AST::Span.new(start, @pos))
    end

    private def parse_assertion_start : AST::Node
      start = @pos
      advance
      AST::Assertion.new(AST::Span.new(start, @pos), AST::Assertion::Kind::Start)
    end

    private def parse_assertion_end : AST::Node
      start = @pos
      advance
      AST::Assertion.new(AST::Span.new(start, @pos), AST::Assertion::Kind::End)
    end

    private def parse_escape : AST::Node
      start = @pos
      advance # skip '\\'
      if eof?
        raise ParseError.new("unexpected end of pattern after backslash")
      end

      case current_char
      when 'd', 'D', 's', 'S', 'w', 'W'
        parse_perl_class(start)
      when 'b', 'B'
        parse_word_boundary(start)
      when '<', '>'
        parse_angle_word_boundary(start)
      when 'A', 'z', 'Z'
        parse_anchor(start)
      when '0'..'7'
        return parse_octal_literal(start) if @octal
        raise ParseError.new("backreferences are not supported")
      when '8', '9'
        raise ParseError.new(@octal ? "unrecognized escape sequence" : "backreferences are not supported")
      when 'x', 'u', 'U'
        parse_hex_literal(start)
      when 'p', 'P'
        parse_unicode_class(start)
      else
        parse_escaped_literal(start)
      end
    end

    private def parse_perl_class(start : Int32) : AST::Node
      c = current_char
      advance

      kind = case c
             when 'd' then AST::ClassPerl::Kind::Digit
             when 'D' then AST::ClassPerl::Kind::DigitNeg
             when 's' then AST::ClassPerl::Kind::Space
             when 'S' then AST::ClassPerl::Kind::SpaceNeg
             when 'w' then AST::ClassPerl::Kind::Word
             when 'W' then AST::ClassPerl::Kind::WordNeg
             else
               raise "unreachable"
             end

      AST::ClassPerl.new(AST::Span.new(start, @pos), kind)
    end

    private def parse_unicode_class(start : Int32) : AST::Node
      # Parse \p or \P
      negated = current_char == 'P'
      advance # skip 'p' or 'P'
      bump_space

      if eof?
        raise ParseError.new("unexpected end of pattern in Unicode property escape")
      end

      if current_char == '{'
        # Parse \p{...} form
        advance # skip '{'
        bump_space

        prop_name = String.build do |io|
          while !eof?
            bump_space
            break if eof? || current_char == '}'
            io << current_char
            advance
          end
        end

        if eof?
          raise ParseError.new("unexpected end of pattern in Unicode property escape")
        end

        advance # skip '}'

        AST::ClassUnicode.new(AST::Span.new(start, @pos), negated, prop_name)
      else
        # Parse \pL form (single letter property)
        if eof?
          raise ParseError.new("unexpected end of pattern in Unicode property escape")
        end

        unless current_char.letter?
          raise ParseError.new("invalid Unicode property", nil, AST::Span.new(@pos, @pos + 1))
        end

        prop_char = current_char
        advance

        # Convert single character to property name
        prop_name = prop_char.to_s
        AST::ClassUnicode.new(AST::Span.new(start, @pos), negated, prop_name)
      end
    end

    private def parse_word_boundary(start : Int32) : AST::Node
      c = current_char
      advance

      if c == 'b' && !eof? && current_char == '{'
        if special_kind = maybe_parse_special_word_boundary
          return AST::Assertion.new(AST::Span.new(start, @pos), special_kind)
        end
      end

      kind = case c
             when 'b' then AST::Assertion::Kind::WordBoundary
             when 'B' then AST::Assertion::Kind::NonWordBoundary
             else
               raise "unreachable"
             end

      AST::Assertion.new(AST::Span.new(start, @pos), kind)
    end

    private def parse_angle_word_boundary(start : Int32) : AST::Node
      c = current_char
      advance

      kind = case c
             when '<' then AST::Assertion::Kind::WordBoundaryStartAngle
             when '>' then AST::Assertion::Kind::WordBoundaryEndAngle
             else
               raise "unreachable"
             end

      AST::Assertion.new(AST::Span.new(start, @pos), kind)
    end

    private def maybe_parse_special_word_boundary : AST::Assertion::Kind?
      original_pos = @pos
      advance # skip '{'
      bump_space

      return raise(ParseError.new("special word boundary or repetition unexpected end of pattern", nil, AST::Span.new(original_pos - 2, @pos))) if eof?

      unless special_word_boundary_char?(current_char)
        @pos = original_pos
        return nil
      end

      content_start = @pos
      while !eof? && special_word_boundary_char?(current_char)
        advance
        bump_space
      end

      raise ParseError.new("special word boundary unclosed", nil, AST::Span.new(original_pos, @pos)) if eof? || current_char != '}'

      content_end = @pos
      content = @input[content_start...@pos]
      advance # skip '}'

      case content
      when "start"      then AST::Assertion::Kind::WordBoundaryStart
      when "end"        then AST::Assertion::Kind::WordBoundaryEnd
      when "start-half" then AST::Assertion::Kind::WordBoundaryStartHalf
      when "end-half"   then AST::Assertion::Kind::WordBoundaryEndHalf
      else
        raise ParseError.new("unrecognized special word boundary assertion", nil, AST::Span.new(content_start, content_end))
      end
    end

    private def special_word_boundary_char?(char : Char) : Bool
      char.ascii_letter? || char == '-'
    end

    private def parse_anchor(start : Int32) : AST::Node
      c = current_char
      advance

      kind = case c
             when 'A' then AST::Assertion::Kind::StartText
             when 'z' then AST::Assertion::Kind::EndText
             when 'Z' then AST::Assertion::Kind::EndTextWithNewline
             else
               raise "unreachable"
             end

      AST::Assertion.new(AST::Span.new(start, @pos), kind)
    end

    private def parse_escaped_literal(start : Int32) : AST::Node
      if current_char == 'x'
        return parse_hex_escape(start, in_character_class: false)
      end

      c = current_char
      advance

      escaped_char = case c
                     when 'a' then '\a'
                     when 'f' then '\f'
                     when 'n' then '\n'
                     when 'r' then '\r'
                     when 't' then '\t'
                     when 'v' then '\v'
                     else
                       # Any character can be escaped
                       c
                     end

      AST::Literal.new(
        AST::Span.new(start, @pos),
        AST::Literal::Kind::Escaped,
        c: escaped_char
      )
    end

    private def parse_hex_literal(start : Int32) : AST::Node
      kind = current_char
      advance # skip x/u/U
      bump_space

      raise ParseError.new("unexpected end of pattern in hex escape") if eof?

      if current_char == '{'
        parse_hex_brace_literal(start, kind)
      else
        digits = case kind
                 when 'x' then 2
                 when 'u' then 4
                 else          8
                 end
        parse_fixed_hex_literal(start, digits, kind, kind == 'x' ? AST::Literal::Kind::Hex : AST::Literal::Kind::Unicode)
      end
    end

    private def parse_octal_literal(start : Int32) : AST::Node
      value = 0_u32
      digits = 0

      while !eof? && octal_digit?(current_char) && digits < 3
        value = value * 8 + current_char.to_s.to_i(8).to_u32
        advance
        digits += 1
      end

      AST::Literal.new(
        AST::Span.new(start, @pos),
        AST::Literal::Kind::Octal,
        c: scalar_value_to_char(value)
      )
    end

    private def parse_fixed_hex_literal(start : Int32, digits : Int32, prefix : Char, literal_kind : AST::Literal::Kind) : AST::Node
      value = 0_u32

      digits.times do
        bump_space
        raise ParseError.new("unexpected end of pattern in hex escape") if eof?
        raise ParseError.new("invalid hex digit in escape") unless ascii_hex_digit?(current_char)

        value = value * 16 + current_char.to_s.to_i(16).to_u32
        advance
      end

      build_hex_literal(start, literal_kind, value, form: AST::Literal::Form::Fixed, fixed_digits: digits, escape_prefix: prefix)
    end

    private def parse_hex_brace_literal(start : Int32, kind : Char) : AST::Node
      advance # skip '{'
      bump_space
      scratch = String.build do |io|
        while !eof? && current_char != '}'
          raise ParseError.new("invalid hex digit in escape") unless ascii_hex_digit?(current_char)
          io << current_char
          advance
          bump_space
        end
      end

      raise ParseError.new("unexpected end of pattern in hex escape") if eof?
      raise ParseError.new("empty hex escape") if scratch.empty?

      value = scratch.to_u32(16)
      advance # skip '}'

      build_hex_literal(start, kind == 'x' ? AST::Literal::Kind::Hex : AST::Literal::Kind::Unicode, value, form: AST::Literal::Form::Brace, escape_prefix: kind)
    rescue ArgumentError
      raise ParseError.new("invalid hex escape")
    end

    private def scalar_value_to_char(value : UInt32) : Char
      value.chr
    rescue ArgumentError
      raise ParseError.new("invalid hex escape")
    end

    private def parse_hex_escape(start : Int32, *, in_character_class : Bool) : AST::Node
      advance # skip 'x'
      bump_space

      if eof? || !ascii_hex_digit?(current_char)
        message = in_character_class ? "invalid escape sequence in character class" : "invalid escape sequence"
        raise ParseError.new(message)
      end
      first = current_char
      advance
      bump_space

      if eof? || !ascii_hex_digit?(current_char)
        message = in_character_class ? "invalid escape sequence in character class" : "invalid escape sequence"
        raise ParseError.new(message)
      end
      second = current_char
      advance

      value = first.to_s.to_i(16) * 16 + second.to_s.to_i(16)
      build_hex_literal(start, AST::Literal::Kind::Hex, value.to_u32, form: AST::Literal::Form::Fixed, fixed_digits: 2, escape_prefix: 'x')
    end

    private def build_hex_literal(start : Int32, kind : AST::Literal::Kind, value : UInt32, form : AST::Literal::Form? = nil, fixed_digits : Int32? = nil, escape_prefix : Char? = nil) : AST::Literal
      if kind.hex? && !@unicode
        AST::Literal.new(
          AST::Span.new(start, @pos),
          kind,
          bytes: Bytes[value.to_u8],
          form: form,
          fixed_digits: fixed_digits,
          escape_prefix: escape_prefix
        )
      else
        AST::Literal.new(
          AST::Span.new(start, @pos),
          kind,
          c: scalar_value_to_char(value),
          form: form,
          fixed_digits: fixed_digits,
          escape_prefix: escape_prefix
        )
      end
    end

    private def ascii_hex_digit?(char : Char) : Bool
      ('0' <= char <= '9') || ('a' <= char <= 'f') || ('A' <= char <= 'F')
    end

    private def octal_digit?(char : Char) : Bool
      '0' <= char <= '7'
    end

    private def parse_class_bracketed : AST::Node
      start = @pos
      advance # skip '['

      negated = false
      if current_char == '^'
        negated = true
        advance # skip '^'
      end

      bump_space

      prefix_items = [] of AST::ClassSetItem
      if !eof? && (current_char == ']' || current_char == '-')
        literal = parse_class_literal
        prefix_items << AST::ClassSetItem.new(literal.span, AST::ClassSetItem::Kind::Literal, literal)
      end

      class_set = parse_class_set(prefix_items)

      raise ParseError.new("unclosed character class") if eof? || current_char != ']'
      advance # skip ']'

      AST::ClassBracketed.new(AST::Span.new(start, @pos), negated, class_set)
    end

    private def parse_class_set(prefix_items : Array(AST::ClassSetItem) = [] of AST::ClassSetItem) : AST::ClassSet
      start = @pos
      lhs = parse_class_set_operand(prefix_items)

      while op_kind = parse_class_set_binary_op_kind
        rhs = parse_class_set_operand
        span = AST::Span.new(start, @pos)
        lhs = AST::ClassSet.new(
          span,
          AST::ClassSet::Kind::BinaryOp,
          binary_op: AST::ClassSetBinaryOp.new(span, op_kind, lhs, rhs)
        )
      end

      lhs
    end

    private def parse_class_set_operand(prefix_items : Array(AST::ClassSetItem) = [] of AST::ClassSetItem) : AST::ClassSet
      start = @pos
      items = prefix_items.dup

      while !eof? && current_char != ']'
        bump_space
        break if eof? || current_char == ']'
        break if parse_class_set_binary_op_kind?(peek: true)
        items << parse_class_set_range_or_item
      end

      case items.size
      when 0
        empty_span = AST::Span.new(start, @pos)
        AST::ClassSet.new(
          empty_span,
          AST::ClassSet::Kind::Item,
          item: AST::ClassSetItem.new(empty_span, AST::ClassSetItem::Kind::Empty)
        )
      when 1
        AST::ClassSet.new(AST::Span.new(start, @pos), AST::ClassSet::Kind::Item, item: items.first)
      else
        union_span = AST::Span.new(start, @pos)
        union = AST::ClassSetUnion.new(union_span, items)
        AST::ClassSet.new(
          union_span,
          AST::ClassSet::Kind::Item,
          item: AST::ClassSetItem.new(union_span, AST::ClassSetItem::Kind::Union, union)
        )
      end
    end

    private def parse_class_set_range_or_item : AST::ClassSetItem
      first = parse_class_set_primitive_item
      return first if eof? || current_char != '-' || peek_char == ']' || peek_char == '-'

      advance # skip '-'
      second = parse_class_set_primitive_item

      first_literal = first.item.as?(AST::Literal)
      second_literal = second.item.as?(AST::Literal)
      unless first.kind == AST::ClassSetItem::Kind::Literal && second.kind == AST::ClassSetItem::Kind::Literal && first_literal && second_literal
        raise ParseError.new("invalid character class range")
      end
      if first_char = first_literal.c
        if second_char = second_literal.c
          raise ParseError.new("invalid character class range") if first_char > second_char
        end
      end

      range = AST::ClassSetRange.new(
        AST::Span.new(first.span.start.offset, second.span.end.offset),
        first_literal,
        second_literal
      )
      AST::ClassSetItem.new(range.span, AST::ClassSetItem::Kind::Range, range)
    end

    private def parse_class_set_primitive_item : AST::ClassSetItem
      return AST::ClassSetItem.new(AST::Span.new(@pos, @pos), AST::ClassSetItem::Kind::Empty) if eof? || current_char == ']'

      node = if ascii_class = maybe_parse_ascii_class
               ascii_class
             else
               case current_char
               when '\\'
                 parse_class_escape
               when '['
                 parse_class_bracketed
               else
                 parse_class_literal
               end
             end

      AST::ClassSetItem.new(node.span, class_set_item_kind_for(node), node)
    end

    private def class_set_item_kind_for(node : AST::Node) : AST::ClassSetItem::Kind
      case node
      when AST::Literal
        AST::ClassSetItem::Kind::Literal
      when AST::ClassPerl
        AST::ClassSetItem::Kind::Perl
      when AST::ClassUnicode
        AST::ClassSetItem::Kind::Unicode
      when AST::ClassAscii
        AST::ClassSetItem::Kind::Ascii
      when AST::ClassSetRange
        AST::ClassSetItem::Kind::Range
      when AST::ClassBracketed
        AST::ClassSetItem::Kind::Bracketed
      when AST::ClassSetUnion
        AST::ClassSetItem::Kind::Union
      else
        AST::ClassSetItem::Kind::Empty
      end
    end

    private def parse_class_set_binary_op_kind?(peek : Bool = false) : AST::ClassSetBinaryOp::Kind?
      saved_pos = @pos
      kind = case current_char
             when '&'
               peek_char == '&' ? AST::ClassSetBinaryOp::Kind::Intersection : nil
             when '-'
               peek_char == '-' ? AST::ClassSetBinaryOp::Kind::Difference : nil
             when '~'
               peek_char == '~' ? AST::ClassSetBinaryOp::Kind::SymmetricDifference : nil
             else
               nil
             end

      if kind && !peek
        advance
        advance
      else
        @pos = saved_pos if peek && kind
      end
      kind
    end

    private def parse_class_set_binary_op_kind : AST::ClassSetBinaryOp::Kind?
      parse_class_set_binary_op_kind?(peek: false)
    end

    private def maybe_parse_ascii_class : AST::ClassAscii?
      return nil unless current_char == '['

      start_pos = @pos
      advance # skip '['
      if eof? || current_char != ':'
        @pos = start_pos
        return nil
      end

      advance # skip ':'

      negated = false
      if !eof? && current_char == '^'
        negated = true
        advance
      end

      name_start = @pos
      while !eof? && current_char != ':'
        advance
      end
      if eof?
        @pos = start_pos
        return nil
      end

      name = @input[name_start...@pos]
      unless current_char == ':'
        @pos = start_pos
        return nil
      end
      advance # skip ':'

      if eof? || current_char != ']'
        @pos = start_pos
        return nil
      end
      advance # skip ']'

      kind = AST::ClassAscii::Kind.from_name(name)
      unless kind
        @pos = start_pos
        return nil
      end

      AST::ClassAscii.new(AST::Span.new(start_pos, @pos), kind, negated)
    end

    private def parse_class_escape : AST::Node
      start = @pos
      advance # skip '\\'
      return AST::Empty.new(AST::Span.new(start, @pos)) if eof?

      case current_char
      when 'd', 'D', 's', 'S', 'w', 'W'
        parse_perl_class(start)
      when 'p', 'P'
        parse_unicode_class(start)
      else
        parse_class_escaped_literal(start)
      end
    end

    private def parse_class_escaped_literal(start : Int32) : AST::Node
      if current_char == 'x' || current_char == 'u' || current_char == 'U'
        return parse_hex_literal(start)
      end

      c = current_char
      advance

      escaped_char = case c
                     when 'a' then '\u{07}'
                     when 'f' then '\f'
                     when 'n' then '\n'
                     when 'r' then '\r'
                     when 't' then '\t'
                     when 'v' then '\v'
                     when '\\', '-', ']', '^', '['
                       c
                     else
                       raise ParseError.new("invalid escape sequence in character class")
                     end

      AST::Literal.new(
        AST::Span.new(start, @pos),
        AST::Literal::Kind::Escaped,
        c: escaped_char
      )
    end

    private def parse_class_literal : AST::Node
      start = @pos
      c = current_char
      advance

      AST::Literal.new(
        AST::Span.new(start, @pos),
        AST::Literal::Kind::Verbatim,
        c: c
      )
    end

    private def parse_group : AST::Node
      start = @pos
      advance # skip '('
      bump_space

      if current_char == '?'
        advance # skip '?'
        bump_space

        case current_char
        when 'P'
          if peek_char == '<'
            advance # skip 'P'
            advance # skip '<'
            parse_named_capture_group(start)
          else
            raise ParseError.new("unsupported group syntax")
          end
        when '<'
          case peek_char
          when '='
            raise ParseError.new("look-behind groups not supported")
          when '!'
            raise ParseError.new("look-behind groups not supported")
          else
            advance # skip '<'
            parse_named_capture_group(start)
          end
        when ':'
          # Non-capturing group: (?:...)
          advance # skip ':'
          child = parse_alternation
          raise ParseError.new("unclosed group") if eof? || current_char != ')'
          advance # skip ')'

          AST::Group.new(
            AST::Span.new(start, @pos),
            AST::Group::Kind::NonCapture,
            child
          )
        when 'i', 'm', 's', 'u', 'x', 'R', 'U', '-'
          # Parse flags for (?i...) or (?-i...)
          flags_start = @pos
          flags_items = parse_flags_items

          if current_char == ':'
            # Flag group with scope: (?i:...)
            # Save current flag state
            old_ignore_whitespace = @ignore_whitespace
            old_swap_greed = @swap_greed
            old_ignore_case = @ignore_case
            old_multi_line = @multi_line
            old_dot_matches_new_line = @dot_matches_new_line
            old_unicode = @unicode
            old_crlf = @crlf

            # Apply new flags
            apply_flags_from_items(flags_items)

            advance # skip ':'
            child = parse_alternation
            raise ParseError.new("unclosed group") if eof? || current_char != ')'
            advance # skip ')'

            # Restore flag state
            @ignore_whitespace = old_ignore_whitespace
            @swap_greed = old_swap_greed
            @ignore_case = old_ignore_case
            @multi_line = old_multi_line
            @dot_matches_new_line = old_dot_matches_new_line
            @unicode = old_unicode
            @crlf = old_crlf

            flags = AST::Flags.new(AST::Span.new(flags_start, @pos), flags_items)
            AST::Group.new(
              AST::Span.new(start, @pos),
              AST::Group::Kind::NonCapture,
              child,
              flags: flags
            )
          else
            # Global flags: (?i)
            raise ParseError.new("unclosed group") if eof? || current_char != ')'
            advance # skip ')'

            # Apply flags to parser state
            apply_flags_from_items(flags_items)

            # Create SetFlags node for global flags
            AST::SetFlags.new(AST::Span.new(start, @pos), flags_items)
          end
        when '='
          # Lookahead: (?=...) - not supported
          raise ParseError.new("look-ahead groups not supported")
        when '!'
          # Negative lookahead: (?!...) - not supported
          raise ParseError.new("look-ahead groups not supported")
        else
          if can_start_flag_set?(current_char)
            parse_unknown_flag_group(start)
          else
            raise ParseError.new("unsupported group syntax")
          end
        end
      else
        # Regular capturing group
        capture_index = next_capture_index
        child = parse_alternation
        raise ParseError.new("unclosed group") if eof? || current_char != ')'
        advance # skip ')'

        AST::Group.new(
          AST::Span.new(start, @pos),
          AST::Group::Kind::Capture,
          child,
          capture_index: capture_index
        )
      end
    end

    private def parse_named_capture_group(start : Int32) : AST::Node
      name_start = @pos
      first = true
      while !eof? && current_char != '>'
        raise ParseError.new("invalid capture name") unless valid_capture_name_char?(current_char, first)

        first = false
        advance
      end
      raise ParseError.new("unclosed capture group name", nil, AST::Span.new(@pos, @pos)) if eof?

      name = @input[name_start...@pos]
      raise ParseError.new("empty capture name", nil, AST::Span.new(@pos, @pos)) if name.empty?
      name_span = AST::Span.new(name_start, @pos)
      if original = @capture_names[name]?
        raise ParseError.new("duplicate capture name", :group_name_duplicate, name_span, original)
      end

      @capture_names[name] = name_span
      advance # skip '>'

      capture_index = next_capture_index
      child = parse_alternation
      raise ParseError.new("unclosed group") if eof? || current_char != ')'
      advance # skip ')'

      AST::Group.new(
        AST::Span.new(start, @pos),
        AST::Group::Kind::Capture,
        child,
        capture_index: capture_index,
        name: name
      )
    end

    private def next_capture_index : Int32
      raise ParseError.new("capture limit exceeded", nil, AST::Span.new(@pos, @pos)) if @capture_index == Int32::MAX

      @capture_index += 1
    end

    private def valid_capture_name_char?(char : Char, first : Bool) : Bool
      if first
        char == '_' || char.letter?
      else
        char == '_' || char == '.' || char == '[' || char == ']' || char.alphanumeric?
      end
    end

    private def can_start_flag_set?(char : Char) : Bool
      char != ':' && char != '=' && char != '!' && char != '<' && char != 'P'
    end

    private def parse_unknown_flag_group(start : Int32) : AST::Node
      flags_start = @pos
      flags_items = parse_flags_items
      if flags_items.empty?
        raise ParseError.new("repetition operator not preceded by expression", nil, AST::Span.new(start + 1, start + 1))
      end

      if current_char == ':'
        old_ignore_whitespace = @ignore_whitespace
        old_swap_greed = @swap_greed
        old_ignore_case = @ignore_case
        old_multi_line = @multi_line
        old_dot_matches_new_line = @dot_matches_new_line
        old_unicode = @unicode
        old_crlf = @crlf

        apply_flags_from_items(flags_items)

        advance
        child = parse_alternation
        raise ParseError.new("unclosed group") if eof? || current_char != ')'
        advance

        @ignore_whitespace = old_ignore_whitespace
        @swap_greed = old_swap_greed
        @ignore_case = old_ignore_case
        @multi_line = old_multi_line
        @dot_matches_new_line = old_dot_matches_new_line
        @unicode = old_unicode
        @crlf = old_crlf

        flags = AST::Flags.new(AST::Span.new(flags_start, @pos), flags_items)
        AST::Group.new(
          AST::Span.new(start, @pos),
          AST::Group::Kind::NonCapture,
          child,
          flags: flags
        )
      else
        raise ParseError.new("unclosed group") if eof? || current_char != ')'
        advance
        apply_flags_from_items(flags_items)
        AST::SetFlags.new(AST::Span.new(start, @pos), flags_items)
      end
    end

    private def parse_literal : AST::Node
      start = @pos
      bytes = [] of UInt8

      while !eof? && !"|().*+?{[\\^$".includes?(current_char)
        # In verbose mode, stop at whitespace or comment
        break if @ignore_whitespace && (current_char.ascii_whitespace? || current_char == '#')
        break if !bytes.empty? && repetition_operator_char?(peek_char)

        current_char.to_s.each_byte { |byte| bytes << byte }
        advance

        break if repetition_operator_char?(current_char)
      end

      if bytes.empty?
        AST::Empty.new(AST::Span.new(start, @pos))
      else
        AST::Literal.new(
          AST::Span.new(start, @pos),
          AST::Literal::Kind::Verbatim,
          bytes: Bytes.new(bytes.size) { |i| bytes[i] }
        )
      end
    end

    private def repetition_operator_char?(char : Char) : Bool
      case char
      when '*', '+', '?', '{'
        true
      else
        false
      end
    end

    private def parse_repetition(expr : AST::Node) : AST::Node
      return expr if eof?

      start = expr.span.start.offset
      case current_char
      when '*'
        advance
        greedy = parse_repetition_greediness
        op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::ZeroOrMore)
        AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
      when '+'
        advance
        greedy = parse_repetition_greediness
        op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::OneOrMore)
        AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
      when '?'
        advance
        greedy = parse_repetition_greediness
        op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::ZeroOrOne)
        AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
      when '{'
        parse_counted_repetition(expr, start)
      else
        expr
      end
    end

    private def parse_counted_repetition(expr : AST::Node, start : Int32) : AST::Node
      # Parse {n}, {n,}, {n,m}
      repetition_start = @pos
      advance # skip '{'
      bump_repetition_space

      if eof?
        raise ParseError.new("unclosed repetition count", nil, AST::Span.new(repetition_start, @pos))
      end

      min = if current_char == ','
              if @empty_min_range
                0_u32
              else
                raise ParseError.new("empty repetition count")
              end
            else
              parse_repetition_decimal
            end
      bump_repetition_space

      if eof?
        raise ParseError.new("unclosed repetition count", nil, AST::Span.new(repetition_start, @pos))
      end

      if current_char == '}'
        # {n} form
        advance # skip '}'
        greedy = parse_repetition_greediness
        op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::Range, min: min, max: min)
        AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
      elsif current_char == ','
        advance # skip ','
        bump_repetition_space

        if eof?
          raise ParseError.new("unclosed repetition count", nil, AST::Span.new(repetition_start, @pos))
        end

        if current_char == '}'
          # {n,} form
          advance # skip '}'
          greedy = parse_repetition_greediness
          op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::Range, min: min)
          AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
        else
          max = parse_repetition_decimal
          bump_repetition_space

          if eof? || current_char != '}'
            raise ParseError.new("unclosed repetition count", nil, AST::Span.new(repetition_start, @pos))
          end

          advance # skip '}'
          greedy = parse_repetition_greediness
          raise ParseError.new("invalid repetition range", nil, AST::Span.new(repetition_start, @pos)) if max < min
          op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::Range, min: min, max: max)
          AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
        end
      else
        raise ParseError.new("unclosed repetition count", nil, AST::Span.new(repetition_start, @pos))
      end
    end

    private def parse_repetition_greediness : Bool
      bump_space if @ignore_whitespace
      greedy = !@swap_greed
      if current_char == '?'
        advance
        greedy = !greedy
      end
      greedy
    end

    private def bump_repetition_space : Nil
      while !eof? && current_char.ascii_whitespace?
        advance
      end
    end

    private def parse_decimal : UInt32
      start = @pos
      value = 0_u64
      saw_digit = false

      while !eof? && current_char.ascii_number?
        saw_digit = true
        value = value * 10_u64 + (current_char.ord - '0'.ord).to_u64
        advance
        raise ParseError.new("invalid decimal", nil, AST::Span.new(start, @pos)) if value > UInt32::MAX
      end

      raise ParseError.new("empty decimal", nil, AST::Span.new(start, @pos)) unless saw_digit

      value.to_u32
    end

    private def parse_repetition_decimal : UInt32
      parse_decimal
    rescue ex : ParseError
      case ex.message
      when "empty decimal"
        raise ParseError.new("empty repetition count", nil, ex.span)
      when "invalid decimal"
        raise ParseError.new("invalid decimal", nil, ex.span)
      else
        raise ex
      end
    end

    # Helper methods
    private def eof? : Bool
      @pos >= @len
    end

    private def current_char : Char
      @input[@pos]
    rescue IndexError
      '\0'
    end

    private def peek_char : Char
      @input[@pos + 1]
    rescue IndexError
      '\0'
    end

    private def parse_flags_items : Array(AST::FlagsItem)
      items = [] of AST::FlagsItem
      seen_flags = {} of Char => AST::Span
      last_negation_span = nil.as(AST::Span?)

      while !eof? && current_char != ':' && current_char != ')'
        bump_space
        break if eof? || current_char == ':' || current_char == ')'

        if current_char == '-'
          if original = last_negation_span
            raise ParseError.new("repeated flag negation", :flag_repeated_negation, AST::Span.new(@pos, @pos + 1), original)
          end

          # Negation operator
          start_pos = @pos
          advance
          span = AST::Span.new(start_pos, @pos)
          items << AST::FlagsItem.new(
            span,
            AST::FlagsItem::Kind::Negation
          )
          last_negation_span = span
        else
          # Flag character
          start_pos = @pos
          flag_char = parse_flag_char
          if original = seen_flags[flag_char]?
            raise ParseError.new("duplicate flag", :flag_duplicate, AST::Span.new(start_pos, start_pos + 1), original)
          end
          advance
          span = AST::Span.new(start_pos, @pos)
          items << AST::FlagsItem.new(
            span,
            AST::FlagsItem::Kind::Flag,
            flag: flag_char
          )
          seen_flags[flag_char] = span
          last_negation_span = nil
        end
      end

      raise ParseError.new("unexpected end of flags") if eof?
      if span = last_negation_span
        raise ParseError.new("dangling flag negation", :flag_dangling_negation, span)
      end

      items
    end

    private def parse_flag_char : Char
      case current_char
      when 'i', 'm', 's', 'U', 'u', 'R', 'x'
        current_char
      else
        raise ParseError.new("unrecognized flag")
      end
    end

    private def apply_flags_from_items(items : Array(AST::FlagsItem)) : Nil
      # Track negation state
      negated = false

      items.each do |item|
        case item.kind
        when AST::FlagsItem::Kind::Negation
          negated = true
        when AST::FlagsItem::Kind::Flag
          case item.flag
          when 'x'
            @ignore_whitespace = !negated
          when 'U'
            @swap_greed = !negated
          when 'i'
            @ignore_case = !negated
          when 'm'
            @multi_line = !negated
          when 's'
            @dot_matches_new_line = !negated
          when 'u'
            @unicode = !negated
          when 'R'
            @crlf = !negated
          end
          negated = false
        end
      end
    end

    private def bump_space : Nil
      return unless @ignore_whitespace

      while !eof?
        if current_char.ascii_whitespace?
          advance
        elsif current_char == '#'
          comment_start = @pos
          advance
          comment_text = String.build do |io|
            while !eof?
              c = current_char
              advance
              break if c == '\n'
              io << c
            end
          end
          @comments << AST::Comment.new(AST::Span.new(comment_start, @pos), comment_text)
        else
          break
        end
      end
    end

    private def advance : Nil
      @pos += 1
    end

    private def check_nest_limit(node : AST::Node, depth : Int32 = 0) : Nil
      case node
      when AST::Empty, AST::SetFlags, AST::Literal, AST::Dot,
           AST::Assertion, AST::ClassUnicode, AST::ClassPerl
      when AST::ClassBracketed
        next_depth = increment_nest_depth(depth, node.span)
        check_nest_limit(node.kind, next_depth)
      when AST::Repetition
        next_depth = increment_nest_depth(depth, node.span)
        check_nest_limit(node.child, next_depth)
      when AST::Group
        next_depth = increment_nest_depth(depth, node.span)
        check_nest_limit(node.child, next_depth)
      when AST::Alternation
        next_depth = increment_nest_depth(depth, node.span)
        node.children.each { |child| check_nest_limit(child, next_depth) }
      when AST::Concat
        next_depth = increment_nest_depth(depth, node.span)
        node.children.each { |child| check_nest_limit(child, next_depth) }
      end
    end

    private def check_nest_limit(class_set : AST::ClassSet, depth : Int32) : Nil
      case class_set.kind
      when AST::ClassSet::Kind::Item
        if item = class_set.item
          check_nest_limit(item, depth)
        end
      when AST::ClassSet::Kind::BinaryOp
        if binary_op = class_set.binary_op
          next_depth = increment_nest_depth(depth, binary_op.span)
          check_nest_limit(binary_op.lhs, next_depth)
          check_nest_limit(binary_op.rhs, next_depth)
        end
      end
    end

    private def check_nest_limit(item : AST::ClassSetItem, depth : Int32) : Nil
      case item.kind
      when AST::ClassSetItem::Kind::Empty,
           AST::ClassSetItem::Kind::Literal,
           AST::ClassSetItem::Kind::Range,
           AST::ClassSetItem::Kind::Ascii,
           AST::ClassSetItem::Kind::Unicode,
           AST::ClassSetItem::Kind::Perl
      when AST::ClassSetItem::Kind::Bracketed
        next_depth = increment_nest_depth(depth, item.span)
        check_nest_limit(item.item.as(AST::ClassBracketed), next_depth)
      when AST::ClassSetItem::Kind::Union
        next_depth = increment_nest_depth(depth, item.span)
        item.item.as(AST::ClassSetUnion).items.each do |union_item|
          check_nest_limit(union_item, next_depth)
        end
      end
    end

    private def increment_nest_depth(depth : Int32, span : AST::Span) : Int32
      next_depth = depth + 1
      if limit = @nest_limit
        raise ParseError.new("nest limit exceeded", :nest_limit_exceeded, span) if next_depth > limit
      end
      next_depth
    end
  end

  # Main entry point for parsing regular expressions
  def self.parse(pattern : String, **options) : Hir::Hir
    Parser.new(**options).parse(pattern)
  end
end
