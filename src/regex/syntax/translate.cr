require "./hir"
require "./unicode"

module Regex::Syntax
  class TranslatorBuilder
    def initialize
      @utf8 = true
      @line_terminator = '\n'.ord.to_u8
      @ignore_case = false
      @multi_line = false
      @dot_matches_new_line = false
      @swap_greed = false
      @unicode = true
      @crlf = false
    end

    def build : Translator
      Translator.new(
        unicode: @unicode,
        utf8: @utf8,
        ignore_case: @ignore_case,
        multi_line: @multi_line,
        dot_matches_new_line: @dot_matches_new_line,
        swap_greed: @swap_greed,
        crlf: @crlf,
        line_terminator: @line_terminator
      )
    end

    def utf8(yes : Bool) : self
      @utf8 = yes
      self
    end

    def line_terminator(byte : UInt8) : self
      @line_terminator = byte
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

  # Translates AST nodes to HIR nodes using the same staged pipeline as Rust:
  # AST parsing first, semantic lowering second.
  class Translator
    @unicode : Bool
    @utf8 : Bool
    @ignore_case : Bool
    @multi_line : Bool
    @dot_matches_new_line : Bool
    @swap_greed : Bool
    @ignore_whitespace : Bool
    @crlf : Bool
    @nest_limit : Int32?
    @line_terminator : UInt8

    def initialize(*,
                   unicode : Bool = true,
                   utf8 : Bool = true,
                   ignore_case : Bool = false,
                   multi_line : Bool = false,
                   dot_matches_new_line : Bool = false,
                   swap_greed : Bool = false,
                   ignore_whitespace : Bool = false,
                   crlf : Bool = false,
                   nest_limit : Int32? = nil,
                   line_terminator : UInt8 = '\n'.ord.to_u8)
      @unicode = unicode
      @utf8 = utf8
      @ignore_case = ignore_case
      @multi_line = multi_line
      @dot_matches_new_line = dot_matches_new_line
      @swap_greed = swap_greed
      @ignore_whitespace = ignore_whitespace
      @crlf = crlf
      @nest_limit = nest_limit
      @line_terminator = line_terminator
    end

    # Translate an AST node to HIR node
    def translate(ast : AST::Node) : Hir::Node
      case ast
      when AST::Literal
        translate_literal(ast)
      when AST::ClassPerl
        translate_class_perl(ast)
      when AST::ClassUnicode
        translate_class_unicode(ast)
      when AST::ClassBracketed
        translate_class_bracketed(ast)
      when AST::Dot
        translate_dot(ast)
      when AST::Repetition
        translate_repetition(ast)
      when AST::Group
        translate_group(ast)
      when AST::Alternation
        translate_alternation(ast)
      when AST::Concat
        translate_concat(ast)
      when AST::Assertion
        translate_assertion(ast)
      when AST::SetFlags
        translate_set_flags(ast)
      when AST::Empty
        Hir::Empty.new
      else
        Hir::Empty.new
      end
    end

    private def translate_literal(literal : AST::Literal) : Hir::Node
      if bytes = literal.bytes
        ensure_valid_utf8_bytes!(bytes, literal.span) if @utf8 && !@unicode
        if @ignore_case
          @unicode ? Hir.case_fold_unicode(Hir::Hir.new(Hir::Literal.new(bytes))).node : translate_case_folded_bytes(bytes)
        else
          Hir::Literal.new(bytes)
        end
      elsif c = literal.c
        bytes = char_to_utf8_bytes(c)
        if @ignore_case
          @unicode ? Hir.case_fold_unicode(Hir::Hir.new(Hir::Literal.new(bytes))).node : translate_case_folded_char(c)
        else
          Hir::Literal.new(bytes)
        end
      else
        Hir::Empty.new
      end
    end

    private def translate_class_perl(class_perl : AST::ClassPerl) : Hir::Node
      if @unicode
        translate_class_perl_unicode(class_perl)
      else
        translate_class_perl_ascii(class_perl)
      end
    end

    private def translate_class_perl_unicode(class_perl : AST::ClassPerl) : Hir::Node
      case class_perl.kind
      when AST::ClassPerl::Kind::Digit
        Unicode.property_class("Decimal_Number", false)
      when AST::ClassPerl::Kind::Space
        Unicode.property_class("White_Space", false)
      when AST::ClassPerl::Kind::Word
        # Use Unicode word property (Perl word)
        Unicode.property_class("word", false)
      when AST::ClassPerl::Kind::DigitNeg
        Unicode.property_class("Decimal_Number", true)
      when AST::ClassPerl::Kind::SpaceNeg
        Unicode.property_class("White_Space", true)
      when AST::ClassPerl::Kind::WordNeg
        # Use Unicode word property (Perl word) negated
        Unicode.property_class("word", true)
      else
        Hir::CharClass.new
      end
    end

    private def translate_class_perl_ascii(class_perl : AST::ClassPerl) : Hir::Node
      case class_perl.kind
      when AST::ClassPerl::Kind::Digit, AST::ClassPerl::Kind::DigitNeg
        ranges = [('0'.ord.to_u8)..('9'.ord.to_u8)]
        negated = class_perl.kind.digit_neg?
        validate_utf8_byte_intervals!(ranges, class_perl.span, negated: negated)
        Hir::CharClass.new(negated, ranges)
      when AST::ClassPerl::Kind::Word, AST::ClassPerl::Kind::WordNeg
        ranges = [
          ('a'.ord.to_u8)..('z'.ord.to_u8),
          ('A'.ord.to_u8)..('Z'.ord.to_u8),
          ('0'.ord.to_u8)..('9'.ord.to_u8),
          '_'.ord.to_u8..'_'.ord.to_u8,
        ]
        negated = class_perl.kind.word_neg?
        validate_utf8_byte_intervals!(ranges, class_perl.span, negated: negated)
        Hir::CharClass.new(negated, ranges)
      when AST::ClassPerl::Kind::Space, AST::ClassPerl::Kind::SpaceNeg
        ranges = [
          ' '.ord.to_u8..' '.ord.to_u8,
          '\t'.ord.to_u8..'\t'.ord.to_u8,
          '\n'.ord.to_u8..'\n'.ord.to_u8,
          '\r'.ord.to_u8..'\r'.ord.to_u8,
          '\f'.ord.to_u8..'\f'.ord.to_u8,
          '\v'.ord.to_u8..'\v'.ord.to_u8,
        ]
        negated = class_perl.kind.space_neg?
        validate_utf8_byte_intervals!(ranges, class_perl.span, negated: negated)
        Hir::CharClass.new(negated, ranges)
      else
        Hir::CharClass.new
      end
    end

    private def translate_class_unicode(class_unicode : AST::ClassUnicode) : Hir::Node
      raise ParseError.new("Unicode not allowed") unless @unicode

      if @ignore_case
        base_class = Unicode.property_class(class_unicode.name, false)
        folded = Hir.case_fold_unicode(Hir::Hir.new(base_class)).node.as(Hir::UnicodeClass)
        Hir::UnicodeClass.new(class_unicode.negated?, canonicalize_intervals(folded.intervals))
      else
        Unicode.property_class(class_unicode.name, class_unicode.negated?)
      end
    end

    private def translate_class_bracketed(class_bracketed : AST::ClassBracketed) : Hir::Node
      # Translate the ClassSet structure
      class_set = class_bracketed.kind

      if @unicode
        if single_class_item?(class_set) && (item = class_set.item) && single_class_item_negated?(item)
          negated = class_bracketed.negated? ^ single_class_item_negated?(item)
          build_unicode_class(translate_single_class_item_unicode_base(item), negated)
        else
          intervals = translate_class_set_unicode(class_set)
          build_unicode_class(intervals, class_bracketed.negated?)
        end
      else
        if single_class_item?(class_set) && (item = class_set.item) && single_class_item_negated?(item)
          negated = class_bracketed.negated? ^ single_class_item_negated?(item)
          build_byte_class(translate_single_class_item_bytes_base(item), negated, class_bracketed.span)
        else
          intervals = translate_class_set_bytes(class_set)
          build_byte_class(intervals, class_bracketed.negated?, class_bracketed.span)
        end
      end
    end

    private def build_unicode_class(intervals : Array(Range(UInt32, UInt32)), negated : Bool) : Hir::UnicodeClass
      folded = if @ignore_case
                 Hir::UnicodeClass.new(false, intervals).case_fold_simple.intervals
               else
                 intervals
               end
      klass = Hir::UnicodeClass.new(negated, folded)
      klass
    end

    private def build_byte_class(intervals : Array(Range(UInt8, UInt8)), negated : Bool, span : AST::Span) : Hir::CharClass
      validate_utf8_byte_intervals!(intervals, span, negated: negated)
      folded = if @ignore_case
                 Hir::CharClass.new(false, intervals).case_fold_simple.intervals
               else
                 intervals
               end
      klass = Hir::CharClass.new(negated, folded)
      validate_utf8_byte_intervals!(klass.intervals, span, negated: klass.negated?)
      klass
    end

    private def single_class_item?(class_set : AST::ClassSet) : Bool
      return false unless class_set.kind.item?
      return false unless item = class_set.item

      case item.item
      when AST::ClassPerl
        true
      when AST::ClassUnicode
        true
      else
        false
      end
    end

    private def single_class_item_negated?(item : AST::ClassSetItem) : Bool
      case node = item.item
      when AST::ClassPerl
        node.kind.negated?
      when AST::ClassUnicode
        node.negated?
      else
        false
      end
    end

    private def translate_single_class_item_bytes_base(item : AST::ClassSetItem) : Array(Range(UInt8, UInt8))
      case node = item.item
      when AST::ClassPerl
        translate_class_perl(positive_perl_class(node)).as(Hir::CharClass).intervals
      when AST::ClassUnicode
        translate_class_unicode(AST::ClassUnicode.new(node.span, false, node.name)).as(Hir::UnicodeClass).intervals.map { |rng| rng.begin.to_u8..rng.end.to_u8 }
      when AST::ClassAscii
        ascii_class_bytes(node.kind)
      else
        [] of Range(UInt8, UInt8)
      end
    end

    private def translate_single_class_item_unicode_base(item : AST::ClassSetItem) : Array(Range(UInt32, UInt32))
      case node = item.item
      when AST::ClassPerl
        translated = translate_class_perl(positive_perl_class(node))
        if translated.is_a?(Hir::UnicodeClass)
          translated.intervals
        else
          translated.as(Hir::CharClass).intervals.map { |rng| rng.begin.to_u32..rng.end.to_u32 }
        end
      when AST::ClassUnicode
        translate_class_unicode(AST::ClassUnicode.new(node.span, false, node.name)).as(Hir::UnicodeClass).intervals
      when AST::ClassAscii
        ascii_class_unicode(node.kind)
      else
        [] of Range(UInt32, UInt32)
      end
    end

    private def positive_perl_class(node : AST::ClassPerl) : AST::ClassPerl
      kind = if node.kind.digit?
               AST::ClassPerl::Kind::Digit
             elsif node.kind.space?
               AST::ClassPerl::Kind::Space
             else
               AST::ClassPerl::Kind::Word
             end
      AST::ClassPerl.new(node.span, kind)
    end

    private def translate_class_set_bytes(class_set : AST::ClassSet) : Array(Range(UInt8, UInt8))
      case class_set.kind
      when AST::ClassSet::Kind::Item
        if item = class_set.item
          canonicalize_intervals(translate_class_set_item_bytes(item))
        else
          [] of Range(UInt8, UInt8)
        end
      when AST::ClassSet::Kind::BinaryOp
        if binary_op = class_set.binary_op
          lhs_intervals = translate_class_set_bytes(binary_op.lhs)
          rhs_intervals = translate_class_set_bytes(binary_op.rhs)

          case binary_op.kind
          when AST::ClassSetBinaryOp::Kind::Intersection
            intersect_intervals(lhs_intervals, rhs_intervals)
          when AST::ClassSetBinaryOp::Kind::Difference
            difference_intervals(lhs_intervals, rhs_intervals)
          when AST::ClassSetBinaryOp::Kind::SymmetricDifference
            symmetric_difference_intervals(lhs_intervals, rhs_intervals)
          else
            [] of Range(UInt8, UInt8)
          end
        else
          [] of Range(UInt8, UInt8)
        end
      else
        [] of Range(UInt8, UInt8)
      end
    end

    private def translate_class_set_unicode(class_set : AST::ClassSet) : Array(Range(UInt32, UInt32))
      case class_set.kind
      when AST::ClassSet::Kind::Item
        if item = class_set.item
          canonicalize_intervals(translate_class_set_item_unicode(item))
        else
          [] of Range(UInt32, UInt32)
        end
      when AST::ClassSet::Kind::BinaryOp
        if binary_op = class_set.binary_op
          lhs_intervals = translate_class_set_unicode(binary_op.lhs)
          rhs_intervals = translate_class_set_unicode(binary_op.rhs)

          case binary_op.kind
          when AST::ClassSetBinaryOp::Kind::Intersection
            intersect_intervals(lhs_intervals, rhs_intervals)
          when AST::ClassSetBinaryOp::Kind::Difference
            difference_intervals(lhs_intervals, rhs_intervals)
          when AST::ClassSetBinaryOp::Kind::SymmetricDifference
            symmetric_difference_intervals(lhs_intervals, rhs_intervals)
          else
            [] of Range(UInt32, UInt32)
          end
        else
          [] of Range(UInt32, UInt32)
        end
      else
        [] of Range(UInt32, UInt32)
      end
    end

    private def translate_class_set_item_bytes(item : AST::ClassSetItem) : Array(Range(UInt8, UInt8))
      case item.kind
      when AST::ClassSetItem::Kind::Literal
        if literal = item.item.as?(AST::Literal)
          translate_literal_to_range_bytes(literal)
        else
          [] of Range(UInt8, UInt8)
        end
      when AST::ClassSetItem::Kind::Range
        if range = item.item.as?(AST::ClassSetRange)
          translate_class_set_range_bytes(range)
        else
          [] of Range(UInt8, UInt8)
        end
      when AST::ClassSetItem::Kind::Union
        if union = item.item.as?(AST::ClassSetUnion)
          translate_class_set_union_bytes(union)
        else
          [] of Range(UInt8, UInt8)
        end
      when AST::ClassSetItem::Kind::Perl
        if perl = item.item.as?(AST::ClassPerl)
          translate_class_perl(perl).as(Hir::CharClass).intervals
        else
          [] of Range(UInt8, UInt8)
        end
      when AST::ClassSetItem::Kind::Unicode
        if unicode = item.item.as?(AST::ClassUnicode)
          node = translate_class_unicode(unicode).as(Hir::UnicodeClass)
          intervals = node.intervals.map { |rng| rng.begin.to_u8..rng.end.to_u8 }
          node.negated? ? invert_byte_intervals(intervals) : intervals
        else
          [] of Range(UInt8, UInt8)
        end
      when AST::ClassSetItem::Kind::Ascii
        if ascii = item.item.as?(AST::ClassAscii)
          intervals = ascii_class_bytes(ascii.kind)
          ascii.negated? ? invert_byte_intervals(intervals) : intervals
        else
          [] of Range(UInt8, UInt8)
        end
      when AST::ClassSetItem::Kind::Bracketed
        if bracketed = item.item.as?(AST::ClassBracketed)
          node = translate_class_bracketed(bracketed).as(Hir::CharClass)
          node.negated? ? invert_byte_intervals(node.intervals) : node.intervals
        else
          [] of Range(UInt8, UInt8)
        end
      else
        [] of Range(UInt8, UInt8)
      end
    end

    private def translate_class_set_item_unicode(item : AST::ClassSetItem) : Array(Range(UInt32, UInt32))
      case item.kind
      when AST::ClassSetItem::Kind::Literal
        if literal = item.item.as?(AST::Literal)
          translate_literal_to_range_unicode(literal)
        else
          [] of Range(UInt32, UInt32)
        end
      when AST::ClassSetItem::Kind::Range
        if range = item.item.as?(AST::ClassSetRange)
          translate_class_set_range_unicode(range)
        else
          [] of Range(UInt32, UInt32)
        end
      when AST::ClassSetItem::Kind::Union
        if union = item.item.as?(AST::ClassSetUnion)
          translate_class_set_union_unicode(union)
        else
          [] of Range(UInt32, UInt32)
        end
      when AST::ClassSetItem::Kind::Perl
        if perl = item.item.as?(AST::ClassPerl)
          # For Unicode mode, Perl classes become Unicode classes
          node = translate_class_perl(perl)
          if node.is_a?(Hir::UnicodeClass)
            node.intervals
          else
            # Convert byte ranges to Unicode ranges
            node.as(Hir::CharClass).intervals.map { |rng| rng.begin.to_u32..rng.end.to_u32 }
          end
        else
          [] of Range(UInt32, UInt32)
        end
      when AST::ClassSetItem::Kind::Unicode
        if unicode = item.item.as?(AST::ClassUnicode)
          node = translate_class_unicode(unicode).as(Hir::UnicodeClass)
          node.negated? ? invert_unicode_intervals(node.intervals) : node.intervals
        else
          [] of Range(UInt32, UInt32)
        end
      when AST::ClassSetItem::Kind::Ascii
        if ascii = item.item.as?(AST::ClassAscii)
          intervals = ascii_class_unicode(ascii.kind)
          ascii.negated? ? invert_unicode_intervals(intervals) : intervals
        else
          [] of Range(UInt32, UInt32)
        end
      when AST::ClassSetItem::Kind::Bracketed
        if bracketed = item.item.as?(AST::ClassBracketed)
          node = translate_class_bracketed(bracketed)
          if node.is_a?(Hir::UnicodeClass)
            node.negated? ? invert_unicode_intervals(node.intervals) : node.intervals
          else
            # Convert byte ranges to Unicode ranges
            byte_node = node.as(Hir::CharClass)
            intervals = byte_node.intervals.map { |rng| rng.begin.to_u32..rng.end.to_u32 }
            byte_node.negated? ? invert_unicode_intervals(intervals) : intervals
          end
        else
          [] of Range(UInt32, UInt32)
        end
      else
        [] of Range(UInt32, UInt32)
      end
    end

    private def translate_class_set_union_bytes(union : AST::ClassSetUnion) : Array(Range(UInt8, UInt8))
      intervals = [] of Range(UInt8, UInt8)
      union.items.each do |item|
        intervals.concat(translate_class_set_item_bytes(item))
      end
      canonicalize_intervals(intervals)
    end

    private def translate_class_set_union_unicode(union : AST::ClassSetUnion) : Array(Range(UInt32, UInt32))
      intervals = [] of Range(UInt32, UInt32)
      union.items.each do |item|
        intervals.concat(translate_class_set_item_unicode(item))
      end
      canonicalize_intervals(intervals)
    end

    private def translate_class_set_range_bytes(range : AST::ClassSetRange) : Array(Range(UInt8, UInt8))
      start_literal = range.start
      end_literal = range.end

      start_char = start_literal.c
      end_char = end_literal.c
      start_byte = single_byte_literal(start_literal)
      end_byte = single_byte_literal(end_literal)

      if start_char && end_char
        # In byte mode (non-Unicode), only ASCII characters are allowed
        # Characters above 255 would overflow when converting to UInt8
        return [] of Range(UInt8, UInt8) unless start_char.ascii? && end_char.ascii?

        if @ignore_case
          # For case-insensitive matching, we need to include both cases
          start_lower = start_char.downcase.ord.to_u8
          end_lower = end_char.downcase.ord.to_u8
          start_upper = start_char.upcase.ord.to_u8
          end_upper = end_char.upcase.ord.to_u8

          # Create ranges for both cases
          ranges = [] of Range(UInt8, UInt8)
          ranges << (start_lower..end_lower) if start_lower <= end_lower
          ranges << (start_upper..end_upper) if start_upper <= end_upper
          ranges
        else
          [(start_char.ord.to_u8..end_char.ord.to_u8)]
        end
      elsif start_byte && end_byte
        [(start_byte..end_byte)]
      else
        [] of Range(UInt8, UInt8)
      end
    end

    private def translate_class_set_range_unicode(range : AST::ClassSetRange) : Array(Range(UInt32, UInt32))
      start_literal = range.start
      end_literal = range.end

      start_char = start_literal.c
      end_char = end_literal.c

      if start_char && end_char
        if @ignore_case
          # For case-insensitive matching, we need to include both cases
          start_lower = start_char.downcase.ord.to_u32
          end_lower = end_char.downcase.ord.to_u32
          start_upper = start_char.upcase.ord.to_u32
          end_upper = end_char.upcase.ord.to_u32

          # Create ranges for both cases
          ranges = [] of Range(UInt32, UInt32)
          ranges << (start_lower..end_lower) if start_lower <= end_lower
          ranges << (start_upper..end_upper) if start_upper <= end_upper
          ranges
        else
          [(start_char.ord.to_u32..end_char.ord.to_u32)]
        end
      else
        [] of Range(UInt32, UInt32)
      end
    end

    private def translate_literal_to_range_bytes(literal : AST::Literal) : Array(Range(UInt8, UInt8))
      if bytes = literal.bytes
        return [] of Range(UInt8, UInt8) unless bytes.size == 1

        byte = bytes[0]
        return [(byte..byte)] unless @ignore_case && byte.chr.ascii?

        lower = byte.chr.downcase.ord.to_u8
        upper = byte.chr.upcase.ord.to_u8
        return lower == upper ? [(lower..lower)] : [(lower..lower), (upper..upper)]
      end

      if c = literal.c
        raise ParseError.new("Unicode not allowed") unless c.ascii?

        if @ignore_case
          # For case-insensitive matching, include both cases
          lower = c.downcase.ord.to_u8
          upper = c.upcase.ord.to_u8
          if lower == upper
            [(lower..lower)]
          else
            [(lower..lower), (upper..upper)]
          end
        else
          [(c.ord.to_u8..c.ord.to_u8)]
        end
      else
        [] of Range(UInt8, UInt8)
      end
    end

    private def translate_literal_to_range_unicode(literal : AST::Literal) : Array(Range(UInt32, UInt32))
      if c = literal.c
        if @ignore_case
          node = Hir.case_fold_unicode(Hir::Hir.new(Hir::UnicodeClass.new(false, [c.ord.to_u32..c.ord.to_u32]))).node
          case node
          when Hir::UnicodeClass
            canonicalize_intervals(node.intervals)
          when Hir::CharClass
            canonicalize_intervals(node.intervals.map { |rng| rng.begin.to_u32..rng.end.to_u32 })
          else
            [(c.ord.to_u32..c.ord.to_u32)]
          end
        else
          [(c.ord.to_u32..c.ord.to_u32)]
        end
      else
        [] of Range(UInt32, UInt32)
      end
    end

    private def single_byte_literal(literal : AST::Literal) : UInt8?
      if bytes = literal.bytes
        bytes.size == 1 ? bytes[0] : nil
      else
        nil
      end
    end

    private def char_to_utf8_bytes(c : Char) : Bytes
      string = c.to_s
      slice = string.to_slice
      Bytes.new(slice.size) { |index| slice[index] }
    end

    private def translate_dot(dot : AST::Dot) : Hir::Node
      if @utf8 && (!@unicode || @line_terminator > 0x7F)
        raise ParseError.new("invalid UTF-8", :invalid_utf8, dot.span)
      end

      if @dot_matches_new_line
        kind = @unicode ? Hir::Dot::AnyChar : Hir::Dot::AnyByte
        ensure_valid_utf8_dot!(kind)
        return Hir::DotNode.new(kind)
      end

      if @unicode
        if @crlf
          kind = Hir::Dot::AnyCharExceptCRLF
          ensure_valid_utf8_dot!(kind)
          Hir::DotNode.new(kind)
        else
          raise ParseError.new("invalid line terminator", :invalid_line_terminator, dot.span) unless @line_terminator <= 0x7F
          if @line_terminator == '\n'.ord.to_u8
            kind = Hir::Dot::AnyCharExceptLF
            ensure_valid_utf8_dot!(kind)
            Hir::DotNode.new(kind)
          else
            Hir::UnicodeClass.new(false, dot_unicode_intervals(@line_terminator.chr))
          end
        end
      else
        if @crlf
          kind = Hir::Dot::AnyByteExceptCRLF
          ensure_valid_utf8_dot!(kind)
          Hir::DotNode.new(kind)
        else
          if @line_terminator == '\n'.ord.to_u8
            kind = Hir::Dot::AnyByteExceptLF
            ensure_valid_utf8_dot!(kind)
            Hir::DotNode.new(kind)
          else
            Hir::CharClass.new(false, dot_byte_intervals(@line_terminator))
          end
        end
      end
    end

    private def dot_unicode_intervals(line_terminator : Char) : Array(Range(UInt32, UInt32))
      codepoint = line_terminator.ord.to_u32
      intervals = [] of Range(UInt32, UInt32)
      intervals << (0_u32..(codepoint - 1).to_u32) if codepoint > 0
      intervals << ((codepoint + 1).to_u32..0x10FFFF_u32) if codepoint < 0x10FFFF
      intervals
    end

    private def dot_byte_intervals(line_terminator : UInt8) : Array(Range(UInt8, UInt8))
      intervals = [] of Range(UInt8, UInt8)
      intervals << (0_u8..(line_terminator - 1).to_u8) if line_terminator > 0
      intervals << ((line_terminator + 1).to_u8..255_u8) if line_terminator < 255
      intervals
    end

    private def translate_concat(concat : AST::Concat) : Hir::Node
      children = concat.children.map { |child| translate(child) }
      # Filter out empty nodes
      filtered = children.reject(Hir::Empty)
      case filtered.size
      when 0
        Hir::Empty.new
      when 1
        filtered.first
      else
        Regex::Syntax::Hir::Hir.concat(filtered).node
      end
    end

    private def translate_alternation(alternation : AST::Alternation) : Hir::Node
      children = alternation.children.map { |child| translate(child) }
      # Don't filter out empty nodes from alternations - empty branches are valid
      case children.size
      when 0
        Regex::Syntax::Hir::Hir.fail.node
      when 1
        children.first
      else
        Regex::Syntax::Hir::Hir.alternation(children).node
      end
    end

    private def translate_assertion(assertion : AST::Assertion) : Hir::Node
      case assertion.kind
      when AST::Assertion::Kind::Start
        if @multi_line
          if @crlf
            Hir::Look.new(Hir::Look::Kind::StartCRLF)
          else
            Hir::Look.new(Hir::Look::Kind::StartLF)
          end
        else
          Hir::Look.new(Hir::Look::Kind::StartText)
        end
      when AST::Assertion::Kind::End
        if @multi_line
          if @crlf
            Hir::Look.new(Hir::Look::Kind::EndCRLF)
          else
            Hir::Look.new(Hir::Look::Kind::EndLF)
          end
        else
          Hir::Look.new(Hir::Look::Kind::EndTextOptionalLF)
        end
      when AST::Assertion::Kind::StartText
        Hir::Look.new(Hir::Look::Kind::StartText)
      when AST::Assertion::Kind::EndText
        Hir::Look.new(Hir::Look::Kind::EndText)
      when AST::Assertion::Kind::EndTextWithNewline
        Hir::Look.new(Hir::Look::Kind::EndTextOptionalLF)
      when AST::Assertion::Kind::WordBoundary
        Hir::Look.new(@unicode ? Hir::Look::Kind::WordUnicode : Hir::Look::Kind::WordAscii)
      when AST::Assertion::Kind::NonWordBoundary
        Hir::Look.new(@unicode ? Hir::Look::Kind::WordUnicodeNegate : Hir::Look::Kind::WordAsciiNegate)
      when AST::Assertion::Kind::WordBoundaryStart,
           AST::Assertion::Kind::WordBoundaryStartAngle
        Hir::Look.new(@unicode ? Hir::Look::Kind::WordStartUnicode : Hir::Look::Kind::WordStartAscii)
      when AST::Assertion::Kind::WordBoundaryEnd,
           AST::Assertion::Kind::WordBoundaryEndAngle
        Hir::Look.new(@unicode ? Hir::Look::Kind::WordEndUnicode : Hir::Look::Kind::WordEndAscii)
      when AST::Assertion::Kind::WordBoundaryStartHalf
        Hir::Look.new(@unicode ? Hir::Look::Kind::WordStartHalfUnicode : Hir::Look::Kind::WordStartHalfAscii)
      when AST::Assertion::Kind::WordBoundaryEndHalf
        Hir::Look.new(@unicode ? Hir::Look::Kind::WordEndHalfUnicode : Hir::Look::Kind::WordEndHalfAscii)
      else
        Hir::Empty.new
      end
    end

    private def translate_repetition(repetition : AST::Repetition) : Hir::Node
      child = translate(repetition.child)
      if repetition.op.kind == AST::RepetitionOp::Kind::Range &&
         repetition.op.min == 0_u32 &&
         repetition.op.max == 0_u32
        return Hir::Empty.new
      end

      case repetition.op.kind
      when AST::RepetitionOp::Kind::ZeroOrOne
        Regex::Syntax::Hir::Hir.repetition(child, 0_u32, 1_u32, greedy: repetition.greedy?).node
      when AST::RepetitionOp::Kind::ZeroOrMore
        Regex::Syntax::Hir::Hir.repetition(child, 0_u32, nil, greedy: repetition.greedy?).node
      when AST::RepetitionOp::Kind::OneOrMore
        Regex::Syntax::Hir::Hir.repetition(child, 1_u32, nil, greedy: repetition.greedy?).node
      when AST::RepetitionOp::Kind::Range
        Regex::Syntax::Hir::Hir.repetition(
          child,
          repetition.op.min || 0_u32,
          repetition.op.max,
          greedy: repetition.greedy?
        ).node
      else
        child
      end
    end

    private def translate_group(group : AST::Group) : Hir::Node
      # For non-capturing groups with flags, we need to apply flags to child
      if group.kind == AST::Group::Kind::NonCapture && (flags = group.flags)
        # Create a new translator with modified flags
        new_flags = parse_ast_flags(flags)
        translator = with_modified_flags(new_flags)
        return translator.translate(group.child)
      end

      # Inline flag-setting nodes inside any group should not leak out past
      # that group's boundary, so every non-flag-group child translation gets
      # an isolated translator snapshot.
      child = with_modified_flags(Hash(String, Bool).new).translate(group.child)

      case group.kind
      when AST::Group::Kind::Capture
        # Capture groups become Capture nodes in HIR
        Hir::Capture.new(child, group.capture_index || 0, group.name)
      when AST::Group::Kind::NonCapture, AST::Group::Kind::Atomic,
           AST::Group::Kind::Lookahead, AST::Group::Kind::Lookbehind,
           AST::Group::Kind::NegativeLookahead, AST::Group::Kind::NegativeLookbehind
        child
      else
        child
      end
    end

    private def translate_case_folded_char(c : Char) : Hir::Node
      # Convert single character to character class with both cases
      if 'A' <= c <= 'Z'
        lower = (c.ord + 32).to_u8
        upper = c.ord.to_u8
        Hir::CharClass.new(false, [lower..lower, upper..upper])
      elsif 'a' <= c <= 'z'
        lower = c.ord.to_u8
        upper = (c.ord - 32).to_u8
        Hir::CharClass.new(false, [lower..lower, upper..upper])
      else
        Hir::Literal.new(char_to_utf8_bytes(c))
      end
    end

    private def translate_case_folded_bytes(bytes : Bytes) : Hir::Node
      # Convert bytes to concatenation of character classes/literals
      nodes = [] of Hir::Node

      bytes.each do |byte|
        c = byte.chr
        if 'A' <= c <= 'Z'
          lower = (c.ord + 32).to_u8
          upper = c.ord.to_u8
          nodes << Hir::CharClass.new(false, [lower..lower, upper..upper])
        elsif 'a' <= c <= 'z'
          lower = c.ord.to_u8
          upper = (c.ord - 32).to_u8
          nodes << Hir::CharClass.new(false, [lower..lower, upper..upper])
        else
          nodes << Hir::Literal.new(Bytes.new(1) { byte })
        end
      end

      case nodes.size
      when 0
        Hir::Empty.new
      when 1
        nodes.first
      else
        Regex::Syntax::Hir::Hir.concat(nodes).node
      end
    end

    private def translate_set_flags(set_flags : AST::SetFlags) : Hir::Node
      # Update translator flags based on SetFlags
      update_flags_from_ast(set_flags)
      # SetFlags nodes don't produce HIR nodes, they just affect flags
      Hir::Empty.new
    end

    private def update_flags_from_ast(set_flags : AST::SetFlags)
      # Parse flags from AST and update translator state
      flags = parse_ast_flags_from_setflags(set_flags)
      apply_flags(flags)
    end

    private def parse_ast_flags_from_setflags(set_flags : AST::SetFlags) : Hash(String, Bool)
      result = {} of String => Bool
      negated = false

      set_flags.items.each do |item|
        case item.kind
        when AST::FlagsItem::Kind::Negation
          negated = true
        when AST::FlagsItem::Kind::Flag
          if flag = item.flag
            result[flag.to_s] = !negated
            negated = false
          end
        end
      end

      result
    end

    private def apply_flags(new_flags : Hash(String, Bool))
      @ignore_case = new_flags.fetch("i", @ignore_case)
      @multi_line = new_flags.fetch("m", @multi_line)
      @dot_matches_new_line = new_flags.fetch("s", @dot_matches_new_line)
      @swap_greed = new_flags.fetch("U", @swap_greed)
      @ignore_whitespace = new_flags.fetch("x", @ignore_whitespace)
      @unicode = new_flags.fetch("u", @unicode)
      @crlf = new_flags.fetch("R", @crlf)
    end

    private def parse_flags(flags_str : String) : Hash(String, Bool)
      flags = {} of String => Bool
      i = 0
      while i < flags_str.size
        c = flags_str[i]
        if c == '-'
          # Negative flag: -i
          i += 1
          next if i >= flags_str.size
          flag = flags_str[i].to_s
          flags[flag] = false
        else
          # Positive flag: i
          flag = c.to_s
          flags[flag] = true
        end
        i += 1
      end
      flags
    end

    private def parse_ast_flags(flags : AST::Flags) : Hash(String, Bool)
      result = {} of String => Bool
      negated = false

      flags.items.each do |item|
        case item.kind
        when AST::FlagsItem::Kind::Negation
          negated = true
        when AST::FlagsItem::Kind::Flag
          if flag = item.flag
            result[flag.to_s] = !negated
            negated = false
          end
        end
      end

      result
    end

    # Returns byte ranges for an ASCII character class kind
    private def ascii_class_bytes(kind : AST::ClassAscii::Kind) : Array(Range(UInt8, UInt8))
      case kind
      when AST::ClassAscii::Kind::Alnum
        [('0'.ord.to_u8)..('9'.ord.to_u8), ('A'.ord.to_u8)..('Z'.ord.to_u8), ('a'.ord.to_u8)..('z'.ord.to_u8)]
      when AST::ClassAscii::Kind::Alpha
        [('A'.ord.to_u8)..('Z'.ord.to_u8), ('a'.ord.to_u8)..('z'.ord.to_u8)]
      when AST::ClassAscii::Kind::Ascii
        [0x00_u8..0x7F_u8]
      when AST::ClassAscii::Kind::Blank
        [('\t'.ord.to_u8)..('\t'.ord.to_u8), (' '.ord.to_u8)..(' '.ord.to_u8)]
      when AST::ClassAscii::Kind::Cntrl
        [0x00_u8..0x1F_u8, 0x7F_u8..0x7F_u8]
      when AST::ClassAscii::Kind::Digit
        [('0'.ord.to_u8)..('9'.ord.to_u8)]
      when AST::ClassAscii::Kind::Graph
        [('!'.ord.to_u8)..('~'.ord.to_u8)]
      when AST::ClassAscii::Kind::Lower
        [('a'.ord.to_u8)..('z'.ord.to_u8)]
      when AST::ClassAscii::Kind::Print
        [(' '.ord.to_u8)..('~'.ord.to_u8)]
      when AST::ClassAscii::Kind::Punct
        [('!'.ord.to_u8)..('/'.ord.to_u8), (':'.ord.to_u8)..('@'.ord.to_u8), ('['.ord.to_u8)..('`'.ord.to_u8), ('{'.ord.to_u8)..('~'.ord.to_u8)]
      when AST::ClassAscii::Kind::Space
        [('\t'.ord.to_u8)..('\t'.ord.to_u8), ('\n'.ord.to_u8)..('\n'.ord.to_u8), 0x0B_u8..0x0B_u8, 0x0C_u8..0x0C_u8, ('\r'.ord.to_u8)..('\r'.ord.to_u8), (' '.ord.to_u8)..(' '.ord.to_u8)]
      when AST::ClassAscii::Kind::Upper
        [('A'.ord.to_u8)..('Z'.ord.to_u8)]
      when AST::ClassAscii::Kind::Word
        [('0'.ord.to_u8)..('9'.ord.to_u8), ('A'.ord.to_u8)..('Z'.ord.to_u8), ('_'.ord.to_u8)..('_'.ord.to_u8), ('a'.ord.to_u8)..('z'.ord.to_u8)]
      when AST::ClassAscii::Kind::Xdigit
        [('0'.ord.to_u8)..('9'.ord.to_u8), ('A'.ord.to_u8)..('F'.ord.to_u8), ('a'.ord.to_u8)..('f'.ord.to_u8)]
      else
        [] of Range(UInt8, UInt8)
      end
    end

    # Returns Unicode code point ranges for an ASCII character class kind
    private def ascii_class_unicode(kind : AST::ClassAscii::Kind) : Array(Range(UInt32, UInt32))
      ascii_class_bytes(kind).map do |range|
        range.begin.to_u32..range.end.to_u32
      end
    end

    # Invert byte intervals (0-255 range)
    private def invert_byte_intervals(intervals : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return [] of Range(UInt8, UInt8) if intervals.empty?
      invert_canonical_intervals(canonicalize_intervals(intervals), 255_u8)
    end

    # Invert Unicode intervals (0-0x10FFFF range)
    private def invert_unicode_intervals(intervals : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return [] of Range(UInt32, UInt32) if intervals.empty?
      invert_canonical_intervals(canonicalize_intervals(intervals), 0x10FFFF_u32)
    end

    # Helper functions for binary operations on canonical intervals.
    private def canonicalize_intervals(intervals : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return [] of Range(UInt8, UInt8) if intervals.empty?
      return intervals if canonical_intervals?(intervals)

      sorted = intervals.sort_by(&.begin)
      merged = [] of Range(UInt8, UInt8)
      current = sorted.first

      sorted[1..].each do |range|
        if range.begin <= current.end + 1
          current = current.begin..Math.max(current.end, range.end)
        else
          merged << current
          current = range
        end
      end
      merged << current
      merged
    end

    private def canonicalize_intervals(intervals : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return [] of Range(UInt32, UInt32) if intervals.empty?
      return intervals if canonical_intervals?(intervals)

      sorted = intervals.sort_by(&.begin)
      merged = [] of Range(UInt32, UInt32)
      current = sorted.first

      sorted[1..].each do |range|
        if range.begin <= current.end + 1
          current = current.begin..Math.max(current.end, range.end)
        else
          merged << current
          current = range
        end
      end
      merged << current
      merged
    end

    private def canonical_intervals?(intervals : Array(Range(UInt8, UInt8))) : Bool
      intervals.each_cons_pair do |left, right|
        return false if left.begin > right.begin
        return false if left.end.to_u16 + 1 >= right.begin.to_u16
      end
      true
    end

    private def canonical_intervals?(intervals : Array(Range(UInt32, UInt32))) : Bool
      intervals.each_cons_pair do |left, right|
        return false if left.begin > right.begin
        return false if left.end.to_u64 + 1 >= right.begin.to_u64
      end
      true
    end

    private def union_intervals(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return b if a.empty?
      return a if b.empty?

      result = Array(Range(UInt8, UInt8)).new(a.size + b.size)
      i = 0
      j = 0
      current = uninitialized Range(UInt8, UInt8)
      has_current = false

      while i < a.size || j < b.size
        next_range = if j >= b.size || (i < a.size && a[i].begin <= b[j].begin)
                       range = a[i]
                       i += 1
                       range
                     else
                       range = b[j]
                       j += 1
                       range
                     end

        if has_current && next_range.begin.to_u16 <= current.end.to_u16 + 1
          current = current.begin..Math.max(current.end, next_range.end)
        else
          result << current if has_current
          current = next_range
          has_current = true
        end
      end

      result << current if has_current
      result
    end

    private def union_intervals(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return b if a.empty?
      return a if b.empty?

      result = Array(Range(UInt32, UInt32)).new(a.size + b.size)
      i = 0
      j = 0
      current = uninitialized Range(UInt32, UInt32)
      has_current = false

      while i < a.size || j < b.size
        next_range = if j >= b.size || (i < a.size && a[i].begin <= b[j].begin)
                       range = a[i]
                       i += 1
                       range
                     else
                       range = b[j]
                       j += 1
                       range
                     end

        if has_current && next_range.begin.to_u64 <= current.end.to_u64 + 1
          current = current.begin..Math.max(current.end, next_range.end)
        else
          result << current if has_current
          current = next_range
          has_current = true
        end
      end

      result << current if has_current
      result
    end

    private def invert_canonical_intervals(intervals : Array(Range(UInt8, UInt8)), max_value : UInt8) : Array(Range(UInt8, UInt8))
      result = [] of Range(UInt8, UInt8)
      next_start = 0_u8

      intervals.each do |range|
        if next_start < range.begin
          result << (next_start..(range.begin - 1).to_u8)
        end
        next_start = range.end == max_value ? max_value : (range.end + 1).to_u8
      end

      if intervals.last.end < max_value
        result << (next_start..max_value)
      end
      result
    end

    private def invert_canonical_intervals(intervals : Array(Range(UInt32, UInt32)), max_value : UInt32) : Array(Range(UInt32, UInt32))
      result = [] of Range(UInt32, UInt32)
      next_start = 0_u32

      intervals.each do |range|
        if next_start < range.begin
          result << (next_start..(range.begin - 1).to_u32)
        end
        next_start = range.end == max_value ? max_value : (range.end + 1).to_u32
      end

      if intervals.last.end < max_value
        result << (next_start..max_value)
      end
      result
    end

    # Intersection of two interval sets
    private def intersect_intervals(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return [] of Range(UInt8, UInt8) if a.empty? || b.empty?

      result = [] of Range(UInt8, UInt8)

      i, j = 0, 0
      while i < a.size && j < b.size
        range_a = a[i]
        range_b = b[j]

        # Check for overlap
        if range_a.end < range_b.begin
          i += 1
        elsif range_b.end < range_a.begin
          j += 1
        else
          # There's an overlap
          start = Math.max(range_a.begin, range_b.begin)
          finish = Math.min(range_a.end, range_b.end)
          result << (start..finish)

          # Move past the interval that ends first
          if range_a.end < range_b.end
            i += 1
          else
            j += 1
          end
        end
      end

      result
    end

    private def intersect_intervals(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return [] of Range(UInt32, UInt32) if a.empty? || b.empty?

      result = [] of Range(UInt32, UInt32)

      i, j = 0, 0
      while i < a.size && j < b.size
        range_a = a[i]
        range_b = b[j]

        # Check for overlap
        if range_a.end < range_b.begin
          i += 1
        elsif range_b.end < range_a.begin
          j += 1
        else
          # There's an overlap
          start = Math.max(range_a.begin, range_b.begin)
          finish = Math.min(range_a.end, range_b.end)
          result << (start..finish)

          # Move past the interval that ends first
          if range_a.end < range_b.end
            i += 1
          else
            j += 1
          end
        end
      end

      result
    end

    # Difference of two interval sets (a - b)
    private def difference_intervals(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return a if b.empty?
      return [] of Range(UInt8, UInt8) if a.empty?

      result = [] of Range(UInt8, UInt8)

      i, j = 0, 0
      while i < a.size
        range_a = a[i]

        # Skip b intervals that are completely before range_a
        while j < b.size && b[j].end < range_a.begin
          j += 1
        end

        # If no more b intervals or next b interval starts after range_a ends
        if j >= b.size || b[j].begin > range_a.end
          result << range_a
          i += 1
          next
        end

        # Process overlap
        current_start = range_a.begin
        while j < b.size && b[j].begin <= range_a.end
          range_b = b[j]

          # Add part of range_a before range_b
          if current_start < range_b.begin
            result << (current_start..(range_b.begin - 1).to_u8)
          end

          # Update current_start to after range_b
          current_start = Math.max(current_start, range_b.end + 1)

          # Move to next b interval if this one is done
          if range_b.end >= range_a.end
            break
          end

          j += 1
        end

        # Add remaining part of range_a after last overlapping b interval
        if current_start <= range_a.end
          result << (current_start..range_a.end)
        end

        i += 1
      end

      result
    end

    private def difference_intervals(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return a if b.empty?
      return [] of Range(UInt32, UInt32) if a.empty?

      result = [] of Range(UInt32, UInt32)

      i, j = 0, 0
      while i < a.size
        range_a = a[i]

        # Skip b intervals that are completely before range_a
        while j < b.size && b[j].end < range_a.begin
          j += 1
        end

        # If no more b intervals or next b interval starts after range_a ends
        if j >= b.size || b[j].begin > range_a.end
          result << range_a
          i += 1
          next
        end

        # Process overlap
        current_start = range_a.begin
        while j < b.size && b[j].begin <= range_a.end
          range_b = b[j]

          # Add part of range_a before range_b
          if current_start < range_b.begin
            result << (current_start..(range_b.begin - 1).to_u32)
          end

          # Update current_start to after range_b
          current_start = Math.max(current_start, range_b.end + 1)

          # Move to next b interval if this one is done
          if range_b.end >= range_a.end
            break
          end

          j += 1
        end

        # Add remaining part of range_a after last overlapping b interval
        if current_start <= range_a.end
          result << (current_start..range_a.end)
        end

        i += 1
      end

      result
    end

    # Symmetric difference of two interval sets (a xor b)
    private def symmetric_difference_intervals(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return b if a.empty?
      return a if b.empty?

      intersection = intersect_intervals(a, b)
      difference_intervals(union_intervals(a, b), intersection)
    end

    private def symmetric_difference_intervals(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return b if a.empty?
      return a if b.empty?

      intersection = intersect_intervals(a, b)
      difference_intervals(union_intervals(a, b), intersection)
    end

    private def with_modified_flags(new_flags : Hash(String, Bool)) : Translator
      # Create a new translator with modified flags
      unicode = new_flags.fetch("u", @unicode)
      ignore_case = new_flags.fetch("i", @ignore_case)
      multi_line = new_flags.fetch("m", @multi_line)
      dot_matches_new_line = new_flags.fetch("s", @dot_matches_new_line)
      swap_greed = new_flags.fetch("U", @swap_greed)
      ignore_whitespace = new_flags.fetch("x", @ignore_whitespace)
      crlf = new_flags.fetch("R", @crlf)

      Translator.new(
        unicode: unicode,
        utf8: @utf8,
        ignore_case: ignore_case,
        multi_line: multi_line,
        dot_matches_new_line: dot_matches_new_line,
        swap_greed: swap_greed,
        ignore_whitespace: ignore_whitespace,
        crlf: crlf,
        nest_limit: @nest_limit
      )
    end

    private def ensure_valid_utf8_bytes!(bytes : Bytes, span : AST::Span) : Nil
      string = String.new(bytes)
      raise ParseError.new("invalid UTF-8", :invalid_utf8, span) unless string.valid_encoding?
    end

    private def validate_utf8_byte_intervals!(intervals : Array(Range(UInt8, UInt8)), span : AST::Span, *, negated : Bool) : Nil
      return unless @utf8

      effective = negated ? invert_byte_intervals(intervals) : canonicalize_intervals(intervals)
      effective.each do |range|
        raise ParseError.new("invalid UTF-8", :invalid_utf8, span) if range.end > 0x7F_u8
      end
    end

    private def ensure_valid_utf8_dot!(kind : Hir::Dot) : Nil
      return unless @utf8

      case kind
      when Hir::Dot::AnyByte, Hir::Dot::AnyByteExceptLF, Hir::Dot::AnyByteExceptCRLF
        raise ParseError.new("invalid UTF-8")
      else
      end
    end
  end
end
