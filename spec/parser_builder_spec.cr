require "./spec_helper"

describe Regex::Syntax::ParserBuilder do
  it "parses with default options through the top-level helper" do
    Regex::Syntax.parse("a|b").node.should be_a(Regex::Syntax::Hir::Alternation)
  end

  it "builds parsers with configured options like Rust" do
    parser = Regex::Syntax::ParserBuilder.new
      .case_insensitive(true)
      .multi_line(true)
      .dot_matches_new_line(true)
      .swap_greed(true)
      .ignore_whitespace(true)
      .crlf(true)
      .nest_limit(10)
      .build

    parser.should be_a(Regex::Syntax::Parser)

    multiline = Regex::Syntax::ParserBuilder.new.multi_line(true).build.parse("^")
    multiline.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartLF)

    octal = Regex::Syntax::ParserBuilder.new.octal(true).build.parse(%q(\141))
    octal.node.as(Regex::Syntax::Hir::Literal).bytes.should eq(Bytes[0x61_u8])

    byte_mode = Regex::Syntax::ParserBuilder.new.unicode(false).utf8(false).build.parse(%q(\xFF))
    byte_mode.node.as(Regex::Syntax::Hir::Literal).bytes.should eq(Bytes[0xFF_u8])
  end

  it "supports line terminator customization through the builder" do
    unicode_dot = Regex::Syntax::ParserBuilder.new
      .line_terminator('a'.ord.to_u8)
      .build
      .parse(".")
    unicode_dot.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
    unicode_dot.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
      0_u32..('a'.ord.to_u32 - 1),
      ('a'.ord.to_u32 + 1)..0x10FFFF_u32,
    ])

    byte_dot = Regex::Syntax::ParserBuilder.new
      .unicode(false)
      .utf8(false)
      .line_terminator(0xFF_u8)
      .build
      .parse(".")
    byte_dot.node.should be_a(Regex::Syntax::Hir::CharClass)
    byte_dot.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0_u8..0xFE_u8])
  end

  it "matches Rust's line terminator error split" do
    expect_raises(Regex::Syntax::Hir::Error) do
      Regex::Syntax::ParserBuilder.new
        .line_terminator(0xFF_u8)
        .build
        .parse(".")
    end.kind.should eq(Regex::Syntax::Hir::ErrorKind::InvalidUtf8)

    expect_raises(Regex::Syntax::Hir::Error) do
      Regex::Syntax::ParserBuilder.new
        .utf8(false)
        .line_terminator(0xFF_u8)
        .build
        .parse(".")
    end.kind.should eq(Regex::Syntax::Hir::ErrorKind::InvalidLineTerminator)
  end
end
