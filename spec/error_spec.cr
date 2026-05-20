require "./spec_helper"

describe Regex::Syntax do
  it "formats parser errors without panicking on multiline patterns" do
    err = begin
      Regex::Syntax::AstParser.new.parse("a{\n")
      raise "expected parser error"
    rescue ex : Regex::Syntax::AST::Error
      ex
    end

    err.to_s.should_not be_empty
    err.pattern.should eq("a{\n")
  end

  it "formats multiline spans with vendored-style dividers and line notes" do
    err = Regex::Syntax::AST::Error.new(
      Regex::Syntax::AST::ErrorKind::ClassUnclosed,
      "ab\ncd",
      Regex::Syntax::AST::Span.new(0, 3)
    )

    err.to_s.should eq(<<-TEXT.chomp)
regex parse error:
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
1: ab
2: cd
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
on line 1 (column 1) through line 2 (column 0)
error: unclosed character class
TEXT
  end

  it "formats repetition quantifier decimal errors like Rust" do
    err = begin
      Regex::Syntax::AstParser.new.parse(%q(\\u{[^}]*}))
      raise "expected parser error"
    rescue ex : Regex::Syntax::AST::Error
      ex
    end

    err.kind.should eq(Regex::Syntax::AST::ErrorKind::RepetitionCountDecimalEmpty)
    err.to_s.should eq(<<-TEXT.chomp)
regex parse error:
    \\\\u{[^}]*}
        ^
error: repetition quantifier expects a valid decimal
TEXT
  end

  it "formats auxiliary spans on the same line" do
    err = begin
      Regex::Syntax::AstParser.new.parse("(?ii)")
      raise "expected parser error"
    rescue ex : Regex::Syntax::AST::Error
      ex
    end

    err.kind.should eq(Regex::Syntax::AST::ErrorKind::FlagDuplicate)
    err.span.should eq(Regex::Syntax::AST::Span.new(3, 4))
    err.auxiliary_span.should eq(Regex::Syntax::AST::Span.new(2, 3))
    err.to_s.should eq(<<-TEXT.chomp)
regex parse error:
    (?ii)
      ^^
error: duplicate flag
TEXT
  end

  it "raises structured HIR errors for unicode-disabled translation" do
    err = begin
      Regex::Syntax::Parser.new(unicode: false).parse(%q(\pZ))
      raise "expected translate error"
    rescue ex : Regex::Syntax::Hir::Error
      ex
    end

    err.kind.should eq(Regex::Syntax::Hir::ErrorKind::UnicodeNotAllowed)
    err.pattern.should eq(%q(\pZ))
    err.to_s.should contain("error: Unicode not allowed here")
  end
end
