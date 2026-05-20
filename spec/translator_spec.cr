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

    it "rejects negated ASCII Perl classes when utf8 is enabled" do
      translator = Regex::Syntax::Translator.new(unicode: false)
      ast = Regex::Syntax::AST::ClassPerl.new(
        Regex::Syntax::AST::Span.new(0, 2),
        Regex::Syntax::AST::ClassPerl::Kind::DigitNeg
      )

      expect_raises(Regex::Syntax::ParseError, /invalid UTF-8/) do
        translator.translate(ast)
      end
    end

    it "translates negated ASCII Perl classes when utf8 is disabled" do
      translator = Regex::Syntax::Translator.new(unicode: false, utf8: false)
      ast = Regex::Syntax::AST::ClassPerl.new(
        Regex::Syntax::AST::Span.new(0, 2),
        Regex::Syntax::AST::ClassPerl::Kind::DigitNeg
      )

      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::CharClass)
      hir.as(Regex::Syntax::Hir::CharClass).negated?.should be_true
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

  describe "translator regressions" do
    it "handles empty concat inside alternation like Rust regression_alt_empty_concat" do
      span = Regex::Syntax::AST::Span.new(0, 0)
      ast = Regex::Syntax::AST::Alternation.new(
        span,
        [Regex::Syntax::AST::Concat.new(span, [] of Regex::Syntax::AST::Node)] of Regex::Syntax::AST::Node
      )

      hir = Regex::Syntax::Translator.new.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::Empty)
    end

    it "handles empty alternation inside concat like Rust regression_empty_alt" do
      span = Regex::Syntax::AST::Span.new(0, 0)
      ast = Regex::Syntax::AST::Concat.new(
        span,
        [Regex::Syntax::AST::Alternation.new(span, [] of Regex::Syntax::AST::Node)] of Regex::Syntax::AST::Node
      )

      hir = Regex::Syntax::Translator.new.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::CharClass)
      hir.as(Regex::Syntax::Hir::CharClass).intervals.should eq([] of Range(UInt8, UInt8))
    end

    it "handles singleton alternation inside concat like Rust regression_singleton_alt" do
      span = Regex::Syntax::AST::Span.new(0, 0)
      ast = Regex::Syntax::AST::Concat.new(
        span,
        [Regex::Syntax::AST::Alternation.new(span, [Regex::Syntax::AST::Dot.new(span)] of Regex::Syntax::AST::Node)] of Regex::Syntax::AST::Node
      )

      hir = Regex::Syntax::Translator.new.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::DotNode)
      hir.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyCharExceptLF)
    end

    it "matches Rust regression_fuzz_match" do
      pattern = "[(\u{6} \0-\u{afdf5}]  \0 "
      hir = Regex::Syntax::ParserBuilder.new
        .octal(false)
        .ignore_whitespace(true)
        .build
        .parse(pattern)

      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      children = hir.node.as(Regex::Syntax::Hir::Concat).children
      children.map(&.class).should eq([
        Regex::Syntax::Hir::UnicodeClass,
        Regex::Syntax::Hir::Literal,
      ])
      children[0].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0_u32..0xAFDF5_u32,
      ])
      children[1].as(Regex::Syntax::Hir::Literal).bytes.should eq(Bytes[0x00_u8])
    end

    it "does not panic on Rust regression_fuzz_difference1" do
      pattern = %q(\W\W|\W[^\v--\W\W\P{Script_Extensions:Pau_Cin_Hau}\u10A1A1-\U{3E3E3}--~~~~--~~~~~~~~------~~~~~~--~~~~~~]*)
      hir = Regex::Syntax.parse(pattern)
      hir.should be_a(Regex::Syntax::Hir::Hir)
    end

    it "does not panic on Rust regression_fuzz_char_decrement1" do
      pattern = "w[w[^w?\rw\rw[^w?\rw[^w?\rw[^w?\rw[^w?\rw[^w?\rw[^w?\r\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0w?\rw[^w?\rw[^w?\rw[^w\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\u{1}\0]\0\0\0\0\0\0\0\0\0*\0\0\u{1}\0]\0\0-*\0][^w?\rw[^w?\rw[^w?\rw[^w?\rw[^w?\rw[^w?\rw[^w\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\u{1}\0]\0\0\0\0\0\0\0\0\0x\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\0\0\0\0*??\0\u{7f}{2}\u{10}??\0\0\0\0\0\0\0\0\0\u{3}\0\0\0}\0-*\0]\0\0\0\0\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\u{1}\0]\0\0-*\0]\0\0\0\0\0\0\0\u{1}\0]\0\u{1}\u{1}H-i]-]\0\0\0\0\u{1}\0]\0\0\0\u{1}\0]\0\0-*\0\0\0\0\u{1}9-\u{7f}]\0'|-\u{7f}]\0'|(?i-ux)[-\u{7f}]\0'\u{3}\0\0\0}\0-*\0]<D\0\0\0\0\0\0\u{1}]\0\0\0\0]\0\0-*\0]\0\0 "
      hir = Regex::Syntax.parse(pattern)
      hir.should be_a(Regex::Syntax::Hir::Hir)
    end
  end
end
