require "./spec_helper"

describe Regex::Syntax::AstParser do
  describe "#parse" do
    it "parses simple ASCII class [[:alpha:]]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[[:alpha:]]")

      # Should be a ClassBracketed, not a Concat
      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)

      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)
      class_bracketed.negated?.should be_false

      # The class set should contain an ASCII class item
      class_set = class_bracketed.kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::Item)

      class_set_item = class_set.item.as(Regex::Syntax::AST::ClassSetItem)
      class_set_item.kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Ascii)

      ascii_class = class_set_item.item.as(Regex::Syntax::AST::ClassAscii)
      ascii_class.kind.should eq(Regex::Syntax::AST::ClassAscii::Kind::Alpha)
      ascii_class.negated?.should be_false
    end

    it "parses negated ASCII class [[:^alpha:]]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[[:^alpha:]]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)

      class_set = class_bracketed.kind
      class_set_item = class_set.item.as(Regex::Syntax::AST::ClassSetItem)
      class_set_item.kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Ascii)

      ascii_class = class_set_item.item.as(Regex::Syntax::AST::ClassAscii)
      ascii_class.kind.should eq(Regex::Syntax::AST::ClassAscii::Kind::Alpha)
      ascii_class.negated?.should be_true
    end

    it "parses ASCII class with other characters [[:alpha:]a]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[[:alpha:]a]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)

      # Should be a union with ASCII class and literal
      class_set = class_bracketed.kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::Item)

      class_set_item = class_set.item.as(Regex::Syntax::AST::ClassSetItem)
      class_set_item.kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Union)

      union = class_set_item.item.as(Regex::Syntax::AST::ClassSetUnion)
      union.items.size.should eq(2)

      # First item should be ASCII class
      union.items[0].kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Ascii)
      # Second item should be literal
      union.items[1].kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Literal)
    end

    it "backtracks invalid ASCII classes instead of emitting ClassAscii" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[[:alnnum:]]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)
      class_set_item = class_bracketed.kind.item.as(Regex::Syntax::AST::ClassSetItem)
      class_set_item.kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Bracketed)
    end

    it "parses binary intersection [a&&b]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[a&&b]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)

      # Should be a binary operation, not a union of literals
      class_set = class_bracketed.kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)

      binary_op = class_set.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      binary_op.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Intersection)
    end

    it "parses binary difference [a--b]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[a--b]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)

      class_set = class_bracketed.kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)

      binary_op = class_set.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      binary_op.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Difference)
    end

    it "parses binary symmetric difference [a~~b]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[a~~b]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)

      class_set = class_bracketed.kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)

      binary_op = class_set.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      binary_op.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::SymmetricDifference)
    end

    it "parses ASCII class with binary operation [[:alpha:]&&a-z]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[[:alpha:]&&a-z]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)

      class_set = class_bracketed.kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)

      binary_op = class_set.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      binary_op.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Intersection)

      # LHS should be ASCII class
      lhs = binary_op.lhs
      lhs.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::Item)
      lhs.item.as(Regex::Syntax::AST::ClassSetItem).kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Ascii)

      # RHS should be a range
      rhs = binary_op.rhs
      rhs.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::Item)
      rhs.item.as(Regex::Syntax::AST::ClassSetItem).kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Range)
    end

    it "parses multiple binary operations [a&&b--c]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[a&&b--c]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_bracketed = ast.root.as(Regex::Syntax::AST::ClassBracketed)

      # Should be a binary operation (difference)
      class_set = class_bracketed.kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)

      binary_op = class_set.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      binary_op.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Difference)

      # LHS should be intersection
      lhs = binary_op.lhs
      lhs.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)
      lhs.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp).kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Intersection)
    end

    it "parses left-associative repeated difference [a--b--c]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[a--b--c]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_set = ast.root.as(Regex::Syntax::AST::ClassBracketed).kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)

      outer = class_set.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      outer.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Difference)
      outer.rhs.item.as(Regex::Syntax::AST::ClassSetItem).kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Literal)

      inner = outer.lhs.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      inner.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::Difference)
      inner.lhs.item.as(Regex::Syntax::AST::ClassSetItem).kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Literal)
      inner.rhs.item.as(Regex::Syntax::AST::ClassSetItem).kind.should eq(Regex::Syntax::AST::ClassSetItem::Kind::Literal)
    end

    it "parses left-associative repeated symmetric difference [a~~b~~c]" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("[a~~b~~c]")

      ast.root.should be_a(Regex::Syntax::AST::ClassBracketed)
      class_set = ast.root.as(Regex::Syntax::AST::ClassBracketed).kind
      class_set.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)

      outer = class_set.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp)
      outer.kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::SymmetricDifference)
      outer.lhs.kind.should eq(Regex::Syntax::AST::ClassSet::Kind::BinaryOp)
      outer.lhs.binary_op.as(Regex::Syntax::AST::ClassSetBinaryOp).kind.should eq(Regex::Syntax::AST::ClassSetBinaryOp::Kind::SymmetricDifference)
    end

    it "assigns sequential capture indices" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("(a)(b)")

      ast.root.should be_a(Regex::Syntax::AST::Concat)
      concat = ast.root.as(Regex::Syntax::AST::Concat)
      concat.children.size.should eq(2)

      first = concat.children[0].as(Regex::Syntax::AST::Group)
      second = concat.children[1].as(Regex::Syntax::AST::Group)
      first.capture_index.should eq(1)
      second.capture_index.should eq(2)
    end

    it "parses named captures" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("(?P<word>a)")

      ast.root.should be_a(Regex::Syntax::AST::Group)
      group = ast.root.as(Regex::Syntax::AST::Group)
      group.kind.should eq(Regex::Syntax::AST::Group::Kind::Capture)
      group.capture_index.should eq(1)
      group.name.should eq("word")
    end

    it "rejects duplicate named captures" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /duplicate capture name/) do
        parser.parse("(?P<word>a)(?<word>b)")
      end
    end

    it "rejects invalid named capture syntax" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /invalid capture name/) do
        parser.parse("(?P<1word>a)")
      end
    end

    it "rejects unsupported backreferences" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /backreferences are not supported/) do
        parser.parse(%q(\0))
      end

      expect_raises(Regex::Syntax::ParseError, /backreferences are not supported/) do
        parser.parse(%q(\9))
      end
    end

    it "rejects unsupported look-behind groups" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /look-behind/) do
        parser.parse("(?<=a)b")
      end

      expect_raises(Regex::Syntax::ParseError, /look-behind/) do
        parser.parse("(?<!a)b")
      end
    end

    it "parses fixed-width hex escapes" do
      parser = Regex::Syntax::AstParser.new

      x = parser.parse(%q(\x41)).root.as(Regex::Syntax::AST::Literal)
      x.kind.should eq(Regex::Syntax::AST::Literal::Kind::Hex)
      x.c.should eq('A')

      u = parser.parse(%q(\u03A9)).root.as(Regex::Syntax::AST::Literal)
      u.kind.should eq(Regex::Syntax::AST::Literal::Kind::Unicode)
      u.c.should eq('Ω')

      long = parser.parse(%q(\U0001F600)).root.as(Regex::Syntax::AST::Literal)
      long.kind.should eq(Regex::Syntax::AST::Literal::Kind::Unicode)
      long.c.should eq('😀')
    end

    it "parses brace hex escapes" do
      parser = Regex::Syntax::AstParser.new

      x = parser.parse(%q(\x{26C4})).root.as(Regex::Syntax::AST::Literal)
      x.kind.should eq(Regex::Syntax::AST::Literal::Kind::Hex)
      x.c.should eq('⛄')

      u = parser.parse(%q(\u{26c4})).root.as(Regex::Syntax::AST::Literal)
      u.kind.should eq(Regex::Syntax::AST::Literal::Kind::Unicode)
      u.c.should eq('⛄')

      long = parser.parse(%q(\U{10FFFF})).root.as(Regex::Syntax::AST::Literal)
      long.kind.should eq(Regex::Syntax::AST::Literal::Kind::Unicode)
      long.c.should eq('\u{10FFFF}')
    end

    it "rejects invalid fixed-width and brace hex escapes" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /unexpected end of pattern in hex escape/) do
        parser.parse(%q(\xF))
      end

      expect_raises(Regex::Syntax::ParseError, /invalid hex digit in escape/) do
        parser.parse(%q(\uFFFG))
      end

      expect_raises(Regex::Syntax::ParseError, /empty hex escape/) do
        parser.parse(%q(\x{}))
      end

      expect_raises(Regex::Syntax::ParseError, /invalid hex escape/) do
        parser.parse(%q(\x{D800}))
      end
    end

    it "parses primitive literals, Perl classes, and special escapes like Rust" do
      parser = Regex::Syntax::AstParser.new

      parser.parse(".").root.should be_a(Regex::Syntax::AST::Dot)
      parser.parse("^").root.should be_a(Regex::Syntax::AST::Assertion)
      parser.parse("$").root.should be_a(Regex::Syntax::AST::Assertion)
      parser.parse("a").root.as(Regex::Syntax::AST::Literal).bytes.should eq("a".to_slice)
      parser.parse("☃").root.as(Regex::Syntax::AST::Literal).bytes.should eq("☃".to_slice)

      parser.parse(%q(\d)).root.as(Regex::Syntax::AST::ClassPerl).kind.should eq(
        Regex::Syntax::AST::ClassPerl::Kind::Digit
      )
      parser.parse(%q(\D)).root.as(Regex::Syntax::AST::ClassPerl).kind.should eq(
        Regex::Syntax::AST::ClassPerl::Kind::DigitNeg
      )
      parser.parse(%q(\s)).root.as(Regex::Syntax::AST::ClassPerl).kind.should eq(
        Regex::Syntax::AST::ClassPerl::Kind::Space
      )
      parser.parse(%q(\w)).root.as(Regex::Syntax::AST::ClassPerl).kind.should eq(
        Regex::Syntax::AST::ClassPerl::Kind::Word
      )

      {
        %q(\a) => '\a',
        %q(\f) => '\f',
        %q(\t) => '\t',
        %q(\n) => '\n',
        %q(\r) => '\r',
        %q(\v) => '\v',
      }.each do |pattern, expected|
        literal = parser.parse(pattern).root.as(Regex::Syntax::AST::Literal)
        literal.kind.should eq(Regex::Syntax::AST::Literal::Kind::Escaped)
        literal.c.should eq(expected)
      end
    end

    it "parses newlines as verbatim literals between dots like Rust" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse(".\n.")

      ast.root.should be_a(Regex::Syntax::AST::Concat)
      concat = ast.root.as(Regex::Syntax::AST::Concat)
      concat.children.size.should eq(3)
      concat.children[0].should be_a(Regex::Syntax::AST::Dot)
      concat.children[1].as(Regex::Syntax::AST::Literal).bytes.should eq("\n".to_slice)
      concat.children[2].should be_a(Regex::Syntax::AST::Dot)
    end

    it "parses octal escapes only when enabled" do
      parser = Regex::Syntax::AstParser.new(octal: true)

      ast = parser.parse(%q(\141))
      ast.root.should be_a(Regex::Syntax::AST::Literal)
      literal = ast.root.as(Regex::Syntax::AST::Literal)
      literal.kind.should eq(Regex::Syntax::AST::Literal::Kind::Octal)
      literal.c.should eq('a')

      split = parser.parse(%q(\778))
      split.root.should be_a(Regex::Syntax::AST::Concat)
      concat = split.root.as(Regex::Syntax::AST::Concat)
      concat.children.size.should eq(2)
      concat.children[0].as(Regex::Syntax::AST::Literal).kind.should eq(Regex::Syntax::AST::Literal::Kind::Octal)
      concat.children[0].as(Regex::Syntax::AST::Literal).c.should eq('?')
      trailing = concat.children[1].as(Regex::Syntax::AST::Literal)
      trailing.kind.should eq(Regex::Syntax::AST::Literal::Kind::Verbatim)
      trailing.bytes.should eq(Bytes[0x38])
    end

    it "rejects non-octal escapes when octal mode is enabled" do
      parser = Regex::Syntax::AstParser.new(octal: true)

      expect_raises(Regex::Syntax::ParseError, /unrecognized escape sequence/) do
        parser.parse(%q(\8))
      end
    end

    it "parses verbose-mode groups with insignificant whitespace like Rust" do
      parser = Regex::Syntax::AstParser.new

      named = parser.parse("(?x)( ?P<foo> a )")
      named.root.should be_a(Regex::Syntax::AST::Concat)
      named_concat = named.root.as(Regex::Syntax::AST::Concat)
      named_concat.children[0].should be_a(Regex::Syntax::AST::SetFlags)
      named_group = named_concat.children[1].as(Regex::Syntax::AST::Group)
      named_group.kind.should eq(Regex::Syntax::AST::Group::Kind::Capture)
      named_group.name.should eq("foo")

      capture = parser.parse("(?x)(  a )")
      capture.root.should be_a(Regex::Syntax::AST::Concat)
      capture_concat = capture.root.as(Regex::Syntax::AST::Concat)
      capture_concat.children[1].should be_a(Regex::Syntax::AST::Group)
      capture_concat.children[1].as(Regex::Syntax::AST::Group).kind.should eq(
        Regex::Syntax::AST::Group::Kind::Capture
      )

      non_capture = parser.parse("(?x)(  ?:  a )")
      non_capture.root.should be_a(Regex::Syntax::AST::Concat)
      non_capture_concat = non_capture.root.as(Regex::Syntax::AST::Concat)
      non_capture_concat.children[1].should be_a(Regex::Syntax::AST::Group)
      non_capture_concat.children[1].as(Regex::Syntax::AST::Group).kind.should eq(
        Regex::Syntax::AST::Group::Kind::NonCapture
      )
    end

    it "parses verbose-mode hex escapes with insignificant whitespace like Rust" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse(%q((?x)\x { 53 }))

      ast.root.should be_a(Regex::Syntax::AST::Concat)
      concat = ast.root.as(Regex::Syntax::AST::Concat)
      concat.children[0].should be_a(Regex::Syntax::AST::SetFlags)
      literal = concat.children[1].as(Regex::Syntax::AST::Literal)
      literal.kind.should eq(Regex::Syntax::AST::Literal::Kind::Hex)
      literal.c.should eq('S')
    end

    it "accepts trailing dashes in verbose-mode character classes like Rust" do
      parser = Regex::Syntax::AstParser.new

      parser.parse("(?x)[ / - ]").root.should be_a(Regex::Syntax::AST::Concat)
      parser.parse("(?x)[ a - ]").root.should be_a(Regex::Syntax::AST::Concat)

      expect_raises(Regex::Syntax::ParseError) do
        parser.parse("(?x)[ / -")
      end
    end

    it "parses alternations like Rust" do
      parser = Regex::Syntax::AstParser.new

      ast = parser.parse("a|b|c")
      ast.root.should be_a(Regex::Syntax::AST::Alternation)
      alternation = ast.root.as(Regex::Syntax::AST::Alternation)
      alternation.children.size.should eq(3)
      alternation.children[0].as(Regex::Syntax::AST::Literal).bytes.should eq("a".to_slice)
      alternation.children[1].as(Regex::Syntax::AST::Literal).bytes.should eq("b".to_slice)
      alternation.children[2].as(Regex::Syntax::AST::Literal).bytes.should eq("c".to_slice)

      nested = parser.parse("(a|b)")
      nested.root.should be_a(Regex::Syntax::AST::Group)
      group = nested.root.as(Regex::Syntax::AST::Group)
      group.child.should be_a(Regex::Syntax::AST::Alternation)
      group.child.as(Regex::Syntax::AST::Alternation).children.size.should eq(2)
    end

    it "parses uncounted repetitions like Rust" do
      parser = Regex::Syntax::AstParser.new

      star = parser.parse("a*").root.as(Regex::Syntax::AST::Repetition)
      star.op.kind.should eq(Regex::Syntax::AST::RepetitionOp::Kind::ZeroOrMore)
      star.greedy?.should be_true

      reluctant = parser.parse("a??").root.as(Regex::Syntax::AST::Repetition)
      reluctant.op.kind.should eq(Regex::Syntax::AST::RepetitionOp::Kind::ZeroOrOne)
      reluctant.greedy?.should be_false

      concat = parser.parse("|a?").root.as(Regex::Syntax::AST::Alternation)
      concat.children[0].should be_a(Regex::Syntax::AST::Empty)
      concat.children[1].should be_a(Regex::Syntax::AST::Repetition)

      expect_raises(Regex::Syntax::ParseError, /repetition operator not preceded by expression/) do
        parser.parse("*")
      end
    end

    it "parses counted repetitions like Rust" do
      parser = Regex::Syntax::AstParser.new

      exact = parser.parse("a{5}").root.as(Regex::Syntax::AST::Repetition)
      exact.op.kind.should eq(Regex::Syntax::AST::RepetitionOp::Kind::Range)
      exact.op.min.should eq(5)
      exact.op.max.should eq(5)
      exact.greedy?.should be_true

      atleast = parser.parse("a{5,}").root.as(Regex::Syntax::AST::Repetition)
      atleast.op.min.should eq(5)
      atleast.op.max.should be_nil

      bounded = parser.parse("a{5,9}").root.as(Regex::Syntax::AST::Repetition)
      bounded.op.min.should eq(5)
      bounded.op.max.should eq(9)

      reluctant = parser.parse("a{5}?").root.as(Regex::Syntax::AST::Repetition)
      reluctant.greedy?.should be_false

      expect_raises(Regex::Syntax::ParseError, /invalid repetition range/) do
        parser.parse("a{2,1}")
      end
    end

    it "captures comments via parse_with_comments like Rust" do
      parser = Regex::Syntax::AstParser.new
      pattern = "(?x)\n# This is comment 1.\nfoo # This is comment 2.\n  # This is comment 3.\nbar\n# This is comment 4."

      ast_with_comments = parser.parse_with_comments(pattern)

      ast_with_comments.ast.root.should be_a(Regex::Syntax::AST::Concat)
      concat = ast_with_comments.ast.root.as(Regex::Syntax::AST::Concat)
      concat.children.size.should eq(3)

      concat.children[0].should be_a(Regex::Syntax::AST::SetFlags)
      concat.children[1].as(Regex::Syntax::AST::Literal).bytes.should eq("foo".to_slice)
      concat.children[2].as(Regex::Syntax::AST::Literal).bytes.should eq("bar".to_slice)

      ast_with_comments.comments.map(&.comment).should eq([
        " This is comment 1.",
        " This is comment 2.",
        " This is comment 3.",
        " This is comment 4.",
      ])

      ast_with_comments.comments.map(&.span).should eq([
        Regex::Syntax::AST::Span.new(5, 26),
        Regex::Syntax::AST::Span.new(30, 51),
        Regex::Syntax::AST::Span.new(53, 74),
        Regex::Syntax::AST::Span.new(78, 98),
      ])
    end

    it "resets parser state between parses" do
      parser = Regex::Syntax::AstParser.new
      parser.parse("(?i:a)")

      ast = parser.parse("a")
      literal = ast.root.as(Regex::Syntax::AST::Literal)
      literal.kind.should eq(Regex::Syntax::AST::Literal::Kind::Verbatim)
      literal.bytes.should eq("a".to_slice)
    end

    it "parses special word boundary assertions" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse(%q(\b{start-half}))

      ast.root.should be_a(Regex::Syntax::AST::Assertion)
      ast.root.as(Regex::Syntax::AST::Assertion).kind.should eq(
        Regex::Syntax::AST::Assertion::Kind::WordBoundaryStartHalf
      )
    end

    it "backtracks special word boundary parsing for counted repetitions" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse(%q(\b{5}))

      ast.root.should be_a(Regex::Syntax::AST::Repetition)
      repetition = ast.root.as(Regex::Syntax::AST::Repetition)
      repetition.child.should be_a(Regex::Syntax::AST::Assertion)
      repetition.child.as(Regex::Syntax::AST::Assertion).kind.should eq(
        Regex::Syntax::AST::Assertion::Kind::WordBoundary
      )
    end
  end
end
