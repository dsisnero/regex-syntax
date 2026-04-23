require "set"
require "./regex/syntax/hir"
require "./regex/syntax/ast"
require "./regex/syntax/parser"
require "./regex/syntax/translate"

module Regex::Syntax
  VERSION = "0.1.0"

  # AST parser for regex source text.
  class AstParser
    @input : String
    @pos : Int32
    @len : Int32
    @unicode : Bool
    @ignore_whitespace : Bool
    @nest_limit : Int32?
    @octal : Bool
    @capture_index : Int32
    @capture_names : Set(String)
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

    def initialize(*, unicode : Bool = true, ignore_whitespace : Bool = false, ignore_case : Bool = false, multi_line : Bool = false, dot_matches_new_line : Bool = false, swap_greed : Bool = false, crlf : Bool = false, nest_limit : Int32? = nil, octal : Bool = false)
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
      @capture_index = 0
      @capture_names = Set(String).new
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
      node = parse_repetition(node)
      node
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
        raise ParseError.new("repetition operator not preceded by expression")
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

      if eof?
        raise ParseError.new("unexpected end of pattern in Unicode property escape")
      end

      if current_char == '{'
        # Parse \p{...} form
        advance # skip '{'

        # Parse property name
        prop_start = @pos
        while !eof? && current_char != '}'
          advance
        end

        if eof?
          raise ParseError.new("unclosed Unicode property escape")
        end

        prop_name = @input[prop_start...@pos]
        advance # skip '}'

        AST::ClassUnicode.new(AST::Span.new(start, @pos), negated, prop_name)
      else
        # Parse \pL form (single letter property)
        if eof?
          raise ParseError.new("unexpected end of pattern in Unicode property escape")
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

      return raise(ParseError.new("special word boundary or repetition unexpected end of pattern")) if eof?

      unless special_word_boundary_char?(current_char)
        @pos = original_pos
        return nil
      end

      content_start = @pos
      while !eof? && special_word_boundary_char?(current_char)
        advance
        bump_space
      end

      raise ParseError.new("special word boundary unclosed") if eof? || current_char != '}'

      content = @input[content_start...@pos]
      advance # skip '}'

      case content
      when "start"      then AST::Assertion::Kind::WordBoundaryStart
      when "end"        then AST::Assertion::Kind::WordBoundaryEnd
      when "start-half" then AST::Assertion::Kind::WordBoundaryStartHalf
      when "end-half"   then AST::Assertion::Kind::WordBoundaryEndHalf
      else
        raise ParseError.new("unrecognized special word boundary assertion")
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
        parse_fixed_hex_literal(start, digits, kind == 'x' ? AST::Literal::Kind::Hex : AST::Literal::Kind::Unicode)
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

    private def parse_fixed_hex_literal(start : Int32, digits : Int32, literal_kind : AST::Literal::Kind) : AST::Node
      value = 0_u32

      digits.times do
        bump_space
        raise ParseError.new("unexpected end of pattern in hex escape") if eof?
        raise ParseError.new("invalid hex digit in escape") unless ascii_hex_digit?(current_char)

        value = value * 16 + current_char.to_s.to_i(16).to_u32
        advance
      end

      char = scalar_value_to_char(value)
      AST::Literal.new(
        AST::Span.new(start, @pos),
        literal_kind,
        c: char
      )
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
      char = scalar_value_to_char(value)
      advance # skip '}'

      AST::Literal.new(
        AST::Span.new(start, @pos),
        kind == 'x' ? AST::Literal::Kind::Hex : AST::Literal::Kind::Unicode,
        c: char
      )
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

      if eof? || !ascii_hex_digit?(current_char)
        message = in_character_class ? "invalid escape sequence in character class" : "invalid escape sequence"
        raise ParseError.new(message)
      end
      first = current_char
      advance

      if eof? || !ascii_hex_digit?(current_char)
        message = in_character_class ? "invalid escape sequence in character class" : "invalid escape sequence"
        raise ParseError.new(message)
      end
      second = current_char
      advance

      value = first.to_s.to_i(16) * 16 + second.to_s.to_i(16)
      AST::Literal.new(
        AST::Span.new(start, @pos),
        AST::Literal::Kind::Hex,
        c: value.chr
      )
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

      class_set = parse_class_set

      raise ParseError.new("unclosed character class") if eof? || current_char != ']'
      advance # skip ']'

      AST::ClassBracketed.new(AST::Span.new(start, @pos), negated, class_set)
    end

    private def parse_class_set : AST::ClassSet
      start = @pos
      lhs = parse_class_set_operand

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

    private def parse_class_set_operand : AST::ClassSet
      start = @pos
      items = [] of AST::ClassSetItem

      while !eof? && current_char != ']'
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
      if current_char == 'x'
        return parse_hex_escape(start, in_character_class: true)
      end

      c = current_char
      advance

      escaped_char = case c
                     when 'n' then '\n'
                     when 'r' then '\r'
                     when 't' then '\t'
                     when '\\', '-', ']', '^'
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
          raise ParseError.new("unsupported group syntax")
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
      raise ParseError.new("unclosed group") if eof?

      name = @input[name_start...@pos]
      raise ParseError.new("empty capture name") if name.empty?
      raise ParseError.new("duplicate capture name") if @capture_names.includes?(name)

      @capture_names.add(name)
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
      raise ParseError.new("capture limit exceeded") if @capture_index == Int32::MAX

      @capture_index += 1
    end

    private def valid_capture_name_char?(char : Char, first : Bool) : Bool
      if first
        char == '_' || char.letter?
      else
        char == '_' || char == '.' || char == '[' || char == ']' || char.alphanumeric?
      end
    end

    private def parse_literal : AST::Node
      start = @pos
      bytes = [] of UInt8

      while !eof? && !"|().*+?{[\\".includes?(current_char)
        # In verbose mode, stop at whitespace or comment
        break if @ignore_whitespace && (current_char.ascii_whitespace? || current_char == '#')

        current_char.to_s.each_byte { |byte| bytes << byte }
        advance
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

    private def parse_repetition(expr : AST::Node) : AST::Node
      return expr if eof?

      start = expr.span.start.offset
      case current_char
      when '*'
        advance
        # Check for ? suffix (explicit non-greedy)
        greedy = !@swap_greed
        if current_char == '?'
          advance
          greedy = false
        end
        op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::ZeroOrMore)
        AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
      when '+'
        advance
        # Check for ? suffix (explicit non-greedy)
        greedy = !@swap_greed
        if current_char == '?'
          advance
          greedy = false
        end
        op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::OneOrMore)
        AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
      when '?'
        advance
        # Check for ? suffix (explicit non-greedy)
        greedy = !@swap_greed
        if current_char == '?'
          advance
          greedy = false
        end
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
      advance # skip '{'

      if eof?
        raise ParseError.new("unclosed repetition count")
      end

      # Parse min count
      min_start = @pos
      while !eof? && current_char.ascii_number?
        advance
      end

      if @pos == min_start
        raise ParseError.new("empty repetition count")
      end

      min_str = @input[min_start...@pos]
      min = min_str.to_i

      if eof?
        raise ParseError.new("unclosed repetition count")
      end

      if current_char == '}'
        # {n} form
        advance # skip '}'
        # Check for ? suffix (explicit non-greedy)
        greedy = !@swap_greed
        if current_char == '?'
          advance
          greedy = false
        end
        op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::Range, min: min, max: min)
        AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
      elsif current_char == ','
        advance # skip ','

        if eof?
          raise ParseError.new("unclosed repetition count")
        end

        if current_char == '}'
          # {n,} form
          advance # skip '}'
          # Check for ? suffix (explicit non-greedy)
          greedy = !@swap_greed
          if current_char == '?'
            advance
            greedy = false
          end
          op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::Range, min: min)
          AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
        else
          # Parse max count
          max_start = @pos
          while !eof? && current_char.ascii_number?
            advance
          end

          if @pos == max_start
            raise ParseError.new("empty repetition count")
          end

          max_str = @input[max_start...@pos]
          max = max_str.to_i

          if eof? || current_char != '}'
            raise ParseError.new("unclosed repetition count")
          end

          advance # skip '}'
          # Check for ? suffix (explicit non-greedy)
          greedy = !@swap_greed
          if current_char == '?'
            advance
            greedy = false
          end
          raise ParseError.new("invalid repetition range") if max < min
          op = AST::RepetitionOp.new(AST::RepetitionOp::Kind::Range, min: min, max: max)
          AST::Repetition.new(AST::Span.new(start, @pos), op, greedy, expr)
        end
      else
        raise ParseError.new("unclosed repetition count")
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
            raise ParseError.new("repeated flag negation at #{original}")
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
            raise ParseError.new("duplicate flag at #{original}")
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
        raise ParseError.new("dangling flag negation at #{span}")
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
        raise ParseError.new("nest limit exceeded at #{span}") if next_depth > limit
      end
      next_depth
    end
  end

  # Main entry point for parsing regular expressions
  def self.parse(pattern : String, **options) : Hir::Hir
    Parser.new(**options).parse(pattern)
  end

  # Error types
  class Error < Exception
  end

  class ParseError < Error
  end
end
