require "./spec_helper"

describe "Perl character class unicode flag" do
  it "\\d returns UnicodeClass when unicode: true" do
    parser = Regex::Syntax::Parser.new(unicode: true)
    hir = parser.parse("\\d")
    hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
  end

  it "\\d returns CharClass when unicode: false" do
    parser = Regex::Syntax::Parser.new(unicode: false)
    hir = parser.parse("\\d")
    hir.node.should be_a(Regex::Syntax::Hir::CharClass)
  end

  it "\\w returns UnicodeClass when unicode: true" do
    parser = Regex::Syntax::Parser.new(unicode: true)
    hir = parser.parse("\\w")
    hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
  end

  it "\\w returns CharClass when unicode: false" do
    parser = Regex::Syntax::Parser.new(unicode: false)
    hir = parser.parse("\\w")
    hir.node.should be_a(Regex::Syntax::Hir::CharClass)
  end

  it "\\s returns UnicodeClass when unicode: true" do
    parser = Regex::Syntax::Parser.new(unicode: true)
    hir = parser.parse("\\s")
    hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
  end

  it "\\s returns CharClass when unicode: false" do
    parser = Regex::Syntax::Parser.new(unicode: false)
    hir = parser.parse("\\s")
    hir.node.should be_a(Regex::Syntax::Hir::CharClass)
  end

  it "\\D returns negated UnicodeClass when unicode: true" do
    parser = Regex::Syntax::Parser.new(unicode: true)
    hir = parser.parse("\\D")
    hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
    hir.node.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_true
  end

  it "\\D returns negated CharClass when unicode: false" do
    parser = Regex::Syntax::Parser.new(unicode: false)
    hir = parser.parse("\\D")
    hir.node.should be_a(Regex::Syntax::Hir::CharClass)
    hir.node.as(Regex::Syntax::Hir::CharClass).negated?.should be_true
  end
end
