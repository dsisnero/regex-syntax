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
      Regex::Syntax::Hir::Hir.concat(nodes).node
    when CharClass
      ranges = case_fold_ascii_ranges(node.intervals)
      CharClass.new(node.negated?, ranges)
    when UnicodeClass
      node
    when Concat
      Regex::Syntax::Hir::Hir.concat(node.children.map { |child| case_fold_ascii_node(child) }).node
    when Alternation
      Regex::Syntax::Hir::Hir.alternation(node.children.map { |child| case_fold_ascii_node(child) }).node
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
      Regex::Syntax::Hir::Hir.concat(node.children.map { |child| case_fold_unicode_node(child) }).node
    when Alternation
      Regex::Syntax::Hir::Hir.alternation(node.children.map { |child| case_fold_unicode_node(child) }).node
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
      if variants.size == 1
        nodes << Literal.new(char.to_s.to_slice)
      else
        nodes << UnicodeClass.new(false, variants.map { |code_point| code_point..code_point })
      end
    end
    return nodes.first if nodes.size == 1
    Regex::Syntax::Hir::Hir.concat(nodes).node
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

    def subs : Array(Node)
      [] of Node
    end
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

    def self.empty : self
      new(false, [] of Range(UInt8, UInt8))
    end

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

    def push(range : Range(UInt8, UInt8)) : self
      @intervals = IntervalOps.canonicalize(@intervals + [range])
      normalize_full_domain_negation
      self
    end

    def ranges : Array(Range(UInt8, UInt8))
      @intervals
    end

    def ascii? : Bool
      last = @intervals.last?
      last ? last.end <= 0x7F_u8 : true
    end

    def minimum_len : Int32?
      @intervals.empty? ? nil : 1
    end

    def maximum_len : Int32?
      @intervals.empty? ? nil : 1
    end

    def literal : Bytes?
      return nil unless @intervals.size == 1 && @intervals[0].begin == @intervals[0].end

      Bytes[@intervals[0].begin]
    end

    def to_unicode_class : UnicodeClass?
      return nil unless ascii?

      UnicodeClass.new(false, @intervals.map { |range| range.begin.to_u32..range.end.to_u32 })
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

    def try_case_fold_simple : self
      case_fold_simple
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

    def self.empty : self
      new(false, [] of Range(UInt32, UInt32))
    end

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

    def push(range : Range(UInt32, UInt32)) : self
      @intervals = IntervalOps.canonicalize(@intervals + [range])
      normalize_full_domain_negation
      self
    end

    def ranges : Array(Range(UInt32, UInt32))
      @intervals
    end

    def ascii? : Bool
      last = @intervals.last?
      last ? last.end <= 0x7F_u32 : true
    end

    def minimum_len : Int32?
      first = @intervals.first?
      first ? utf8_len(first.begin) : nil
    end

    def maximum_len : Int32?
      last = @intervals.last?
      last ? utf8_len(last.end) : nil
    end

    def literal : Bytes?
      return nil unless @intervals.size == 1 && @intervals[0].begin == @intervals[0].end

      char = @intervals[0].begin.chr
      string = char.to_s
      Bytes.new(string.bytesize) { |i| string.to_slice[i] }
    end

    def to_byte_class : CharClass?
      return nil unless ascii?

      CharClass.new(false, @intervals.map { |range| range.begin.to_u8..range.end.to_u8 })
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

    def try_case_fold_simple : self
      case_fold_simple
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

    private def utf8_len(codepoint : UInt32) : Int32
      return 1 if codepoint <= 0x7F_u32
      return 2 if codepoint <= 0x7FF_u32
      return 3 if codepoint <= 0xFFFF_u32

      4
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

      def reversed : Kind
        case self
        when StartText
          EndText
        when EndText, EndTextOptionalLF
          StartText
        when StartLF
          EndLF
        when EndLF
          StartLF
        when StartCRLF
          EndCRLF
        when EndCRLF
          StartCRLF
        when WordAscii, WordAsciiNegate, WordUnicode, WordUnicodeNegate
          self
        when WordStartAscii
          WordEndAscii
        when WordEndAscii
          WordStartAscii
        when WordStartUnicode
          WordEndUnicode
        when WordEndUnicode
          WordStartUnicode
        when WordStartHalfAscii
          WordEndHalfAscii
        when WordEndHalfAscii
          WordStartHalfAscii
        when WordStartHalfUnicode
          WordEndHalfUnicode
        when WordEndHalfUnicode
          WordStartHalfUnicode
        else
          raise "unreachable look kind: #{self}"
        end
      end

      def as_repr : UInt32
        LookSet.bit_for(self)
      end

      def self.from_repr(repr : UInt32) : Kind?
        case repr
        when 0b00_0000_0000_0000_0001_u32 then StartText
        when 0b00_0000_0000_0000_0010_u32 then EndText
        when 0b00_0000_0000_0000_0100_u32 then StartLF
        when 0b00_0000_0000_0000_1000_u32 then EndLF
        when 0b00_0000_0000_0001_0000_u32 then StartCRLF
        when 0b00_0000_0000_0010_0000_u32 then EndCRLF
        when 0b00_0000_0000_0100_0000_u32 then WordAscii
        when 0b00_0000_0000_1000_0000_u32 then WordAsciiNegate
        when 0b00_0000_0001_0000_0000_u32 then WordUnicode
        when 0b00_0000_0010_0000_0000_u32 then WordUnicodeNegate
        when 0b00_0000_0100_0000_0000_u32 then WordStartAscii
        when 0b00_0000_1000_0000_0000_u32 then WordEndAscii
        when 0b00_0001_0000_0000_0000_u32 then WordStartUnicode
        when 0b00_0010_0000_0000_0000_u32 then WordEndUnicode
        when 0b00_0100_0000_0000_0000_u32 then WordStartHalfAscii
        when 0b00_1000_0000_0000_0000_u32 then WordEndHalfAscii
        when 0b01_0000_0000_0000_0000_u32 then WordStartHalfUnicode
        when 0b10_0000_0000_0000_0000_u32 then WordEndHalfUnicode
        else
          nil
        end
      end

      def as_char : Char
        LookSet.display_char(self)
      end
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

    def self.absolute_start?(kind : Kind) : Bool
      kind == Kind::StartText
    end

    def self.absolute_end?(kind : Kind) : Bool
      kind == Kind::EndText || kind == Kind::EndTextOptionalLF
    end
  end

  class LookSet
    include Enumerable(Look::Kind)

    getter bits : UInt32

    def initialize(@bits : UInt32 = 0_u32)
    end

    def self.empty : self
      new
    end

    def self.singleton(kind : Look::Kind) : self
      new(bit_for(kind))
    end

    def self.full : self
      bits = 0_u32
      ordered_kinds.each do |kind|
        bits |= bit_for(kind)
      end
      new(bits)
    end

    def empty? : Bool
      @bits == 0_u32
    end

    def len : Int32
      count = 0
      each { count += 1 }
      count
    end

    def contains(kind : Look::Kind) : Bool
      (@bits & self.class.bit_for(kind)) != 0_u32
    end

    def contains_anchor : Bool
      contains_anchor_haystack || contains_anchor_line
    end

    def contains_anchor_haystack : Bool
      contains(Look::Kind::StartText) || contains(Look::Kind::EndText)
    end

    def contains_anchor_line : Bool
      contains(Look::Kind::StartLF) ||
        contains(Look::Kind::EndLF) ||
        contains(Look::Kind::StartCRLF) ||
        contains(Look::Kind::EndCRLF)
    end

    def contains_anchor_lf : Bool
      contains(Look::Kind::StartLF) || contains(Look::Kind::EndLF)
    end

    def contains_anchor_crlf : Bool
      contains(Look::Kind::StartCRLF) || contains(Look::Kind::EndCRLF)
    end

    def contains_word : Bool
      contains_word_unicode || contains_word_ascii
    end

    def contains_word_unicode : Bool
      contains(Look::Kind::WordUnicode) ||
        contains(Look::Kind::WordUnicodeNegate) ||
        contains(Look::Kind::WordStartUnicode) ||
        contains(Look::Kind::WordEndUnicode) ||
        contains(Look::Kind::WordStartHalfUnicode) ||
        contains(Look::Kind::WordEndHalfUnicode)
    end

    def contains_word_ascii : Bool
      contains(Look::Kind::WordAscii) ||
        contains(Look::Kind::WordAsciiNegate) ||
        contains(Look::Kind::WordStartAscii) ||
        contains(Look::Kind::WordEndAscii) ||
        contains(Look::Kind::WordStartHalfAscii) ||
        contains(Look::Kind::WordEndHalfAscii)
    end

    def insert(kind : Look::Kind) : LookSet
      LookSet.new(@bits | self.class.bit_for(kind))
    end

    def insert!(kind : Look::Kind) : self
      @bits |= self.class.bit_for(kind)
      self
    end

    def remove(kind : Look::Kind) : LookSet
      LookSet.new(@bits & ~self.class.bit_for(kind))
    end

    def remove!(kind : Look::Kind) : self
      @bits &= ~self.class.bit_for(kind)
      self
    end

    def subtract(other : LookSet) : LookSet
      LookSet.new(@bits & ~other.bits)
    end

    def subtract!(other : LookSet) : self
      @bits &= ~other.bits
      self
    end

    def union(other : LookSet) : LookSet
      LookSet.new(@bits | other.bits)
    end

    def union!(other : LookSet) : self
      @bits |= other.bits
      self
    end

    def intersect(other : LookSet) : LookSet
      LookSet.new(@bits & other.bits)
    end

    def intersect!(other : LookSet) : self
      @bits &= other.bits
      self
    end

    def self.read_repr(slice : Bytes) : LookSet
      raise IndexError.new if slice.size < 4

      LookSet.new(IO::ByteFormat::SystemEndian.decode(UInt32, slice[0, 4]))
    end

    def write_repr(slice : Bytes) : Nil
      raise IndexError.new if slice.size < 4

      IO::ByteFormat::SystemEndian.encode(@bits, slice[0, 4])
    end

    def each(& : Look::Kind ->) : Nil
      self.class.ordered_kinds.each do |kind|
        yield kind if contains(kind)
      end
    end

    def inspect(io : IO) : Nil
      if empty?
        io << "∅"
        return
      end

      each do |kind|
        io << self.class.display_char(kind)
      end
    end

    def ==(other : LookSet) : Bool
      @bits == other.bits
    end

    def self.bit_for(kind : Look::Kind) : UInt32
      index = case kind
              when Look::Kind::StartText
                0
              when Look::Kind::EndText, Look::Kind::EndTextOptionalLF
                1
              when Look::Kind::StartLF
                2
              when Look::Kind::EndLF
                3
              when Look::Kind::StartCRLF
                4
              when Look::Kind::EndCRLF
                5
              when Look::Kind::WordAscii
                6
              when Look::Kind::WordAsciiNegate
                7
              when Look::Kind::WordUnicode
                8
              when Look::Kind::WordUnicodeNegate
                9
              when Look::Kind::WordStartAscii
                10
              when Look::Kind::WordEndAscii
                11
              when Look::Kind::WordStartUnicode
                12
              when Look::Kind::WordEndUnicode
                13
              when Look::Kind::WordStartHalfAscii
                14
              when Look::Kind::WordEndHalfAscii
                15
              when Look::Kind::WordStartHalfUnicode
                16
              when Look::Kind::WordEndHalfUnicode
                17
              else
                raise "unreachable look kind: #{kind}"
              end
      1_u32 << index
    end

    protected def self.ordered_kinds : Array(Look::Kind)
      [
        Look::Kind::StartText,
        Look::Kind::EndText,
        Look::Kind::StartLF,
        Look::Kind::EndLF,
        Look::Kind::StartCRLF,
        Look::Kind::EndCRLF,
        Look::Kind::WordAscii,
        Look::Kind::WordAsciiNegate,
        Look::Kind::WordUnicode,
        Look::Kind::WordUnicodeNegate,
        Look::Kind::WordStartAscii,
        Look::Kind::WordEndAscii,
        Look::Kind::WordStartUnicode,
        Look::Kind::WordEndUnicode,
        Look::Kind::WordStartHalfAscii,
        Look::Kind::WordEndHalfAscii,
        Look::Kind::WordStartHalfUnicode,
        Look::Kind::WordEndHalfUnicode,
      ]
    end

    def self.display_char(kind : Look::Kind) : Char
      case kind
      when Look::Kind::StartText
        'A'
      when Look::Kind::EndText, Look::Kind::EndTextOptionalLF
        'z'
      when Look::Kind::StartLF
        '^'
      when Look::Kind::EndLF
        '$'
      when Look::Kind::StartCRLF
        'r'
      when Look::Kind::EndCRLF
        'R'
      when Look::Kind::WordAscii
        'b'
      when Look::Kind::WordAsciiNegate
        'B'
      when Look::Kind::WordUnicode
        '𝛃'
      when Look::Kind::WordUnicodeNegate
        '𝚩'
      when Look::Kind::WordStartAscii
        '<'
      when Look::Kind::WordEndAscii
        '>'
      when Look::Kind::WordStartUnicode
        '〈'
      when Look::Kind::WordEndUnicode
        '〉'
      when Look::Kind::WordStartHalfAscii
        '◁'
      when Look::Kind::WordEndHalfAscii
        '▷'
      when Look::Kind::WordStartHalfUnicode
        '◀'
      when Look::Kind::WordEndHalfUnicode
        '▶'
      else
        raise "unreachable look kind: #{kind}"
      end
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

    def subs : Array(Node)
      [sub] of Node
    end

    def with(sub : Node) : Repetition
      Repetition.new(sub, min, max, greedy: greedy?)
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

    def subs : Array(Node)
      [sub] of Node
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

    def subs : Array(Node)
      children
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

    def subs : Array(Node)
      children
    end
  end

  struct Properties
    @hir : Hir?
    @look_set : LookSet
    @look_set_prefix : LookSet
    @look_set_prefix_any : LookSet
    @look_set_suffix : LookSet
    @look_set_suffix_any : LookSet
    @utf8 : Bool
    @explicit_captures_len : Int32
    @static_explicit_captures_len : Int32?
    @minimum_len : Int32?
    @maximum_len : Int32?
    @literal : Bool
    @alternation_literal : Bool

    getter hir : Hir?

    def initialize(hir : Hir)
      @hir = hir
      @look_set = hir.look_set
      @look_set_prefix = hir.look_set_prefix
      @look_set_prefix_any = hir.look_set_prefix_any
      @look_set_suffix = hir.look_set_suffix
      @look_set_suffix_any = hir.look_set_suffix_any
      @utf8 = hir.utf8?
      @explicit_captures_len = hir.explicit_captures_len
      @static_explicit_captures_len = hir.static_explicit_captures_len
      @minimum_len = hir.minimum_len
      @maximum_len = hir.maximum_len
      @literal = hir.literal?
      @alternation_literal = hir.alternation_literal?
    end

    def self.union(props : Enumerable(Properties)) : self
      array = props.to_a
      fix = array.empty? ? LookSet.empty : LookSet.full
      static_len = array.empty? ? 0 : array.first.static_explicit_captures_len
      minimum_len = nil.as(Int32?)
      maximum_len = nil.as(Int32?)
      look_set = LookSet.empty
      look_set_prefix = fix
      look_set_suffix = fix
      look_set_prefix_any = LookSet.empty
      look_set_suffix_any = LookSet.empty
      utf8 = true
      explicit_captures_len = 0
      alternation_literal = true
      min_poisoned = false
      max_poisoned = false

      array.each do |prop|
        look_set = look_set.union(prop.look_set)
        look_set_prefix = look_set_prefix.intersect(prop.look_set_prefix)
        look_set_suffix = look_set_suffix.intersect(prop.look_set_suffix)
        look_set_prefix_any = look_set_prefix_any.union(prop.look_set_prefix_any)
        look_set_suffix_any = look_set_suffix_any.union(prop.look_set_suffix_any)
        utf8 &&= prop.utf8?
        explicit_captures_len = self.saturating_add(explicit_captures_len, prop.explicit_captures_len)
        static_len = nil if static_len != prop.static_explicit_captures_len
        alternation_literal &&= prop.literal?

        unless min_poisoned
          if child_min = prop.minimum_len
            minimum_len = child_min if minimum_len.nil? || child_min < minimum_len
          else
            minimum_len = nil
            min_poisoned = true
          end
        end

        unless max_poisoned
          if child_max = prop.maximum_len
            maximum_len = child_max if maximum_len.nil? || child_max > maximum_len
          else
            maximum_len = nil
            max_poisoned = true
          end
        end
      end

      new(
        look_set: look_set,
        look_set_prefix: look_set_prefix,
        look_set_prefix_any: look_set_prefix_any,
        look_set_suffix: look_set_suffix,
        look_set_suffix_any: look_set_suffix_any,
        utf8: utf8,
        explicit_captures_len: explicit_captures_len,
        static_explicit_captures_len: static_len,
        minimum_len: minimum_len,
        maximum_len: maximum_len,
        literal: false,
        alternation_literal: alternation_literal
      )
    end

    private def initialize(*,
                           look_set : LookSet,
                           look_set_prefix : LookSet,
                           look_set_prefix_any : LookSet,
                           look_set_suffix : LookSet,
                           look_set_suffix_any : LookSet,
                           utf8 : Bool,
                           explicit_captures_len : Int32,
                           static_explicit_captures_len : Int32?,
                           minimum_len : Int32?,
                           maximum_len : Int32?,
                           literal : Bool,
                           alternation_literal : Bool)
      @hir = nil
      @look_set = look_set
      @look_set_prefix = look_set_prefix
      @look_set_prefix_any = look_set_prefix_any
      @look_set_suffix = look_set_suffix
      @look_set_suffix_any = look_set_suffix_any
      @utf8 = utf8
      @explicit_captures_len = explicit_captures_len
      @static_explicit_captures_len = static_explicit_captures_len
      @minimum_len = minimum_len
      @maximum_len = maximum_len
      @literal = literal
      @alternation_literal = alternation_literal
    end

    def look_set : LookSet
      @look_set
    end

    def look_set_prefix : LookSet
      @look_set_prefix
    end

    def look_set_prefix_any : LookSet
      @look_set_prefix_any
    end

    def look_set_suffix : LookSet
      @look_set_suffix
    end

    def look_set_suffix_any : LookSet
      @look_set_suffix_any
    end

    def utf8? : Bool
      @utf8
    end

    def explicit_captures_len : Int32
      @explicit_captures_len
    end

    def static_explicit_captures_len : Int32?
      @static_explicit_captures_len
    end

    def minimum_len : Int32?
      @minimum_len
    end

    def maximum_len : Int32?
      @maximum_len
    end

    def literal? : Bool
      @literal
    end

    def alternation_literal? : Bool
      @alternation_literal
    end

    def memory_usage : Int32
      sizeof(self)
    end

    private def self.saturating_add(left : Int32, right : Int32) : Int32
      if left > Int32::MAX - right
        Int32::MAX
      else
        left + right
      end
    end
  end

  # High-level intermediate representation for a regular expression
  class Hir < Node
    getter node : Node

    def initialize(@node : Node)
    end

    def kind : Node
      @node
    end

    def into_kind : Node
      @node
    end

    def properties : Properties
      Properties.new(self)
    end

    # Create a dot expression
    def self.dot(dot : Dot) : Hir
      Hir.new(DotNode.new(dot))
    end

    def self.empty : Hir
      Hir.new(Empty.new)
    end

    def self.fail : Hir
      Hir.new(CharClass.new(false, [] of Range(UInt8, UInt8)))
    end

    # Create a literal expression
    def self.literal(bytes : Bytes) : Hir
      return empty if bytes.empty?

      Hir.new(Literal.new(bytes))
    end

    def self.look(kind : Look::Kind) : Hir
      Hir.new(Look.new(kind))
    end

    def self.capture(capture : Capture) : Hir
      Hir.new(capture)
    end

    def self.concat(children : Array(Node)) : Hir
      flattened = [] of Node
      children.each do |child|
        case child
        when Empty
        when Concat
          flattened.concat(child.children)
        else
          flattened << child
        end
      end
      flattened = merge_adjacent_literals(flattened)
      case flattened.size
      when 0
        Hir.new(Empty.new)
      when 1
        Hir.new(flattened.first)
      else
        Hir.new(Concat.new(flattened))
      end
    end

    def self.alternation(children : Array(Node)) : Hir
      return fail if children.empty?

      flattened = [] of Node
      children.each do |child|
        case child
        when Alternation
          flattened.concat(child.children)
        else
          flattened << child
        end
      end
      if flattened.all? { |child| child.is_a?(CharClass) || child.is_a?(UnicodeClass) }
        if merged = merge_class_alternation(flattened)
          return Hir.new(merged)
        end
      end
      case flattened.size
      when 0
        fail
      when 1
        Hir.new(flattened.first)
      else
        Hir.new(Alternation.new(flattened))
      end
    end

    def self.repetition(sub : Node, min : UInt32, max : UInt32?, greedy : Bool = true) : Hir
      if zero_width_assertion_only?(sub)
        min = Math.min(min, 1_u32)
        max = max ? Math.min(max, 1_u32) : 1_u32
      end

      if min == 0_u32 && max == 0_u32
        Hir.new(Empty.new)
      elsif min == 1_u32 && max == 1_u32
        Hir.new(sub)
      else
        Hir.new(Repetition.new(sub, min, max, greedy: greedy))
      end
    end

    def self.repetition(rep : Repetition) : Hir
      repetition(rep.sub, rep.min, rep.max, greedy: rep.greedy?)
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

    def explicit_captures_len : Int32
      self.class.capture_count(node)
    end

    def static_explicit_captures_len : Int32?
      self.class.static_capture_count(node)
    end

    def minimum_len : Int32?
      lengths = self.class.lengths(node)
      lengths[:possible] ? lengths[:min] : nil
    end

    def maximum_len : Int32?
      lengths = self.class.lengths(node)
      return nil unless lengths[:possible]

      lengths[:max]
    end

    def utf8? : Bool
      self.class.utf8_valid?(node)
    end

    def look_set : LookSet
      self.class.analysis(node)[:look_set]
    end

    def look_set_prefix : LookSet
      self.class.analysis(node)[:look_set_prefix]
    end

    def look_set_prefix_any : LookSet
      self.class.analysis(node)[:look_set_prefix_any]
    end

    def look_set_suffix : LookSet
      self.class.analysis(node)[:look_set_suffix]
    end

    def look_set_suffix_any : LookSet
      self.class.analysis(node)[:look_set_suffix_any]
    end

    def literal? : Bool
      self.class.analysis(node)[:literal]
    end

    def alternation_literal? : Bool
      self.class.analysis(node)[:alternation_literal]
    end

    def all_assertions? : Bool
      !look_set.empty? && minimum_len == 0
    end

    private def self.merge_adjacent_literals(children : Array(Node)) : Array(Node)
      merged = [] of Node
      buffer = [] of UInt8
      flush = -> do
        unless buffer.empty?
          merged << Literal.new(Bytes.new(buffer.size) { |i| buffer[i] })
          buffer.clear
        end
      end

      children.each do |child|
        case child
        when Literal
          child.bytes.each { |byte| buffer << byte }
        else
          flush.call
          merged << child
        end
      end
      flush.call
      merged
    end

    private def self.merge_class_alternation(children : Array(Node)) : Node?
      unicode_classes = [] of UnicodeClass
      byte_classes = [] of CharClass

      children.each do |child|
        case child
        when UnicodeClass
          unicode_classes << child
        when CharClass
          byte_classes << child
        else
          return nil
        end
      end

      if unicode_classes.empty?
        merged = CharClass.empty
        byte_classes.each { |klass| merged.union(klass) }
        return merged
      end

      converted_byte_classes = byte_classes.compact_map(&.to_unicode_class)
      return nil unless converted_byte_classes.size == byte_classes.size

      merged = UnicodeClass.empty
      unicode_classes.each { |klass| merged.union(klass) }
      converted_byte_classes.each { |klass| merged.union(klass) }
      merged
    end

    def self.analysis(node : Node) : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      case node
      when Empty
        empty_analysis
      when Literal
        literal_analysis(node.bytes)
      when CharClass
        class_analysis(node.negated?, node.intervals)
      when UnicodeClass
        class_analysis(node.negated?, node.intervals)
      when DotNode
        non_literal_analysis
      when Look
        look = LookSet.singleton(node.kind)
        {
          look_set:            look,
          look_set_prefix:     look,
          look_set_suffix:     look,
          look_set_prefix_any: look,
          look_set_suffix_any: look,
          literal:             false,
          alternation_literal: false,
        }
      when Repetition
        repetition_analysis(node)
      when Capture
        capture_analysis(node)
      when Concat
        concat_analysis(node.children)
      when Alternation
        alternation_analysis(node.children)
      else
        non_literal_analysis
      end
    end

    def self.capture_count(node : Node) : Int32
      case node
      when Capture
        1 + capture_count(node.sub)
      when Concat
        node.children.sum { |child| capture_count(child) }
      when Alternation
        node.children.sum { |child| capture_count(child) }
      when Repetition
        capture_count(node.sub)
      else
        0
      end
    end

    private def self.empty_analysis : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      {
        look_set:            LookSet.empty,
        look_set_prefix:     LookSet.empty,
        look_set_suffix:     LookSet.empty,
        look_set_prefix_any: LookSet.empty,
        look_set_suffix_any: LookSet.empty,
        literal:             false,
        alternation_literal: false,
      }
    end

    private def self.literal_analysis(bytes : Bytes) : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      empty = LookSet.empty
      {
        look_set:            empty,
        look_set_prefix:     empty,
        look_set_suffix:     empty,
        look_set_prefix_any: empty,
        look_set_suffix_any: empty,
        literal:             !bytes.empty?,
        alternation_literal: !bytes.empty?,
      }
    end

    private def self.class_analysis(negated : Bool, intervals) : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      empty = LookSet.empty
      singleton = !negated && intervals.size == 1 && intervals[0].begin == intervals[0].end
      {
        look_set:            empty,
        look_set_prefix:     empty,
        look_set_suffix:     empty,
        look_set_prefix_any: empty,
        look_set_suffix_any: empty,
        literal:             singleton,
        alternation_literal: singleton,
      }
    end

    private def self.non_literal_analysis : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      empty_analysis
    end

    private def self.repetition_analysis(node : Repetition) : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      child = analysis(node.sub)
      {
        look_set:            child[:look_set],
        look_set_prefix:     node.min > 0_u32 ? child[:look_set_prefix] : LookSet.empty,
        look_set_suffix:     node.min > 0_u32 ? child[:look_set_suffix] : LookSet.empty,
        look_set_prefix_any: child[:look_set_prefix_any],
        look_set_suffix_any: child[:look_set_suffix_any],
        literal:             false,
        alternation_literal: false,
      }
    end

    private def self.capture_analysis(node : Capture) : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      child = analysis(node.sub)
      {
        look_set:            child[:look_set],
        look_set_prefix:     child[:look_set_prefix],
        look_set_suffix:     child[:look_set_suffix],
        look_set_prefix_any: child[:look_set_prefix_any],
        look_set_suffix_any: child[:look_set_suffix_any],
        literal:             false,
        alternation_literal: false,
      }
    end

    private def self.concat_analysis(children : Array(Node)) : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      look_set = LookSet.empty
      look_set_prefix = LookSet.empty
      look_set_suffix = LookSet.empty
      look_set_prefix_any = LookSet.empty
      look_set_suffix_any = LookSet.empty
      literal = true
      alternation_literal = true

      analyses = children.map { |child| analysis(child) }
      analyses.each do |child|
        look_set = look_set.union(child[:look_set])
        literal &&= child[:literal]
        alternation_literal &&= child[:alternation_literal]
      end

      children.each_with_index do |child, index|
        child_analysis = analyses[index]
        look_set_prefix = look_set_prefix.union(child_analysis[:look_set_prefix])
        look_set_prefix_any = look_set_prefix_any.union(child_analysis[:look_set_prefix_any])
        child_lengths = lengths(child)
        child_max = child_lengths[:max]
        break if child_max.nil? || child_max > 0
      end

      (children.size - 1).downto(0) do |index|
        child = children[index]
        child_analysis = analyses[index]
        look_set_suffix = look_set_suffix.union(child_analysis[:look_set_suffix])
        look_set_suffix_any = look_set_suffix_any.union(child_analysis[:look_set_suffix_any])
        child_lengths = lengths(child)
        child_max = child_lengths[:max]
        break if child_max.nil? || child_max > 0
      end

      {
        look_set:            look_set,
        look_set_prefix:     look_set_prefix,
        look_set_suffix:     look_set_suffix,
        look_set_prefix_any: look_set_prefix_any,
        look_set_suffix_any: look_set_suffix_any,
        literal:             literal,
        alternation_literal: alternation_literal,
      }
    end

    private def self.alternation_analysis(children : Array(Node)) : NamedTuple(
      look_set: LookSet,
      look_set_prefix: LookSet,
      look_set_suffix: LookSet,
      look_set_prefix_any: LookSet,
      look_set_suffix_any: LookSet,
      literal: Bool,
      alternation_literal: Bool)
      analyses = children.map { |child| analysis(child) }
      look_set = LookSet.empty
      look_set_prefix_any = LookSet.empty
      look_set_suffix_any = LookSet.empty
      look_set_prefix = analyses.empty? ? LookSet.empty : analyses.first[:look_set_prefix]
      look_set_suffix = analyses.empty? ? LookSet.empty : analyses.first[:look_set_suffix]
      alternation_literal = !analyses.empty?

      analyses.each do |child|
        look_set = look_set.union(child[:look_set])
        look_set_prefix = look_set_prefix.intersect(child[:look_set_prefix])
        look_set_suffix = look_set_suffix.intersect(child[:look_set_suffix])
        look_set_prefix_any = look_set_prefix_any.union(child[:look_set_prefix_any])
        look_set_suffix_any = look_set_suffix_any.union(child[:look_set_suffix_any])
        alternation_literal &&= child[:literal]
      end

      if alternation_literal && children.all? { |child| single_literal_atom?(child) }
        alternation_literal = false
      end

      {
        look_set:            look_set,
        look_set_prefix:     look_set_prefix,
        look_set_suffix:     look_set_suffix,
        look_set_prefix_any: look_set_prefix_any,
        look_set_suffix_any: look_set_suffix_any,
        literal:             false,
        alternation_literal: alternation_literal,
      }
    end

    def self.static_capture_count(node : Node) : Int32?
      case node
      when Empty, Literal, CharClass, UnicodeClass, DotNode, Look
        0
      when Capture
        child = static_capture_count(node.sub)
        child.nil? ? nil : child + 1
      when Concat
        total = 0
        node.children.each do |part|
          part_total = static_capture_count(part)
          return nil unless part_total

          total += part_total
        end
        total
      when Alternation
        counts = [] of Int32
        node.children.each do |branch|
          branch_lengths = lengths(branch)
          next unless branch_lengths[:possible]

          branch_count = static_capture_count(branch)
          return nil unless branch_count

          counts << branch_count
        end
        return 0 if counts.empty?
        first = counts.first
        counts.all? { |count| count == first } ? first : nil
      when Repetition
        if node.min == 0_u32
          if node.max == 0_u32
            0
          else
            child = static_capture_count(node.sub)
            child == 0 ? 0 : nil
          end
        else
          static_capture_count(node.sub)
        end
      else
        nil
      end
    end

    def self.lengths(node : Node) : NamedTuple(possible: Bool, min: Int32, max: Int32?)
      case node
      when Empty, Look
        {possible: true, min: 0, max: 0}
      when Literal
        size = node.bytes.size.to_i32
        {possible: true, min: size, max: size}
      when DotNode
        case node.kind
        when Dot::AnyChar, Dot::AnyCharExceptLF, Dot::AnyCharExceptCRLF
          {possible: true, min: 1, max: 4}
        else
          {possible: true, min: 1, max: 1}
        end
      when CharClass
        intervals = node.negated? ? IntervalOps.invert(node.intervals) : node.intervals
        intervals.empty? ? {possible: false, min: 0, max: nil} : {possible: true, min: 1, max: 1}
      when UnicodeClass
        intervals = node.negated? ? IntervalOps.invert(node.intervals) : node.intervals
        return {possible: false, min: 0, max: nil} if intervals.empty?

        min_len = 4
        max_len = 1
        intervals.each do |range|
          min_len = Math.min(min_len, utf8_len(range.begin))
          max_len = Math.max(max_len, utf8_len(range.end))
        end
        {possible: true, min: min_len, max: max_len}
      when Capture
        lengths(node.sub)
      when Concat
        min = 0
        max = 0
        max_unbounded = false
        node.children.each do |part|
          part_lengths = lengths(part)
          return {possible: false, min: 0, max: nil} unless part_lengths[:possible]

          min = saturating_add(min, part_lengths[:min])
          part_max = part_lengths[:max]
          if max_unbounded || part_max.nil?
            max_unbounded = true
          else
            max = saturating_add(max, part_max)
          end
        end
        {possible: true, min: min, max: max_unbounded ? nil : max}
      when Alternation
        alt_min : Int32? = nil
        alt_max : Int32? = nil
        possible = false
        unbounded = false
        node.children.each do |branch|
          branch_lengths = lengths(branch)
          next unless branch_lengths[:possible]

          possible = true
          if current_min = alt_min
            alt_min = Math.min(current_min, branch_lengths[:min])
          else
            alt_min = branch_lengths[:min]
          end
          branch_max = branch_lengths[:max]
          if branch_max.nil?
            unbounded = true
          else
            if current_max = alt_max
              alt_max = Math.max(current_max, branch_max)
            else
              alt_max = branch_max
            end
          end
        end
        return {possible: false, min: 0, max: nil} unless possible

        {possible: true, min: alt_min || 0, max: unbounded ? nil : alt_max}
      when Repetition
        child_lengths = lengths(node.sub)
        if !child_lengths[:possible]
          return node.min == 0_u32 ? {possible: true, min: 0, max: 0} : {possible: false, min: 0, max: nil}
        end

        min = node.min == 0_u32 ? 0 : saturating_mul(child_lengths[:min], node.min)
        child_max = child_lengths[:max]
        max = if child_max == 0
                0
              elsif node.max.nil? || child_max.nil?
                nil
              else
                saturating_mul(child_max, node.max || 0_u32)
              end
        {possible: true, min: min, max: max}
      else
        {possible: false, min: 0, max: nil}
      end
    end

    def self.utf8_valid?(node : Node) : Bool
      case node
      when Empty, Look
        true
      when Literal
        valid_utf8_bytes?(node.bytes)
      when DotNode
        !{Dot::AnyByte, Dot::AnyByteExceptLF, Dot::AnyByteExceptCRLF}.includes?(node.kind)
      when CharClass
        intervals = node.negated? ? IntervalOps.invert(node.intervals) : node.intervals
        intervals.all? { |range| range.end <= 0x7F_u8 }
      when UnicodeClass
        true
      when Capture
        utf8_valid?(node.sub)
      when Concat
        node.children.all? { |child| utf8_valid?(child) }
      when Alternation
        node.children.all? { |child| utf8_valid?(child) }
      when Repetition
        utf8_valid?(node.sub)
      else
        false
      end
    end

    private def self.saturating_add(left : Int32, right : Int32) : Int32
      sum = left.to_i64 + right.to_i64
      sum > Int32::MAX ? Int32::MAX : sum.to_i32
    end

    private def self.saturating_mul(left : Int32, right : UInt32) : Int32
      product = left.to_i64 * right.to_i64
      product > Int32::MAX ? Int32::MAX : product.to_i32
    end

    private def self.utf8_len(codepoint : UInt32) : Int32
      return 1 if codepoint <= 0x7F_u32
      return 2 if codepoint <= 0x7FF_u32
      return 3 if codepoint <= 0xFFFF_u32

      4
    end

    private def self.valid_utf8_bytes?(bytes : Bytes) : Bool
      i = 0
      while i < bytes.size
        byte = bytes[i]
        if byte <= 0x7F_u8
          i += 1
        elsif byte >= 0xC2_u8 && byte <= 0xDF_u8
          return false unless continuation_byte?(bytes, i + 1)
          i += 2
        elsif byte == 0xE0_u8
          return false unless bounded_continuation_byte?(bytes, i + 1, 0xA0_u8, 0xBF_u8)
          return false unless continuation_byte?(bytes, i + 2)
          i += 3
        elsif (0xE1_u8..0xEC_u8).includes?(byte) || (0xEE_u8..0xEF_u8).includes?(byte)
          return false unless continuation_byte?(bytes, i + 1)
          return false unless continuation_byte?(bytes, i + 2)
          i += 3
        elsif byte == 0xED_u8
          return false unless bounded_continuation_byte?(bytes, i + 1, 0x80_u8, 0x9F_u8)
          return false unless continuation_byte?(bytes, i + 2)
          i += 3
        elsif byte == 0xF0_u8
          return false unless bounded_continuation_byte?(bytes, i + 1, 0x90_u8, 0xBF_u8)
          return false unless continuation_byte?(bytes, i + 2)
          return false unless continuation_byte?(bytes, i + 3)
          i += 4
        elsif (0xF1_u8..0xF3_u8).includes?(byte)
          return false unless continuation_byte?(bytes, i + 1)
          return false unless continuation_byte?(bytes, i + 2)
          return false unless continuation_byte?(bytes, i + 3)
          i += 4
        elsif byte == 0xF4_u8
          return false unless bounded_continuation_byte?(bytes, i + 1, 0x80_u8, 0x8F_u8)
          return false unless continuation_byte?(bytes, i + 2)
          return false unless continuation_byte?(bytes, i + 3)
          i += 4
        else
          return false
        end
      end
      true
    end

    private def self.continuation_byte?(bytes : Bytes, index : Int32) : Bool
      return false unless index < bytes.size

      byte = bytes[index]
      byte >= 0x80_u8 && byte <= 0xBF_u8
    end

    private def self.bounded_continuation_byte?(bytes : Bytes, index : Int32, min : UInt8, max : UInt8) : Bool
      return false unless index < bytes.size

      byte = bytes[index]
      byte >= min && byte <= max
    end

    private def self.zero_width_assertion_only?(node : Node) : Bool
      case node
      when Look
        true
      when Capture
        zero_width_assertion_only?(node.sub)
      when Concat
        node.children.all? { |child| zero_width_assertion_only?(child) }
      when Alternation
        node.children.all? { |child| zero_width_assertion_only?(child) }
      when Repetition
        zero_width_assertion_only?(node.sub)
      else
        false
      end
    end

    private def self.single_literal_atom?(node : Node) : Bool
      case node
      when Literal
        node.bytes.size == 1
      when CharClass
        !node.negated? && node.intervals.size == 1 && node.intervals[0].begin == node.intervals[0].end
      when UnicodeClass
        !node.negated? && node.intervals.size == 1 && node.intervals[0].begin == node.intervals[0].end
      else
        false
      end
    end
  end
end
