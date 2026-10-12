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

  it "exposes non-mutating set operations like Rust" do
    left = Regex::Syntax::Hir::IntervalSet(UInt8).new([1_u8..5_u8, 10_u8..12_u8])
    right = Regex::Syntax::Hir::IntervalSet(UInt8).new([3_u8..4_u8, 8_u8..10_u8])

    left.union(right).intervals.should eq([1_u8..5_u8, 8_u8..12_u8])
    left.intersect(right).intervals.should eq([3_u8..4_u8, 10_u8..10_u8])
    left.difference(right).intervals.should eq([1_u8..2_u8, 5_u8..5_u8, 11_u8..12_u8])
    left.symmetric_difference(right).intervals.should eq([1_u8..2_u8, 5_u8..5_u8, 8_u8..9_u8, 11_u8..12_u8])
    left.intervals.should eq([1_u8..5_u8, 10_u8..12_u8])
  end

  it "supports negation and push for byte intervals" do
    set = Regex::Syntax::Hir::IntervalSet(UInt8).new
    set.push(1_u8..3_u8).push(5_u8..5_u8)
    set.intervals.should eq([1_u8..3_u8, 5_u8..5_u8])

    set.negate!
    set.intervals.should eq([0_u8..0_u8, 4_u8..4_u8, 6_u8..255_u8])
  end

  it "exposes non-mutating negate and case folding like Rust" do
    set = Regex::Syntax::Hir::IntervalSet(UInt8).new([0_u8..0_u8, 2_u8..3_u8])
    negated = set.negate
    negated.intervals.should eq([1_u8..1_u8, 4_u8..255_u8])
    set.intervals.should eq([0_u8..0_u8, 2_u8..3_u8])

    unicode = Regex::Syntax::Hir::IntervalSet(UInt32).new([0x61_u32..0x61_u32])
    folded = unicode.case_fold_simple
    folded.intervals.should contain(0x41_u32..0x41_u32)
    folded.intervals.should contain(0x61_u32..0x61_u32)
    unicode.intervals.should eq([0x61_u32..0x61_u32])
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

describe "Rust folded-state preservation through symmetric difference" do
  it "preserves two folded byte sets" do
    left = Regex::Syntax::Hir::IntervalSet(UInt8).new([65_u8..90_u8]).case_fold_simple!
    right = Regex::Syntax::Hir::IntervalSet(UInt8).new([66_u8..67_u8]).case_fold_simple!
    left.symmetric_difference!(right)
    left.intervals.should eq([65_u8..65_u8, 68_u8..90_u8, 97_u8..97_u8, 100_u8..122_u8])
    left.folded?.should be_true
  end

  it "preserves two folded Unicode sets" do
    left = Regex::Syntax::Hir::IntervalSet(UInt32).new([65_u32..90_u32]).case_fold_simple!
    right = Regex::Syntax::Hir::IntervalSet(UInt32).new([66_u32..67_u32]).case_fold_simple!
    left.symmetric_difference!(right)
    left.intervals.should eq([65_u32..65_u32, 68_u32..90_u32, 97_u32..97_u32, 100_u32..122_u32, 383_u32..383_u32, 8490_u32..8490_u32])
    left.folded?.should be_true
  end
end
