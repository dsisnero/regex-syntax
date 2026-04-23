require "./spec_helper"

describe Regex::Syntax::Translator do
  describe "Perl character classes" do
    it "translates \\d to UnicodeClass when unicode: true" do
      translator = Regex::Syntax::Translator.new(unicode: true)
      ast = Regex::Syntax::AST::ClassPerl.new(
        Regex::Syntax::AST::Span.new(0, 2),
        Regex::Syntax::AST::ClassPerl::Kind::Digit
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::UnicodeClass)
      hir.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_false
    end

    it "translates \\d to CharClass when unicode: false" do
      translator = Regex::Syntax::Translator.new(unicode: false)
      ast = Regex::Syntax::AST::ClassPerl.new(
        Regex::Syntax::AST::Span.new(0, 2),
        Regex::Syntax::AST::ClassPerl::Kind::Digit
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::CharClass)
      hir.as(Regex::Syntax::Hir::CharClass).negated?.should be_false
      hir.as(Regex::Syntax::Hir::CharClass).intervals.should eq([48_u8..57_u8])
    end

    it "translates \\D to negated UnicodeClass when unicode: true" do
      translator = Regex::Syntax::Translator.new(unicode: true)
      ast = Regex::Syntax::AST::ClassPerl.new(
        Regex::Syntax::AST::Span.new(0, 2),
        Regex::Syntax::AST::ClassPerl::Kind::DigitNeg
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::UnicodeClass)
      hir.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_true
    end

    it "translates \\s to UnicodeClass when unicode: true" do
      translator = Regex::Syntax::Translator.new(unicode: true)
      ast = Regex::Syntax::AST::ClassPerl.new(
        Regex::Syntax::AST::Span.new(0, 2),
        Regex::Syntax::AST::ClassPerl::Kind::Space
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::UnicodeClass)
      hir.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_false
    end

    it "translates \\w to UnicodeClass when unicode: true" do
      translator = Regex::Syntax::Translator.new(unicode: true)
      ast = Regex::Syntax::AST::ClassPerl.new(
        Regex::Syntax::AST::Span.new(0, 2),
        Regex::Syntax::AST::ClassPerl::Kind::Word
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::UnicodeClass)
      hir.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_false
      hir.as(Regex::Syntax::Hir::UnicodeClass).intervals.any? { |range| range.begin <= 0x00AA_u32 && 0x00AA_u32 <= range.end }.should be_true
    end

    it "preserves capture names in translated HIR" do
      translator = Regex::Syntax::Translator.new(unicode: true)
      ast = Regex::Syntax::AST::Group.new(
        Regex::Syntax::AST::Span.new(0, 10),
        Regex::Syntax::AST::Group::Kind::Capture,
        Regex::Syntax::AST::Literal.new(
          Regex::Syntax::AST::Span.new(8, 9),
          Regex::Syntax::AST::Literal::Kind::Verbatim,
          c: 'a'
        ),
        capture_index: 1,
        name: "word"
      )

      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::Capture)
      capture = hir.as(Regex::Syntax::Hir::Capture)
      capture.index.should eq(1)
      capture.name.should eq("word")
    end
  end

  describe "literal translation" do
    it "translates verbatim literal to Hir::Literal" do
      translator = Regex::Syntax::Translator.new
      # Create a literal with a single character
      ast = Regex::Syntax::AST::Literal.new(
        Regex::Syntax::AST::Span.new(0, 1),
        Regex::Syntax::AST::Literal::Kind::Verbatim,
        c: 'h'
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::Literal)
      literal = hir.as(Regex::Syntax::Hir::Literal)
      String.new(literal.bytes).should eq("h")
    end

    it "translates byte literal to Hir::Literal" do
      translator = Regex::Syntax::Translator.new
      # Create a literal with bytes
      bytes = Bytes.new(5) { |i| ('a'.ord + i).to_u8 }
      ast = Regex::Syntax::AST::Literal.new(
        Regex::Syntax::AST::Span.new(0, 5),
        Regex::Syntax::AST::Literal::Kind::Verbatim,
        bytes: bytes
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::Literal)
      literal = hir.as(Regex::Syntax::Hir::Literal)
      String.new(literal.bytes).should eq("abcde")
    end
  end

  describe "dot translation" do
    it "translates dot to Hir::DotNode" do
      translator = Regex::Syntax::Translator.new
      ast = Regex::Syntax::AST::Dot.new(
        Regex::Syntax::AST::Span.new(0, 1)
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::DotNode)
    end
  end

  describe "empty translation" do
    it "translates empty to Hir::Empty" do
      translator = Regex::Syntax::Translator.new
      ast = Regex::Syntax::AST::Empty.new(
        Regex::Syntax::AST::Span.new(0, 0)
      )
      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::Empty)
    end
  end
end
