require "./unicode"

module Regex::Syntax
  # Parser for converting regex strings to HIR

  class Parser
    @input : String
    @pos : Int32
    @len : Int32
    @unicode : Bool
    @ignore_case : Bool
    @multi_line : Bool
    @dot_matches_new_line : Bool
    @swap_greed : Bool
    @ignore_whitespace : Bool
    @crlf : Bool
    @nest_limit : Int32?
    @nest_depth : Int32
    @capture_index : Int32

    def initialize(*, unicode : Bool = true, ignore_case : Bool = false, multi_line : Bool = false, dot_matches_new_line : Bool = false, swap_greed : Bool = false, ignore_whitespace : Bool = false, crlf : Bool = false, nest_limit : Int32? = nil)
      @unicode = unicode
      @ignore_case = ignore_case
      @multi_line = multi_line
      @dot_matches_new_line = dot_matches_new_line
      @swap_greed = swap_greed
      @ignore_whitespace = ignore_whitespace
      @crlf = crlf
      @nest_limit = nest_limit
      @input = ""
      @pos = 0
      @len = 0
      @nest_depth = 0
      @capture_index = 0
    end

    def parse(pattern : String) : Hir::Hir
      @input = pattern
      @pos = 0
      @len = pattern.size
      @nest_depth = 0
      @capture_index = 0

      # Check nest limit
      if nest_limit = @nest_limit
        raise ParseError.new("nest limit exceeded") if @nest_depth > nest_limit
      end

      hir = parse_alternation
      Hir::Hir.new(hir)
    end

    private def parse_alternation : Hir::Node
      # Parse concatenation sequences separated by |
      terms = [] of Hir::Node
      terms << parse_concatenation

      while current_char == '|'
        advance # skip '|'
        terms << parse_concatenation
      end

      if terms.size == 1
        terms.first
      else
        Hir::Alternation.new(terms)
      end
    end

    private def parse_concatenation : Hir::Node
      # Parse sequence of atoms
      atoms = [] of Hir::Node
      skip_ignored_whitespace_and_comments

      while !eof? && current_char != '|' && current_char != ')'
        skip_ignored_whitespace_and_comments
        break if eof? || current_char == '|' || current_char == ')'
        atom = parse_atom
        # Skip empty nodes
        unless atom.is_a?(Hir::Empty)
          atoms << atom
        end
        skip_ignored_whitespace_and_comments
      end

      case atoms.size
      when 0
        Hir::Empty.new
      when 1
        atoms.first
      else
        Hir::Concat.new(atoms)
      end
    end

    private def parse_atom : Hir::Node
      node = parse_primary
      node = apply_case_folding(node) if @ignore_case

      # Check for quantifiers
      case current_char
      when '*'
        advance
        greedy = default_greedy
        if current_char == '?'
          greedy = !default_greedy
          advance
        elsif current_char == '+'
          # Possessive quantifier (no backtracking) - treat as greedy in DFA
          advance
        end
        node = Hir::Repetition.new(node, 0, nil, greedy: greedy)
      when '+'
        advance
        greedy = default_greedy
        if current_char == '?'
          greedy = !default_greedy
          advance
        elsif current_char == '+'
          # Possessive quantifier (no backtracking) - treat as greedy in DFA
          advance
        end
        node = Hir::Repetition.new(node, 1, nil, greedy: greedy)
      when '?'
        advance
        greedy = default_greedy
        possessive = false
        if current_char == '?'
          greedy = !default_greedy
          advance
        elsif current_char == '+'
          # Possessive quantifier (no backtracking) - treat as greedy in DFA
          possessive = true
          advance
        end
        if possessive
          # Treat ?+ as equivalent to * for compatibility
          node = Hir::Repetition.new(node, 0, nil, greedy: true)
        else
          node = Hir::Repetition.new(node, 0, 1, greedy: greedy)
        end
      when '{'
        advance
        node = parse_repetition_range(node)
      end

      node
    end

    private def parse_repetition_range(sub : Hir::Node) : Hir::Node
      # Parse {n}, {n,}, {n,m}
      # Expect current position after '{'
      # Parse min digits
      min_str = ""
      while current_char.ascii_number?
        min_str += current_char
        advance
      end
      raise ParseError.new("invalid repetition: missing min value") if min_str.empty?
      min = min_str.to_i

      max = nil
      if current_char == '}'
        # {n} exact repetition
        max = min
        advance
      elsif current_char == ','
        advance
        if current_char == '}'
          # {n,} at least n
          # max stays nil
          advance
        else
          # {n,m}
          max_str = ""
          while current_char.ascii_number?
            max_str += current_char
            advance
          end
          raise ParseError.new("invalid repetition: missing max value") if max_str.empty?
          max = max_str.to_i
          raise ParseError.new("invalid repetition: max < min") if max < min
          if current_char != '}'
            raise ParseError.new("invalid repetition: expected '}'")
          end
          advance
        end
      else
        raise ParseError.new("invalid repetition: expected ',' or '}'")
      end

      # Check for non-greedy modifier '?'
      greedy = default_greedy
      if current_char == '?'
        greedy = !default_greedy
        advance
      elsif current_char == '+'
        # Possessive quantifier (no backtracking) - treat as greedy in DFA
        advance
      end

      Hir::Repetition.new(sub, min, max, greedy: greedy)
    end

    private def parse_primary : Hir::Node
      case current_char
      when '^'
        advance
        Hir::Look.new(@multi_line ? Hir::Look::Kind::Start : Hir::Look::Kind::StartText)
      when '$'
        advance
        Hir::Look.new(@multi_line ? Hir::Look::Kind::End : Hir::Look::Kind::EndTextWithNewline)
      when '.'
        advance
        parse_dot
      when '['
        advance
        parse_character_class
      when '('
        advance
        parse_group
      when '\\'
        advance
        parse_escape
      when ')'
        # End of group - caller will handle
        Hir::Empty.new
      else
        parse_literal
      end
    end

    private def parse_dot : Hir::Node
      dot_kind = if @dot_matches_new_line
                   @unicode ? Hir::Dot::AnyChar : Hir::Dot::AnyByte
                 elsif @crlf
                   @unicode ? Hir::Dot::AnyCharExceptCRLF : Hir::Dot::AnyByteExceptCRLF
                 else
                   @unicode ? Hir::Dot::AnyCharExceptLF : Hir::Dot::AnyByteExceptLF
                 end
      Hir.dot(dot_kind).node
    end

    private def parse_character_class : Hir::Node
      # Check for negation
      negated = false
      if current_char == '^'
        negated = true
        advance
      end

      if @unicode
        ranges = [] of Range(UInt32, UInt32)

        while !eof? && current_char != ']'
          start_codepoint = parse_character_class_codepoint

          if current_char == '-' && peek_next_char != ']'
            # Range
            advance # skip '-'
            end_codepoint = parse_character_class_codepoint

            # Validate range
            if start_codepoint > end_codepoint
              raise ParseError.new("invalid character class range")
            end

            ranges << (start_codepoint..end_codepoint)
          else
            # Single character
            ranges << (start_codepoint..start_codepoint)
          end
        end

        if current_char != ']'
          raise ParseError.new("unclosed character class")
        end
        advance # skip ']'

        Hir::UnicodeClass.new(negated, ranges)
      else
        ranges = [] of Range(UInt8, UInt8)

        while !eof? && current_char != ']'
          start_byte = parse_character_class_char

          if current_char == '-' && peek_next_char != ']'
            # Range
            advance # skip '-'
            end_byte = parse_character_class_char

            # Validate range
            if start_byte > end_byte
              raise ParseError.new("invalid character class range")
            end

            ranges << (start_byte..end_byte)
          else
            # Single character
            ranges << (start_byte..start_byte)
          end
        end

        if current_char != ']'
          raise ParseError.new("unclosed character class")
        end
        advance # skip ']'

        Hir::CharClass.new(negated, ranges)
      end
    end

    private def parse_character_class_char : UInt8
      if current_char == '\\'
        advance
        parse_escape_byte
      else
        byte = current_char.ord.to_u8
        advance
        byte
      end
    end

    private def parse_character_class_codepoint : UInt32
      if current_char == '\\'
        advance
        parse_escape_char.ord.to_u32
      else
        codepoint = current_char.ord.to_u32
        advance
        codepoint
      end
    end

    private def parse_group : Hir::Node
      # Check for special group types
      if current_char == '?'
        advance
        return parse_non_capturing_group
      end

      # Regular capturing group
      @nest_depth += 1
      begin
        child = parse_alternation
      ensure
        @nest_depth -= 1
      end

      if current_char != ')'
        raise ParseError.new("unclosed group")
      end
      advance # skip ')'

      @capture_index += 1
      Hir::Capture.new(child, @capture_index)
    end

    private def parse_non_capturing_group : Hir::Node
      # Parse flags after '?'
      flags = parse_flags

      # Check for group type
      case current_char
      when ':'
        # (?:...) non-capturing group
        advance # skip ':'
        child = with_inline_flags(flags) do
          @nest_depth += 1
          begin
            parse_alternation
          ensure
            @nest_depth -= 1
          end
        end
        raise ParseError.new("unclosed group") if current_char != ')'
        advance # skip ')'
        child
      when '='
        raise ParseError.new("look-ahead groups are not supported")
      when '!'
        raise ParseError.new("negative look-ahead groups are not supported")
      when '<'
        raise ParseError.new("look-behind groups are not supported")
      when '>'
        raise ParseError.new("atomic groups are not supported")
      else
        # Could be inline flags: (?i) or (?-i) or (?i:...)
        if current_char == ':'
          advance # skip ':'
          child = with_inline_flags(flags) do
            @nest_depth += 1
            begin
              parse_alternation
            ensure
              @nest_depth -= 1
            end
          end
          raise ParseError.new("unclosed group") if current_char != ')'
          advance # skip ')'
          child
        else
          raise ParseError.new("unclosed group") if current_char != ')'
          advance # skip ')'
          apply_parser_flags(flags)
          Hir::Empty.new
        end
      end
    end

    private def parse_flags : Hash(String, Bool)
      flags = {} of String => Bool

      # Parse flag string like "i", "is", "i-s", etc.
      while !eof? && current_char != ')' && current_char != ':' &&
            current_char != '=' && current_char != '!' &&
            current_char != '<' && current_char != '>'
        if current_char == '-'
          advance # skip '-'
          if eof? || current_char == ')' || current_char == ':'
            raise ParseError.new("invalid flag syntax: missing flag after '-'")
          end
          flag = current_char.to_s
          advance
          validate_flag!(flag)
          flags[flag] = false
        else
          flag = current_char.to_s
          advance
          validate_flag!(flag)
          flags[flag] = true
        end
      end

      flags
    end

    private def parse_escape : Hir::Node
      if eof?
        raise ParseError.new("trailing backslash at end of pattern")
      end

      case current_char
      when 'd', 'D', 'w', 'W', 's', 'S'
        # Perl character classes
        parse_perl_character_class
      when 'p', 'P'
        # Unicode property classes
        parse_unicode_property_class
      when 'b', 'B', 'A', 'z', 'Z'
        # Assertions
        parse_assertion
      when 'x', 'u', '0'..'7'
        parse_escape_char_literal
      else
        # Simple escape sequence like \n, \t, \r, etc.
        parse_escape_char_literal
      end
    end

    private def parse_perl_character_class : Hir::Node
      char = current_char
      advance

      case char
      when 'd'
        # Digit class
        ranges = [('0'.ord.to_u8)..('9'.ord.to_u8)]
        Hir::CharClass.new(false, ranges)
      when 'w'
        # Word character class (ASCII only for now)
        ranges = [
          ('a'.ord.to_u8)..('z'.ord.to_u8),
          ('A'.ord.to_u8)..('Z'.ord.to_u8),
          ('0'.ord.to_u8)..('9'.ord.to_u8),
          '_'.ord.to_u8..'_'.ord.to_u8,
        ]
        Hir::CharClass.new(false, ranges)
      when 's'
        # Whitespace class (ASCII only for now)
        ranges = [
          ' '.ord.to_u8..' '.ord.to_u8,
          '\t'.ord.to_u8..'\t'.ord.to_u8,
          '\n'.ord.to_u8..'\n'.ord.to_u8,
          '\r'.ord.to_u8..'\r'.ord.to_u8,
          '\f'.ord.to_u8..'\f'.ord.to_u8,
          '\v'.ord.to_u8..'\v'.ord.to_u8,
        ]
        Hir::CharClass.new(false, ranges)
      when 'D', 'W', 'S'
        # Negated versions: negate against the class ranges.
        base = case char
               when 'D'
                 [('0'.ord.to_u8)..('9'.ord.to_u8)]
               when 'W'
                 [
                   ('a'.ord.to_u8)..('z'.ord.to_u8),
                   ('A'.ord.to_u8)..('Z'.ord.to_u8),
                   ('0'.ord.to_u8)..('9'.ord.to_u8),
                   '_'.ord.to_u8..'_'.ord.to_u8,
                 ]
               else # 'S'
                 [
                   ' '.ord.to_u8..' '.ord.to_u8,
                   '\t'.ord.to_u8..'\t'.ord.to_u8,
                   '\n'.ord.to_u8..'\n'.ord.to_u8,
                   '\r'.ord.to_u8..'\r'.ord.to_u8,
                   '\f'.ord.to_u8..'\f'.ord.to_u8,
                   '\v'.ord.to_u8..'\v'.ord.to_u8,
                 ]
               end
        Hir::CharClass.new(true, base)
      else
        Hir::CharClass.new
      end
    end

    private def parse_unicode_property_class : Hir::Node
      # Parse \p{...} or \P{...}
      negated = current_char == 'P'
      advance # skip 'p' or 'P'

      # Expect '{'
      raise ParseError.new("invalid Unicode property class: expected '{'") unless current_char == '{'
      advance # skip '{'

      # Parse property name
      property = ""
      while !eof? && current_char != '}'
        property += current_char
        advance
      end

      # Expect '}'
      raise ParseError.new("invalid Unicode property class: expected '}'") unless current_char == '}'
      advance # skip '}'

      # Look up Unicode property and convert to character ranges
      Unicode.property_class(property, negated)
    end

    private def parse_assertion : Hir::Node
      char = current_char
      advance

      case char
      when 'b'
        Hir::Look.new(Hir::Look::Kind::WordBoundary)
      when 'B'
        Hir::Look.new(Hir::Look::Kind::NonWordBoundary)
      when 'A'
        Hir::Look.new(Hir::Look::Kind::StartText)
      when 'z'
        Hir::Look.new(Hir::Look::Kind::EndText)
      when 'Z'
        Hir::Look.new(Hir::Look::Kind::EndTextWithNewline)
      else
        # Should not happen
        Hir::Empty.new
      end
    end

    private def parse_escape_char : Char
      case current_char
      when 'n'
        advance
        '\n'
      when 't'
        advance
        '\t'
      when 'r'
        advance
        '\r'
      when 'f'
        advance
        '\f'
      when 'v'
        advance
        '\v'
      when 'a'
        advance
        '\a'
      when 'e'
        advance
        '\e'
      when '0'..'7'
        # Parse octal escape (1-3 octal digits)
        value = 0
        digits = 0
        while digits < 3 && current_char.in?('0'..'7')
          value = value * 8 + (current_char - '0')
          advance
          digits += 1
        end
        # If we consumed no digits, should not happen because pattern matched '0'..'7'
        value.chr
      when 'x'
        advance # skip 'x'
        if current_char == '{'
          # \x{...} variable-length hex (1-6 digits)
          advance # skip '{'
          value = 0
          digits = 0
          while digits < 6 && (hex = current_char.to_i?(16))
            value = value * 16 + hex
            advance
            digits += 1
          end
          raise ParseError.new("invalid hex escape: expected '}'") if current_char != '}'
          advance # skip '}'
          # Validate value range (0..0x10FFFF)
          if value > 0x10FFFF
            raise ParseError.new("hex escape value out of range")
          end
          value.chr
        else
          # \xHH exactly two hex digits
          raise ParseError.new("invalid hex escape: expected hex digit") unless current_char.to_i?(16)
          value = current_char.to_i(16)
          advance
          raise ParseError.new("invalid hex escape: expected second hex digit") unless current_char.to_i?(16)
          value = value * 16 + current_char.to_i(16)
          advance
          value.chr
        end
      when 'u'
        advance # skip 'u'
        if current_char == '{'
          advance # skip '{'
          value = 0
          digits = 0
          while digits < 6 && (hex = current_char.to_i?(16))
            value = value * 16 + hex
            advance
            digits += 1
          end
          raise ParseError.new("invalid Unicode escape: expected '}'") if current_char != '}'
          advance # skip '}'
          # Validate value range (0..0x10FFFF) and not surrogate
          if value > 0x10FFFF
            raise ParseError.new("Unicode escape value out of range")
          end
          # Reject surrogate code points (0xD800..0xDFFF)
          if 0xD800 <= value <= 0xDFFF
            raise ParseError.new("Unicode escape cannot be surrogate")
          end
          value.chr
        elsif current_char.to_i?(16)
          value = 0
          digits = 0
          while digits < 4 && (hex = current_char.to_i?(16))
            value = value * 16 + hex
            advance
            digits += 1
          end
          raise ParseError.new("invalid Unicode escape: expected 4 hex digits") if digits < 4
          value.chr
        else
          'u'
        end
      else
        # Escaped character like \\, \., \*, etc.
        char = current_char
        advance
        char
      end
    end

    private def parse_escape_byte : UInt8
      case current_char
      when 'n'
        advance
        '\n'.ord.to_u8
      when 't'
        advance
        '\t'.ord.to_u8
      when 'r'
        advance
        '\r'.ord.to_u8
      when 'f'
        advance
        '\f'.ord.to_u8
      when 'v'
        advance
        '\v'.ord.to_u8
      when 'a'
        advance
        '\a'.ord.to_u8
      when 'e'
        advance
        '\e'.ord.to_u8
      when '0'..'7'
        # Parse octal escape (1-3 octal digits)
        value = 0
        digits = 0
        while digits < 3 && current_char.in?('0'..'7')
          value = value * 8 + (current_char - '0')
          advance
          digits += 1
        end
        # Validate byte range
        if value > 255
          raise ParseError.new("octal escape value out of byte range: #{value}")
        end
        value.to_u8
      when 'x'
        advance # skip 'x'
        if current_char == '{'
          # \x{...} variable-length hex (1-6 digits)
          advance # skip '{'
          value = 0
          digits = 0
          while digits < 6 && (hex = current_char.to_i?(16))
            value = value * 16 + hex
            advance
            digits += 1
          end
          raise ParseError.new("invalid hex escape: expected '}'") if current_char != '}'
          advance # skip '}'
          # Validate value range (0..255 for byte mode)
          if value > 255
            raise ParseError.new("hex escape value out of byte range: #{value}")
          end
          value.to_u8
        else
          # \xHH exactly two hex digits
          raise ParseError.new("invalid hex escape: expected hex digit") unless current_char.to_i?(16)
          value = current_char.to_i(16)
          advance
          raise ParseError.new("invalid hex escape: expected second hex digit") unless current_char.to_i?(16)
          value = value * 16 + current_char.to_i(16)
          advance
          if value > 255
            raise ParseError.new("hex escape value out of byte range: #{value}")
          end
          value.to_u8
        end
      else
        # Escaped character like \\, \., \*, etc.
        char = current_char
        advance
        char.ord.to_u8
      end
    end

    private def parse_escape_char_literal : Hir::Node
      char = parse_escape_char
      Hir::Literal.new(char.to_s.to_slice)
    end

    private def parse_literal : Hir::Node
      bytes = [] of UInt8

      while !eof? && !"|().*+?{[\\".includes?(current_char)
        break if @ignore_whitespace && (current_char.ascii_whitespace? || current_char == '#')
        current_char.to_s.each_byte { |byte| bytes << byte }
        advance
      end

      if bytes.empty?
        Hir::Empty.new
      else
        Hir::Literal.new(Bytes.new(bytes.size) { |i| bytes[i] })
      end
    end

    private def validate_flag!(flag : String) : Nil
      # Keep permissive support for commonly seen flags. Only i is currently semantic.
      return if {"i", "m", "s", "R", "U", "u", "x"}.includes?(flag)
      raise ParseError.new("unsupported inline flag: #{flag}")
    end

    private def apply_parser_flags(flags : Hash(String, Bool)) : Nil
      @ignore_case = flags["i"] if flags.has_key?("i")
      @unicode = flags["u"] if flags.has_key?("u")
      @multi_line = flags["m"] if flags.has_key?("m")
      @dot_matches_new_line = flags["s"] if flags.has_key?("s")
      @swap_greed = flags["U"] if flags.has_key?("U")
      @ignore_whitespace = flags["x"] if flags.has_key?("x")
      @crlf = flags["R"] if flags.has_key?("R")
    end

    private def with_inline_flags(flags : Hash(String, Bool), & : -> Hir::Node) : Hir::Node
      old_ignore_case = @ignore_case
      old_unicode = @unicode
      old_multi_line = @multi_line
      old_dot_matches_new_line = @dot_matches_new_line
      old_swap_greed = @swap_greed
      old_ignore_whitespace = @ignore_whitespace
      old_crlf = @crlf
      apply_parser_flags(flags)
      begin
        yield
      ensure
        @ignore_case = old_ignore_case
        @unicode = old_unicode
        @multi_line = old_multi_line
        @dot_matches_new_line = old_dot_matches_new_line
        @swap_greed = old_swap_greed
        @ignore_whitespace = old_ignore_whitespace
        @crlf = old_crlf
      end
    end

    private def default_greedy : Bool
      !@swap_greed
    end

    private def skip_ignored_whitespace_and_comments : Nil
      return unless @ignore_whitespace
      while !eof?
        if current_char.ascii_whitespace?
          advance
        elsif current_char == '#'
          advance
          while !eof? && current_char != '\n'
            advance
          end
        else
          break
        end
      end
    end

    private def apply_case_folding(node : Hir::Node) : Hir::Node
      hir = Hir::Hir.new(node)
      folded = if @unicode
                 Hir.case_fold_unicode(hir)
               else
                 Hir.case_fold_ascii(hir)
               end
      folded.node
    end

    # Helper methods

    private def eof? : Bool
      @pos >= @len
    end

    private def current_char : Char
      if eof?
        '\0'
      else
        @input[@pos]
      end
    end

    private def peek_next_char : Char
      if @pos + 1 >= @len
        '\0'
      else
        @input[@pos + 1]
      end
    end

    private def advance
      @pos += 1 unless eof?
    end
  end
end
