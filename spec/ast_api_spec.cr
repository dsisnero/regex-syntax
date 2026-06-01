require "./spec_helper"

describe Regex::Syntax::AST do
  it "exposes vendored AST enum aliases" do
    Regex::Syntax::AST::AssertionKind::Start.should eq(Regex::Syntax::AST::Assertion::Kind::Start)
    Regex::Syntax::AST::ClassAsciiKind::Alpha.should eq(Regex::Syntax::AST::ClassAscii::Kind::Alpha)
    Regex::Syntax::AST::ClassPerlKind::Word.should eq(Regex::Syntax::AST::ClassPerl::Kind::Word)
    Regex::Syntax::AST::ClassSetBinaryOpKind::Intersection.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Intersection)
    Regex::Syntax::AST::ClassSetItemKind::Literal.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Literal)
    Regex::Syntax::AST::FlagsItemKind::Negation.should eq(Regex::Syntax::AST::FlagsItem::Kind::Negation)
    Regex::Syntax::AST::GroupKind::Capture.should eq(Regex::Syntax::AST::Group::Kind::Capture)
    Regex::Syntax::AST::LiteralKind::Verbatim.should eq(Regex::Syntax::AST::Literal::Kind::Verbatim)
    Regex::Syntax::AST::RepetitionKind::Range.should eq(Regex::Syntax::AST::RepetitionOp::Kind::Range)
  end

  it "exposes span helper methods" do
    span = Regex::Syntax::AST::Span.new(2, 5)
    span.one_line?.should be_true
    span.is_one_line.should be_true
    span.with_start(Regex::Syntax::AST::Position.new(1)).start.offset.should eq(1)
    span.with_end(Regex::Syntax::AST::Position.new(9)).end.offset.should eq(9)
    span.empty?.should be_false
    span.is_empty.should be_false

    position = Regex::Syntax::AST::Position.new(7, 3, 2)
    position.offset.should eq(7)
    position.line.should eq(3)
    position.column.should eq(2)

    splat = Regex::Syntax::AST::Span.splat(position)
    splat.start.should eq(position)
    splat.end.should eq(position)
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
    range.is_valid.should be_true
  end

  it "exposes class set union helpers" do
    literal = Regex::Syntax::AST::Literal.new(Regex::Syntax::AST::Span.new(0, 1), Regex::Syntax::AST::Literal::Kind::Verbatim, c: 'a')
    item = Regex::Syntax::AST::ClassSetItem.new(literal.span, Regex::Syntax::AST::ClassSetItem::Kind::Literal, literal)
    union = Regex::Syntax::AST::ClassSetUnion.new(Regex::Syntax::AST::Span.new(0, 1))
    union.push(item).items.size.should eq(1)
    union.span.start.should eq(item.span.start)
    union.span.end.should eq(item.span.end)
    union.into_item.kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Literal)

    set = Regex::Syntax::AST::ClassSet.new(Regex::Syntax::AST::Span.new(0, 1), Regex::Syntax::AST::ClassSet::Kind::Item, item: item)
    union_item = set.union(item).item
    union_item.should_not be_nil
    union_item.as(Regex::Syntax::AST::ClassSetItem).kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Union)
    Regex::Syntax::AST::ClassSet.union(union).item.should eq(item)
    item.span.should eq(literal.span)
  end

  it "exposes repetition and flags helpers" do
    op = Regex::Syntax::AST::RepetitionOp.new(Regex::Syntax::AST::RepetitionOp::Kind::Range, 1_u32, 2_u32)
    op.valid?.should be_true
    op.is_valid.should be_true
    if range = op.range
      range.kind.bounded?.should be_true
      range.valid?.should be_true
    else
      fail "expected range"
    end

    flag_item = Regex::Syntax::AST::FlagsItem.new(
      Regex::Syntax::AST::Span.new(0, 1),
      Regex::Syntax::AST::FlagsItem::Kind::Negation
    )
    flag_item.negation?.should be_true
    flag_item.is_negation.should be_true
    Regex::Syntax::AST::FlagsItemKind::Negation.is_negation.should be_true

    flags = Regex::Syntax::AST::Flags.new(Regex::Syntax::AST::Span.new(0, 0))
    flags.add_item(flag_item).should be_nil
    flags.items.size.should eq(1)

    positive_i = Regex::Syntax::AST::FlagsItem.new(
      Regex::Syntax::AST::Span.new(1, 2),
      Regex::Syntax::AST::FlagsItem::Kind::Flag,
      'i'
    )
    positive_i.flag_enum.should eq(Regex::Syntax::AST::Flag::CaseInsensitive)
    flags.add_item(positive_i).should be_nil
    flags.flag_state(Regex::Syntax::AST::Flag::CaseInsensitive).should be_false
    flags.add_item(positive_i).should eq(1)
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
    group.is_capturing.should be_true
    group.capture_name.should be_nil

    concat = Regex::Syntax::AST::Concat.new(Regex::Syntax::AST::Span.new(0, 0), children)
    concat.into_ast.kind.should be_a(Regex::Syntax::AST::Empty)

    alt = Regex::Syntax::AST::Alternation.new(Regex::Syntax::AST::Span.new(0, 0), children)
    alt.into_ast.kind.should be_a(Regex::Syntax::AST::Empty)

    ast = Regex::Syntax::AST::Ast.empty
    ast.kind.should be_a(Regex::Syntax::AST::Empty)
    ast.empty?.should be_true
    ast.is_empty.should be_true
    Regex::Syntax::AST::Ast.dot(Regex::Syntax::AST::Span.new(1, 2)).kind.should be_a(Regex::Syntax::AST::Dot)
  end

  it "exposes direct AST node constructors like vendored ast/mod.rs" do
    span = Regex::Syntax::AST::Span.new(0, 1)
    assertion = Regex::Syntax::AST::Assertion.new(span, Regex::Syntax::AST::AssertionKind::Start)
    Regex::Syntax::AST::Ast.assertion(assertion).kind.should eq(assertion)

    perl = Regex::Syntax::AST::ClassPerl.new(span, Regex::Syntax::AST::ClassPerlKind::DigitNeg)
    Regex::Syntax::AST::Ast.class_perl(perl).kind.should eq(perl)

    ascii = Regex::Syntax::AST::ClassAscii.new(span, Regex::Syntax::AST::ClassAsciiKind::Alpha, false)
    ascii.kind.should eq(Regex::Syntax::AST::ClassAsciiKind::Alpha)
    Regex::Syntax::AST::ClassAsciiKind.from_name("alpha").should eq(Regex::Syntax::AST::ClassAsciiKind::Alpha)

    unicode = Regex::Syntax::AST::ClassUnicode.new(span, false, "Greek")
    Regex::Syntax::AST::Ast.class_unicode(unicode).kind.should eq(unicode)

    literal = Regex::Syntax::AST::Literal.new(span, Regex::Syntax::AST::LiteralKind::Verbatim, c: 'a')
    range = Regex::Syntax::AST::ClassSetRange.new(span, literal, literal)
    binary_lhs = Regex::Syntax::AST::ClassSet.new(span, Regex::Syntax::AST::ClassSet::Kind::Item, item: Regex::Syntax::AST::ClassSetItem.new(span, Regex::Syntax::AST::ClassSetItemKind::Range, range))
    binary_rhs = Regex::Syntax::AST::ClassSet.new(span, Regex::Syntax::AST::ClassSet::Kind::Item, item: Regex::Syntax::AST::ClassSetItem.new(span, Regex::Syntax::AST::ClassSetItemKind::Literal, literal))
    binary = Regex::Syntax::AST::ClassSetBinaryOp.new(span, Regex::Syntax::AST::ClassSetBinaryOpKind::Intersection, binary_lhs, binary_rhs)
    bracketed = Regex::Syntax::AST::ClassBracketed.new(span, false, Regex::Syntax::AST::ClassSet.new(span, Regex::Syntax::AST::ClassSet::Kind::BinaryOp, binary_op: binary))
    Regex::Syntax::AST::Ast.class_bracketed(bracketed).kind.should eq(bracketed)

    repetition = Regex::Syntax::AST::Repetition.new(
      span,
      Regex::Syntax::AST::RepetitionOp.new(Regex::Syntax::AST::RepetitionKind::ZeroOrMore),
      true,
      literal
    )
    Regex::Syntax::AST::Ast.repetition(repetition).kind.should eq(repetition)

    comment = Regex::Syntax::AST::Comment.new(span, " note")
    with_comments = Regex::Syntax::AST::WithComments.new(Regex::Syntax::AST::Ast.empty(span), [comment])
    with_comments.comments.first.comment.should eq(" note")
  end

  it "exposes unicode, literal, and capture compatibility helpers" do
    escaped = Regex::Syntax::AST::Literal.new(
      Regex::Syntax::AST::Span.new(0, 2),
      Regex::Syntax::AST::Literal::Kind::Escaped,
      c: '\n'
    )
    escaped.special_kind.should eq(Regex::Syntax::AST::Literal::SpecialLiteralKind::LineFeed)

    hex = Regex::Syntax::AST::Literal.new(
      Regex::Syntax::AST::Span.new(0, 4),
      Regex::Syntax::AST::Literal::Kind::Unicode,
      c: 'A',
      form: Regex::Syntax::AST::Literal::Form::Fixed,
      fixed_digits: 4,
      escape_prefix: 'u'
    )
    hex.hex_kind.should eq(Regex::Syntax::AST::Literal::HexLiteralKind::UnicodeShort)
    if hex_kind = hex.hex_kind
      hex_kind.digits.should eq(4_u32)
    else
      fail "expected hex_kind"
    end

    unicode = Regex::Syntax::AST::ClassUnicode.new(
      Regex::Syntax::AST::Span.new(0, 14),
      true,
      "scx!=Katakana"
    )
    unicode.kind.kind.named_value?.should be_true
    unicode.kind.op.should eq(Regex::Syntax::AST::ClassUnicode::ClassUnicodeOpKind::NotEqual)
    if op = unicode.kind.op
      op.is_equal.should be_false
    else
      fail "expected unicode op"
    end
    unicode.kind.property_name.should eq("scx")
    unicode.kind.property_value.should eq("Katakana")
    unicode.is_negated.should be_false

    equal_op = Regex::Syntax::AST::ClassUnicode::ClassUnicodeOpKind::Equal
    equal_op.is_equal.should be_true

    named_group = Regex::Syntax::AST::Group.new(
      Regex::Syntax::AST::Span.new(0, 8),
      Regex::Syntax::AST::Group::Kind::Capture,
      Regex::Syntax::AST::Empty.new(Regex::Syntax::AST::Span.new(7, 7)),
      capture_index: 2,
      name: "word",
      starts_with_p: true
    )
    named_group.starts_with_p?.should be_true
    if capture_name = named_group.capture_name
      capture_name.name.should eq("word")
      capture_name.index.should eq(2_u32)
    else
      fail "expected capture_name"
    end
  end

  it "exposes set-flags and ast constructors" do
    item = Regex::Syntax::AST::FlagsItem.new(
      Regex::Syntax::AST::Span.new(2, 3),
      Regex::Syntax::AST::FlagsItem::Kind::Flag,
      'm'
    )
    set_flags = Regex::Syntax::AST::SetFlags.new(Regex::Syntax::AST::Span.new(0, 4), [item])
    set_flags.flags.flag_state(Regex::Syntax::AST::Flag::MultiLine).should be_true

    literal = Regex::Syntax::AST::Literal.new(
      Regex::Syntax::AST::Span.new(0, 1),
      Regex::Syntax::AST::Literal::Kind::Verbatim,
      c: 'a'
    )
    Regex::Syntax::AST::Ast.literal(literal).kind.should be_a(Regex::Syntax::AST::Literal)
  end
end
