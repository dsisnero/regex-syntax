require "./spec_helper"

describe Regex::Syntax::AST do
  it "exposes span helper methods" do
    span = Regex::Syntax::AST::Span.new(2, 5)
    span.one_line?.should be_true
    span.with_start(Regex::Syntax::AST::Position.new(1)).start.offset.should eq(1)
    span.with_end(Regex::Syntax::AST::Position.new(9)).end.offset.should eq(9)
  end

  it "exposes literal and range helper methods" do
    literal = Regex::Syntax::AST::Literal.new(
      Regex::Syntax::AST::Span.new(0, 1),
      Regex::Syntax::AST::Literal::Kind::Hex,
      bytes: Bytes[0x41_u8]
    )
    literal.byte.should eq(0x41_u8)

    start = Regex::Syntax::AST::Literal.new(Regex::Syntax::AST::Span.new(0, 1), Regex::Syntax::AST::Literal::Kind::Verbatim, c: 'a')
    finish = Regex::Syntax::AST::Literal.new(Regex::Syntax::AST::Span.new(2, 3), Regex::Syntax::AST::Literal::Kind::Verbatim, c: 'z')
    range = Regex::Syntax::AST::ClassSetRange.new(Regex::Syntax::AST::Span.new(0, 3), start, finish)
    range.valid?.should be_true
  end

  it "exposes class set union helpers" do
    literal = Regex::Syntax::AST::Literal.new(Regex::Syntax::AST::Span.new(0, 1), Regex::Syntax::AST::Literal::Kind::Verbatim, c: 'a')
    item = Regex::Syntax::AST::ClassSetItem.new(literal.span, Regex::Syntax::AST::ClassSetItem::Kind::Literal, literal)
    union = Regex::Syntax::AST::ClassSetUnion.new(Regex::Syntax::AST::Span.new(0, 1))
    union.push(item).items.size.should eq(1)

    set = Regex::Syntax::AST::ClassSet.new(Regex::Syntax::AST::Span.new(0, 1), Regex::Syntax::AST::ClassSet::Kind::Item, item: item)
    union_item = set.union(item).item
    union_item.should_not be_nil
    union_item.as(Regex::Syntax::AST::ClassSetItem).kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Union)
  end

  it "exposes repetition and flags helpers" do
    op = Regex::Syntax::AST::RepetitionOp.new(Regex::Syntax::AST::RepetitionOp::Kind::Range, 1_u32, 2_u32)
    op.valid?.should be_true

    flag_item = Regex::Syntax::AST::FlagsItem.new(
      Regex::Syntax::AST::Span.new(0, 1),
      Regex::Syntax::AST::FlagsItem::Kind::Negation
    )
    flag_item.negation?.should be_true

    flags = Regex::Syntax::AST::Flags.new(Regex::Syntax::AST::Span.new(0, 0))
    flags.add_item(flag_item).items.size.should eq(1)
  end

  it "exposes group and ast wrapper helpers" do
    child = Regex::Syntax::AST::Empty.new(Regex::Syntax::AST::Span.new(0, 0))
    children = [child] of Regex::Syntax::AST::Node
    group = Regex::Syntax::AST::Group.new(
      Regex::Syntax::AST::Span.new(0, 2),
      Regex::Syntax::AST::Group::Kind::Capture,
      child,
      capture_index: 1
    )
    group.capturing?.should be_true

    concat = Regex::Syntax::AST::Concat.new(Regex::Syntax::AST::Span.new(0, 0), children)
    concat.into_ast.kind.should be_a(Regex::Syntax::AST::Concat)

    alt = Regex::Syntax::AST::Alternation.new(Regex::Syntax::AST::Span.new(0, 0), children)
    alt.into_ast.kind.should be_a(Regex::Syntax::AST::Alternation)

    Regex::Syntax::AST::Ast.empty.kind.should be_a(Regex::Syntax::AST::Empty)
  end
end
