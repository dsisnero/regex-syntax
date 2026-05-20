module Regex::Syntax::Hir
  class IntervalSet(B)
    include Enumerable(Range(B, B))

    getter? folded

    def initialize(intervals : Enumerable(Range(B, B)) = [] of Range(B, B))
      @ranges = canonicalize(intervals.to_a)
      @folded = @ranges.empty?
    end

    def push(interval : Range(B, B)) : self
      @ranges = canonicalize(@ranges + [interval])
      @folded = false unless @ranges.empty?
      self
    end

    def each(& : Range(B, B) ->) : Nil
      @ranges.each { |range| yield range }
    end

    def intervals : Array(Range(B, B))
      @ranges
    end

    def iter : IntervalSetIter(B)
      IntervalSetIter(B).new(@ranges)
    end

    def case_fold_simple! : self
      @ranges = case_fold_ranges(@ranges)
      @folded = true
      self
    end

    def union!(other : IntervalSet(B)) : self
      return self if other.intervals.empty? || @ranges == other.intervals

      @ranges = union_ranges(@ranges, other.intervals)
      @folded = @folded && other.folded?
      self
    end

    def intersect!(other : IntervalSet(B)) : self
      if @ranges.empty?
        return self
      elsif other.intervals.empty?
        @ranges = [] of Range(B, B)
        @folded = true
        return self
      end

      @ranges = intersect_ranges(@ranges, other.intervals)
      @folded = @folded && other.folded?
      self
    end

    def difference!(other : IntervalSet(B)) : self
      return self if @ranges.empty? || other.intervals.empty?

      @ranges = difference_ranges(@ranges, other.intervals)
      @folded = @folded && other.folded?
      self
    end

    def symmetric_difference!(other : IntervalSet(B)) : self
      intersection = IntervalSet(B).new(@ranges)
      intersection.intersect!(other)
      union!(other)
      difference!(intersection)
      self
    end

    def negate! : self
      @ranges = invert_ranges(@ranges)
      @folded = true if full_domain?(@ranges)
      self
    end

    def ==(other : self) : Bool
      @ranges == other.intervals
    end

    private def canonicalize(ranges : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      IntervalOps.canonicalize(ranges)
    end

    private def canonicalize(ranges : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      IntervalOps.canonicalize(ranges)
    end

    private def case_fold_ranges(ranges : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      IntervalOps.case_fold_ascii(ranges)
    end

    private def case_fold_ranges(ranges : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      IntervalOps.case_fold_unicode(ranges)
    end

    private def union_ranges(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      IntervalOps.union(a, b)
    end

    private def union_ranges(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      IntervalOps.union(a, b)
    end

    private def intersect_ranges(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      IntervalOps.intersect(a, b)
    end

    private def intersect_ranges(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      IntervalOps.intersect(a, b)
    end

    private def difference_ranges(a : Array(Range(UInt8, UInt8)), b : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      IntervalOps.difference(a, b)
    end

    private def difference_ranges(a : Array(Range(UInt32, UInt32)), b : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      IntervalOps.difference(a, b)
    end

    private def invert_ranges(ranges : Array(Range(UInt8, UInt8))) : Array(Range(UInt8, UInt8))
      IntervalOps.invert(ranges)
    end

    private def invert_ranges(ranges : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
      IntervalOps.invert(ranges)
    end

    private def full_domain?(ranges : Array(Range(UInt8, UInt8))) : Bool
      ranges.size == 1 && ranges[0].begin == 0_u8 && ranges[0].end == 255_u8
    end

    private def full_domain?(ranges : Array(Range(UInt32, UInt32))) : Bool
      ranges.size == 1 && ranges[0].begin == 0_u32 && ranges[0].end == 0x10FFFF_u32
    end
  end

  class IntervalSetIter(B)
    include Iterator(Range(B, B))

    def initialize(@intervals : Array(Range(B, B)))
      @index = 0
    end

    def next
      return stop if @index >= @intervals.size

      interval = @intervals[@index]
      @index += 1
      interval
    end
  end
end
