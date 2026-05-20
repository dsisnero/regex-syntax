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
      concat.children[0].should be_a(Regex::Syntax::Hir::UnicodeClass)
      concat.children[1].should be_a(Regex::Syntax::Hir::UnicodeClass)
    end

    it "parses global inline flags (?i) for following expression" do
      hir = Regex::Syntax.parse("(?i)ab")
      hir.node.should be_a(Regex::Syntax::Hir::Concat)
      concat = hir.node.as(Regex::Syntax::Hir::Concat)
      concat.children.size.should eq(2)
      concat.children[0].should be_a(Regex::Syntax::Hir::UnicodeClass)
      concat.children[1].should be_a(Regex::Syntax::Hir::UnicodeClass)
    end

    it "rejects unsupported look-ahead groups" do
      expect_parse_error(/look-ahead/) do
        Regex::Syntax.parse("(?=a)b")
      end
    end

    it "rejects unsupported look-behind groups" do
      expect_parse_error(/look-behind/) do
        Regex::Syntax.parse("(?<=a)b")
      end

      expect_parse_error(/look-behind/) do
        Regex::Syntax.parse("(?<!a)b")
      end
    end

    it "supports verbose mode flag (?x)" do
      hir = Regex::Syntax.parse("(?x)a b # comment\n c")
      hir.node.should be_a(Regex::Syntax::Hir::Literal)
      String.new(hir.node.as(Regex::Syntax::Hir::Literal).bytes).should eq("abc")
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
      hir.node.should be_a(Regex::Syntax::Hir::Look)
      hir.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::WordUnicode)
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

    it "translates line-anchor flag combinations like Rust" do
      Regex::Syntax.parse(%q((?m)\A)).node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::StartText
      )
      Regex::Syntax.parse(%q((?m)\z)).node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::EndText
      )
      Regex::Syntax.parse("(?m)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::StartLF
      )
      Regex::Syntax.parse("(?m)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::EndLF
      )
      Regex::Syntax.parse("(?R)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::StartText
      )
      Regex::Syntax.parse("(?R)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF
      )
      Regex::Syntax.parse("(?Rm)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::StartCRLF
      )
      Regex::Syntax.parse("(?Rm)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::EndCRLF
      )
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

    it "translates capture-group variants like Rust" do
      empty_named = Regex::Syntax.parse("(?P<foo>)")
      empty_named.node.should be_a(Regex::Syntax::Hir::Capture)
      empty_capture = empty_named.node.as(Regex::Syntax::Hir::Capture)
      empty_capture.index.should eq(1)
      empty_capture.name.should eq("foo")
      empty_capture.sub.should be_a(Regex::Syntax::Hir::Empty)

      named_pair = Regex::Syntax.parse("(?P<foo>a)(?P<bar>b)")
      named_pair.node.should be_a(Regex::Syntax::Hir::Concat)
      pair_children = named_pair.node.as(Regex::Syntax::Hir::Concat).children
      pair_children[0].should be_a(Regex::Syntax::Hir::Capture)
      pair_children[1].should be_a(Regex::Syntax::Hir::Capture)
      pair_children[0].as(Regex::Syntax::Hir::Capture).name.should eq("foo")
      pair_children[0].as(Regex::Syntax::Hir::Capture).index.should eq(1)
      pair_children[1].as(Regex::Syntax::Hir::Capture).name.should eq("bar")
      pair_children[1].as(Regex::Syntax::Hir::Capture).index.should eq(2)

      noncapture = Regex::Syntax.parse("(?:)")
      noncapture.node.should be_a(Regex::Syntax::Hir::Empty)
    end

    it "translates scoped flag interactions like Rust" do
      byte_scoped = Regex::Syntax.parse("(?i-u:a)β")
      byte_scoped.node.should be_a(Regex::Syntax::Hir::Concat)
      byte_children = byte_scoped.node.as(Regex::Syntax::Hir::Concat).children
      byte_children.size.should eq(2)
      byte_children[1].should be_a(Regex::Syntax::Hir::Literal)
      String.new(byte_children[1].as(Regex::Syntax::Hir::Literal).bytes).should eq("β")
      byte_children[0].should be_a(Regex::Syntax::Hir::CharClass)
      byte_children[0].as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        0x41_u8..0x41_u8,
        0x61_u8..0x61_u8,
      ])

      nested = Regex::Syntax.parse("(?:(?i-u)a)b")
      nested.node.should be_a(Regex::Syntax::Hir::Concat)
      nested_children = nested.node.as(Regex::Syntax::Hir::Concat).children
      nested_children[0].should be_a(Regex::Syntax::Hir::CharClass)
      nested_children[1].should be_a(Regex::Syntax::Hir::Literal)
      String.new(nested_children[1].as(Regex::Syntax::Hir::Literal).bytes).should eq("b")

      captured = Regex::Syntax.parse("((?i-u)a)b")
      captured.node.should be_a(Regex::Syntax::Hir::Concat)
      captured_children = captured.node.as(Regex::Syntax::Hir::Concat).children
      captured_children[0].should be_a(Regex::Syntax::Hir::Capture)
      captured_children[0].as(Regex::Syntax::Hir::Capture).sub.should be_a(Regex::Syntax::Hir::CharClass)
      captured_children[1].should be_a(Regex::Syntax::Hir::Literal)

      mixed = Regex::Syntax.parse("(?i)(?-i:a)a")
      mixed.node.should be_a(Regex::Syntax::Hir::Concat)
      mixed_children = mixed.node.as(Regex::Syntax::Hir::Concat).children
      mixed_children[0].should be_a(Regex::Syntax::Hir::Literal)
      String.new(mixed_children[0].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
      mixed_children[1].should be_a(Regex::Syntax::Hir::UnicodeClass)

      multiline = Regex::Syntax.parse("(?im)a^")
      multiline.node.should be_a(Regex::Syntax::Hir::Concat)
      multiline_children = multiline.node.as(Regex::Syntax::Hir::Concat).children
      multiline_children[0].should be_a(Regex::Syntax::Hir::UnicodeClass)
      multiline_children[1].should be_a(Regex::Syntax::Hir::Look)
      multiline_children[1].as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartLF)

      mixed_multiline = Regex::Syntax.parse("(?im)a^(?i-m)a^")
      mixed_multiline.node.should be_a(Regex::Syntax::Hir::Concat)
      mixed_multiline_children = mixed_multiline.node.as(Regex::Syntax::Hir::Concat).children
      mixed_multiline_children.size.should eq(4)
      mixed_multiline_children[1].as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartLF)
      mixed_multiline_children[3].as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)

      nested_scoped = Regex::Syntax.parse("(?:a(?i)a)a")
      nested_scoped.node.should be_a(Regex::Syntax::Hir::Concat)
      nested_scoped_children = nested_scoped.node.as(Regex::Syntax::Hir::Concat).children
      nested_scoped_children.size.should eq(3)
      nested_scoped_children[0].should be_a(Regex::Syntax::Hir::Literal)
      String.new(nested_scoped_children[0].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
      nested_scoped_children[1].should be_a(Regex::Syntax::Hir::UnicodeClass)
      nested_scoped_children[2].should be_a(Regex::Syntax::Hir::Literal)
      String.new(nested_scoped_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")

      nested_reset = Regex::Syntax.parse("(?i)(?:a(?-i)a)a")
      nested_reset.node.should be_a(Regex::Syntax::Hir::Concat)
      nested_reset_children = nested_reset.node.as(Regex::Syntax::Hir::Concat).children
      nested_reset_children.size.should eq(3)
      nested_reset_children[0].should be_a(Regex::Syntax::Hir::UnicodeClass)
      nested_reset_children[1].should be_a(Regex::Syntax::Hir::Literal)
      String.new(nested_reset_children[1].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
      nested_reset_children[2].should be_a(Regex::Syntax::Hir::UnicodeClass)

      swap = Regex::Syntax.parse("(?U)a*a*?(?-U)a*a*?")
      swap.node.should be_a(Regex::Syntax::Hir::Concat)
      swap_children = swap.node.as(Regex::Syntax::Hir::Concat).children
      swap_children.size.should eq(4)
      swap_children.each(&.should be_a(Regex::Syntax::Hir::Repetition))
      swap_children[0].as(Regex::Syntax::Hir::Repetition).greedy?.should be_false
      swap_children[1].as(Regex::Syntax::Hir::Repetition).greedy?.should be_true
      swap_children[2].as(Regex::Syntax::Hir::Repetition).greedy?.should be_true
      swap_children[3].as(Regex::Syntax::Hir::Repetition).greedy?.should be_false
    end

    it "enforces nest_limit on repetitions" do
      expect_parse_error(/nest limit exceeded/) do
        Regex::Syntax::Parser.new(nest_limit: 0).parse("a+")
      end
    end

    it "raises on invalid Unicode properties" do
      expect_parse_error(/invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{DefinitelyNotAProperty}))
      end
    end

    it "supports octal escapes only when enabled" do
      expect_parse_error(/backreferences are not supported/) do
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
      hir = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("[[:^digit:]]")
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

  describe "hir class operations" do
    it "canonicalizes byte and unicode classes like Rust" do
      bytes = Regex::Syntax::Hir::CharClass.new(false, [0x78_u8..0x7A_u8, 0x77_u8..0x79_u8, 0x61_u8..0x63_u8])
      bytes.intervals.should eq([0x61_u8..0x63_u8, 0x77_u8..0x7A_u8])

      unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [0x78_u32..0x7A_u32, 0x77_u32..0x79_u32, 0x61_u32..0x63_u32])
      unicode.intervals.should eq([0x61_u32..0x63_u32, 0x77_u32..0x7A_u32])
    end

    it "canonicalizes reversed byte and unicode ranges like Rust" do
      bytes = Regex::Syntax::Hir::CharClass.new(false, [0xFF_u8..0x00_u8])
      bytes.intervals.should eq([0x00_u8..0xFF_u8])

      unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [0x00FF_u32..0x0000_u32])
      unicode.intervals.should eq([0x0000_u32..0x00FF_u32])
    end

    it "case folds byte and unicode classes like Rust" do
      bytes = Regex::Syntax::Hir::CharClass.new(false, [0x6B_u8..0x6B_u8])
      bytes.case_fold_simple
      bytes.intervals.should eq([0x4B_u8..0x4B_u8, 0x6B_u8..0x6B_u8])

      unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [0x6B_u32..0x6B_u32])
      unicode.case_fold_simple
      unicode.intervals.should eq([0x4B_u32..0x4B_u32, 0x6B_u32..0x6B_u32, 0x212A_u32..0x212A_u32])
    end

    it "negates and combines byte classes like Rust" do
      negated = Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x61_u8])
      negated.negate
      negated.intervals.should eq([0x00_u8..0x60_u8, 0x62_u8..0xFF_u8])

      union = Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x67_u8, 0x6D_u8..0x74_u8, 0x41_u8..0x43_u8])
      union.union(Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x7A_u8]))
      union.intervals.should eq([0x41_u8..0x43_u8, 0x61_u8..0x7A_u8])

      intersection = Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x62_u8, 0x63_u8..0x64_u8, 0x65_u8..0x66_u8])
      intersection.intersect(Regex::Syntax::Hir::CharClass.new(false, [0x62_u8..0x63_u8, 0x64_u8..0x65_u8, 0x66_u8..0x67_u8]))
      intersection.intervals.should eq([0x62_u8..0x66_u8])

      difference = Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x7A_u8])
      difference.difference(Regex::Syntax::Hir::CharClass.new(false, [0x6D_u8..0x6D_u8]))
      difference.intervals.should eq([0x61_u8..0x6C_u8, 0x6E_u8..0x7A_u8])
    end

    it "negates and combines unicode classes like Rust" do
      negated = Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x61_u32])
      negated.negate
      negated.intervals.should eq([0x00_u32..0x60_u32, 0x62_u32..0x10FFFF_u32])

      union = Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x67_u32, 0x6D_u32..0x74_u32, 0x41_u32..0x43_u32])
      union.union(Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x7A_u32]))
      union.intervals.should eq([0x41_u32..0x43_u32, 0x61_u32..0x7A_u32])

      intersection = Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x62_u32, 0x63_u32..0x64_u32, 0x65_u32..0x66_u32])
      intersection.intersect(Regex::Syntax::Hir::UnicodeClass.new(false, [0x62_u32..0x63_u32, 0x64_u32..0x65_u32, 0x66_u32..0x67_u32]))
      intersection.intervals.should eq([0x62_u32..0x66_u32])

      difference = Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x7A_u32])
      difference.difference(Regex::Syntax::Hir::UnicodeClass.new(false, [0x6D_u32..0x6D_u32]))
      difference.intervals.should eq([0x61_u32..0x6C_u32, 0x6E_u32..0x7A_u32])
    end

    it "computes symmetric difference for byte and unicode classes like Rust" do
      bytes = Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0x6D_u8])
      bytes.symmetric_difference(Regex::Syntax::Hir::CharClass.new(false, [0x67_u8..0x74_u8]))
      bytes.intervals.should eq([0x61_u8..0x66_u8, 0x6E_u8..0x74_u8])

      unicode = Regex::Syntax::Hir::UnicodeClass.new(false, [0x61_u32..0x6D_u32])
      unicode.symmetric_difference(Regex::Syntax::Hir::UnicodeClass.new(false, [0x67_u32..0x74_u32]))
      unicode.intervals.should eq([0x61_u32..0x66_u32, 0x6E_u32..0x74_u32])
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
      hir.node.should be_a(Regex::Syntax::Hir::Literal)
      literal = hir.node.as(Regex::Syntax::Hir::Literal)
      String.new(literal.bytes).should eq(".+*?()|[]{}^$#&-~")
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
      ascii = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("[a]")
      ascii.node.should be_a(Regex::Syntax::Hir::CharClass)
      ascii.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x61_u8..0x61_u8])

      nul = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q([\x00]))
      nul.node.should be_a(Regex::Syntax::Hir::CharClass)
      nul.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x00_u8..0x00_u8])

      ff = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q([\xFF]))
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

      ascii_ignore_case = Regex::Syntax::Parser.new(unicode: false, utf8: false, ignore_case: true).parse("[k]")
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
      expect_parse_error(/invalid Unicode property value/) do
        Regex::Syntax.parse(%q(\p{scx:Foo}))
      end
    end

    it "raises on invalid age values" do
      expect_parse_error(/invalid Unicode property value/) do
        Regex::Syntax.parse(%q(\p{age:Foo}))
      end
    end

    it "rejects Unicode property classes in byte mode like Rust" do
      expect_parse_error(/Unicode not allowed/) do
        Regex::Syntax::Parser.new(unicode: false).parse(%q(\pZ))
      end

      expect_parse_error(/Unicode not allowed/) do
        Regex::Syntax::Parser.new(unicode: false).parse(%q(\p{Separator}))
      end

      expect_parse_error(/Unicode not allowed/) do
        Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q([\pZ]))
      end
    end

    it "rejects non-ASCII scalar literals in byte classes like Rust" do
      expect_parse_error(/Unicode not allowed/) do
        Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("[Δ]")
      end

      expect_parse_error(/Unicode not allowed/) do
        Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("[é]")
      end

      byte_class = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q([\xFF]))
      byte_class.node.should be_a(Regex::Syntax::Hir::CharClass)
      byte_class.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0xFF_u8..0xFF_u8])
    end

    it "raises on unsupported Unicode property namespaces" do
      expect_parse_error(/invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{foo:bar}))
      end
    end

    it "raises on invalid one-letter Unicode properties" do
      expect_parse_error(/invalid Unicode property/) do
        Regex::Syntax.parse(%q(\pE))
      end
    end

    it "does not treat non-binary property names as binary shorthands" do
      expect_parse_error(/invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{scx}))
      end
    end

    it "preserves the isc normalization special case" do
      expect_parse_error(/invalid Unicode property/) do
        Regex::Syntax.parse(%q(\p{isc}))
      end

      expect_parse_error(/invalid Unicode property/) do
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

  describe "translator parity" do
    it "translates empty expressions like Rust" do
      Regex::Syntax.parse("").node.should be_a(Regex::Syntax::Hir::Empty)
      Regex::Syntax.parse("(?i)").node.should be_a(Regex::Syntax::Hir::Empty)
      Regex::Syntax.parse("(?:)").node.should be_a(Regex::Syntax::Hir::Empty)

      capture = Regex::Syntax.parse("()")
      capture.node.should be_a(Regex::Syntax::Hir::Capture)
      capture.node.as(Regex::Syntax::Hir::Capture).sub.should be_a(Regex::Syntax::Hir::Empty)

      named_capture = Regex::Syntax.parse("(?P<wat>)")
      named_capture.node.should be_a(Regex::Syntax::Hir::Capture)
      named = named_capture.node.as(Regex::Syntax::Hir::Capture)
      named.index.should eq(1)
      named.name.should eq("wat")
      named.sub.should be_a(Regex::Syntax::Hir::Empty)

      alternation = Regex::Syntax.parse("|")
      alternation.node.should be_a(Regex::Syntax::Hir::Alternation)
      alternation.node.as(Regex::Syntax::Hir::Alternation).children.map(&.class).should eq([
        Regex::Syntax::Hir::Empty,
        Regex::Syntax::Hir::Empty,
      ])

      mixed = Regex::Syntax.parse("(a||c)")
      mixed.node.should be_a(Regex::Syntax::Hir::Capture)
      mixed_alt = mixed.node.as(Regex::Syntax::Hir::Capture).sub
      mixed_alt.should be_a(Regex::Syntax::Hir::Alternation)
      mixed_alt.as(Regex::Syntax::Hir::Alternation).children.map(&.class).should eq([
        Regex::Syntax::Hir::Literal,
        Regex::Syntax::Hir::Empty,
        Regex::Syntax::Hir::Literal,
      ])
    end

    it "translates literals and escapes like Rust" do
      literal = Regex::Syntax.parse("abcd")
      literal.node.should be_a(Regex::Syntax::Hir::Literal)
      String.new(literal.node.as(Regex::Syntax::Hir::Literal).bytes).should eq("abcd")

      snowman = Regex::Syntax.parse("☃")
      snowman.node.should be_a(Regex::Syntax::Hir::Literal)
      String.new(snowman.node.as(Regex::Syntax::Hir::Literal).bytes).should eq("☃")

      escaped = Regex::Syntax.parse(%q(\\\.\+\*\?\(\)\|\[\]\{\}\^\$\#))
      escaped.node.should be_a(Regex::Syntax::Hir::Literal)
      String.new(escaped.node.as(Regex::Syntax::Hir::Literal).bytes).should eq(%q(\.+*?()|[]{}^$#))

      byte_literal = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)\xFF))
      byte_literal.node.should be_a(Regex::Syntax::Hir::Literal)
      byte_literal.node.as(Regex::Syntax::Hir::Literal).bytes.should eq(Bytes[0xFF_u8])

      expect_hir_error(
        Regex::Syntax::Hir::ErrorKind::InvalidUtf8,
        Regex::Syntax::AST::Span.new(5, 9)
      ) { Regex::Syntax.parse(%q((?-u)\xFF)) }
    end

    it "translates case-insensitive literals like Rust" do
      unicode_single = Regex::Syntax.parse("(?i)a")
      unicode_single.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_single.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x41_u32..0x41_u32,
        0x61_u32..0x61_u32,
      ])

      unicode_scoped = Regex::Syntax.parse("(?i:a)")
      unicode_scoped.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode_scoped.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x41_u32..0x41_u32,
        0x61_u32..0x61_u32,
      ])

      mixed_case = Regex::Syntax.parse("a(?i)a(?-i)a")
      mixed_case.node.should be_a(Regex::Syntax::Hir::Concat)
      mixed_children = mixed_case.node.as(Regex::Syntax::Hir::Concat).children
      mixed_children.size.should eq(3)
      mixed_children[0].should be_a(Regex::Syntax::Hir::Literal)
      String.new(mixed_children[0].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
      mixed_children[1].should be_a(Regex::Syntax::Hir::UnicodeClass)
      mixed_children[1].as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x41_u32..0x41_u32,
        0x61_u32..0x61_u32,
      ])
      mixed_children[2].should be_a(Regex::Syntax::Hir::Literal)
      String.new(mixed_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")

      punctuation = Regex::Syntax.parse("(?i)ab@c")
      punctuation.node.should be_a(Regex::Syntax::Hir::Concat)
      punctuation_children = punctuation.node.as(Regex::Syntax::Hir::Concat).children
      punctuation_children.size.should eq(4)
      punctuation_children[0].should be_a(Regex::Syntax::Hir::UnicodeClass)
      punctuation_children[1].should be_a(Regex::Syntax::Hir::UnicodeClass)
      punctuation_children[2].should be_a(Regex::Syntax::Hir::Literal)
      String.new(punctuation_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("@")
      punctuation_children[3].should be_a(Regex::Syntax::Hir::UnicodeClass)

      greek = Regex::Syntax.parse("(?i)β")
      greek.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      greek.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x0392_u32..0x0392_u32,
        0x03B2_u32..0x03B2_u32,
        0x03D0_u32..0x03D0_u32,
      ])

      byte_single = Regex::Syntax.parse("(?i-u)a")
      byte_single.node.should be_a(Regex::Syntax::Hir::CharClass)
      byte_single.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        0x41_u8..0x41_u8,
        0x61_u8..0x61_u8,
      ])

      byte_mixed_case = Regex::Syntax.parse("(?-u)a(?i)a(?-i)a")
      byte_mixed_case.node.should be_a(Regex::Syntax::Hir::Concat)
      byte_mixed_children = byte_mixed_case.node.as(Regex::Syntax::Hir::Concat).children
      byte_mixed_children.size.should eq(3)
      byte_mixed_children[0].should be_a(Regex::Syntax::Hir::Literal)
      String.new(byte_mixed_children[0].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")
      byte_mixed_children[1].should be_a(Regex::Syntax::Hir::CharClass)
      byte_mixed_children[1].as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        0x41_u8..0x41_u8,
        0x61_u8..0x61_u8,
      ])
      byte_mixed_children[2].should be_a(Regex::Syntax::Hir::Literal)
      String.new(byte_mixed_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("a")

      byte_sequence = Regex::Syntax.parse("(?i-u)ab@c")
      byte_sequence.node.should be_a(Regex::Syntax::Hir::Concat)
      byte_sequence_children = byte_sequence.node.as(Regex::Syntax::Hir::Concat).children
      byte_sequence_children.size.should eq(4)
      byte_sequence_children[0].should be_a(Regex::Syntax::Hir::CharClass)
      byte_sequence_children[1].should be_a(Regex::Syntax::Hir::CharClass)
      byte_sequence_children[2].should be_a(Regex::Syntax::Hir::Literal)
      String.new(byte_sequence_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("@")
      byte_sequence_children[3].should be_a(Regex::Syntax::Hir::CharClass)

      byte_hex = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?i-u)\x61))
      byte_hex.node.should be_a(Regex::Syntax::Hir::CharClass)
      byte_hex.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        0x41_u8..0x41_u8,
        0x61_u8..0x61_u8,
      ])

      byte_ff = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?i-u)\xFF))
      byte_ff.node.should be_a(Regex::Syntax::Hir::Literal)
      byte_ff.node.as(Regex::Syntax::Hir::Literal).bytes.should eq(Bytes[0xFF_u8])

      byte_unicode = Regex::Syntax.parse("(?i-u)β")
      byte_unicode.node.should be_a(Regex::Syntax::Hir::Literal)
      String.new(byte_unicode.node.as(Regex::Syntax::Hir::Literal).bytes).should eq("β")

      byte_single_bytes = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?i-u)a")
      byte_single_bytes.node.should be_a(Regex::Syntax::Hir::CharClass)
      byte_single_bytes.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        0x41_u8..0x41_u8,
        0x61_u8..0x61_u8,
      ])
    end

    it "translates dot and line anchors like Rust" do
      dot = Regex::Syntax.parse(".")
      dot.node.should be_a(Regex::Syntax::Hir::DotNode)
      dot.node.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyCharExceptLF)

      dotall = Regex::Syntax.parse("(?s).")
      dotall.node.should be_a(Regex::Syntax::Hir::DotNode)
      dotall.node.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyChar)

      byte_dot = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?-u).")
      byte_dot.node.should be_a(Regex::Syntax::Hir::DotNode)
      byte_dot.node.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyByteExceptLF)

      crlf_dot = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?R-u).")
      crlf_dot.node.should be_a(Regex::Syntax::Hir::DotNode)
      crlf_dot.node.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyByteExceptCRLF)

      expect_hir_error(
        Regex::Syntax::Hir::ErrorKind::InvalidUtf8,
        Regex::Syntax::AST::Span.new(5, 6)
      ) { Regex::Syntax.parse("(?-u).") }

      expect_hir_error(
        Regex::Syntax::Hir::ErrorKind::InvalidUtf8,
        Regex::Syntax::AST::Span.new(6, 7)
      ) { Regex::Syntax.parse("(?R-u).") }

      expect_hir_error(
        Regex::Syntax::Hir::ErrorKind::InvalidUtf8,
        Regex::Syntax::AST::Span.new(6, 7)
      ) { Regex::Syntax.parse("(?s-u).") }

      expect_hir_error(
        Regex::Syntax::Hir::ErrorKind::InvalidUtf8,
        Regex::Syntax::AST::Span.new(7, 8)
      ) { Regex::Syntax.parse("(?Rs-u).") }

      Regex::Syntax.parse("^").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
      Regex::Syntax.parse("$").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF)
      Regex::Syntax.parse(%q(\A)).node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
      Regex::Syntax.parse(%q(\z)).node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndText)
      Regex::Syntax.parse("(?m)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartLF)
      Regex::Syntax.parse("(?m)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndLF)
      Regex::Syntax.parse("(?R)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
      Regex::Syntax.parse("(?R)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF)
      Regex::Syntax.parse("(?Rm)^").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartCRLF)
      Regex::Syntax.parse("(?Rm)$").node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::EndCRLF)
    end

    it "translates ASCII classes like Rust" do
      lower = Regex::Syntax.parse("[[:lower:]]")
      lower.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      lower.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        ('a'.ord.to_u32)..('z'.ord.to_u32),
      ])

      negated_lower = Regex::Syntax.parse("[[:^lower:]]")
      negated_lower.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      negated_lower.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0_u32..('a'.ord.to_u32 - 1),
        ('z'.ord.to_u32 + 1)..0x10FFFF_u32,
      ])

      folded_lower = Regex::Syntax.parse("(?i)[[:lower:]]")
      folded_lower.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      folded_lower.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        ('A'.ord.to_u32)..('Z'.ord.to_u32),
        ('a'.ord.to_u32)..('z'.ord.to_u32),
        0x017F_u32..0x017F_u32,
        0x212A_u32..0x212A_u32,
      ])

      byte_lower = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?-u)[[:lower:]]")
      byte_lower.node.should be_a(Regex::Syntax::Hir::CharClass)
      byte_lower.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        ('a'.ord.to_u8)..('z'.ord.to_u8),
      ])

      folded_byte_lower = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?i-u)[[:lower:]]")
      folded_byte_lower.node.should be_a(Regex::Syntax::Hir::CharClass)
      folded_byte_lower.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        ('A'.ord.to_u8)..('Z'.ord.to_u8),
        ('a'.ord.to_u8)..('z'.ord.to_u8),
      ])

      expect_parse_error(/invalid UTF-8/) do
        Regex::Syntax.parse("(?-u)[[:^lower:]]")
      end

      expect_parse_error(/invalid UTF-8/) do
        Regex::Syntax.parse("(?i-u)[[:^lower:]]")
      end
    end

    it "translates multiple ASCII classes in one bracketed class like Rust" do
      unicode = Regex::Syntax.parse("[[:alnum:][:^ascii:]]")
      unicode.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        ('0'.ord.to_u32)..('9'.ord.to_u32),
        ('A'.ord.to_u32)..('Z'.ord.to_u32),
        ('a'.ord.to_u32)..('z'.ord.to_u32),
        0x80_u32..0x10FFFF_u32,
      ])

      bytes = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?-u)[[:alnum:][:^ascii:]]")
      bytes.node.should be_a(Regex::Syntax::Hir::CharClass)
      bytes.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        ('0'.ord.to_u8)..('9'.ord.to_u8),
        ('A'.ord.to_u8)..('Z'.ord.to_u8),
        ('a'.ord.to_u8)..('z'.ord.to_u8),
        0x80_u8..0xFF_u8,
      ])
    end

    it "flattens class-only alternations like Rust" do
      unicode = Regex::Syntax.parse("[a-z]|[A-Z]")
      unicode.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      unicode.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        ('A'.ord.to_u32)..('Z'.ord.to_u32),
        ('a'.ord.to_u32)..('z'.ord.to_u32),
      ])

      mixed_invalid = Regex::Syntax::Parser.new(utf8: false).parse("[Δδ]|(?-u:[\\x90-\\xFF])|[Λλ]")
      mixed_invalid.node.should be_a(Regex::Syntax::Hir::Alternation)
      mixed_invalid.node.as(Regex::Syntax::Hir::Alternation).children.map(&.class).should eq([
        Regex::Syntax::Hir::UnicodeClass,
        Regex::Syntax::Hir::CharClass,
        Regex::Syntax::Hir::UnicodeClass,
      ])

      byte_union = Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("[a-z]|(?-u:[\\x90-\\xFF])|[A-Z]")
      byte_union.node.should be_a(Regex::Syntax::Hir::CharClass)
      byte_union.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([
        ('A'.ord.to_u8)..('Z'.ord.to_u8),
        ('a'.ord.to_u8)..('z'.ord.to_u8),
        0x90_u8..0xFF_u8,
      ])
    end

    it "translates Unicode Perl classes like Rust" do
      digit = Regex::Syntax.parse("\\d")
      digit.node.should be_a(Regex::Syntax::Hir::UnicodeClass)

      space = Regex::Syntax.parse("\\s")
      space.node.should be_a(Regex::Syntax::Hir::UnicodeClass)

      word = Regex::Syntax.parse("\\w")
      word.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      word.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.any? { |range| range.begin <= 0x00AA_u32 && 0x00AA_u32 <= range.end }.should be_true

      folded_digit = Regex::Syntax.parse("(?i)\\d")
      folded_digit.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      folded_digit.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        digit.node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      )

      folded_space = Regex::Syntax.parse("(?i)\\s")
      folded_space.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      folded_space.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        space.node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      )

      folded_word = Regex::Syntax.parse("(?i)\\w")
      folded_word.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      folded_word.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        word.node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      )
    end

    it "translates ignore-whitespace escape cases like Rust" do
      Regex::Syntax::ParserBuilder.new.octal(true).build.parse("(?x)\\12 3").node.as(Regex::Syntax::Hir::Literal).bytes.should eq("\n3".to_slice)
      Regex::Syntax.parse("(?x)\\x { 53 }").node.as(Regex::Syntax::Hir::Literal).bytes.should eq("S".to_slice)
      Regex::Syntax.parse("(?x)\\x 53").node.as(Regex::Syntax::Hir::Literal).bytes.should eq("S".to_slice)
      Regex::Syntax.parse("(?x)\\x5 3").node.as(Regex::Syntax::Hir::Literal).bytes.should eq("S".to_slice)

      verbose_property = Regex::Syntax.parse("(?x)\\p # comment\n{ # comment\n    Separator # comment\n} # comment")
      verbose_property.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      verbose_property.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq(
        Regex::Syntax.parse("\\p{Separator}").node.as(Regex::Syntax::Hir::UnicodeClass).intervals
      )
    end

    it "rejects invalid UTF-8 byte classes like Rust when utf8 is enabled" do
      {
        %q((?-u)\D),
        %q((?-u)\S),
        %q((?-u)\W),
        %q((?i-u)\D),
        %q((?i-u)\S),
        %q((?i-u)\W),
        %q((?-u)[^a]),
        %q((?-u)[[:^lower:]]),
      }.each do |pattern|
        expect_parse_error(/invalid UTF-8/) do
          Regex::Syntax.parse(pattern)
        end
      end
    end

    it "allows the same byte classes like Rust when utf8 is disabled" do
      parser = Regex::Syntax::Parser.new(unicode: false, utf8: false)

      parser.parse(%q(\D)).node.should be_a(Regex::Syntax::Hir::CharClass)
      parser.parse(%q(\S)).node.should be_a(Regex::Syntax::Hir::CharClass)
      parser.parse(%q(\W)).node.should be_a(Regex::Syntax::Hir::CharClass)

      negated_literal = parser.parse(%q([^a]))
      negated_literal.node.should be_a(Regex::Syntax::Hir::CharClass)
      negated_literal.node.as(Regex::Syntax::Hir::CharClass).negated?.should be_true
      negated_literal.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0x61_u8..0x61_u8])

      negated_ascii = parser.parse(%q([[:^lower:]]))
      negated_ascii.node.should be_a(Regex::Syntax::Hir::CharClass)
      negated_ascii.node.as(Regex::Syntax::Hir::CharClass).negated?.should be_false
      negated_ascii.node.as(Regex::Syntax::Hir::CharClass).intervals.first.should eq(0x00_u8..0x60_u8)
      negated_ascii.node.as(Regex::Syntax::Hir::CharClass).intervals.last.should eq(0x7B_u8..0xFF_u8)
    end

    it "translates repetition and smart repetition like Rust" do
      Regex::Syntax.parse("a{0}").node.should be_a(Regex::Syntax::Hir::Empty)
      Regex::Syntax.parse("a{1}").node.should be_a(Regex::Syntax::Hir::Literal)
      Regex::Syntax.parse(%q(\B{32111})).node.as(Regex::Syntax::Hir::Look).kind.should eq(
        Regex::Syntax::Hir::Look::Kind::WordUnicodeNegate
      )

      optional = Regex::Syntax.parse("a?")
      optional.node.should be_a(Regex::Syntax::Hir::Repetition)
      optional_rep = optional.node.as(Regex::Syntax::Hir::Repetition)
      optional_rep.min.should eq(0_u32)
      optional_rep.max.should eq(1_u32)
      optional_rep.greedy?.should be_true

      lazy_range = Regex::Syntax.parse("a{1,2}?")
      lazy_range.node.should be_a(Regex::Syntax::Hir::Repetition)
      lazy_rep = lazy_range.node.as(Regex::Syntax::Hir::Repetition)
      lazy_rep.min.should eq(1_u32)
      lazy_rep.max.should eq(2_u32)
      lazy_rep.greedy?.should be_false

      concat = Regex::Syntax.parse("ab?")
      concat.node.should be_a(Regex::Syntax::Hir::Concat)
      concat_children = concat.node.as(Regex::Syntax::Hir::Concat).children
      concat_children[0].should be_a(Regex::Syntax::Hir::Literal)
      concat_children[1].should be_a(Regex::Syntax::Hir::Repetition)

      capture = Regex::Syntax.parse("(ab)?")
      capture.node.should be_a(Regex::Syntax::Hir::Repetition)
      capture.node.as(Regex::Syntax::Hir::Repetition).sub.should be_a(Regex::Syntax::Hir::Capture)

      alternation = Regex::Syntax.parse("a|b?")
      alternation.node.should be_a(Regex::Syntax::Hir::Alternation)
      alternation.node.as(Regex::Syntax::Hir::Alternation).children.map(&.class).should eq([
        Regex::Syntax::Hir::Literal,
        Regex::Syntax::Hir::Repetition,
      ])
    end

    it "flattens concat and alternation like Rust" do
      Regex::Syntax.parse("abc").node.should be_a(Regex::Syntax::Hir::Literal)
      Regex::Syntax.parse("(?:foo)(?:bar)").node.should be_a(Regex::Syntax::Hir::Literal)
      String.new(Regex::Syntax.parse("(?:foo)(?:bar)").node.as(Regex::Syntax::Hir::Literal).bytes).should eq("foobar")
      String.new(Regex::Syntax.parse("quux(?:foo)(?:bar)baz").node.as(Regex::Syntax::Hir::Literal).bytes).should eq("quuxfoobarbaz")

      smart_concat = Regex::Syntax.parse("foo(?:bar^baz)quux")
      smart_concat.node.should be_a(Regex::Syntax::Hir::Concat)
      smart_concat_children = smart_concat.node.as(Regex::Syntax::Hir::Concat).children
      smart_concat_children[0].should be_a(Regex::Syntax::Hir::Literal)
      String.new(smart_concat_children[0].as(Regex::Syntax::Hir::Literal).bytes).should eq("foobar")
      smart_concat_children[1].should be_a(Regex::Syntax::Hir::Look)
      smart_concat_children[1].as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
      smart_concat_children[2].should be_a(Regex::Syntax::Hir::Literal)
      String.new(smart_concat_children[2].as(Regex::Syntax::Hir::Literal).bytes).should eq("bazquux")

      simple_alt = Regex::Syntax.parse("(?:foo)|(?:bar)")
      simple_alt.node.should be_a(Regex::Syntax::Hir::Alternation)
      simple_alt.node.as(Regex::Syntax::Hir::Alternation).children.map { |node|
        String.new(node.as(Regex::Syntax::Hir::Literal).bytes)
      }.should eq(["foo", "bar"])

      nested_alt = Regex::Syntax.parse("quux|(?:abc|(?:def|mno)|xyz)|baz")
      nested_alt.node.should be_a(Regex::Syntax::Hir::Alternation)
      nested_alt.node.as(Regex::Syntax::Hir::Alternation).children.map { |node|
        String.new(node.as(Regex::Syntax::Hir::Literal).bytes)
      }.should eq(["quux", "abc", "def", "mno", "xyz", "baz"])
    end

    it "preserves look-only concat and alternation structure like Rust" do
      cat = Regex::Syntax.parse("(^$)")
      cat.node.should be_a(Regex::Syntax::Hir::Capture)
      cat_sub = cat.node.as(Regex::Syntax::Hir::Capture).sub
      cat_sub.should be_a(Regex::Syntax::Hir::Concat)
      cat_sub.as(Regex::Syntax::Hir::Concat).children.map(&.class).should eq([
        Regex::Syntax::Hir::Look,
        Regex::Syntax::Hir::Look,
      ])

      alt = Regex::Syntax.parse("^|$|\\b")
      alt.node.should be_a(Regex::Syntax::Hir::Alternation)
      alt.node.as(Regex::Syntax::Hir::Alternation).children.map(&.class).should eq([
        Regex::Syntax::Hir::Look,
        Regex::Syntax::Hir::Look,
        Regex::Syntax::Hir::Look,
      ])

      nested = Regex::Syntax.parse(%q((^$|$\b|\b\B)))
      nested.node.should be_a(Regex::Syntax::Hir::Capture)
      nested_alt = nested.node.as(Regex::Syntax::Hir::Capture).sub
      nested_alt.should be_a(Regex::Syntax::Hir::Alternation)
      nested_alt.as(Regex::Syntax::Hir::Alternation).children.map(&.class).should eq([
        Regex::Syntax::Hir::Concat,
        Regex::Syntax::Hir::Concat,
        Regex::Syntax::Hir::Concat,
      ])
    end
  end

  describe "hir analysis parity" do
    it "computes explicit capture counts like Rust" do
      Regex::Syntax.parse("a").explicit_captures_len.should eq(0)
      Regex::Syntax.parse("(?:a)").explicit_captures_len.should eq(0)
      Regex::Syntax.parse("(?i-u:a)").explicit_captures_len.should eq(0)
      Regex::Syntax.parse("(?i-u)a").explicit_captures_len.should eq(0)
      Regex::Syntax.parse("(a)").explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(?P<foo>a)").explicit_captures_len.should eq(1)
      Regex::Syntax.parse("()").explicit_captures_len.should eq(1)
      Regex::Syntax.parse("()a").explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(a)+").explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(a)(b)").explicit_captures_len.should eq(2)
      Regex::Syntax.parse("(a)|(b)").explicit_captures_len.should eq(2)
      Regex::Syntax.parse("((a))").explicit_captures_len.should eq(2)
      Regex::Syntax.parse("([a&&b])").explicit_captures_len.should eq(1)
    end

    it "computes static capture counts like Rust" do
      Regex::Syntax.parse("").static_explicit_captures_len.should eq(0)
      Regex::Syntax.parse("foo|bar").static_explicit_captures_len.should eq(0)
      Regex::Syntax.parse("(foo)|bar").static_explicit_captures_len.should be_nil
      Regex::Syntax.parse("foo|(bar)").static_explicit_captures_len.should be_nil
      Regex::Syntax.parse("(foo|bar)").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(a|b|c|d|e|f)").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(a)|(b)|(c)|(d)|(e)|(f)").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(a)(b)|(c)(d)|(e)(f)").static_explicit_captures_len.should eq(2)
      Regex::Syntax.parse("(a)(b)(c)(d)(e)(f)").static_explicit_captures_len.should eq(6)
      Regex::Syntax.parse("(a)(b)(extra)|(a)(b)()").static_explicit_captures_len.should eq(3)
      Regex::Syntax.parse("(a)(b)((?:extra)?)").static_explicit_captures_len.should eq(3)
      Regex::Syntax.parse("(a)(b)(extra)?").static_explicit_captures_len.should be_nil
      Regex::Syntax.parse("(foo)|(bar)").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(foo)(bar)").static_explicit_captures_len.should eq(2)
      Regex::Syntax.parse("(foo)+(bar)").static_explicit_captures_len.should eq(2)
      Regex::Syntax.parse("(foo)*(bar)").static_explicit_captures_len.should be_nil
      Regex::Syntax.parse("(foo)?{0}").static_explicit_captures_len.should eq(0)
      Regex::Syntax.parse("(foo)?{1}").static_explicit_captures_len.should be_nil
      Regex::Syntax.parse("(foo){1}").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(foo){1,}").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(foo){1,}?").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(foo){1,}??").static_explicit_captures_len.should be_nil
      Regex::Syntax.parse("(foo){0,}").static_explicit_captures_len.should be_nil
      Regex::Syntax.parse("(foo)(?:bar)").static_explicit_captures_len.should eq(1)
      Regex::Syntax.parse("(foo(?:bar)+)(?:baz(boo))").static_explicit_captures_len.should eq(2)
      Regex::Syntax.parse("(?P<bar>foo)(?:bar)(bal|loon)").static_explicit_captures_len.should eq(2)
      Regex::Syntax.parse("(foo)?").static_explicit_captures_len.should be_nil
    end

    it "computes minimum and maximum match lengths like Rust" do
      Regex::Syntax.parse("").minimum_len.should eq(0)
      Regex::Syntax.parse("").maximum_len.should eq(0)
      Regex::Syntax.parse("()").minimum_len.should eq(0)
      Regex::Syntax.parse("()*").minimum_len.should eq(0)
      Regex::Syntax.parse("()+").minimum_len.should eq(0)
      Regex::Syntax.parse("()?").minimum_len.should eq(0)
      Regex::Syntax.parse("^$\\b\\B").minimum_len.should eq(0)
      Regex::Syntax.parse("^$\\b\\B").maximum_len.should eq(0)
      Regex::Syntax.parse("a*").minimum_len.should eq(0)
      Regex::Syntax.parse("a*").maximum_len.should be_nil
      Regex::Syntax.parse("a?").minimum_len.should eq(0)
      Regex::Syntax.parse("a{0}").minimum_len.should eq(0)
      Regex::Syntax.parse("a{0,}").minimum_len.should eq(0)
      Regex::Syntax.parse("a{0,1}").minimum_len.should eq(0)
      Regex::Syntax.parse("a{0,10}").minimum_len.should eq(0)
      Regex::Syntax.parse("a*|b").minimum_len.should eq(0)
      Regex::Syntax.parse("b|a*").minimum_len.should eq(0)
      Regex::Syntax.parse("a|").minimum_len.should eq(0)
      Regex::Syntax.parse("|a").minimum_len.should eq(0)
      Regex::Syntax.parse("a||b").minimum_len.should eq(0)
      Regex::Syntax.parse("a*a?(abcd)*").minimum_len.should eq(0)
      Regex::Syntax.parse("^").minimum_len.should eq(0)
      Regex::Syntax.parse("$").minimum_len.should eq(0)
      Regex::Syntax.parse("(?m)^").minimum_len.should eq(0)
      Regex::Syntax.parse("(?m)$").minimum_len.should eq(0)
      Regex::Syntax.parse("\\A").minimum_len.should eq(0)
      Regex::Syntax.parse("\\z").minimum_len.should eq(0)
      Regex::Syntax.parse("\\B").minimum_len.should eq(0)
      Regex::Syntax.parse("(?-u)\\B").minimum_len.should eq(0)
      Regex::Syntax.parse("\\b").minimum_len.should eq(0)
      Regex::Syntax.parse("(?-u)\\b").minimum_len.should eq(0)
      Regex::Syntax.parse("[a&&b]").minimum_len.should be_nil
      Regex::Syntax.parse("[a&&b]").maximum_len.should be_nil
      Regex::Syntax.parse("\\w").minimum_len.should eq(1)
      Regex::Syntax.parse("\\w").maximum_len.should eq(4)
      Regex::Syntax.parse("(?-u)\\w").minimum_len.should eq(1)
      Regex::Syntax.parse("(?-u)\\w").maximum_len.should eq(1)
      Regex::Syntax.parse("a+").minimum_len.should eq(1)
      Regex::Syntax.parse("a{1}").minimum_len.should eq(1)
      Regex::Syntax.parse("a{1,}").minimum_len.should eq(1)
      Regex::Syntax.parse("a{1,2}").minimum_len.should eq(1)
      Regex::Syntax.parse("a{1,10}").minimum_len.should eq(1)
      Regex::Syntax.parse("b|a").minimum_len.should eq(1)
      Regex::Syntax.parse("a*a+(abcd)*").minimum_len.should eq(1)
      Regex::Syntax.parse("x{2,10}").minimum_len.should eq(2)
      Regex::Syntax.parse("x{2,10}").maximum_len.should eq(10)
      Regex::Syntax.parse("x{2,}").minimum_len.should eq(2)
      Regex::Syntax.parse("x{2,}").maximum_len.should be_nil
    end

    it "computes UTF-8 validity like Rust" do
      Regex::Syntax.parse("a").utf8?.should be_true
      Regex::Syntax.parse("ab").utf8?.should be_true
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?-u)a").utf8?.should be_true
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("(?-u)ab").utf8?.should be_true
      Regex::Syntax.parse(%q(\xFF)).utf8?.should be_true
      Regex::Syntax.parse(%q(\xFF\xFF)).utf8?.should be_true
      Regex::Syntax.parse(%q([^a])).utf8?.should be_true
      Regex::Syntax.parse(%q([^a][^a])).utf8?.should be_true
      Regex::Syntax.parse(%q(\b)).utf8?.should be_true
      Regex::Syntax.parse(%q(\B)).utf8?.should be_true
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)\b)).utf8?.should be_true
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("a").utf8?.should be_true
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse("ab").utf8?.should be_true
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)\xFF)).utf8?.should be_false
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)\xFF\xFF)).utf8?.should be_false
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)[^a])).utf8?.should be_false
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)[^a][^a])).utf8?.should be_false
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u).)).utf8?.should be_false
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)\W)).utf8?.should be_false
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q((?-u)\B)).utf8?.should be_true
      Regex::Syntax::Parser.new(unicode: false, utf8: false).parse(%q(\xE2\x98\x83)).utf8?.should be_true
      Regex::Syntax.parse("\\w").utf8?.should be_true
    end

    it "tracks assertion-only expressions like Rust" do
      Regex::Syntax.parse(%q(\b)).all_assertions?.should be_true
      Regex::Syntax.parse(%q(\B)).all_assertions?.should be_true
      Regex::Syntax.parse("^").all_assertions?.should be_true
      Regex::Syntax.parse("$").all_assertions?.should be_true
      Regex::Syntax.parse(%q(\A)).all_assertions?.should be_true
      Regex::Syntax.parse(%q(\z)).all_assertions?.should be_true
      Regex::Syntax.parse(%q($^\z\A\b\B)).all_assertions?.should be_true
      Regex::Syntax.parse(%q($|^|\z|\A|\b|\B)).all_assertions?.should be_true
      Regex::Syntax.parse(%q(^$|$^)).all_assertions?.should be_true
      Regex::Syntax.parse(%q((\b+())*^)).all_assertions?.should be_true
      Regex::Syntax.parse("^a").all_assertions?.should be_false
    end

    it "tracks look-set prefix-any like Rust" do
      hir = Regex::Syntax.parse(%q((?-u)(?i:(?:\b|_)win(?:32|64|dows)?(?:\b|_))))
      hir.look_set_prefix_any.contains(Regex::Syntax::Hir::Look::Kind::WordAscii).should be_true
    end

    it "unions properties like Rust" do
      hir1 = Regex::Syntax.parse("ab?c?")
      hir2 = Regex::Syntax.parse("[a&&b]")
      hir3 = Regex::Syntax.parse("wxy?z?")

      unioned = Regex::Syntax::Hir::Properties.union([
        hir1.properties,
        hir2.properties,
        hir3.properties,
      ])
      unioned.minimum_len.should be_nil
      unioned.maximum_len.should be_nil

      hir4 = Regex::Syntax.parse("a+")
      unioned = Regex::Syntax::Hir::Properties.union([
        hir1.properties,
        hir4.properties,
        hir3.properties,
      ])
      unioned.minimum_len.should eq(1)
      unioned.maximum_len.should be_nil
    end

    it "reports property memory usage like Rust" do
      Regex::Syntax.parse("abc").properties.memory_usage.should be > 0
    end

    it "tracks anchored look-set prefixes and suffixes like Rust" do
      Regex::Syntax.parse("^").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("^^").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("^$").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("^$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("^foo|^bar").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("foo$|bar$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("^(foo|bar)").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("(foo|bar)$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("^+").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$+").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("^++").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$++").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("(^)+").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("($)+").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("$^").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$^|^$").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$^|^$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse(%q(\b^)).look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse(%q($\b)).look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("^(?m:^)").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("(?m:$)$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("(?m:^)^").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$(?m:$)").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse("(?m)^").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("(?m)$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("(?m:^$)|$^").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("(?m:^$)|$^").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("$^|(?m:^$)").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("$^|(?m:^$)").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("a^").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("$a").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("a^").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("$a").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("^foo|bar").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("foo|bar$").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("^*").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("$*").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("^*+").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("$*+").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("^+*").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("$+*").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("(^)*").look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("($)*").look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
    end

    it "tracks any anchoredness like Rust" do
      Regex::Syntax.parse("^").look_set.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse("$").look_set.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      Regex::Syntax.parse(%q(\A)).look_set.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      Regex::Syntax.parse(%q(\z)).look_set.contains(Regex::Syntax::Hir::Look::Kind::EndText).should be_true
      Regex::Syntax.parse("(?m)^").look_set.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("(?m)$").look_set.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      Regex::Syntax.parse("$").look_set.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      Regex::Syntax.parse("^").look_set.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
    end

    it "tracks literal-ness like Rust" do
      Regex::Syntax.parse("a").literal?.should be_true
      Regex::Syntax.parse("ab").literal?.should be_true
      Regex::Syntax.parse("abc").literal?.should be_true
      Regex::Syntax.parse("(?m)abc").literal?.should be_true
      Regex::Syntax.parse("(?:a)").literal?.should be_true
      Regex::Syntax.parse("foo(?:a)").literal?.should be_true
      Regex::Syntax.parse("(?:a)foo").literal?.should be_true
      Regex::Syntax.parse("[a]").literal?.should be_true
      Regex::Syntax.parse("").literal?.should be_false
      Regex::Syntax.parse("^").literal?.should be_false
      Regex::Syntax.parse("a|b").literal?.should be_false
      Regex::Syntax.parse("(a)").literal?.should be_false
      Regex::Syntax.parse("a+").literal?.should be_false
      Regex::Syntax.parse("foo(a)").literal?.should be_false
      Regex::Syntax.parse("(a)foo").literal?.should be_false
      Regex::Syntax.parse("[ab]").literal?.should be_false
    end

    it "tracks alternation-literal-ness like Rust" do
      Regex::Syntax.parse("a").alternation_literal?.should be_true
      Regex::Syntax.parse("ab").alternation_literal?.should be_true
      Regex::Syntax.parse("abc").alternation_literal?.should be_true
      Regex::Syntax.parse("(?m)abc").alternation_literal?.should be_true
      Regex::Syntax.parse("foo|bar").alternation_literal?.should be_true
      Regex::Syntax.parse("foo|bar|baz").alternation_literal?.should be_true
      Regex::Syntax.parse("[a]").alternation_literal?.should be_true
      Regex::Syntax.parse("(?:ab)|cd").alternation_literal?.should be_true
      Regex::Syntax.parse("ab|(?:cd)").alternation_literal?.should be_true
      Regex::Syntax.parse("").alternation_literal?.should be_false
      Regex::Syntax.parse("^").alternation_literal?.should be_false
      Regex::Syntax.parse("(a)").alternation_literal?.should be_false
      Regex::Syntax.parse("a+").alternation_literal?.should be_false
      Regex::Syntax.parse("foo(a)").alternation_literal?.should be_false
      Regex::Syntax.parse("(a)foo").alternation_literal?.should be_false
      Regex::Syntax.parse("[ab]").alternation_literal?.should be_false
      Regex::Syntax.parse("[ab]|b").alternation_literal?.should be_false
      Regex::Syntax.parse("a|[ab]").alternation_literal?.should be_false
      Regex::Syntax.parse("(a)|b").alternation_literal?.should be_false
      Regex::Syntax.parse("a|(b)").alternation_literal?.should be_false
      Regex::Syntax.parse("a|b").alternation_literal?.should be_false
      Regex::Syntax.parse("a|b|c").alternation_literal?.should be_false
      Regex::Syntax.parse("[a]|b").alternation_literal?.should be_false
      Regex::Syntax.parse("a|[b]").alternation_literal?.should be_false
      Regex::Syntax.parse("(?:a)|b").alternation_literal?.should be_false
      Regex::Syntax.parse("a|(?:b)").alternation_literal?.should be_false
      Regex::Syntax.parse("(?:z|xx)@|xx").alternation_literal?.should be_false
    end
  end

  describe "look-set parity" do
    it "iterates look sets like Rust" do
      Regex::Syntax::Hir::LookSet.empty.to_a.size.should eq(0)
      Regex::Syntax::Hir::LookSet.full.to_a.size.should eq(18)

      set = Regex::Syntax::Hir::LookSet.empty
        .insert(Regex::Syntax::Hir::Look::Kind::StartLF)
        .insert(Regex::Syntax::Hir::Look::Kind::WordUnicode)
      set.to_a.size.should eq(2)

      Regex::Syntax::Hir::LookSet.empty
        .insert(Regex::Syntax::Hir::Look::Kind::StartLF)
        .to_a.size.should eq(1)

      Regex::Syntax::Hir::LookSet.empty
        .insert(Regex::Syntax::Hir::Look::Kind::WordAsciiNegate)
        .to_a.size.should eq(1)
    end

    it "renders look sets like Rust" do
      Regex::Syntax::Hir::LookSet.empty.inspect.should eq("∅")
      Regex::Syntax::Hir::LookSet.full.inspect.should eq("Az^$rRbB𝛃𝚩<>〈〉◁▷◀▶")
    end

    it "round-trips look-set reprs like Rust" do
      set = Regex::Syntax::Hir::LookSet.empty
        .insert(Regex::Syntax::Hir::Look::Kind::StartLF)
        .insert(Regex::Syntax::Hir::Look::Kind::WordUnicode)
      bytes = Bytes.new(4, 0_u8)
      set.write_repr(bytes)
      Regex::Syntax::Hir::LookSet.read_repr(bytes).should eq(set)
    end

    it "removes and subtracts look sets like Rust" do
      set = Regex::Syntax::Hir::LookSet.full
      set.remove(Regex::Syntax::Hir::Look::Kind::StartText).contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false

      left = Regex::Syntax::Hir::LookSet.empty
        .insert(Regex::Syntax::Hir::Look::Kind::StartLF)
        .insert(Regex::Syntax::Hir::Look::Kind::WordUnicode)
      right = Regex::Syntax::Hir::LookSet.empty.insert(Regex::Syntax::Hir::Look::Kind::StartLF)
      left.subtract(right).should eq(
        Regex::Syntax::Hir::LookSet.empty.insert(Regex::Syntax::Hir::Look::Kind::WordUnicode)
      )
    end

    it "tracks anchor and word convenience predicates like Rust" do
      empty = Regex::Syntax::Hir::LookSet.empty
      empty.contains_anchor.should be_false
      empty.contains_word.should be_false

      haystack = Regex::Syntax::Hir::LookSet.empty.insert(Regex::Syntax::Hir::Look::Kind::StartText)
      haystack.contains_anchor.should be_true
      haystack.contains_anchor_haystack.should be_true
      haystack.contains_anchor_line.should be_false

      lf = Regex::Syntax::Hir::LookSet.empty.insert(Regex::Syntax::Hir::Look::Kind::StartLF)
      lf.contains_anchor.should be_true
      lf.contains_anchor_line.should be_true
      lf.contains_anchor_lf.should be_true
      lf.contains_anchor_crlf.should be_false

      crlf = Regex::Syntax::Hir::LookSet.empty.insert(Regex::Syntax::Hir::Look::Kind::EndCRLF)
      crlf.contains_anchor_line.should be_true
      crlf.contains_anchor_crlf.should be_true
      crlf.contains_anchor_lf.should be_false

      ascii_word = Regex::Syntax::Hir::LookSet.empty.insert(Regex::Syntax::Hir::Look::Kind::WordAsciiNegate)
      ascii_word.contains_word.should be_true
      ascii_word.contains_word_ascii.should be_true
      ascii_word.contains_word_unicode.should be_false

      unicode_word = Regex::Syntax::Hir::LookSet.empty.insert(Regex::Syntax::Hir::Look::Kind::WordEndUnicode)
      unicode_word.contains_word.should be_true
      unicode_word.contains_word_unicode.should be_true
      unicode_word.contains_word_ascii.should be_false
    end
  end

  describe "look helper parity" do
    it "reverses look kinds like Rust" do
      Regex::Syntax::Hir::Look::Kind::StartText.reversed.should eq(Regex::Syntax::Hir::Look::Kind::EndText)
      Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF.reversed.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
      Regex::Syntax::Hir::Look::Kind::StartLF.reversed.should eq(Regex::Syntax::Hir::Look::Kind::EndLF)
      Regex::Syntax::Hir::Look::Kind::WordUnicode.reversed.should eq(Regex::Syntax::Hir::Look::Kind::WordUnicode)
      Regex::Syntax::Hir::Look::Kind::WordStartHalfAscii.reversed.should eq(Regex::Syntax::Hir::Look::Kind::WordEndHalfAscii)
    end

    it "round-trips look reprs like Rust" do
      Regex::Syntax::Hir::Look::Kind::StartText.as_repr.should eq(1_u32)
      Regex::Syntax::Hir::Look::Kind::WordUnicode.as_repr.should eq(1_u32 << 8)
      Regex::Syntax::Hir::Look::Kind.from_repr(1_u32).should eq(Regex::Syntax::Hir::Look::Kind::StartText)
      Regex::Syntax::Hir::Look::Kind.from_repr(1_u32 << 17).should eq(Regex::Syntax::Hir::Look::Kind::WordEndHalfUnicode)
      Regex::Syntax::Hir::Look::Kind.from_repr(0_u32).should be_nil
    end

    it "renders look glyphs like Rust" do
      Regex::Syntax::Hir::Look::Kind::StartText.as_char.should eq('A')
      Regex::Syntax::Hir::Look::Kind::EndText.as_char.should eq('z')
      Regex::Syntax::Hir::Look::Kind::WordAscii.as_char.should eq('b')
      Regex::Syntax::Hir::Look::Kind::WordEndUnicode.as_char.should eq('〉')
    end
  end

  describe "hir class helper parity" do
    it "exposes byte-class helpers like Rust" do
      klass = Regex::Syntax::Hir::CharClass.empty
      klass.minimum_len.should be_nil
      klass.maximum_len.should be_nil
      klass.ascii?.should be_true

      klass.push(0x61_u8..0x61_u8)
      klass.push(0x62_u8..0x63_u8)
      klass.ranges.should eq([0x61_u8..0x63_u8])
      klass.minimum_len.should eq(1)
      klass.maximum_len.should eq(1)
      klass.literal.should be_nil

      singleton = Regex::Syntax::Hir::CharClass.empty.push(0x7A_u8..0x7A_u8)
      singleton.literal.should eq(Bytes[0x7A_u8])
      singleton.ascii?.should be_true
      singleton.to_unicode_class.should_not be_nil
      singleton.to_unicode_class.as(Regex::Syntax::Hir::UnicodeClass).ranges.should eq([0x7A_u32..0x7A_u32])

      non_ascii = Regex::Syntax::Hir::CharClass.empty.push(0xFF_u8..0xFF_u8)
      non_ascii.ascii?.should be_false
      non_ascii.to_unicode_class.should be_nil

      foldable = Regex::Syntax::Hir::CharClass.empty.push(0x41_u8..0x41_u8)
      foldable.try_case_fold_simple.ranges.should eq([0x41_u8..0x41_u8, 0x61_u8..0x61_u8])
    end

    it "exposes unicode-class helpers like Rust" do
      klass = Regex::Syntax::Hir::UnicodeClass.empty
      klass.minimum_len.should be_nil
      klass.maximum_len.should be_nil
      klass.ascii?.should be_true

      klass.push(0x61_u32..0x61_u32)
      klass.push(0x62_u32..0x63_u32)
      klass.ranges.should eq([0x61_u32..0x63_u32])
      klass.minimum_len.should eq(1)
      klass.maximum_len.should eq(1)
      klass.literal.should be_nil

      snowman = Regex::Syntax::Hir::UnicodeClass.empty.push(0x2603_u32..0x2603_u32)
      literal = snowman.literal
      literal.should_not be_nil
      String.new(literal.as(Bytes)).should eq("☃")
      snowman.ascii?.should be_false
      snowman.minimum_len.should eq(3)
      snowman.maximum_len.should eq(3)
      snowman.to_byte_class.should be_nil

      ascii = Regex::Syntax::Hir::UnicodeClass.empty.push(0x41_u32..0x43_u32)
      ascii.to_byte_class.should_not be_nil
      ascii.to_byte_class.as(Regex::Syntax::Hir::CharClass).ranges.should eq([0x41_u8..0x43_u8])

      foldable = Regex::Syntax::Hir::UnicodeClass.empty.push('K'.ord.to_u32..'K'.ord.to_u32)
      foldable.try_case_fold_simple.ranges.should contain('k'.ord.to_u32..'k'.ord.to_u32)
    end
  end

  describe "hir constructor parity" do
    it "builds empty and failing HIR values like Rust" do
      empty = Regex::Syntax::Hir::Hir.empty
      empty.node.should be_a(Regex::Syntax::Hir::Empty)
      empty.minimum_len.should eq(0)
      empty.maximum_len.should eq(0)
      empty.utf8?.should be_true

      fail_hir = Regex::Syntax::Hir::Hir.fail
      fail_hir.node.should be_a(Regex::Syntax::Hir::CharClass)
      fail_hir.node.as(Regex::Syntax::Hir::CharClass).intervals.should be_empty
      fail_hir.minimum_len.should be_nil
      fail_hir.maximum_len.should be_nil
      fail_hir.utf8?.should be_true
    end

    it "normalizes empty literals and empty alternations like Rust" do
      Regex::Syntax::Hir::Hir.literal(Bytes.empty).node.should be_a(Regex::Syntax::Hir::Empty)
      Regex::Syntax::Hir::Hir.alternation([] of Regex::Syntax::Hir::Node).node.should be_a(Regex::Syntax::Hir::CharClass)
    end

    it "builds look HIR values directly like Rust" do
      look = Regex::Syntax::Hir::Hir.look(Regex::Syntax::Hir::Look::Kind::StartText)
      look.node.should be_a(Regex::Syntax::Hir::Look)
      look.node.as(Regex::Syntax::Hir::Look).kind.should eq(Regex::Syntax::Hir::Look::Kind::StartText)
      look.all_assertions?.should be_true
    end

    it "builds dot HIR values directly like Rust" do
      dot = Regex::Syntax::Hir::Hir.dot(Regex::Syntax::Hir::Dot::AnyCharExceptLF)
      dot.node.should be_a(Regex::Syntax::Hir::DotNode)
      dot.node.as(Regex::Syntax::Hir::DotNode).kind.should eq(Regex::Syntax::Hir::Dot::AnyCharExceptLF)
    end

    it "exposes kind introspection like Rust" do
      literal = Regex::Syntax::Hir::Hir.literal("abc".to_slice)
      literal.kind.should be_a(Regex::Syntax::Hir::Literal)
      literal.into_kind.should be_a(Regex::Syntax::Hir::Literal)
    end

    it "builds repetition and capture HIR values directly like Rust" do
      repeated = Regex::Syntax::Hir::Hir.repetition(
        Regex::Syntax::Hir::Repetition.new(
          Regex::Syntax::Hir::Literal.new("a".to_slice),
          0_u32,
          0_u32,
          greedy: true
        )
      )
      repeated.node.should be_a(Regex::Syntax::Hir::Empty)

      capture = Regex::Syntax::Hir::Hir.capture(
        Regex::Syntax::Hir::Capture.new(
          Regex::Syntax::Hir::Literal.new("a".to_slice),
          1,
          "name"
        )
      )
      capture.node.should be_a(Regex::Syntax::Hir::Capture)
      capture.node.as(Regex::Syntax::Hir::Capture).index.should eq(1)
      capture.node.as(Regex::Syntax::Hir::Capture).name.should eq("name")
    end

    it "exposes subs and repetition replacement helpers like Rust" do
      literal = Regex::Syntax::Hir::Literal.new("a".to_slice)
      replacement = Regex::Syntax::Hir::Literal.new("b".to_slice)

      repetition = Regex::Syntax::Hir::Repetition.new(literal, 2_u32, 4_u32, greedy: false)
      repetition.subs.should eq([literal] of Regex::Syntax::Hir::Node)
      replaced = repetition.with(replacement)
      replaced.sub.should eq(replacement)
      replaced.min.should eq(2_u32)
      replaced.max.should eq(4_u32)
      replaced.greedy?.should be_false

      capture = Regex::Syntax::Hir::Capture.new(literal, 1, "cap")
      capture.subs.should eq([literal] of Regex::Syntax::Hir::Node)

      concat = Regex::Syntax::Hir::Concat.new([literal, replacement] of Regex::Syntax::Hir::Node)
      concat.subs.should eq([literal, replacement] of Regex::Syntax::Hir::Node)

      alternation = Regex::Syntax::Hir::Alternation.new([literal, replacement] of Regex::Syntax::Hir::Node)
      alternation.subs.should eq([literal, replacement] of Regex::Syntax::Hir::Node)

      hir = Regex::Syntax::Hir::Hir.concat([
        literal,
        Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::StartText),
      ] of Regex::Syntax::Hir::Node)
      hir.kind.subs.size.should eq(2)
    end
  end

  describe "hir properties wrapper parity" do
    it "exposes a public properties view like Rust" do
      hir = Regex::Syntax.parse("(?i)(a)|b")
      props = hir.properties

      props.explicit_captures_len.should eq(1)
      props.static_explicit_captures_len.should be_nil
      props.minimum_len.should eq(1)
      props.maximum_len.should eq(1)
      props.literal?.should be_false
      props.alternation_literal?.should be_false
      props.utf8?.should be_true
      props.memory_usage.should be > 0
      props.look_set.should eq(hir.look_set)
      props.look_set_prefix.should eq(hir.look_set_prefix)
      props.look_set_suffix.should eq(hir.look_set_suffix)
    end

    it "unions properties like Rust when an alternate never matches" do
      props = Regex::Syntax::Hir::Properties.union([
        Regex::Syntax.parse("ab?c?").properties,
        Regex::Syntax.parse("[a&&b]").properties,
        Regex::Syntax.parse("wxy?z?").properties,
      ])

      props.minimum_len.should be_nil
      props.maximum_len.should be_nil
      props.literal?.should be_false
      props.alternation_literal?.should be_false
    end

    it "unions properties like Rust when an alternate has unbounded length" do
      props = Regex::Syntax::Hir::Properties.union([
        Regex::Syntax.parse("ab?c?").properties,
        Regex::Syntax.parse("a+").properties,
        Regex::Syntax.parse("wxy?z?").properties,
      ])

      props.minimum_len.should eq(1)
      props.maximum_len.should be_nil
      props.literal?.should be_false
      props.alternation_literal?.should be_false
    end

    it "unions prefix and suffix look sets like Rust" do
      props = Regex::Syntax::Hir::Properties.union([
        Regex::Syntax.parse("^foo").properties,
        Regex::Syntax.parse("^bar").properties,
        Regex::Syntax.parse("baz$").properties,
      ])

      props.look_set.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      props.look_set.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
      props.look_set_prefix.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_false
      props.look_set_suffix.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_false
      props.look_set_prefix_any.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
      props.look_set_suffix_any.contains(Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF).should be_true
    end

    it "exposes lookset constructors like Rust" do
      Regex::Syntax::Hir::LookSet.empty.empty?.should be_true
      singleton = Regex::Syntax::Hir::LookSet.singleton(Regex::Syntax::Hir::Look::Kind::StartText)
      singleton.len.should eq(1)
      singleton.contains(Regex::Syntax::Hir::Look::Kind::StartText).should be_true
    end
  end
end
