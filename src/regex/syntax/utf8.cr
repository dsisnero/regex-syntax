module Regex::Syntax::Utf8
  MAX_UTF8_BYTES = 4

  struct Utf8Range
    getter start : UInt8
    getter end : UInt8

    def initialize(@start : UInt8, @end : UInt8)
    end

    def matches(byte : UInt8) : Bool
      @start <= byte && byte <= @end
    end

    def ==(other : Utf8Range) : Bool
      @start == other.start && @end == other.end
    end

    def inspect(io : IO) : Nil
      if @start == @end
        io << "[" << @start.to_s(16).upcase << "]"
      else
        io << "[" << @start.to_s(16).upcase << "-" << @end.to_s(16).upcase << "]"
      end
    end
  end

  struct Utf8Sequence
    getter ranges : Array(Utf8Range)

    def initialize(@ranges : Array(Utf8Range))
    end

    def self.from_encoded_range(start : Array(UInt8), end_ : Array(UInt8)) : self
      raise "invalid encoded length" unless start.size == end_.size
      new(start.each_with_index.map { |byte, i| Utf8Range.new(byte, end_[i]) }.to_a)
    end

    def as_slice : Array(Utf8Range)
      @ranges
    end

    def len : Int32
      @ranges.size
    end

    def reverse! : self
      @ranges.reverse!
      self
    end

    def matches(bytes : Bytes) : Bool
      return false if bytes.size < len

      @ranges.each_with_index.all? { |range, i| range.matches(bytes[i]) }
    end

    def ==(other : Utf8Sequence) : Bool
      @ranges == other.ranges
    end

    def inspect(io : IO) : Nil
      @ranges.each(&.inspect(io))
    end
  end

  class Utf8Sequences
    @range_stack : Array(ScalarRange)

    def initialize(start : Char, end_ : Char)
      @range_stack = [ScalarRange.new(start.ord.to_u32, end_.ord.to_u32)]
    end

    def reset(start : Char, end_ : Char) : Nil
      @range_stack.clear
      push(start.ord.to_u32, end_.ord.to_u32)
    end

    def next : Utf8Sequence?
      while range = @range_stack.pop?
        loop do
          if next_range = split_surrogate(range)
            range = next_range
            next
          end
          break unless range.valid?

          if next_range = split_across_utf8_width(range)
            range = next_range
            next
          end

          if ascii_range = range.as_ascii
            return Utf8Sequence.new([ascii_range])
          end

          if next_range = split_by_mask(range)
            range = next_range
            next
          end

          return build_sequence(range)
        end
      end
      nil
    end

    def to_a : Array(Utf8Sequence)
      sequences = [] of Utf8Sequence
      while sequence = self.next
        sequences << sequence
      end
      sequences
    end

    private def push(start : UInt32, end_ : UInt32) : Nil
      @range_stack << ScalarRange.new(start, end_)
    end

    private def split_surrogate(range : ScalarRange) : ScalarRange?
      return unless split = range.split

      r1, r2 = split
      push(r2.start, r2.end)
      r1
    end

    private def split_across_utf8_width(range : ScalarRange) : ScalarRange?
      (1...MAX_UTF8_BYTES).each do |i|
        max = self.class.max_scalar_value(i)
        if range.start <= max && max < range.end
          push(max + 1, range.end)
          return ScalarRange.new(range.start, max)
        end
      end
      nil
    end

    private def split_by_mask(range : ScalarRange) : ScalarRange?
      (1...MAX_UTF8_BYTES).each do |i|
        mask = (1_u32 << (6 * i)) - 1
        next if (range.start & ~mask) == (range.end & ~mask)

        if (range.start & mask) != 0
          push((range.start | mask) + 1, range.end)
          return ScalarRange.new(range.start, range.start | mask)
        end
        if (range.end & mask) != mask
          push(range.end & ~mask, range.end)
          return ScalarRange.new(range.start, (range.end & ~mask) - 1)
        end
      end
      nil
    end

    private def build_sequence(range : ScalarRange) : Utf8Sequence
      start_bytes = Bytes.new(MAX_UTF8_BYTES, 0_u8)
      end_bytes = Bytes.new(MAX_UTF8_BYTES, 0_u8)
      n = range.encode(start_bytes, end_bytes)
      start_array = Array(UInt8).new(n) { |i| start_bytes[i] }
      end_array = Array(UInt8).new(n) { |i| end_bytes[i] }
      Utf8Sequence.from_encoded_range(start_array, end_array)
    end

    def self.max_scalar_value(nbytes : Int32) : UInt32
      case nbytes
      when 1 then 0x007F_u32
      when 2 then 0x07FF_u32
      when 3 then 0xFFFF_u32
      when 4 then 0x10FFFF_u32
      else
        raise "invalid UTF-8 byte sequence size"
      end
    end
  end

  private struct ScalarRange
    getter start : UInt32
    getter end : UInt32

    def initialize(@start : UInt32, @end : UInt32)
    end

    def split : {ScalarRange, ScalarRange}?
      if @start < 0xE000_u32 && @end > 0xD7FF_u32
        {
          ScalarRange.new(@start, 0xD7FF_u32),
          ScalarRange.new(0xE000_u32, @end),
        }
      end
    end

    def valid? : Bool
      @start <= @end
    end

    def as_ascii : Utf8Range?
      if ascii?
        Utf8Range.new(@start.to_u8, @end.to_u8)
      end
    end

    def ascii? : Bool
      valid? && @end <= 0x7F_u32
    end

    def encode(start_bytes : Slice(UInt8), end_bytes : Slice(UInt8)) : Int32
      start_char = @start.chr
      end_char = @end.chr
      start_string = start_char.to_s
      end_string = end_char.to_s
      start_slice = start_string.to_slice
      end_slice = end_string.to_slice
      raise "encoded length mismatch" unless start_slice.size == end_slice.size

      start_slice.each_with_index { |byte, i| start_bytes[i] = byte }
      end_slice.each_with_index { |byte, i| end_bytes[i] = byte }
      start_slice.size
    end
  end
end
