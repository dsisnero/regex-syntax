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

  it "routes Parser through the same AST-to-HIR pipeline as Regex::Syntax.parse" do
    parser_hir = Regex::Syntax::Parser.new.parse("[[:alpha:]&&a-z]")
    api_hir = Regex::Syntax.parse("[[:alpha:]&&a-z]")

    parser_hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
    api_hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
    parser_hir.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
      api_hir.node.as(Regex::Syntax::Hir::UnicodeClass).intervals
    )
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

    it "parses class intersection through the main parser" do
      hir = Regex::Syntax.parse("[a-c&&b-d]")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.intervals.should eq([('b'.ord.to_u32)..('c'.ord.to_u32)])
    end

    it "parses class difference through the main parser" do
      hir = Regex::Syntax.parse("[a-d--b-c]")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.intervals.should eq([
        ('a'.ord.to_u32)..('a'.ord.to_u32),
        ('d'.ord.to_u32)..('d'.ord.to_u32),
      ])
    end

    it "parses class symmetric difference through the main parser" do
      hir = Regex::Syntax.parse("[a-c~~c-e]")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.intervals.should eq([
        ('a'.ord.to_u32)..('b'.ord.to_u32),
        ('d'.ord.to_u32)..('e'.ord.to_u32),
      ])
    end

    it "parses ASCII classes through Parser directly" do
      hir = Regex::Syntax::Parser.new.parse("[[:alpha:]]")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.intervals.should eq([
        ('A'.ord.to_u32)..('Z'.ord.to_u32),
        ('a'.ord.to_u32)..('z'.ord.to_u32),
      ])
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
      look.kind.should eq(Regex::Syntax::Hir::Look::Kind::WordUnicode)
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
      look.kind.should eq(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF)
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

    it "rejects unsupported look-behind groups" do
      expect_raises(Regex::Syntax::ParseError, /look-behind/) do
        Regex::Syntax.parse("(?<=a)b")
      end

      expect_raises(Regex::Syntax::ParseError, /look-behind/) do
        Regex::Syntax.parse("(?<!a)b")
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
      multiline.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartLF)
    end

    it "supports Unicode and ASCII word-boundary toggles via inline flags" do
      unicode = Regex::Syntax.parse("(?u)\\b")
      unicode.node.should be_a(Regex::Syntax::Hir::Look)
      unicode.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordUnicode)

      ascii = Regex::Syntax.parse("(?-u)\\b")
      ascii.node.should be_a(Regex::Syntax::Hir::Look)
      ascii.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordAscii)
    end

    it "supports special word-boundary assertions" do
      start = Regex::Syntax.parse(%q(\b{start}))
      start.node.should be_a(Regex::Syntax::Hir::Look)
      start.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordStartUnicode)

      finish = Regex::Syntax.parse(%q(\b{end-half}))
      finish.node.should be_a(Regex::Syntax::Hir::Look)
      finish.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordEndHalfUnicode)
    end

    it "supports angle word-boundary assertions" do
      start = Regex::Syntax.parse(%q(\<))
      start.node.should be_a(Regex::Syntax::Hir::Look)
      start.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordStartUnicode)

      finish = Regex::Syntax.parse(%q(\>))
      finish.node.should be_a(Regex::Syntax::Hir::Look)
      finish.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordEndUnicode)
    end

    it "keeps counted repetitions after plain word boundaries" do
      hir = Regex::Syntax.parse(%q(\b{5}))
      hir.node.should be_a(Regex::Syntax::Hir::Repetition)
      repetition = hir.node.as(Regex::Syntax::Hir::Repetition)
      repetition.min.should eq(5)
      repetition.max.should eq(5)
      repetition.sub.should be_a(Regex::Syntax::Hir::Look)
      repetition.sub.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordUnicode)
    end

    it "supports CRLF-aware multiline assertions via inline flags" do
      hir = Regex::Syntax.parse("(?mR)^$")
      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      concat = hir.node.as(Regex::Syntax::Hir::Concat)
      concat.children[0].should be_a(Regex::Syntax::Hir::Look)
      concat.children[1].should be_a(Regex::Syntax::Hir::Look)
      concat.children[0].as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartCRLF)
      concat.children[1].as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndCRLF)
    end

    it "assigns sequential capture indices in HIR" do
      hir = Regex::Syntax.parse("(a)(b)")
      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      concat = hir.node.as(Regex::Syntax::Hir::Concat)
      concat.children[0].should be_a(Regex::Syntax::Hir::Capture)
      concat.children[1].should be_a(Regex::Syntax::Hir::Capture)
      concat.children[0].as(Regex::Syntax::Hir::Capture).index.should eq(1)
      concat.children[1].as(Regex::Syntax::Hir::Capture).index.should eq(2)
    end

    it "preserves named capture metadata in HIR" do
      hir = Regex::Syntax.parse("(?P<word>a)")
      hir.node.should be_a(Regex::Syntax::Hir::Capture)
      capture = hir.node.as(Regex::Syntax::Hir::Capture)
      capture.index.should eq(1)
      capture.name.should eq("word")
    end

    it "enforces nest_limit on repetitions" do
      expect_raises(Regex::Syntax::ParseError, /nest limit exceeded/) do
        Regex::Syntax::Parser.new(nest_limit: 0).parse("a+")
      end
    end

    it "raises on invalid Unicode properties" do
      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{DefinitelyNotAProperty}))
      end
    end

    it "supports octal escapes only when enabled" do
      expect_raises(Regex::Syntax::ParseError, /backreferences are not supported/) do
        Regex::Syntax.parse(%q(\141))
      end

      hir = Regex::Syntax::Parser.new(octal: true).parse(%q(\141))
      hir.node.should be_a(Regex::Syntax::Hir::Literal)
      String.new(hir.node.as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
    end

    it "computes overlapping class difference precisely" do
      hir = Regex::Syntax.parse("[a-c--b]")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      intervals = hir.node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      intervals.should eq([0x61_u32..0x61_u32, 0x63_u32..0x63_u32])
    end

    it "computes overlapping class symmetric difference precisely" do
      hir = Regex::Syntax.parse("[a-c~~b-d]")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      intervals = hir.node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      intervals.should eq([0x61_u32..0x61_u32, 0x64_u32..0x64_u32])
    end

    it "computes negated ASCII class complements on canonical intervals" do
      hir = Regex::Syntax::Parser.new(unicode: false).parse("[[:^digit:]]")
      hir.node.should be_a(Regex::Syntax::Hir::CharClass)
      intervals = hir.node.as(Regex::Syntax::Hir::CharClass).intervals
      intervals.first.should eq(0x00_u8..0x2F_u8)
      intervals.last.should eq(0x3A_u8..0xFF_u8)
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

      # Create ClassSetItem for the literal
      literal_item = Regex::Syntax::AST::ClassSetItem.new(
        span,
        Regex::Syntax::AST::ClassSetItem::Kind::Literal,
        item: literal
      )

      # Create ClassSetUnion with the item
      union = Regex::Syntax::AST::ClassSetUnion.new(span, [literal_item])

      # Create ClassSetItem for the union
      union_item = Regex::Syntax::AST::ClassSetItem.new(
        span,
        Regex::Syntax::AST::ClassSetItem::Kind::Union,
        item: union
      )

      # Create ClassSet
      class_set = Regex::Syntax::AST::ClassSet.new(
        span,
        Regex::Syntax::AST::ClassSet::Kind::Item,
        item: union_item
      )

      # Create ClassBracketed
      class_bracketed = Regex::Syntax::AST::ClassBracketed.new(span, false, class_set)
      class_bracketed.negated?.should be_false
      class_bracketed.kind.should be_a(Regex::Syntax::AST::ClassSet)
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

    it "parses general category queries" do
      hir = Regex::Syntax.parse(%q(\p{gc:Separator}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
      unicode_class.intervals.should eq(Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"])
    end

    it "parses Rust-style binary general category spellings" do
      uppercase = Regex::Syntax.parse(%q(\pZ))
      uppercase.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      uppercase.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )

      lowercase = Regex::Syntax.parse(%q(\pz))
      lowercase.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      lowercase.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )

      spaced = Regex::Syntax.parse(%q(\p{se      PaRa ToR}))
      spaced.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      spaced.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )
    end

    it "parses Rust-style Other general category spellings" do
      named = Regex::Syntax.parse(%q(\p{Other}))
      named.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      named.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["other"]
      )

      one_letter = Regex::Syntax.parse(%q(\pC))
      one_letter.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      one_letter.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["other"]
      )
    end

    it "parses script queries" do
      hir = Regex::Syntax.parse(%q(\p{sc=Greek}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
      unicode_class.intervals.should eq(Regex::Syntax::UnicodeTables::Script::BY_NAME["greek"])
    end

    it "case folds script queries like Rust" do
      plain = Regex::Syntax.parse(%q(\p{Greek})).node.as(Regex::Syntax::Hir::UnicodeClass)

      folded = Regex::Syntax.parse(%q((?i)\p{Greek})).node.as(Regex::Syntax::Hir::UnicodeClass)
      folded.negated?.should be_false
      folded.intervals.size.should be >= plain.intervals.size
      folded.intervals.any? { |range| range.begin <= 0x03A9_u32 && 0x03A9_u32 <= range.end }.should be_true

      negated = Regex::Syntax.parse(%q((?i)\P{Greek})).node.as(Regex::Syntax::Hir::UnicodeClass)
      negated.negated?.should be_true
      negated.intervals.should eq(folded.intervals)
    end

    it "parses script extension queries" do
      hir = Regex::Syntax.parse(%q(\p{scx:Greek}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
      unicode_class.intervals.should eq(Regex::Syntax::UnicodeTables::ScriptExtension::BY_NAME["greek"])
    end

    it "parses canonical Unicode property aliases from vendored tables" do
      gc = Regex::Syntax.parse(%q(\p{General_Category=zs}))
      gc.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      gc.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["spaceseparator"]
      )

      scx = Regex::Syntax.parse(%q(\p{Script_Extensions=Grek}))
      scx.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      scx.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::ScriptExtension::BY_NAME["greek"]
      )
    end

    it "normalizes Rust-style is-prefix Unicode aliases" do
      greek = Regex::Syntax.parse(%q(\p{isGreek}))
      greek.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      greek.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::Script::BY_NAME["greek"]
      )

      separator = Regex::Syntax.parse(%q(\p{IS_Separator}))
      separator.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      separator.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )
    end

    it "parses age queries" do
      hir = Regex::Syntax.parse(%q(\p{age:3.0}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
      unicode_class.intervals.any? { |range| range.begin <= 0x0041_u32 && 0x0041_u32 <= range.end }.should be_true
      unicode_class.intervals.any? { |range| range.begin <= 0x03D7_u32 && 0x03D7_u32 <= range.end }.should be_true
    end

    it "parses grapheme, word, and sentence break queries" do
      gcb = Regex::Syntax.parse(%q(\p{gcb:Extend}))
      gcb.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      gcb.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GraphemeClusterBreak::BY_NAME["extend"]
      )

      wb = Regex::Syntax.parse(%q(\p{wb:Katakana}))
      wb.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      wb.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::WordBreak::BY_NAME["katakana"]
      )

      sb = Regex::Syntax.parse(%q(\p{sb:ATerm}))
      sb.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      sb.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::SentenceBreak::BY_NAME["aterm"]
      )
    end

    it "parses not-equal Unicode property queries" do
      hir = Regex::Syntax.parse(%q(\p{gc!=Separator}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_true
      unicode_class.intervals.should eq(Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"])
    end

    it "handles Rust-style Unicode property double negation" do
      hir = Regex::Syntax.parse(%q(\P{gc!=separator}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
      unicode_class.intervals.should eq(Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"])
    end

    it "parses special binary Unicode properties" do
      any = Regex::Syntax.parse(%q(\p{Any}))
      any.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      any.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x0000_u32..0x10FFFF_u32])

      ascii = Regex::Syntax.parse(%q(\p{ASCII}))
      ascii.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      ascii.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x0000_u32..0x007F_u32])
    end

    it "parses Rust-style gc special values" do
      any = Regex::Syntax.parse(%q(\p{gc:any}))
      any.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      any.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x0000_u32..0x10FFFF_u32])

      assigned = Regex::Syntax.parse(%q(\p{gc:assigned}))
      assigned.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      assigned.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax.parse(%q(\p{assigned})).node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      )

      ascii = Regex::Syntax.parse(%q(\p{gc:ascii}))
      ascii.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      ascii.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([0x0000_u32..0x007F_u32])
    end

    it "canonicalizes complement of Any to the empty Unicode class" do
      hir = Regex::Syntax.parse(%q(\P{any}))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
      unicode_class.intervals.should be_empty
    end

    it "parses bracketed Unicode property escapes" do
      hir = Regex::Syntax.parse(%q([\pZ]))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      hir_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      hir_class.negated?.should be_false
      hir_class.intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )

      negated = Regex::Syntax.parse(%q([\PZ]))
      negated.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      negated_class = negated.node.as(Regex::Syntax::Hir::UnicodeClass)
      negated_class.negated?.should be_true
      negated_class.intervals.should eq(Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"])

      nested_negation = Regex::Syntax.parse(%q([^\PZ]))
      nested_negation.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      nested_negation.node.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_false
      nested_negation.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )
    end

    it "preserves Rust-style bracketed Unicode property negation shapes" do
      direct_negation = Regex::Syntax.parse(%q([^\pZ]))
      direct_negation.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      direct_negation_class = direct_negation.node.as(Regex::Syntax::Hir::UnicodeClass)
      direct_negation_class.negated?.should be_true
      direct_negation_class.intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )

      named_direct_negation = Regex::Syntax.parse(%q([^\p{separator}]))
      named_direct_negation.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      named_direct_negation.node.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_true
      named_direct_negation.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )

      named_nested_negation = Regex::Syntax.parse(%q([^\P{separator}]))
      named_nested_negation.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      named_nested_negation.node.as(Regex::Syntax::Hir::UnicodeClass).negated?.should be_false
      named_nested_negation.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["separator"]
      )
    end

    it "cancels bracketed Perl double negation like Rust" do
      hir = Regex::Syntax.parse(%q([^\D]))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_false
      unicode_class.intervals.should eq(Regex::Syntax.parse(%q(\d)).node.as(Regex::Syntax::Hir::UnicodeClass).intervals)
    end

    it "preserves bracketed negated Unicode properties under ignore-case" do
      folded = Regex::Syntax.parse(%q((?i)\p{Greek})).node.as(Regex::Syntax::Hir::UnicodeClass)
      hir = Regex::Syntax.parse(%q((?i)[\P{greek}]))
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_class = hir.node.as(Regex::Syntax::Hir::UnicodeClass)
      unicode_class.negated?.should be_true
      unicode_class.intervals.should eq(folded.intervals)
    end

    it "preserves Rust-style outer negation with ignore-case on Unicode properties" do
      folded = Regex::Syntax.parse(%q((?i)\p{Greek})).node.as(Regex::Syntax::Hir::UnicodeClass)

      direct_negation = Regex::Syntax.parse(%q((?i)[^\p{greek}]))
      direct_negation.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      direct_negation_class = direct_negation.node.as(Regex::Syntax::Hir::UnicodeClass)
      direct_negation_class.negated?.should be_true
      direct_negation_class.intervals.should eq(folded.intervals)

      nested_negation = Regex::Syntax.parse(%q((?i)[^\P{greek}]))
      nested_negation.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      nested_negation_class = nested_negation.node.as(Regex::Syntax::Hir::UnicodeClass)
      nested_negation_class.negated?.should be_false
      nested_negation_class.intervals.should eq(folded.intervals)
    end

    it "parses bracketed Unicode property unions and binary ops" do
      union = Regex::Syntax.parse(%q([\pZ\p{Greek}]))
      union.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      union_intervals = union.node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      union_intervals.should contain(32_u32..32_u32)
      union_intervals.any? { |range| range.begin <= 0x03A9_u32 && 0x03A9_u32 <= range.end }.should be_true

      difference = Regex::Syntax.parse(%q([\p{sc:Greek}~~\p{scx:Greek}]))
      difference.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      difference.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should_not be_empty
    end

    it "matches Rust's bracketed class behavior across Unicode and byte modes" do
      ascii = Regex::Syntax.parse(%q((?-u)[a]))
      ascii.node.should be_a(Regex::Syntax::Hir::CharClass)
      ascii.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x61_u8..0x61_u8])

      nul = Regex::Syntax.parse(%q((?-u)[\x00]))
      nul.node.should be_a(Regex::Syntax::Hir::CharClass)
      nul.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x00_u8..0x00_u8])

      ff = Regex::Syntax.parse(%q((?-u)[\xFF]))
      ff.node.should be_a(Regex::Syntax::Hir::CharClass)
      ff.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0xFF_u8..0xFF_u8])

      fold_ascii = Regex::Syntax.parse(%q((?i)[a]))
      fold_ascii.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      fold_ascii.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x41_u32..0x41_u32,
        0x61_u32..0x61_u32,
      ])

      fold_kelvin = Regex::Syntax.parse(%q((?i)[k]))
      fold_kelvin.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      fold_kelvin.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x004B_u32..0x004B_u32,
        0x006B_u32..0x006B_u32,
        0x212A_u32..0x212A_u32,
      ])

      fold_beta = Regex::Syntax.parse(%q((?i)[β]))
      fold_beta.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      fold_beta.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x0392_u32..0x0392_u32,
        0x03B2_u32..0x03B2_u32,
        0x03D0_u32..0x03D0_u32,
      ])

      ascii_ignore_case = Regex::Syntax.parse(%q((?i-u)[k]))
      ascii_ignore_case.node.should be_a(Regex::Syntax::Hir::CharClass)
      ascii_ignore_case.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        0x4B_u8..0x4B_u8,
        0x6B_u8..0x6B_u8,
      ])
    end

    it "uses Rust's cf/sc/lc binary special cases" do
      cf = Regex::Syntax.parse(%q(\p{cf}))
      cf.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      cf.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["format"]
      )

      sc = Regex::Syntax.parse(%q(\p{sc}))
      sc.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      sc.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["currencysymbol"]
      )

      lc = Regex::Syntax.parse(%q(\p{lc}))
      lc.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      lc.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME["casedletter"]
      )
    end

    it "raises on invalid script extension values" do
      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property value/) do
        Regex::Syntax.parse(%q(\p{scx:Foo}))
      end
    end

    it "raises on invalid age values" do
      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property value/) do
        Regex::Syntax.parse(%q(\p{age:Foo}))
      end
    end

    it "raises on unsupported Unicode property namespaces" do
      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{foo:bar}))
      end
    end

    it "raises on invalid one-letter Unicode properties" do
      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property/) do
        Regex::Syntax.parse(%q(\pE))
      end
    end

    it "does not treat non-binary property names as binary shorthands" do
      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{scx}))
      end
    end

    it "preserves the isc normalization special case" do
      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{isc}))
      end

      expect_raises(Regex::Syntax::ParseError, /invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{is c}))
      end
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
