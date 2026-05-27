require "./spec_helper"

describe Regex::Syntax::TranslatorBuilder do
  it "builds translators with vendored option surface" do
    builder = Regex::Syntax::TranslatorBuilder.new
    builder.utf8(false).should be(builder)
    builder.line_terminator('a'.ord.to_u8).should be(builder)
    builder.case_insensitive(true).should be(builder)
    builder.multi_line(true).should be(builder)
    builder.dot_matches_new_line(false).should be(builder)
    builder.crlf(false).should be(builder)
    builder.swap_greed(true).should be(builder)
    builder.unicode(false).should be(builder)

    translator = builder
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

  it "exposes direct translator constructors and translate entrypoint" do
    translator = Regex::Syntax::Translator.new(
      unicode: true,
      utf8: true,
      ignore_case: true,
      multi_line: true,
      dot_matches_new_line: false,
      swap_greed: true,
      crlf: true,
      line_terminator: '\n'.ord.to_u8
    )

    literal = Regex::Syntax::AST::Literal.new(
      Regex::Syntax::AST::Span.new(0, 1),
      Regex::Syntax::AST::Literal::Kind::Verbatim,
      c: 'a'
    )
    hir = translator.translate(literal)
    hir.should be_a(Regex::Syntax::Hir::UnicodeClass)

    dot = Regex::Syntax::AST::Dot.new(Regex::Syntax::AST::Span.new(0, 1))
    translated_dot = translator.translate(dot)
    translated_dot.should be_a(Regex::Syntax::Hir::DotNode)
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

  it "translates AST nodes from the builder-built translator directly" do
    translator = Regex::Syntax::TranslatorBuilder.new.build

    alternation = Regex::Syntax::AST::Alternation.new(
      Regex::Syntax::AST::Span.new(0, 3),
      [
        Regex::Syntax::AST::Literal.new(Regex::Syntax::AST::Span.new(0, 1), Regex::Syntax::AST::Literal::Kind::Verbatim, c: 'a'),
        Regex::Syntax::AST::Literal.new(Regex::Syntax::AST::Span.new(2, 3), Regex::Syntax::AST::Literal::Kind::Verbatim, c: 'b'),
      ] of Regex::Syntax::AST::Node
    )

    hir = translator.translate(alternation)
    hir.should be_a(Regex::Syntax::Hir::Alternation)
    hir.as(Regex::Syntax::Hir::Alternation).children.size.should eq(2)
  end
end
