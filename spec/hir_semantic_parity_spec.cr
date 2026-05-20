require "./spec_helper"

describe "HIR semantic parity" do
  it "matches vendored translator literal, flag, group, and anchor matrices" do
    fold_all = Regex::Syntax.parse("(?i)ab@c")
    fold_all.node.should be_a(Regex::Syntax::Hir::Concat)
    fold_all_children = fold_all.node.as(Regex::Syntax::Hir::Concat).children
    fold_all_children.size.should eq(4)
    fold_all_children[0].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x41_u32..0x41_u32, 0x61_u32..0x61_u32])
    fold_all_children[1].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x42_u32..0x42_u32, 0x62_u32..0x62_u32])
    String.new(fold_all_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("@")
    fold_all_children[3].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x43_u32..0x43_u32, 0x63_u32..0x63_u32])

    fold_beta = Regex::Syntax.parse("(?i)β")
    fold_beta.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
    fold_beta.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      'Β'.ord.to_u32..'Β'.ord.to_u32,
      'β'.ord.to_u32..'β'.ord.to_u32,
      'ϐ'.ord.to_u32..'ϐ'.ord.to_u32,
    ])

    ascii_fold = Regex::Syntax.parse("(?i-u)ab@c")
    ascii_fold.node.should be_a(Regex::Syntax::Hir::Concat)
    ascii_fold_children = ascii_fold.node.as(Regex::Syntax::Hir::Concat).children
    ascii_fold_children.size.should eq(4)
    ascii_fold_children[0].as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x41_u8..0x41_u8, 0x61_u8..0x61_u8])
    ascii_fold_children[1].as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x42_u8..0x42_u8, 0x62_u8..0x62_u8])
    String.new(ascii_fold_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("@")
    ascii_fold_children[3].as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x43_u8..0x43_u8, 0x63_u8..0x63_u8])

    Regex::Syntax.parse("(?i-u)β").node.should be_a(Regex::Syntax::Hir::Literal)
    String.new(Regex::Syntax.parse("(?i-u)β").node.as(Regex::Syntax::Hir::Literal).bytes).should eq("β")

    named_empty = Regex::Syntax.parse("(?P<foo>)")
    named_empty.node.should be_a(Regex::Syntax::Hir::Capture)
    named_empty_capture = named_empty.node.as(Regex::Syntax::Hir::Capture)
    named_empty_capture.index.should eq(1)
    named_empty_capture.name.should eq("foo")
    named_empty_capture.sub.should be_a(Regex::Syntax::Hir::Empty)

    pair = Regex::Syntax.parse("(?P<foo>a)(?P<bar>b)")
    pair.node.should be_a(Regex::Syntax::Hir::Concat)
    pair_children = pair.node.as(Regex::Syntax::Hir::Concat).children
    pair_children.map(&.class).should eq([
      Regex::Syntax::Hir::Capture,
      Regex::Syntax::Hir::Capture,
    ])
    pair_children[0].as(Regex::Syntax::Hir::Capture).name.should eq("foo")
    pair_children[1].as(Regex::Syntax::Hir::Capture).name.should eq("bar")

    empty_flag_capture = Regex::Syntax.parse("((?i))")
    empty_flag_capture.node.should be_a(Regex::Syntax::Hir::Capture)
    empty_flag_capture.node.as(Regex::Syntax::Hir::Capture).sub.should be_a(Regex::Syntax::Hir::Empty)

    nested_empty_flag_capture = Regex::Syntax.parse("(((?x)))")
    nested_empty_flag_capture.node.should be_a(Regex::Syntax::Hir::Capture)
    inner = nested_empty_flag_capture.node.as(Regex::Syntax::Hir::Capture).sub
    inner.should be_a(Regex::Syntax::Hir::Capture)
    inner.as(Regex::Syntax::Hir::Capture).sub.should be_a(Regex::Syntax::Hir::Empty)

    Regex::Syntax.parse("(?m)\\A").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
    Regex::Syntax.parse("(?m)\\z").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndText)
    Regex::Syntax.parse("(?R)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
    Regex::Syntax.parse("(?R)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF)
    Regex::Syntax.parse("(?Rm)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartCRLF)
    Regex::Syntax.parse("(?Rm)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndCRLF)

    scoped_ascii = Regex::Syntax.parse("(?i-u:a)β")
    scoped_ascii.node.should be_a(Regex::Syntax::Hir::Concat)
    scoped_ascii_children = scoped_ascii.node.as(Regex::Syntax::Hir::Concat).children
    scoped_ascii_children[0].should be_a(Regex::Syntax::Hir::CharClass)
    scoped_ascii_children[0].as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x41_u8..0x41_u8, 0x61_u8..0x61_u8])
    String.new(scoped_ascii_children[1].as(Regex::Syntax::Hir::Literal).bytes).should eq("β")

    scoped_group = Regex::Syntax.parse("(?:(?i-u)a)b")
    scoped_group.node.should be_a(Regex::Syntax::Hir::Concat)
    scoped_group.node.as(Regex::Syntax::Hir::Concat).children.map(&.class).should eq([
      Regex::Syntax::Hir::CharClass,
      Regex::Syntax::Hir::Literal,
    ])

    captured_scoped_group = Regex::Syntax.parse("((?i-u)a)b")
    captured_scoped_group.node.should be_a(Regex::Syntax::Hir::Concat)
    captured_children = captured_scoped_group.node.as(Regex::Syntax::Hir::Concat).children
    captured_children[0].should be_a(Regex::Syntax::Hir::Capture)
    captured_children[0].as(Regex::Syntax::Hir::Capture).sub.should be_a(Regex::Syntax::Hir::CharClass)
    String.new(captured_children[1].as(Regex::Syntax::Hir::Literal).bytes).should eq("b")

    swap = Regex::Syntax.parse("(?U)a*a*?(?-U)a*a*?")
    swap.node.should be_a(Regex::Syntax::Hir::Concat)
    swap.node.as(Regex::Syntax::Hir::Concat).children.map(&.as(Regex::Syntax::Hir::Repetition).greedy?).should eq([
      false,
      true,
      true,
      false,
    ])

    local_toggle = Regex::Syntax.parse("(?:a(?i)a)a")
    local_toggle.node.should be_a(Regex::Syntax::Hir::Concat)
    local_toggle_children = local_toggle.node.as(Regex::Syntax::Hir::Concat).children
    local_toggle_children.map(&.class).should eq([
      Regex::Syntax::Hir::Literal,
      Regex::Syntax::Hir::UnicodeClass,
      Regex::Syntax::Hir::Literal,
    ])
    String.new(local_toggle_children[0].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
    local_toggle_children[1].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      0x41_u32..0x41_u32,
      0x61_u32..0x61_u32,
    ])
    String.new(local_toggle_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")

    inherited_toggle = Regex::Syntax.parse("(?i)(?:a(?-i)a)a")
    inherited_toggle.node.should be_a(Regex::Syntax::Hir::Concat)
    inherited_children = inherited_toggle.node.as(Regex::Syntax::Hir::Concat).children
    inherited_children.map(&.class).should eq([
      Regex::Syntax::Hir::UnicodeClass,
      Regex::Syntax::Hir::Literal,
      Regex::Syntax::Hir::UnicodeClass,
    ])
    inherited_children[0].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      0x41_u32..0x41_u32,
      0x61_u32..0x61_u32,
    ])
    String.new(inherited_children[1].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
    inherited_children[2].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      0x41_u32..0x41_u32,
      0x61_u32..0x61_u32,
    ])
  end

  it "matches vendored translator class and alternation matrices" do
    mixed_invalid = Regex::Syntax::Parser.new(utf8: false).parse("[Δδ]|(?-u:[\\x90-\\xFF])|[Λλ]")
    mixed_invalid.node.should be_a(Regex::Syntax::Hir::Alternation)
    mixed_children = mixed_invalid.node.as(Regex::Syntax::Hir::Alternation).children
    mixed_children[0].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      'Δ'.ord.to_u32..'Δ'.ord.to_u32,
      'δ'.ord.to_u32..'δ'.ord.to_u32,
    ])
    mixed_children[1].as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x90_u8..0xFF_u8])
    mixed_children[2].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      'Λ'.ord.to_u32..'Λ'.ord.to_u32,
      'λ'.ord.to_u32..'λ'.ord.to_u32,
    ])

    byte_union = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("[a-z]|(?-u:[\\x90-\\xFF])|[A-Z]")
    byte_union.node.should be_a(Regex::Syntax::Hir::CharClass)
    byte_union.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
      0x41_u8..0x5A_u8,
      0x61_u8..0x7A_u8,
      0x90_u8..0xFF_u8,
    ])

    Regex::Syntax.parse(%q([\^&&^])).node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      '^'.ord.to_u32..'^'.ord.to_u32,
    ])
    Regex::Syntax.parse(%q([]&&\]])).node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      ']'.ord.to_u32..']'.ord.to_u32,
    ])
    Regex::Syntax.parse(%q([-&&-])).node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      '-'.ord.to_u32..'-'.ord.to_u32,
    ])
    Regex::Syntax.parse(%q([\&&&&])).node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      '&'.ord.to_u32..'&'.ord.to_u32,
    ])
    Regex::Syntax.parse(%q([\&&&\&])).node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      '&'.ord.to_u32..'&'.ord.to_u32,
    ])
    Regex::Syntax.parse(%q([a-w&&[^c-g]z])).node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      'a'.ord.to_u32..'b'.ord.to_u32,
      'h'.ord.to_u32..'w'.ord.to_u32,
    ])

    negated_intersection = Regex::Syntax.parse(%q([^[a-z&&a-c]])).node.as(Regex::Syntax::Hir::UnicodeClass)
    negated_intersection.negated?.should be_true
    negated_intersection.intervals.should eq([
      'a'.ord.to_u32..'c'.ord.to_u32,
    ])
    double_negated_unicode = Regex::Syntax.parse(%q([^[^\w&&\d]])).node.as(Regex::Syntax::Hir::UnicodeClass)
    double_negated_unicode.negated?.should be_true
    semantic_unicode = Regex::Syntax::Hir::UnicodeClass.new(false, double_negated_unicode.intervals.dup)
    semantic_unicode.negate
    semantic_unicode.intervals.should eq(
      Regex::Syntax.parse(%q(\d)).node.as(Regex::Syntax::Hir::UnicodeClass).intervals
    )

    double_negated_bytes = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)[^[^\w&&\d]])).node.as(Regex::Syntax::Hir::CharClass)
    double_negated_bytes.negated?.should be_true
    semantic_bytes = Regex::Syntax::Hir::CharClass.new(false, double_negated_bytes.intervals.dup)
    semantic_bytes.negate
    semantic_bytes.intervals.should eq([
      '0'.ord.to_u8..'9'.ord.to_u8,
    ])

    Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)[[:alpha:]--[:lower:]])).node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
      'A'.ord.to_u8..'Z'.ord.to_u8,
    ])
  end

  it "matches vendored HIR class operation matrices more literally" do
    bytes = Regex::Syntax::Hir::CharClass.new(false, [
      0x63_u8..0x66_u8,
      0x61_u8..0x67_u8,
      0x64_u8..0x6A_u8,
      0x61_u8..0x63_u8,
      0x6D_u8..0x70_u8,
      0x6C_u8..0x73_u8,
    ])
    bytes.intervals.should eq([0x61_u8..0x6A_u8, 0x6C_u8..0x73_u8])

    unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [
      0x63_u32..0x66_u32,
      0x61_u32..0x67_u32,
      0x64_u32..0x6A_u32,
      0x61_u32..0x63_u32,
      0x6D_u32..0x70_u32,
      0x6C_u32..0x73_u32,
    ])
    unicode.intervals.should eq([0x61_u32..0x6A_u32, 0x6C_u32..0x73_u32])

    byte_fold = Regex::Syntax::Hir::CharClass.new(false, [0x41_u8..0x41_u8, 0x5F_u8..0x5F_u8])
    byte_fold.case_fold_simple
    byte_fold.intervals.should eq([0x41_u8..0x41_u8, 0x5F_u8..0x5F_u8, 0x61_u8..0x61_u8])

    unicode_fold = Regex::Syntax::Hir::UnicodeClass.new(false, ['k'.ord.to_u32..'k'.ord.to_u32])
    unicode_fold.case_fold_simple
    unicode_fold.intervals.should eq([
      'K'.ord.to_u32..'K'.ord.to_u32,
      'k'.ord.to_u32..'k'.ord.to_u32,
      0x212A_u32..0x212A_u32,
    ])

    empty_unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [] of Range(UInt32, UInt32))
    empty_unicode.negate
    empty_unicode.intervals.should eq([0_u32..0x10FFFF_u32])

    full_unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [0_u32..0x10FFFF_u32])
    full_unicode.negate
    full_unicode.intervals.should be_empty

    edge_unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [0_u32..0xD7FF_u32])
    edge_unicode.negate
    edge_unicode.intervals.should eq([0xE000_u32..0x10FFFF_u32])

    byte_intersection = Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x62_u8, 0x63_u8..0x64_u8, 0x65_u8..0x66_u8])
    byte_intersection.intersect(Regex::Syntax::Hir::CharClass.new(false, [0x62_u8..0x63_u8, 0x64_u8..0x65_u8, 0x66_u8..0x67_u8]))
    byte_intersection.intervals.should eq([0x62_u8..0x66_u8])

    unicode_intersection = Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x62_u32, 0x63_u32..0x64_u32, 0x65_u32..0x66_u32])
    unicode_intersection.intersect(Regex::Syntax::Hir::UnicodeClass.new(false, [0x62_u32..0x63_u32, 0x64_u32..0x65_u32, 0x66_u32..0x67_u32]))
    unicode_intersection.intervals.should eq([0x62_u32..0x66_u32])

    byte_difference = Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x7A_u8])
    byte_difference.difference(Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x63_u8, 0x65_u8..0x67_u8, 0x73_u8..0x75_u8]))
    byte_difference.intervals.should eq([0x64_u8..0x64_u8, 0x68_u8..0x72_u8, 0x76_u8..0x7A_u8])

    unicode_difference = Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x7A_u32])
    unicode_difference.difference(Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x63_u32, 0x65_u32..0x67_u32, 0x73_u32..0x75_u32]))
    unicode_difference.intervals.should eq([0x64_u32..0x64_u32, 0x68_u32..0x72_u32, 0x76_u32..0x7A_u32])
  end

  it "matches vendored HIR analysis matrices more literally" do
    Regex::Syntax.parse(%q(\P{any})).minimum_len.should_not eq(0)
    Regex::Syntax.parse("[a--a]").minimum_len.should_not eq(0)
    Regex::Syntax.parse("[a&&b]").minimum_len.should_not eq(0)

    Regex::Syntax.parse("^foo").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
    Regex::Syntax.parse("foo$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
    Regex::Syntax.parse("(?m)^").look_set.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
    Regex::Syntax.parse("(?m)$").look_set.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false

    Regex::Syntax.parse("foo|bar").alternation_literal?.should be_true
    Regex::Syntax.parse("(?:a)|b").alternation_literal?.should be_false
    Regex::Syntax.parse("a|(?:b)").alternation_literal?.should be_false
    Regex::Syntax.parse("(?:z|xx)@|xx").alternation_literal?.should be_false

    Regex::Syntax.parse("$|^|\\z|\\A|\\b|\\B").all_assertions?.should be_true
    Regex::Syntax.parse("^a").all_assertions?.should be_false
  end
end
