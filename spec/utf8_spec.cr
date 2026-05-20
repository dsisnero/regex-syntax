require "./spec_helper"

alias Utf8Range = Regex::Syntax::Utf8::Utf8Range
alias Utf8Sequence = Regex::Syntax::Utf8::Utf8Sequence
alias Utf8Sequences = Regex::Syntax::Utf8::Utf8Sequences

def rutf8(start : Int32, finish : Int32) : Utf8Range
  Utf8Range.new(start.to_u8, finish.to_u8)
end

def encode_surrogate(cp : UInt32) : Bytes
  tag_cont = 0b1000_0000_u8
  tag_three_b = 0b1110_0000_u8
  raise "invalid surrogate" unless 0xD800_u32 <= cp && cp < 0xE000_u32

  Bytes[
    (((cp >> 12) & 0x0F_u32).to_u8 | tag_three_b),
    (((cp >> 6) & 0x3F_u32).to_u8 | tag_cont),
    ((cp & 0x3F_u32).to_u8 | tag_cont),
  ]
end

describe Regex::Syntax::Utf8 do
  it "never accepts surrogate codepoints in UTF-8 ranges like Rust" do
    {
      {'\u{0}', '\u{FFFF}'},
      {'\u{0}', '\u{10FFFF}'},
      {'\u{0}', '\u{10FFFE}'},
      {'\u{80}', '\u{10FFFF}'},
      {'\u{D7FF}', '\u{E000}'},
    }.each do |(start_char, end_char)|
      seqs = Utf8Sequences.new(start_char, end_char).to_a
      (0xD800_u32...0xE000_u32).each do |codepoint|
        bytes = encode_surrogate(codepoint)
        seqs.any?(&.matches(bytes)).should be_false
      end
    end
  end

  it "uses one sequence for a single codepoint like Rust" do
    (0..0x10FFFF).each do |codepoint|
      next if 0xD800 <= codepoint && codepoint < 0xE000

      char = codepoint.to_u32.chr

      Utf8Sequences.new(char, char).to_a.size.should eq(1)
    end
  end

  it "builds BMP UTF-8 byte sequences like Rust" do
    seqs = Utf8Sequences.new('\u{0}', '\u{FFFF}').to_a
    seqs.should eq([
      Utf8Sequence.new([rutf8(0x00, 0x7F)]),
      Utf8Sequence.new([rutf8(0xC2, 0xDF), rutf8(0x80, 0xBF)]),
      Utf8Sequence.new([rutf8(0xE0, 0xE0), rutf8(0xA0, 0xBF), rutf8(0x80, 0xBF)]),
      Utf8Sequence.new([rutf8(0xE1, 0xEC), rutf8(0x80, 0xBF), rutf8(0x80, 0xBF)]),
      Utf8Sequence.new([rutf8(0xED, 0xED), rutf8(0x80, 0x9F), rutf8(0x80, 0xBF)]),
      Utf8Sequence.new([rutf8(0xEE, 0xEF), rutf8(0x80, 0xBF), rutf8(0x80, 0xBF)]),
    ])
  end

  it "reverses UTF-8 sequences like Rust" do
    one = Utf8Sequence.new([rutf8(0xA, 0xB)])
    one.reverse!
    one.as_slice.should eq([rutf8(0xA, 0xB)])

    two = Utf8Sequence.new([rutf8(0xA, 0xB), rutf8(0xB, 0xC)])
    two.reverse!
    two.as_slice.should eq([rutf8(0xB, 0xC), rutf8(0xA, 0xB)])

    three = Utf8Sequence.new([rutf8(0xA, 0xB), rutf8(0xB, 0xC), rutf8(0xC, 0xD)])
    three.reverse!
    three.as_slice.should eq([rutf8(0xC, 0xD), rutf8(0xB, 0xC), rutf8(0xA, 0xB)])

    four = Utf8Sequence.new([rutf8(0xA, 0xB), rutf8(0xB, 0xC), rutf8(0xC, 0xD), rutf8(0xD, 0xE)])
    four.reverse!
    four.as_slice.should eq([rutf8(0xD, 0xE), rutf8(0xC, 0xD), rutf8(0xB, 0xC), rutf8(0xA, 0xB)])
  end

  it "exposes sequence slices, length, and matching like Rust" do
    seq = Utf8Sequence.new([rutf8(0xD0, 0xD3), rutf8(0x80, 0xBF)])
    seq.as_slice.should eq([rutf8(0xD0, 0xD3), rutf8(0x80, 0xBF)])
    seq.len.should eq(2)
    seq.matches(Bytes[0xD1_u8, 0x80_u8]).should be_true
    seq.matches(Bytes[0xD4_u8, 0x80_u8]).should be_false
    seq.matches(Bytes[0xD1_u8]).should be_false
  end

  it "resets UTF-8 sequence iteration like Rust" do
    sequences = Utf8Sequences.new('\u{0}', '\u{7F}')
    sequences.to_a.should eq([Utf8Sequence.new([rutf8(0x00, 0x7F)])])

    sequences.reset('\u{80}', '\u{7FF}')
    sequences.to_a.should eq([Utf8Sequence.new([rutf8(0xC2, 0xDF), rutf8(0x80, 0xBF)])])
  end

  it "renders UTF-8 ranges and sequences like Rust" do
    rutf8(0xA, 0xB).inspect.should eq("[A-B]")
    rutf8(0xA, 0xA).inspect.should eq("[A]")
    Utf8Sequence.new([rutf8(0xC2, 0xDF), rutf8(0x80, 0xBF)]).inspect.should eq("[C2-DF][80-BF]")
  end
end
