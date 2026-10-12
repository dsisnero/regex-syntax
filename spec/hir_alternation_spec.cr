require "./spec_helper"

private def alternation_shape(node : Regex::Syntax::Hir::Node) : String
  case node
  when Regex::Syntax::Hir::Empty
    "empty"
  when Regex::Syntax::Hir::Literal
    "lit(#{node.bytes.hexstring})"
  when Regex::Syntax::Hir::UnicodeClass
    "unicode(#{node.intervals.map { |range| "#{range.begin}-#{range.end}" }.join(",")})"
  when Regex::Syntax::Hir::CharClass
    "bytes(#{node.intervals.map { |range| "#{range.begin}-#{range.end}" }.join(",")})"
  when Regex::Syntax::Hir::Concat
    "cat(#{node.children.map { |child| alternation_shape(child) }.join(",")})"
  when Regex::Syntax::Hir::Alternation
    "alt(#{node.children.map { |child| alternation_shape(child) }.join(",")})"
  else
    raise "Unexpected node #{node.class}"
  end
end

describe "Vendored character class escapes" do
  it "accepts superfluous ASCII punctuation escapes using Rust's predicate" do
    %w[~ ! % / . + * ? ( ) | { } $ # & -].each do |character|
      hir = Regex::Syntax.parse("[\\#{character}]")
      hir.to_s.should eq(Regex::Syntax::Hir::Hir.literal(character.to_slice).to_s)
    end
  end
end

describe "Vendored HIR alternation normalization" do
  it "preserves the Crystal greedy-dot predicate after lowering dots to classes" do
    [".*", ".+", "(?s).*", "(?R).*", "(?-u).*", "(?s-u).*", "(?R-u).*"].each do |pattern|
      Regex::Syntax::Parser.new(utf8: false).parse(pattern).has_greedy_all?.should be_true
    end
    [".*?", ".{1,2}", "[a-z]*"].each do |pattern|
      Regex::Syntax.parse(pattern).has_greedy_all?.should be_false
    end
  end

  # Every assertion from src/hir/translate.rs::test::smart_alternation,
  # pinned at 72d650cb0a880a01ab6dc2137c0888e8f89740f7. Expected shapes
  # are independent of Crystal's smart constructors.
  it "ports the complete smart_alternation matrix with exact node shapes" do
    {
      "(?:foo)|(?:bar)"                  => "alt(lit(666f6f),lit(626172))",
      "quux|(?:abc|def|xyz)|baz"         => "alt(lit(71757578),lit(616263),lit(646566),lit(78797a),lit(62617a))",
      "quux|(?:abc|(?:def|mno)|xyz)|baz" => "alt(lit(71757578),lit(616263),lit(646566),lit(6d6e6f),lit(78797a),lit(62617a))",
      "a|b|c|d|e|f|x|y|z"                => "unicode(97-102,120-122)",
      "[A-Z]foo|[A-Z]quux"               => "cat(unicode(65-90),alt(lit(666f6f),lit(71757578)))",
      "[A-Z][A-Z]|[A-Z]quux"             => "cat(unicode(65-90),alt(unicode(65-90),lit(71757578)))",
      "[A-Z][A-Z]|[A-Z][A-Z]quux"        => "cat(unicode(65-90),unicode(65-90),alt(empty,lit(71757578)))",
      "[A-Z]foo|[A-Z]foobar"             => "cat(unicode(65-90),alt(lit(666f6f),lit(666f6f626172)))",
    }.each do |pattern, expected|
      alternation_shape(Regex::Syntax.parse(pattern).node).should eq(expected), pattern
    end
  end

  it "normalizes singleton Unicode and raw byte literals in Rust's order" do
    {
      "a|b"               => "unicode(97-98)",
      "(?-u:a|b)"         => "unicode(97-98)",
      "β|Δ"               => "unicode(916-916,946-946)",
      "a|a"               => "lit(61)",
      "[^a[^c]]"          => "lit(63)",
      "[^a-b[^c]]"        => "lit(63)",
      "[^a[^c]]|b"        => "unicode(98-99)",
      "(?:a)|b"           => "unicode(97-98)",
      "(?-u:\\xFE|\\xFF)" => "bytes(254-255)",
      "a|(?-u:\\xFF)"     => "bytes(97-97,255-255)",
      "β|(?-u:\\xFF)"     => "alt(lit(ceb2),lit(ff))",
      "ab|ac"             => "alt(lit(6162),lit(6163))",
      "|a"                => "alt(empty,lit(61))",
    }.each do |pattern, expected|
      hir = Regex::Syntax::Parser.new(utf8: false).parse(pattern)
      alternation_shape(hir.node).should eq(expected), pattern
    end
  end

  it "tries Unicode class union before falling back to byte class union" do
    {
      "(?-u:[a-z]|[A-Z])"               => "unicode(65-90,97-122)",
      "[a-z]|(?-u:[\\x90-\\xFF])|[A-Z]" => "bytes(65-90,97-122,144-255)",
      "[Δδ]|(?-u:[\\x90-\\xFF])|[Λλ]"   => "alt(unicode(916-916,948-948),bytes(144-255),unicode(923-923,955-955))",
    }.each do |pattern, expected|
      hir = Regex::Syntax::Parser.new(utf8: false).parse(pattern)
      alternation_shape(hir.node).should eq(expected), pattern
    end
  end

  it "preserves singleton branches and canonicalizes empty class unions" do
    literal = Regex::Syntax::Hir::Hir.literal("a".to_slice)
    Regex::Syntax::Hir::Hir.alternation([literal]).node.should be(literal.node)
    empty = Regex::Syntax::Hir::UnicodeClass.empty
    result = Regex::Syntax::Hir::Hir.alternation([empty, empty] of Regex::Syntax::Hir::Node)
    result.node.should be_a(Regex::Syntax::Hir::CharClass)
    result.node.as(Regex::Syntax::Hir::CharClass).intervals.should be_empty
  end
end
