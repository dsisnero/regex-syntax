require "./spec_helper"

describe Regex::Syntax::TranslatorBuilder do
  it "builds translators with vendored option surface" do
    translator = Regex::Syntax::TranslatorBuilder.new
      .utf8(false)
      .line_terminator('a'.ord.to_u8)
      .case_insensitive(true)
      .multi_line(true)
      .dot_matches_new_line(false)
      .crlf(false)
      .swap_greed(true)
      .unicode(false)
      .build

    ast = Regex::Syntax::AST::Dot.new(Regex::Syntax::AST::Span.new(0, 1))
    hir = translator.translate(ast)
    hir.should be_a(Regex::Syntax::Hir::CharClass)
    hir.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
      0_u8..('a'.ord.to_u8 - 1),
      ('a'.ord.to_u8 + 1)..0xFF_u8,
    ])
  end

  it "matches vendored unicode-case and line-terminator behavior" do
    ast = Regex::Syntax::AST::Dot.new(Regex::Syntax::AST::Span.new(0, 1))

    expect_raises(Regex::Syntax::ParseError, /invalid UTF-8/) do
      Regex::Syntax::TranslatorBuilder.new
        .line_terminator(0xFF_u8)
        .build
        .translate(ast)
    end

    expect_raises(Regex::Syntax::ParseError, /invalid line terminator/) do
      Regex::Syntax::TranslatorBuilder.new
        .utf8(false)
        .line_terminator(0xFF_u8)
        .build
        .translate(ast)
    end
  end
end
