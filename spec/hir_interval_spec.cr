require "./spec_helper"

describe Regex::Syntax::Hir::IntervalSet do
  it "canonicalizes and iterates byte intervals" do
    set = Regex::Syntax::Hir::IntervalSet(UInt8).new([3_u8..5_u8, 1_u8..2_u8, 2_u8..3_u8])

    set.intervals.should eq([1_u8..5_u8])
    set.to_a.should eq([1_u8..5_u8])
    set.iter.to_a.should eq([1_u8..5_u8])
  end

  it "supports byte set operations" do
    right = Regex::Syntax::Hir::IntervalSet(UInt8).new([3_u8..4_u8, 8_u8..10_u8])

    Regex::Syntax::Hir::IntervalSet(UInt8).new([1_u8..5_u8, 10_u8..12_u8]).union!(right).intervals.should eq([1_u8..5_u8, 8_u8..12_u8])
    Regex::Syntax::Hir::IntervalSet(UInt8).new([1_u8..5_u8, 10_u8..12_u8]).intersect!(right).intervals.should eq([3_u8..4_u8, 10_u8..10_u8])
    Regex::Syntax::Hir::IntervalSet(UInt8).new([1_u8..5_u8, 10_u8..12_u8]).difference!(right).intervals.should eq([1_u8..2_u8, 5_u8..5_u8, 11_u8..12_u8])
    Regex::Syntax::Hir::IntervalSet(UInt8).new([1_u8..5_u8, 10_u8..12_u8]).symmetric_difference!(right).intervals.should eq([1_u8..2_u8, 5_u8..5_u8, 8_u8..9_u8, 11_u8..12_u8])
  end

  it "supports negation and push for byte intervals" do
    set = Regex::Syntax::Hir::IntervalSet(UInt8).new
    set.push(1_u8..3_u8).push(5_u8..5_u8)
    set.intervals.should eq([1_u8..3_u8, 5_u8..5_u8])

    set.negate!
    set.intervals.should eq([0_u8..0_u8, 4_u8..4_u8, 6_u8..255_u8])
  end

  it "supports unicode interval operations and case folding" do
    set = Regex::Syntax::Hir::IntervalSet(UInt32).new([0x61_u32..0x61_u32])
    set.case_fold_simple!

    set.intervals.should contain(0x41_u32..0x41_u32)
    set.intervals.should contain(0x61_u32..0x61_u32)

    other = Regex::Syntax::Hir::IntervalSet(UInt32).new([0x61_u32..0x7A_u32])
    set.intersect!(other)
    set.intervals.should eq([0x61_u32..0x61_u32])
  end
end
