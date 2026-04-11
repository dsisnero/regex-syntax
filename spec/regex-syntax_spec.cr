require "./spec_helper"

describe Regex::Syntax do
  it "can be required" do
    # Just test that the module exists
    Regex::Syntax.should_not be_nil
  end

  it "has version constant" do
    Regex::Syntax::VERSION.should be_a(String)
  end

  it "defines Parser class" do
    parser = Regex::Syntax::Parser.new
    parser.should be_a(Regex::Syntax::Parser)
  end

  describe "parsing" do
    it "parses literal string" do
      hir = Regex::Syntax.parse("hello")
      hir.should be_a(Regex::Syntax::Hir::Hir)
      hir.node.should be_a(Regex::Syntax::Hir::Literal)
      literal = hir.node.as(Regex::Syntax::Hir::Literal)
      String.new(literal.bytes).should eq("hello")
    end

    it "parses alternation" do
      hir = Regex::Syntax.parse("a|b")
      hir.node.should be_a(Regex::Syntax::Hir::Alternation)
      alt = hir.node.as(Regex::Syntax::Hir::Alternation)
      alt.children.size.should eq(2)
      alt.children[0].should be_a(Regex::Syntax::Hir::Literal)
      alt.children[1].should be_a(Regex::Syntax::Hir::Literal)
    end

    it "parses concatenation" do
      hir = Regex::Syntax.parse("ab")
      case hir.node
      when Regex::Syntax::Hir::Concat
        concat = hir.node.as(Regex::Syntax::Hir::Concat)
        concat.children.size.should eq(2)
        concat.children[0].should be_a(Regex::Syntax::Hir::Literal)
        concat.children[1].should be_a(Regex::Syntax::Hir::Literal)
      when Regex::Syntax::Hir::Literal
        literal = hir.node.as(Regex::Syntax::Hir::Literal)
        String.new(literal.bytes).should eq("ab")
      else
        fail "Expected Concat or Literal, got #{hir.node.class}"
      end
    end

    it "parses dot" do
      hir = Regex::Syntax.parse(".")
      hir.node.should be_a(Regex::Syntax::Hir::DotNode)
      dot_node = hir.node.as(Regex::Syntax::Hir::DotNode)
      dot_node.kind.should eq(Regex::Syntax::Hir::Dot::AnyCharExceptLF)
    end

    it "parses character class" do
      hir = Regex::Syntax.parse("[a-z]")
      case hir.node
      when Regex::Syntax::Hir::CharClass
        char_class = hir.node.as(Regex::Syntax::Hir::CharClass)
        char_class.intervals.should eq([('a'.ord.to_u8)..('z'.ord.to_u8)])
      when Regex::Syntax::Hir::UnicodeClass
        unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
        unicode_class.intervals.should eq([('a'.ord.to_u32)..('z'.ord.to_u32)])
      else
        fail "Expected CharClass or UnicodeClass, got #{hir.node.class}"
      end
    end

    it "parses repetition *" do
      hir = Regex::Syntax.parse("a*")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(0)
      rep.max.should be_nil
      rep.sub.should be_a(Regex::Syntax::Hir::Literal)
    end

    it "parses repetition +" do
      hir = Regex::Syntax.parse("a+")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(1)
      rep.max.should be_nil
    end

    it "parses repetition ?" do
      hir = Regex::Syntax.parse("a?")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(0)
      rep.max.should eq(1)
    end

    it "parses escape sequences" do
      hir = Regex::Syntax.parse("\\n")
      hir.node.should be_a(Regex::Syntax::Hir::Literal)
      literal = hir.node.as(Regex::Syntax::Hir::Literal)
      String.new(literal.bytes).should eq("\n")
    end

    it "parses word boundary" do
      hir = Regex::Syntax.parse("\\b")
      hir.node.should be_a(Regex::Syntax::Hir::Look)
      look = hir.node.as(Regex::Syntax::Hir::Look)
      look.kind.should eq(Regex::Syntax::Hir::Look::Kind::WordBoundary)
    end

    it "parses start anchor ^" do
      hir = Regex::Syntax.parse("^")
      hir.node.should be_a(Regex::Syntax::Hir::Look)
      look = hir.node.as(Regex::Syntax::Hir::Look)
      look.kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
    end

    it "parses end anchor $" do
      hir = Regex::Syntax.parse("$")
      hir.node.should be_a(Regex::Syntax::Hir::Look)
      look = hir.node.as(Regex::Syntax::Hir::Look)
      look.kind.should eq(Regex::Syntax::Hir::Look::Kind::EndTextWithNewline)
    end

    it "parses non-capturing group (?:...)" do
      hir = Regex::Syntax.parse("(?:ab)")
      # Non-capturing group should parse child expression
      # For now, it just returns the child directly
      case hir.node
      when Regex::Syntax::Hir::Concat
        concat = hir.node.as(Regex::Syntax::Hir::Concat)
        concat.children.size.should eq(2)
        concat.children[0].should be_a(Regex::Syntax::Hir::Literal)
        concat.children[1].should be_a(Regex::Syntax::Hir::Literal)
      when Regex::Syntax::Hir::Literal
        literal = hir.node.as(Regex::Syntax::Hir::Literal)
        String.new(literal.bytes).should eq("ab")
      else
        fail "Expected Concat or Literal, got #{hir.node.class}"
      end
    end

    it "parses flag group (?i:...)" do
      hir = Regex::Syntax.parse("(?i:ab)")
      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      concat = hir.node.as(Regex::Syntax::Hir::Concat)
      concat.children.size.should eq(2)
      concat.children[0].should be_a(Regex::Syntax::Hir::CharClass)
      concat.children[1].should be_a(Regex::Syntax::Hir::CharClass)
    end

    it "parses global inline flags (?i) for following expression" do
      hir = Regex::Syntax.parse("(?i)ab")
      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      concat = hir.node.as(Regex::Syntax::Hir::Concat)
      concat.children.size.should eq(2)
      concat.children[0].should be_a(Regex::Syntax::Hir::CharClass)
      concat.children[1].should be_a(Regex::Syntax::Hir::CharClass)
    end

    it "rejects unsupported look-ahead groups" do
      expect_raises(Regex::Syntax::ParseError, /look-ahead/) do
        Regex::Syntax.parse("(?=a)b")
      end
    end

    it "supports verbose mode flag (?x)" do
      hir = Regex::Syntax.parse("(?x)a b # comment\n c")
      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      concat = hir.node.as(Regex::Syntax::Hir::Concat)
      concat.children.size.should eq(3)
    end

    it "supports ungreedy mode flag (?U)" do
      hir = Regex::Syntax.parse("(?U)a+")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.greedy?.should be_false
    end

    it "supports dotall toggles via inline flags" do
      without_s = Regex::Syntax.parse("(?-s).")
      without_s.node.should be_a(Regex::Syntax::Hir::DotNode)
      without_s.node.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyCharExceptLF)

      with_s = Regex::Syntax.parse("(?s).")
      with_s.node.should be_a(Regex::Syntax::Hir::DotNode)
      with_s.node.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyChar)
    end

    it "supports multiline toggles via inline flags" do
      no_multiline = Regex::Syntax.parse("(?-m)^")
      no_multiline.node.should be_a(Regex::Syntax::Hir::Look)
      no_multiline.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)

      multiline = Regex::Syntax.parse("(?m)^")
      multiline.node.should be_a(Regex::Syntax::Hir::Look)
      multiline.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::Start)
    end

    it "computes whether a pattern can match the empty string" do
      Regex::Syntax.parse("a+").can_match_empty?.should be_false
      Regex::Syntax.parse("a*").can_match_empty?.should be_true
      Regex::Syntax.parse("(?:a|)").can_match_empty?.should be_true
    end
  end

  describe "ast" do
    it "represents bracketed class items" do
      span = Regex::Syntax::AST::Span.new(0, 3)
      literal = Regex::Syntax::AST::Literal.new(span, Regex::Syntax::AST::Literal::Kind::Verbatim, 'a')
      class_set = Regex::Syntax::AST::ClassBracketed.new(span, false, [literal.as(Regex::Syntax::AST::Node)])
      class_set.negated?.should be_false
      class_set.empty?.should be_false
      class_set.items.size.should eq(1)
      class_set.items.first.should be_a(Regex::Syntax::AST::Literal)
    end
  end

  describe "parsing edge cases" do
    it "parses literal ] character" do
      hir = Regex::Syntax.parse("]")
      hir.node.should be_a(Regex::Syntax::Hir::Literal)
      literal = hir.node.as(Regex::Syntax::Hir::Literal)
      String.new(literal.bytes).should eq("]")
    end

    it "parses escaped meta characters" do
      # Test escaping of special regex characters - use raw string to avoid double escaping
      hir = Regex::Syntax.parse(%q(\.\+\*\?\(\)\|\[\]\{\}\^\$\#\&\-\~))
      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      concat = hir.node.as(Regex::Syntax::Hir::Concat)
      concat.children.size.should eq(17)
      # Check that first child is a literal for "."
      concat.children[0].should be_a(Regex::Syntax::Hir::Literal)
      literal = concat.children[0].as(Regex::Syntax::Hir::Literal)
      String.new(literal.bytes).should eq(".")
    end

    it "parses character class with range" do
      hir = Regex::Syntax.parse("[a-z]")
      # ASCII ranges might be converted to UnicodeClass
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      char_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      char_class.negated?.should be_false
      char_class.intervals.size.should eq(1)
    end

    it "parses negated character class" do
      hir = Regex::Syntax.parse("[^a-z]")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      char_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      char_class.negated?.should be_true
    end

    it "parses repetition operators" do
      hir = Regex::Syntax.parse("a*")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(0)
      rep.max.should be_nil
      rep.greedy?.should be_true

      hir = Regex::Syntax.parse("a+")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(1)
      rep.max.should be_nil

      hir = Regex::Syntax.parse("a?")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(0)
      rep.max.should eq(1)
    end

    it "parses exact repetition" do
      hir = Regex::Syntax.parse("a{3}")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(3)
      rep.max.should eq(3)
    end

    it "parses range repetition" do
      hir = Regex::Syntax.parse("a{2,5}")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(2)
      rep.max.should eq(5)
    end

    it "parses open-ended repetition" do
      hir = Regex::Syntax.parse("a{2,}")
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      rep = hir.node.as(Regex::Syntax::Hir::Repetition)
      rep.min.should eq(2)
      rep.max.should be_nil
    end
  end

  describe "unicode properties" do
    it "parses unicode property" do
      # Unicode properties need full syntax like \p{L} not \pL
      hir = Regex::Syntax.parse(%q(\p{L}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
    end

    it "parses negated unicode property" do
      hir = Regex::Syntax.parse(%q(\P{L}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_true
    end
  end

  describe "error handling" do
    it "raises error on unmatched [" do
      expect_raises(Regex::Syntax::ParseError) do
        Regex::Syntax.parse("[abc")
      end
    end

    it "raises error on invalid escape" do
      expect_raises(Regex::Syntax::ParseError) do
        Regex::Syntax.parse("\\")
      end
    end

    it "raises error on invalid repetition" do
      expect_raises(Regex::Syntax::ParseError) do
        Regex::Syntax.parse("a{")
      end
    end
  end
end
