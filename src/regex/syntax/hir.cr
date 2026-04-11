module Regex::Syntax::Hir
  # Apply ASCII-only case folding to a HIR, for ignore_ascii_case support.
  def self.case_fold_ascii(hir : Hir) : Hir
    Hir.new(case_fold_ascii_node(hir.node))
  end

  # Apply Unicode-aware case folding to a HIR, for ignore_case support.
  def self.case_fold_unicode(hir : Hir) : Hir
    Hir.new(case_fold_unicode_node(hir.node))
  end

  private def self.case_fold_ascii_node(node : Node) : Node
    case node
    when Literal
      bytes = node.bytes
      nodes = [] of Node
      bytes.each do |byte|
        if ascii_letter?(byte)
          lower, upper = ascii_fold_pair(byte)
          ranges = [lower..lower, upper..upper]
          nodes << CharClass.new(false, ranges)
        else
          nodes << Literal.new(Bytes.new(1) { byte })
        end
      end
      return nodes.first if nodes.size == 1
      Concat.new(nodes)
    when CharClass
      ranges = case_fold_ascii_ranges(node.intervals)
      CharClass.new(node.negated?, ranges)
    when UnicodeClass
      node
    when Concat
      Concat.new(node.children.map { |child| case_fold_ascii_node(child) })
    when Alternation
      Alternation.new(node.children.map { |child| case_fold_ascii_node(child) })
    when Repetition
      Repetition.new(case_fold_ascii_node(node.sub), node.min, node.max, greedy: node.greedy?)
    when Capture
      Capture.new(case_fold_ascii_node(node.sub), node.index)
    when Look, DotNode, Empty
      node
    else
      node
    end
  end

  private def self.case_fold_unicode_node(node : Node) : Node
    case node
    when Literal
      fold_unicode_literal(node.bytes)
    when CharClass
      if node.negated?
        node
      else
        UnicodeClass.new(false, case_fold_unicode_from_byte_ranges(node.intervals))
      end
    when UnicodeClass
      if node.negated?
        node
      else
        UnicodeClass.new(false, case_fold_unicode_from_codepoint_ranges(node.intervals))
      end
    when Concat
      Concat.new(node.children.map { |child| case_fold_unicode_node(child) })
    when Alternation
      Alternation.new(node.children.map { |child| case_fold_unicode_node(child) })
    when Repetition
      Repetition.new(case_fold_unicode_node(node.sub), node.min, node.max, greedy: node.greedy?)
    when Capture
      Capture.new(case_fold_unicode_node(node.sub), node.index)
    when Look, DotNode, Empty
      node
    else
      node
    end
  end

  private def self.fold_unicode_literal(bytes : Bytes) : Node
    string = String.new(bytes)
    nodes = [] of Node
    string.each_char do |char|
      if char.ascii?
        lower, upper = ascii_fold_pair(char.ord.to_u8)
        ranges = [lower..lower, upper..upper]
        nodes << CharClass.new(false, ranges)
      else
        variants = unicode_case_variants(char)
        nodes << UnicodeClass.new(false, variants.map { |code_point| code_point..code_point })
      end
    end
    return nodes.first if nodes.size == 1
    Concat.new(nodes)
  end

  private def self.unicode_case_variants(char : Char) : Array(UInt32)
    variants = [] of UInt32
    variants << char.ord.to_u32
    variants << char.downcase.ord.to_u32
    variants << char.upcase.ord.to_u32
    variants.uniq!
    variants
  end

  private def self.case_fold_unicode_from_byte_ranges(ranges : Array(Range(UInt8, UInt8))) : Array(Range(UInt32, UInt32))
    folded = [] of Range(UInt32, UInt32)
    ranges.each do |range|
      folded << (range.begin.to_u32..range.end.to_u32)
      upper_start = range.begin > 'A'.ord.to_u8 ? range.begin : 'A'.ord.to_u8
      upper_end = range.end < 'Z'.ord.to_u8 ? range.end : 'Z'.ord.to_u8
      if upper_start <= upper_end
        folded << ((upper_start + 32).to_u32..(upper_end + 32).to_u32)
      end

      lower_start = range.begin > 'a'.ord.to_u8 ? range.begin : 'a'.ord.to_u8
      lower_end = range.end < 'z'.ord.to_u8 ? range.end : 'z'.ord.to_u8
      if lower_start <= lower_end
        folded << ((lower_start - 32).to_u32..(lower_end - 32).to_u32)
      end
    end
    folded
  end

  private def self.case_fold_unicode_from_codepoint_ranges(ranges : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
    folded = [] of Range(UInt32, UInt32)
    ranges.each do |range|
      folded << range
      if range.end - range.begin <= 512
        range.each do |code_point|
          char = code_point.chr
          unicode_case_variants(char).each do |variant|
            folded << (variant..variant)
          end
        end
      end
    end
    folded
  end

  private def self.case_fold_ascii_ranges(ranges : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
    folded = [] of Range(UInt8, UInt8)
    ranges.each do |range|
      folded << range
      upper_start = range.begin > 'A'.ord.to_u8 ? range.begin : 'A'.ord.to_u8
      upper_end = range.end < 'Z'.ord.to_u8 ? range.end : 'Z'.ord.to_u8
      if upper_start <= upper_end
        folded << ((upper_start + 32).to_u8..(upper_end + 32).to_u8)
      end

      lower_start = range.begin > 'a'.ord.to_u8 ? range.begin : 'a'.ord.to_u8
      lower_end = range.end < 'z'.ord.to_u8 ? range.end : 'z'.ord.to_u8
      if lower_start <= lower_end
        folded << ((lower_start - 32).to_u8..(lower_end - 32).to_u8)
      end
    end
    folded
  end

  private def self.ascii_letter?(byte : UInt8) : Bool
    (byte >= 'A'.ord.to_u8 && byte <= 'Z'.ord.to_u8) ||
      (byte >= 'a'.ord.to_u8 && byte <= 'z'.ord.to_u8)
  end

  private def self.ascii_fold_pair(byte : UInt8) : Tuple(UInt8, UInt8)
    if byte >= 'A'.ord.to_u8 && byte <= 'Z'.ord.to_u8
      {(byte + 32).to_u8, byte}
    else
      {byte, (byte - 32).to_u8}
    end
  end

  # A type describing the different flavors of `.`
  enum Dot
    # Matches the UTF-8 encoding of any Unicode scalar value
    AnyChar
    # Matches any byte value
    AnyByte
    # Matches the UTF-8 encoding of any Unicode scalar value except for \n
    AnyCharExceptLF
    # Matches any byte value except for \n
    AnyByteExceptLF
    # Matches the UTF-8 encoding of any Unicode scalar value except for \r and \n
    AnyCharExceptCRLF
    # Matches any byte value except for \r and \n
    AnyByteExceptCRLF
  end

  # Module-level helper for creating dot expressions
  def self.dot(dot : Dot) : Hir
    Hir.new(DotNode.new(dot))
  end

  # Base class for all HIR nodes
  abstract class Node
    # Calculate complexity/priority for disambiguation
    abstract def complexity : Int32

    # Check if contains greedy .* or .+
    abstract def has_greedy_all? : Bool

    # Check if the expression can match the empty string.
    abstract def can_match_empty? : Bool
  end

  # Dot metacharacter (.)
  class DotNode < Node
    getter kind : Dot

    def initialize(@kind : Dot)
    end

    def complexity : Int32
      1
    end

    def has_greedy_all? : Bool
      false
    end

    def can_match_empty? : Bool
      false
    end
  end

  # Empty pattern (matches nothing)
  class Empty < Node
    def complexity : Int32
      0
    end

    def has_greedy_all? : Bool
      false
    end

    def can_match_empty? : Bool
      true
    end
  end

  # Literal byte sequence
  class Literal < Node
    getter bytes : Bytes

    def initialize(@bytes : Bytes)
    end

    def complexity : Int32
      bytes.size * 2
    end

    def has_greedy_all? : Bool
      false
    end

    def can_match_empty? : Bool
      bytes.empty?
    end
  end

  # Character class
  class CharClass < Node
    getter? negated : Bool
    getter intervals : Array(Range(UInt8, UInt8))

    def initialize(negated : Bool = false, @intervals : Array(Range(UInt8, UInt8)) = [] of Range(UInt8, UInt8))
      @negated = negated
    end

    def complexity : Int32
      2
    end

    def has_greedy_all? : Bool
      false
    end

    def can_match_empty? : Bool
      false
    end
  end

  # Unicode character class (codepoint ranges)
  class UnicodeClass < Node
    getter? negated : Bool
    getter intervals : Array(Range(UInt32, UInt32))

    def initialize(negated : Bool = false, @intervals : Array(Range(UInt32, UInt32)) = [] of Range(UInt32, UInt32))
      @negated = negated
    end

    def complexity : Int32
      2
    end

    def has_greedy_all? : Bool
      false
    end

    def can_match_empty? : Bool
      false
    end
  end

  # Look-around assertion
  class Look < Node
    enum Kind
      Start              # ^
      End                # $
      StartText          # \A
      EndText            # \z
      EndTextWithNewline # \Z
      WordBoundary       # \b
      NonWordBoundary    # \B
    end

    getter kind : Kind

    def initialize(@kind : Kind)
    end

    def complexity : Int32
      0
    end

    def has_greedy_all? : Bool
      false
    end

    def can_match_empty? : Bool
      true
    end
  end

  # Repetition
  class Repetition < Node
    getter sub : Node
    getter min : Int32
    getter max : Int32?
    getter? greedy : Bool

    def initialize(@sub : Node, @min : Int32, @max : Int32?, greedy : Bool = true)
      @greedy = greedy
    end

    def complexity : Int32
      min * sub.complexity
    end

    def has_greedy_all? : Bool
      return false unless greedy && max.nil?

      case sub
      when DotNode
        true
      else
        false
      end
    end

    def can_match_empty? : Bool
      min == 0 || sub.can_match_empty?
    end
  end

  # Capture group
  class Capture < Node
    getter sub : Node
    getter index : Int32

    def initialize(@sub : Node, @index : Int32)
    end

    def complexity : Int32
      sub.complexity
    end

    def has_greedy_all? : Bool
      sub.has_greedy_all?
    end

    def can_match_empty? : Bool
      sub.can_match_empty?
    end
  end

  # Concatenation
  class Concat < Node
    getter children : Array(Node)

    def initialize(@children : Array(Node))
    end

    def complexity : Int32
      children.sum(&.complexity)
    end

    def has_greedy_all? : Bool
      children.any?(&.has_greedy_all?)
    end

    def can_match_empty? : Bool
      children.all?(&.can_match_empty?)
    end
  end

  # Alternation
  class Alternation < Node
    getter children : Array(Node)

    def initialize(@children : Array(Node))
    end

    def complexity : Int32
      children.min_of?(&.complexity) || 0
    end

    def has_greedy_all? : Bool
      children.any?(&.has_greedy_all?)
    end

    def can_match_empty? : Bool
      children.any?(&.can_match_empty?)
    end
  end

  # High-level intermediate representation for a regular expression
  class Hir < Node
    getter node : Node

    def initialize(@node : Node)
    end

    # Create a dot expression
    def self.dot(dot : Dot) : Hir
      Hir.new(DotNode.new(dot))
    end

    # Create a literal expression
    def self.literal(bytes : Bytes) : Hir
      Hir.new(Literal.new(bytes))
    end

    def complexity : Int32
      node.complexity
    end

    def has_greedy_all? : Bool
      node.has_greedy_all?
    end

    def can_match_empty? : Bool
      node.can_match_empty?
    end
  end
end
