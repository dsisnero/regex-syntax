require "./spec_helper"

describe Regex::Syntax::Hir::LiteralExtraction do
  it "exposes extract kind predicates like Rust" do
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix.prefix?.should be_true
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix.suffix?.should be_false
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Suffix.suffix?.should be_true
  end

  it "exposes literal byte helpers like Rust" do
    literal = Regex::Syntax::Hir::LiteralExtraction::Literal.exact("ab")
    literal.as_bytes.should eq([97_u8, 98_u8])
    literal.into_bytes.should eq([97_u8, 98_u8])
    literal.len.should eq(2)
    literal.empty?.should be_false
  end

  it "exposes sequence constructors and predicates like Rust" do
    empty = Regex::Syntax::Hir::LiteralExtraction::Seq.empty
    empty.finite?.should be_true
    empty.empty?.should be_true
    empty.len.should eq(0)
    empty.literals.should eq([] of Regex::Syntax::Hir::LiteralExtraction::Literal)

    singleton = Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("x")
    )
    singleton.finite?.should be_true
    singleton.exact?.should be_true
    singleton.inexact?.should be_false
    singleton.min_literal_len.should eq(1)
    singleton.max_literal_len.should eq(1)

    infinite = Regex::Syntax::Hir::LiteralExtraction::Seq.infinite
    infinite.finite?.should be_false
    infinite.inexact?.should be_true
    infinite.len.should be_nil
  end

  it "exposes extractor builder configuration like Rust" do
    extractor = Regex::Syntax::Hir::LiteralExtraction::Extractor.new
      .kind(Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Suffix)
      .limit_class(3)
      .limit_repeat(4)
      .limit_literal_len(5)
      .limit_total(6)

    hir = Regex::Syntax.parse("abc")
    seq = extractor.extract(hir)
    seq.finite?.should be_true
    seq.literals.should_not be_nil
  end
end
