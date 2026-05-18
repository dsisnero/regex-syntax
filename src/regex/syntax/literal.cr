module Regex::Syntax::Hir::LiteralExtraction
  enum ExtractKind
    Prefix
    Suffix

    def prefix? : Bool
      self == Prefix
    end

    def suffix? : Bool
      self == Suffix
    end
  end

  class Literal
    getter bytes : Array(UInt8)
    getter? exact : Bool

    def self.exact(bytes : Enumerable(UInt8)) : self
      new(bytes.to_a, exact: true)
    end

    def self.inexact(bytes : Enumerable(UInt8)) : self
      new(bytes.to_a, exact: false)
    end

    def self.exact(string : String) : self
      exact(string.to_slice)
    end

    def self.inexact(string : String) : self
      inexact(string.to_slice)
    end

    def self.from_byte(byte : UInt8) : self
      exact([byte])
    end

    def self.from_char(char : Char) : self
      exact(char.to_s.to_slice)
    end

    def initialize(@bytes : Array(UInt8), *, @exact : Bool = true)
    end

    def ==(other : self) : Bool
      exact? == other.exact? && bytes == other.bytes
    end

    def clone : self
      self.class.new(bytes.dup, exact: exact?)
    end

    def len : Int32
      bytes.size
    end

    def empty? : Bool
      bytes.empty?
    end

    def make_inexact : Nil
      @exact = false
    end

    def reverse : Nil
      @bytes.reverse!
    end

    def extend(other : Literal) : Nil
      return unless exact?

      @bytes.concat(other.bytes)
    end

    def keep_first_bytes(len : Int32) : Nil
      return if len >= self.len

      make_inexact
      @bytes = @bytes.first(len)
    end

    def keep_last_bytes(len : Int32) : Nil
      return if len >= self.len

      make_inexact
      @bytes = @bytes.last(len)
    end

    def poisonous? : Bool
      empty? || (len == 1 && Regex::Syntax::Hir::LiteralExtraction.rank(bytes[0]) >= 250_u8)
    end
  end

  class Seq
    getter literals : Array(Literal)?

    def self.empty : self
      new([] of Literal)
    end

    def self.infinite : self
      new(nil)
    end

    def self.singleton(literal : Literal) : self
      new([literal])
    end

    def initialize(@literals : Array(Literal)?)
    end

    def ==(other : self) : Bool
      literals == other.literals
    end

    def clone : self
      self.class.new(literals.try(&.map(&.clone)))
    end

    def push(literal : Literal) : Nil
      return unless lits = @literals
      return if lits.last? == literal

      lits << literal
    end

    def make_inexact : Nil
      return unless lits = @literals

      lits.each(&.make_inexact)
    end

    def make_infinite : Nil
      @literals = nil
    end

    def cross_forward(other : Seq) : Nil
      pair = cross_preamble(other)
      return unless pair
      lits1, lits2 = pair

      self_literals = lits1.map(&.clone)
      new_literals = [] of Literal
      self_literals.each do |self_literal|
        unless self_literal.exact?
          new_literals << self_literal
          next
        end

        lits2.each do |other_literal|
          combined = self_literal.clone
          combined.extend(other_literal)
          combined.make_inexact unless other_literal.exact?
          new_literals << combined
        end
      end
      @literals = new_literals
      other.clear_finite_literals
      dedup
    end

    def cross_reverse(other : Seq) : Nil
      pair = cross_preamble(other)
      return unless pair
      lits1, lits2 = pair

      self_literals = lits1.map(&.clone)
      new_literals = [] of Literal
      lits2.each_with_index do |other_literal, i|
        self_literals.each do |self_literal|
          unless self_literal.exact?
            new_literals << self_literal.clone if i == 0
            next
          end

          combined = other_literal.clone
          combined.extend(self_literal)
          combined.make_inexact unless other_literal.exact?
          new_literals << combined
        end
      end
      @literals = new_literals
      other.clear_finite_literals
      dedup
    end

    def union(other : Seq) : Nil
      unless other.finite?
        make_infinite
        return
      end
      return unless lits1 = @literals
      return unless lits2 = other.literals

      lits1.concat(lits2.map(&.clone))
      other.clear_finite_literals
      dedup
    end

    def dedup : Nil
      return unless lits = @literals

      deduped = [] of Literal
      lits.each do |literal|
        if prev = deduped.last?
          if prev.bytes == literal.bytes
            prev.make_inexact if prev.exact? != literal.exact?
            next
          end
        end
        deduped << literal
      end
      @literals = deduped
    end

    def sort : Nil
      return unless lits = @literals

      lits.sort_by!(&.bytes)
    end

    def reverse_literals : Nil
      return unless lits = @literals

      lits.each(&.reverse)
    end

    def minimize_by_preference : Nil
      return unless lits = @literals

      PreferenceTrie.minimize(lits, keep_exact: false)
    end

    def keep_first_bytes(len : Int32) : Nil
      return unless lits = @literals

      lits.each(&.keep_first_bytes(len))
    end

    def keep_last_bytes(len : Int32) : Nil
      return unless lits = @literals

      lits.each(&.keep_last_bytes(len))
    end

    def finite? : Bool
      !@literals.nil?
    end

    def empty? : Bool
      len == 0
    end

    def len : Int32?
      @literals.try(&.size)
    end

    def exact? : Bool
      @literals.try(&.all?(&.exact?)) || false
    end

    def inexact? : Bool
      if lits = @literals
        lits.all? { |literal| !literal.exact? }
      else
        true
      end
    end

    def max_union_len(other : Seq) : Int32?
      len1 = len
      len2 = other.len
      return nil unless len1 && len2

      len1 + len2
    end

    def max_cross_len(other : Seq) : Int32?
      len1 = len
      len2 = other.len
      return nil unless len1 && len2

      len1 * len2
    end

    def min_literal_len : Int32?
      @literals.try(&.min_of?(&.len))
    end

    def max_literal_len : Int32?
      @literals.try(&.max_of?(&.len))
    end

    def longest_common_prefix : Array(UInt8)?
      lits = @literals
      return nil unless lits
      return nil if lits.empty?

      base = lits.first.bytes
      len = base.size
      lits[1..].each do |literal|
        match_len = 0
        while match_len < len &&
              match_len < literal.bytes.size &&
              literal.bytes[match_len] == base[match_len]
          match_len += 1
        end
        len = match_len
        return [] of UInt8 if len == 0
      end
      base.first(len)
    end

    def longest_common_suffix : Array(UInt8)?
      lits = @literals
      return nil unless lits
      return nil if lits.empty?

      base = lits.first.bytes
      len = base.size
      lits[1..].each do |literal|
        match_len = 0
        while match_len < len &&
              match_len < literal.bytes.size &&
              literal.bytes[literal.bytes.size - 1 - match_len] == base[base.size - 1 - match_len]
          match_len += 1
        end
        len = match_len
        return [] of UInt8 if len == 0
      end
      base.last(len)
    end

    def optimize_for_prefix_by_preference : Nil
      optimize_by_preference(prefix: true)
    end

    def optimize_for_suffix_by_preference : Nil
      optimize_by_preference(prefix: false)
    end

    protected def clear_finite_literals : Nil
      @literals.try(&.clear)
    end

    private def cross_preamble(other : Seq) : {Array(Literal), Array(Literal)}?
      unless other.finite?
        if min_literal_len == 0
          make_infinite
        else
          make_inexact
        end
        return nil
      end

      unless lits1 = @literals
        other.clear_finite_literals
        return nil
      end

      lits2 = other.literals
      return nil unless lits2

      {lits1, lits2}
    end

    private def optimize_by_preference(*, prefix : Bool) : Nil
      original_length = len
      return unless original_length
      if min_literal_len == 0
        make_infinite
        return
      end

      minimize_exact_prefix_literals if prefix
      apply_common_affix_optimization(prefix, original_length)

      exact_backup = exact? ? clone : nil
      apply_shrinking_attempts(prefix)
      make_infinite_if_poisonous
      restore_exact_backup_if_better(exact_backup)
    end

    private def minimize_exact_prefix_literals : Nil
      return unless lits = @literals

      PreferenceTrie.minimize(lits, keep_exact: true)
    end

    private def apply_common_affix_optimization(prefix : Bool, original_length : Int32) : Nil
      fixed = prefix ? longest_common_prefix : longest_common_suffix
      return unless fixed

      if rare_short_prefix?(fixed, original_length, prefix)
        keep_first_bytes(1)
        dedup
        return
      end

      return unless use_common_affix?(fixed)

      if prefix
        keep_first_bytes(fixed.size)
      else
        keep_last_bytes(fixed.size)
      end
      dedup
    end

    private def rare_short_prefix?(fixed : Array(UInt8), original_length : Int32, prefix : Bool) : Bool
      prefix &&
        original_length > 1 &&
        fixed.size >= 1 &&
        fixed.size <= 3 &&
        Regex::Syntax::Hir::LiteralExtraction.rank(fixed[0]) < 200_u8
    end

    private def use_common_affix?(fixed : Array(UInt8)) : Bool
      current_length = len
      is_fast = exact? && !current_length.nil? && current_length <= 16
      fixed.size > 4 || (fixed.size > 1 && !is_fast)
    end

    private def apply_shrinking_attempts(prefix : Bool) : Nil
      attempts = [{5, 10}, {4, 10}, {3, 64}, {2, 64}, {1, 10}]
      attempts.each do |keep, limit|
        current_length = len
        break unless current_length
        break if current_length <= limit

        if prefix
          keep_first_bytes(keep)
          minimize_exact_prefix_literals
        else
          keep_last_bytes(keep)
        end
      end
    end

    private def make_infinite_if_poisonous : Nil
      return unless lits = @literals

      make_infinite if lits.any?(&.poisonous?)
    end

    private def restore_exact_backup_if_better(exact_backup : Seq?) : Nil
      return unless exact_backup

      unless finite?
        @literals = exact_backup.literals.try(&.map(&.clone))
        return
      end

      min_len = min_literal_len
      if min_len.nil? || min_len <= 2
        @literals = exact_backup.literals.try(&.map(&.clone))
        return
      end

      current_length = len
      if current_length.nil? || current_length > 64
        @literals = exact_backup.literals.try(&.map(&.clone))
      end
    end
  end

  private class PreferenceTrie
    @states = [] of State
    @matches = [] of Int32?
    @next_literal_index = 1

    def self.minimize(literals : Array(Literal), *, keep_exact : Bool) : Nil
      trie = new
      make_inexact = [] of Int32
      retained = [] of Literal

      literals.each do |literal|
        if conflict_index = trie.insert(literal.bytes)
          make_inexact << (conflict_index - 1) unless keep_exact
        else
          retained << literal
        end
      end

      make_inexact.each do |index|
        retained[index].make_inexact if index < retained.size
      end

      literals.clear
      literals.concat(retained)
    end

    protected def insert(bytes : Array(UInt8)) : Int32?
      prev = root
      if idx = @matches[prev]
        return idx
      end

      bytes.each do |byte|
        transitions = @states[prev].trans
        position = transitions.bsearch_index { |entry| entry[0] >= byte }
        if position && transitions[position][0] == byte
          prev = transitions[position][1]
          if idx = @matches[prev]
            return idx
          end
        else
          next_state = create_state
          insert_at = position || transitions.size
          transitions.insert(insert_at, {byte, next_state})
          prev = next_state
        end
      end

      idx = @next_literal_index
      @next_literal_index += 1
      @matches[prev] = idx
      nil
    end

    private def root : Int32
      @states.empty? ? create_state : 0
    end

    private def create_state : Int32
      id = @states.size.to_i32
      @states << State.new
      @matches << nil
      id
    end

    private class State
      getter trans = [] of Tuple(UInt8, Int32)
    end
  end

  class Extractor
    @kind : ExtractKind
    @limit_class : Int32
    @limit_repeat : Int32
    @limit_literal_len : Int32
    @limit_total : Int32

    def initialize
      @kind = ExtractKind::Prefix
      @limit_class = 10
      @limit_repeat = 10
      @limit_literal_len = 100
      @limit_total = 250
    end

    def kind(kind : ExtractKind) : self
      @kind = kind
      self
    end

    def limit_class(limit : Int32) : self
      @limit_class = limit
      self
    end

    def limit_repeat(limit : Int32) : self
      @limit_repeat = limit
      self
    end

    def limit_literal_len(limit : Int32) : self
      @limit_literal_len = limit
      self
    end

    def limit_total(limit : Int32) : self
      @limit_total = limit
      self
    end

    def extract(hir : Regex::Syntax::Hir::Hir) : Seq
      extract(hir.node)
    end

    def extract(node : Regex::Syntax::Hir::Node) : Seq
      case node
      when Regex::Syntax::Hir::Empty,
           Regex::Syntax::Hir::Look,
           Regex::Syntax::Hir::Literal,
           Regex::Syntax::Hir::CharClass,
           Regex::Syntax::Hir::UnicodeClass,
           Regex::Syntax::Hir::DotNode
        extract_terminal(node)
      when Regex::Syntax::Hir::Repetition
        extract_repetition(node)
      when Regex::Syntax::Hir::Capture
        extract(node.sub)
      when Regex::Syntax::Hir::Concat
        nodes = @kind.prefix? ? node.children : node.children.reverse
        extract_concat(nodes)
      when Regex::Syntax::Hir::Alternation
        extract_alternation(node.children)
      else
        Seq.infinite
      end
    end

    private def extract_terminal(node : Regex::Syntax::Hir::Node) : Seq
      case node
      when Regex::Syntax::Hir::Empty, Regex::Syntax::Hir::Look
        Seq.singleton(Literal.exact([] of UInt8))
      when Regex::Syntax::Hir::Literal
        extract_literal(node)
      when Regex::Syntax::Hir::CharClass
        extract_class_bytes(node)
      when Regex::Syntax::Hir::UnicodeClass
        extract_class_unicode(node)
      when Regex::Syntax::Hir::DotNode
        Seq.infinite
      else
        Seq.infinite
      end
    end

    private def extract_literal(node : Regex::Syntax::Hir::Literal) : Seq
      seq = Seq.singleton(Literal.exact(node.bytes))
      enforce_literal_len(seq)
      seq
    end

    private def extract_concat(nodes : Array(Regex::Syntax::Hir::Node)) : Seq
      seq = Seq.singleton(Literal.exact([] of UInt8))
      nodes.each do |node|
        break if seq.inexact?

        seq = cross(seq, extract(node))
      end
      seq
    end

    private def extract_alternation(nodes : Array(Regex::Syntax::Hir::Node)) : Seq
      seq = Seq.empty
      nodes.each do |node|
        break unless seq.finite?

        seq = union(seq, extract(node))
      end
      seq
    end

    private def extract_repetition(rep : Regex::Syntax::Hir::Repetition) : Seq
      subseq = extract(rep.sub)
      return exact_empty_repetition if zero_exact_repetition?(rep)
      return optional_repetition(rep, subseq) if optional_repetition?(rep)
      return exact_count_repetition(rep, subseq) if exact_count_repetition?(rep)

      ranged_repetition(rep, subseq)
    end

    private def zero_exact_repetition?(rep : Regex::Syntax::Hir::Repetition) : Bool
      rep.min == 0_u32 && rep.max == 0_u32
    end

    private def optional_repetition?(rep : Regex::Syntax::Hir::Repetition) : Bool
      rep.min == 0_u32
    end

    private def exact_count_repetition?(rep : Regex::Syntax::Hir::Repetition) : Bool
      !!rep.max && rep.min == rep.max
    end

    private def exact_empty_repetition : Seq
      Seq.singleton(Literal.exact([] of UInt8))
    end

    private def optional_repetition(rep : Regex::Syntax::Hir::Repetition, subseq : Seq) : Seq
      subseq.make_inexact unless rep.max == 1_u32
      empty = Seq.singleton(Literal.exact([] of UInt8))
      if !rep.greedy?
        tmp = subseq
        subseq = empty
        empty = tmp
      end
      union(subseq, empty)
    end

    private def exact_count_repetition(rep : Regex::Syntax::Hir::Repetition, subseq : Seq) : Seq
      seq = repeated_prefix(subseq, rep.min)
      seq.make_inexact if rep.min > @limit_repeat.to_u32

      if factor = exact_empty_repeat_factor(rep.sub, subseq)
        seq.make_inexact if saturating_mul_u64(factor, rep.min.to_u64) > @limit_repeat.to_u64
      end
      seq
    end

    private def ranged_repetition(rep : Regex::Syntax::Hir::Repetition, subseq : Seq) : Seq
      seq = repeated_prefix(subseq, rep.min)
      seq.make_inexact
      seq
    end

    private def repeated_prefix(subseq : Seq, min : UInt32) : Seq
      seq = Seq.singleton(Literal.exact([] of UInt8))
      repeat_count = Math.min(min, @limit_repeat.to_u32)
      repeat_count.times do
        break if seq.inexact?

        seq = cross(seq, subseq.clone)
      end
      seq
    end

    private def exact_empty_repeat_factor(node : Regex::Syntax::Hir::Node, seq : Seq) : UInt64?
      literals = seq.literals
      return nil unless seq.exact? && literals && literals.size == 1 && literals[0].empty?

      case node
      when Regex::Syntax::Hir::Empty, Regex::Syntax::Hir::Look
        1_u64
      when Regex::Syntax::Hir::Capture
        exact_empty_repeat_factor(node.sub, extract(node.sub)) || 1_u64
      when Regex::Syntax::Hir::Repetition
        return nil unless node.max && node.min == node.max

        child_factor = exact_empty_repeat_factor(node.sub, extract(node.sub)) || 1_u64
        saturating_mul_u64(child_factor, node.min.to_u64)
      else
        1_u64
      end
    end

    private def saturating_mul_u64(left : UInt64, right : UInt64) : UInt64
      return 0_u64 if left == 0_u64 || right == 0_u64
      return UInt64::MAX if left > UInt64::MAX // right

      left * right
    end

    private def extract_class_unicode(cls : Regex::Syntax::Hir::UnicodeClass) : Seq
      return Seq.infinite if cls.negated? || class_over_limit_unicode?(cls)

      seq = Seq.empty
      cls.intervals.each do |range|
        range.each do |codepoint|
          seq.push(Literal.from_char(codepoint.chr))
        end
      end
      enforce_literal_len(seq)
      seq
    end

    private def extract_class_bytes(cls : Regex::Syntax::Hir::CharClass) : Seq
      return Seq.infinite if cls.negated? || class_over_limit_bytes?(cls)

      seq = Seq.empty
      cls.intervals.each do |range|
        range.each do |byte|
          seq.push(Literal.from_byte(byte))
        end
      end
      enforce_literal_len(seq)
      seq
    end

    private def class_over_limit_unicode?(cls : Regex::Syntax::Hir::UnicodeClass) : Bool
      count = 0_u64
      cls.intervals.each do |range|
        return true if count > @limit_class

        count += range.end.to_u64 - range.begin.to_u64 + 1
      end
      count > @limit_class
    end

    private def class_over_limit_bytes?(cls : Regex::Syntax::Hir::CharClass) : Bool
      count = 0_u64
      cls.intervals.each do |range|
        return true if count > @limit_class

        count += range.end.to_u64 - range.begin.to_u64 + 1
      end
      count > @limit_class
    end

    private def cross(seq1 : Seq, seq2 : Seq) : Seq
      if max_cross_len = seq1.max_cross_len(seq2)
        seq2.make_infinite if max_cross_len > @limit_total
      end
      if @kind.suffix?
        seq1.cross_reverse(seq2)
      else
        seq1.cross_forward(seq2)
      end
      enforce_literal_len(seq1)
      seq1
    end

    private def union(seq1 : Seq, seq2 : Seq) : Seq
      if max_union_len = seq1.max_union_len(seq2)
        if max_union_len > @limit_total
          if @kind.prefix?
            seq1.keep_first_bytes(4)
            seq2.keep_first_bytes(4)
          else
            seq1.keep_last_bytes(4)
            seq2.keep_last_bytes(4)
          end
          seq1.dedup
          seq2.dedup
          if trimmed_len = seq1.max_union_len(seq2)
            seq2.make_infinite if trimmed_len > @limit_total
          end
        end
      end
      seq1.union(seq2)
      seq1
    end

    private def enforce_literal_len(seq : Seq) : Nil
      if @kind.prefix?
        seq.keep_first_bytes(@limit_literal_len)
      else
        seq.keep_last_bytes(@limit_literal_len)
      end
    end
  end
end
