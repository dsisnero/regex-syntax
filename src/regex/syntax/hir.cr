module Regex::Syntax::Hir
  module IntervalOps
    extend self

    def canonicalize(intervals : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return [] of Range(UInt8, UInt8) if intervals.empty?

      sorted = intervals.map { |range| canonical_range(range) }
      sorted.sort_by!(&.begin)
      merged = [] of Range(UInt8, UInt8)
      current = sorted.first

      sorted[1..].each do |range|
        if range.begin.to_u16 <= current.end.to_u16 + 1
          current = current.begin..Math.max(current.end, range.end)
        else
          merged << current
          current = range
        end
      end
      merged << current
      merged
    end

    def canonicalize(intervals : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return [] of Range(UInt32, UInt32) if intervals.empty?

      sorted = intervals.map { |range| canonical_range(range) }
      sorted.sort_by!(&.begin)
      merged = [] of Range(UInt32, UInt32)
      current = sorted.first

      sorted[1..].each do |range|
        if range.begin.to_u64 <= current.end.to_u64 + 1
          current = current.begin..Math.max(current.end, range.end)
        else
          merged << current
          current = range
        end
      end
      merged << current
      merged
    end

    def invert(intervals : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      canonical = canonicalize(intervals)
      return [0_u8..255_u8] if canonical.empty?

      result = [] of Range(UInt8, UInt8)
      next_start = 0_u8
      canonical.each do |range|
        if next_start < range.begin
          result << (next_start..(range.begin - 1).to_u8)
        end
        next_start = range.end == 255_u8 ? 255_u8 : (range.end + 1).to_u8
      end
      result << (next_start..255_u8) if canonical.last.end < 255_u8
      result
    end

    def invert(intervals : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      canonical = canonicalize(intervals)
      return [0_u32..0x10FFFF_u32] if canonical.empty?

      result = [] of Range(UInt32, UInt32)
      next_start = 0_u32
      canonical.each do |range|
        if next_start < range.begin
          result << (next_start..(range.begin - 1).to_u32)
        end
        next_start = range.end == 0x10FFFF_u32 ? 0x10FFFF_u32 : (range.end + 1).to_u32
      end
      result << (next_start..0x10FFFF_u32) if canonical.last.end < 0x10FFFF_u32
      result
    end

    def union(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      canonicalize(a + b)
    end

    def union(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      canonicalize(a + b)
    end

    def intersect(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return [] of Range(UInt8, UInt8) if a.empty? || b.empty?
      left = canonicalize(a)
      right = canonicalize(b)
      result = [] of Range(UInt8, UInt8)
      i = 0
      j = 0
      while i < left.size && j < right.size
        l = left[i]
        r = right[j]
        if l.end < r.begin
          i += 1
        elsif r.end < l.begin
          j += 1
        else
          result << (Math.max(l.begin, r.begin)..Math.min(l.end, r.end))
          if l.end < r.end
            i += 1
          else
            j += 1
          end
        end
      end
      result
    end

    def intersect(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return [] of Range(UInt32, UInt32) if a.empty? || b.empty?
      left = canonicalize(a)
      right = canonicalize(b)
      result = [] of Range(UInt32, UInt32)
      i = 0
      j = 0
      while i < left.size && j < right.size
        l = left[i]
        r = right[j]
        if l.end < r.begin
          i += 1
        elsif r.end < l.begin
          j += 1
        else
          result << (Math.max(l.begin, r.begin)..Math.min(l.end, r.end))
          if l.end < r.end
            i += 1
          else
            j += 1
          end
        end
      end
      result
    end

    def difference(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      return canonicalize(a) if b.empty?
      return [] of Range(UInt8, UInt8) if a.empty?
      left = canonicalize(a)
      right = canonicalize(b)
      result = [] of Range(UInt8, UInt8)
      i = 0
      j = 0
      while i < left.size
        l = left[i]
        while j < right.size && right[j].end < l.begin
          j += 1
        end
        if j >= right.size || right[j].begin > l.end
          result << l
          i += 1
          next
        end
        current_start = l.begin
        k = j
        while k < right.size && right[k].begin <= l.end
          r = right[k]
          result << (current_start..(r.begin - 1).to_u8) if current_start < r.begin
          current_start = Math.max(current_start, (r.end + 1).to_u8)
          break if r.end >= l.end
          k += 1
        end
        result << (current_start..l.end) if current_start <= l.end
        i += 1
      end
      result
    end

    def difference(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      return canonicalize(a) if b.empty?
      return [] of Range(UInt32, UInt32) if a.empty?
      left = canonicalize(a)
      right = canonicalize(b)
      result = [] of Range(UInt32, UInt32)
      i = 0
      j = 0
      while i < left.size
        l = left[i]
        while j < right.size && right[j].end < l.begin
          j += 1
        end
        if j >= right.size || right[j].begin > l.end
          result << l
          i += 1
          next
        end
        current_start = l.begin
        k = j
        while k < right.size && right[k].begin <= l.end
          r = right[k]
          result << (current_start..(r.begin - 1).to_u32) if current_start < r.begin
          current_start = Math.max(current_start, (r.end + 1).to_u32)
          break if r.end >= l.end
          k += 1
        end
        result << (current_start..l.end) if current_start <= l.end
        i += 1
      end
      result
    end

    def symmetric_difference(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      difference(union(a, b), intersect(a, b))
    end

    def symmetric_difference(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      difference(union(a, b), intersect(a, b))
    end

    private def canonical_range(range : Range(UInt8, UInt8)) : Range(UInt8, UInt8)
      range.begin <= range.end ? range : (range.end..range.begin)
    end

    private def canonical_range(range : Range(UInt32, UInt32)) : Range(UInt32, UInt32)
      range.begin <= range.end ? range : (range.end..range.begin)
    end

    def case_fold_ascii(intervals : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      folded = canonicalize(intervals)
      additions = [] of Range(UInt8, UInt8)
      folded.each do |range|
        upper_start = range.begin > 'A'.ord.to_u8 ? range.begin : 'A'.ord.to_u8
        upper_end = range.end < 'Z'.ord.to_u8 ? range.end : 'Z'.ord.to_u8
        additions << ((upper_start + 32).to_u8..(upper_end + 32).to_u8) if upper_start <= upper_end

        lower_start = range.begin > 'a'.ord.to_u8 ? range.begin : 'a'.ord.to_u8
        lower_end = range.end < 'z'.ord.to_u8 ? range.end : 'z'.ord.to_u8
        additions << ((lower_start - 32).to_u8..(lower_end - 32).to_u8) if lower_start <= lower_end
      end
      canonicalize(folded + additions)
    end

    def case_fold_unicode(intervals : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      folded = canonicalize(intervals)
      additions = [] of Range(UInt32, UInt32)
      folded.each do |range|
        additions << range
        next if range.end - range.begin > 512

        range.each do |code_point|
          char = code_point.chr
          additions << (char.ord.to_u32..char.ord.to_u32)
          if mapped = Regex::Syntax::UnicodeTables::CaseFoldingSimple::CASE_FOLDING_SIMPLE[char]?
            mapped.each do |mapped_char|
              cp = mapped_char.ord.to_u32
              additions << (cp..cp)
            end
          end
        end
      end
      canonicalize(additions)
    end
  end

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
      Capture.new(case_fold_ascii_node(node.sub), node.index, node.name)
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
      Capture.new(case_fold_unicode_node(node.sub), node.index, node.name)
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
      variants = unicode_case_variants(char)
      nodes << UnicodeClass.new(false, variants.map { |code_point| code_point..code_point })
    end
    return nodes.first if nodes.size == 1
    Concat.new(nodes)
  end

  private def self.unicode_case_variants(char : Char) : Array(UInt32)
    variants = [] of UInt32
    variants << char.ord.to_u32
    if folded = Regex::Syntax::UnicodeTables::CaseFoldingSimple::CASE_FOLDING_SIMPLE[char]?
      folded.each do |mapped_char|
        variants << mapped_char.ord.to_u32
      end
    end
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
      @intervals = IntervalOps.canonicalize(@intervals)
      if negated && full_byte_domain?(@intervals)
        @negated = false
        @intervals = [] of Range(UInt8, UInt8)
      else
        @negated = negated
      end
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

    def negate : self
      if negated?
        @negated = false
      else
        @intervals = IntervalOps.invert(@intervals)
      end
      normalize_full_domain_negation
      self
    end

    def union(other : CharClass) : self
      @intervals = IntervalOps.union(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def intersect(other : CharClass) : self
      @intervals = IntervalOps.intersect(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def difference(other : CharClass) : self
      @intervals = IntervalOps.difference(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def symmetric_difference(other : CharClass) : self
      @intervals = IntervalOps.symmetric_difference(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def case_fold_simple : self
      @intervals = IntervalOps.case_fold_ascii(@intervals)
      normalize_full_domain_negation
      self
    end

    private def full_byte_domain?(intervals : Array(Range(UInt8, UInt8))) : Bool
      intervals.size == 1 && intervals[0].begin == 0_u8 && intervals[0].end == 255_u8
    end

    protected def effective_intervals : Array(Range(UInt8, UInt8))
      negated? ? IntervalOps.invert(@intervals) : @intervals
    end

    private def normalize_full_domain_negation : Nil
      if negated? && full_byte_domain?(@intervals)
        @negated = false
        @intervals = [] of Range(UInt8, UInt8)
      end
    end
  end

  # Unicode character class (codepoint ranges)
  class UnicodeClass < Node
    getter? negated : Bool
    getter intervals : Array(Range(UInt32, UInt32))

    def initialize(negated : Bool = false, @intervals : Array(Range(UInt32, UInt32)) = [] of Range(UInt32, UInt32))
      @intervals = IntervalOps.canonicalize(@intervals)
      if negated && full_unicode_domain?(@intervals)
        @negated = false
        @intervals = [] of Range(UInt32, UInt32)
      else
        @negated = negated
      end
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

    def negate : self
      if negated?
        @negated = false
      else
        @intervals = IntervalOps.invert(@intervals)
      end
      normalize_full_domain_negation
      self
    end

    def union(other : UnicodeClass) : self
      @intervals = IntervalOps.union(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def intersect(other : UnicodeClass) : self
      @intervals = IntervalOps.intersect(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def difference(other : UnicodeClass) : self
      @intervals = IntervalOps.difference(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def symmetric_difference(other : UnicodeClass) : self
      @intervals = IntervalOps.symmetric_difference(effective_intervals, other.effective_intervals)
      @negated = false
      self
    end

    def case_fold_simple : self
      @intervals = IntervalOps.case_fold_unicode(@intervals)
      normalize_full_domain_negation
      self
    end

    private def full_unicode_domain?(intervals : Array(Range(UInt32, UInt32))) : Bool
      intervals.size == 1 && intervals[0].begin == 0_u32 && intervals[0].end == 0x10FFFF_u32
    end

    protected def effective_intervals : Array(Range(UInt32, UInt32))
      negated? ? IntervalOps.invert(@intervals) : @intervals
    end

    private def normalize_full_domain_negation : Nil
      if negated? && full_unicode_domain?(@intervals)
        @negated = false
        @intervals = [] of Range(UInt32, UInt32)
      end
    end
  end

  # Look-around assertion
  class Look < Node
    enum Kind
      StartLF              # ^ in multi-line mode
      EndLF                # $ in multi-line mode
      StartCRLF            # ^ in multi-line CRLF mode
      EndCRLF              # $ in multi-line CRLF mode
      StartText            # \A
      EndText              # \z
      EndTextOptionalLF    # $ or \Z outside multi-line mode
      WordAscii            # \b with unicode disabled
      WordAsciiNegate      # \B with unicode disabled
      WordUnicode          # \b with unicode enabled
      WordUnicodeNegate    # \B with unicode enabled
      WordStartAscii       # \b{start} or \< with unicode disabled
      WordEndAscii         # \b{end} or \> with unicode disabled
      WordStartUnicode     # \b{start} or \< with unicode enabled
      WordEndUnicode       # \b{end} or \> with unicode enabled
      WordStartHalfAscii   # \b{start-half} with unicode disabled
      WordEndHalfAscii     # \b{end-half} with unicode disabled
      WordStartHalfUnicode # \b{start-half} with unicode enabled
      WordEndHalfUnicode   # \b{end-half} with unicode enabled
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
    getter min : UInt32
    getter max : UInt32?
    getter? greedy : Bool

    def initialize(@sub : Node, @min : UInt32, @max : UInt32?, greedy : Bool = true)
      @greedy = greedy
    end

    def complexity : Int32
      complexity = min.to_u64 * sub.complexity.to_u64
      complexity > Int32::MAX ? Int32::MAX : complexity.to_i32
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
      min == 0_u32 || sub.can_match_empty?
    end
  end

  # Capture group
  class Capture < Node
    getter sub : Node
    getter index : Int32
    getter name : String?

    def initialize(@sub : Node, @index : Int32, @name : String? = nil)
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
