require "./spec_helper"

describe Regex::Syntax::Hir::LiteralExtraction do
  it "exposes extract kind predicates like Rust" do
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix.prefix?.should be_true
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix.is_prefix.should be_true
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix.suffix?.should be_false
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix.is_suffix.should be_false
    Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Suffix.suffix?.should be_true
  end

  it "exposes literal byte helpers like Rust" do
    literal = Regex::Syntax::Hir::LiteralExtraction::Literal.exact("ab")
    literal.as_bytes.should eq([97_u8, 98_u8])
    literal.into_bytes.should eq([97_u8, 98_u8])
    literal.len.should eq(2)
    literal.empty?.should be_false

    inexact = Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("xy")
    inexact.exact?.should be_false

    literal.extend(Regex::Syntax::Hir::LiteralExtraction::Literal.exact("cd"))
    literal.as_bytes.should eq("abcd".bytes.to_a)
    literal.reverse
    literal.as_bytes.should eq("dcba".bytes.to_a)
    literal.keep_first_bytes(2)
    literal.as_bytes.should eq("dc".bytes.to_a)
    literal.exact?.should be_false

    tail = Regex::Syntax::Hir::LiteralExtraction::Literal.exact("wxyz")
    tail.keep_last_bytes(2)
    tail.as_bytes.should eq("yz".bytes.to_a)
    tail.make_inexact
    tail.exact?.should be_false

    Regex::Syntax::Hir::LiteralExtraction::Literal.from_byte('a'.ord.to_u8).as_bytes.should eq([97_u8])
    Regex::Syntax::Hir::LiteralExtraction::Literal.from_char('β').as_bytes.should eq("β".bytes.to_a)
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

  it "exposes sequence combinators and optimizers like Rust" do
    a = Regex::Syntax::Hir::LiteralExtraction::Literal.exact("a")
    b = Regex::Syntax::Hir::LiteralExtraction::Literal.exact("b")

    seq = Regex::Syntax::Hir::LiteralExtraction::Seq.empty
    seq.push(a)
    seq.push(a)
    seq.push(b)
    seq.len.should eq(2)
    seq.literals.should eq([a, b])

    seq.make_inexact
    seq.exact?.should be_false
    seq.inexact?.should be_true
    seq.dedup
    seq.literals.should eq([
      Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("a"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("b"),
    ])

    finite = Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("sam")
    )
    finite.union(
      Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
        Regex::Syntax::Hir::LiteralExtraction::Literal.exact("samwise")
      )
    )
    finite.len.should eq(2)
    finite.minimize_by_preference
    finite.literals.should eq([Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("sam")])

    crossed = Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("ab")
    )
    crossed.cross_forward(
      Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
        Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("cd")
      )
    )
    crossed.literals.should eq([Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("abcd")])

    reversed = Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("ab")
    )
    reversed.cross_reverse(
      Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
        Regex::Syntax::Hir::LiteralExtraction::Literal.exact("cd")
      )
    )
    reversed.literals.should eq([Regex::Syntax::Hir::LiteralExtraction::Literal.exact("cdab")])

    merge = Regex::Syntax::Hir::LiteralExtraction::Seq.empty
    merge.push(Regex::Syntax::Hir::LiteralExtraction::Literal.exact("b"))
    merge.push(Regex::Syntax::Hir::LiteralExtraction::Literal.exact("a"))
    merge.sort
    merge.literals.should eq([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("a"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("b"),
    ])
    merge.reverse_literals
    merge.literals.should eq([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("a".reverse),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("b".reverse),
    ])

    prefix = Regex::Syntax::Hir::LiteralExtraction::Seq.new([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("foobar"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("foobaz"),
    ])
    prefix.longest_common_prefix.should eq("fooba".bytes.to_a)
    prefix.longest_common_suffix.should eq([] of UInt8)

    suffix = Regex::Syntax::Hir::LiteralExtraction::Seq.new([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("zzbar"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("yybar"),
    ])
    suffix.longest_common_suffix.should eq("bar".bytes.to_a)

    bytes = Regex::Syntax::Hir::LiteralExtraction::Seq.new([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("abcdef"),
    ])
    bytes.keep_first_bytes(3)
    bytes.literals.should eq([Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("abc")])
    bytes.keep_last_bytes(2)
    bytes.literals.should eq([Regex::Syntax::Hir::LiteralExtraction::Literal.inexact("bc")])

    exact_empty = Regex::Syntax::Hir::LiteralExtraction::Seq.new([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact(""),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("x"),
    ])
    donor = Regex::Syntax::Hir::LiteralExtraction::Seq.new([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("a"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("b"),
    ])
    exact_empty.union_into_empty(donor)
    exact_empty.literals.should eq([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("a"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("b"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("x"),
    ])

    exact_empty.max_union_len(
      Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
        Regex::Syntax::Hir::LiteralExtraction::Literal.exact("q")
      )
    ).should eq(4)
    exact_empty.max_cross_len(
      Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
        Regex::Syntax::Hir::LiteralExtraction::Literal.exact("q")
      )
    ).should eq(3)
    exact_empty.min_literal_len.should eq(1)
    exact_empty.max_literal_len.should eq(1)

    optimizer = Regex::Syntax::Hir::LiteralExtraction::Seq.new([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("sam"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("samwise"),
    ])
    optimizer.optimize_for_prefix_by_preference
    optimizer.finite?.should be_true

    optimizer2 = Regex::Syntax::Hir::LiteralExtraction::Seq.new([
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("foobar"),
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("zzbar"),
    ])
    optimizer2.optimize_for_suffix_by_preference
    optimizer2.finite?.should be_true

    Regex::Syntax::Hir::LiteralExtraction.rank('z'.ord.to_u8).should be_a(UInt8)

    poisoned = Regex::Syntax::Hir::LiteralExtraction::Seq.singleton(
      Regex::Syntax::Hir::LiteralExtraction::Literal.exact("")
    )
    poisoned.make_infinite
    poisoned.finite?.should be_false
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

  it "extracts from HIR nodes and wrappers like Rust" do
    extractor = Regex::Syntax::Hir::LiteralExtraction::Extractor.new
    hir = Regex::Syntax.parse("(foo|bar)baz")
    seq_from_hir = extractor.extract(hir)
    seq_from_node = extractor.extract(hir.node)
    seq_from_hir.should eq(seq_from_node)
  end
end
