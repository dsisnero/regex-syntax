require "./spec_helper"

describe "Flag handling in AST parser" do
  describe "flag groups" do
    it "parses (?i:...) flag group" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("(?i:ab)")

      ast.root.should be_a(Regex::Syntax::AST::Group)
      group = ast.root.as(Regex::Syntax::AST::Group)
      group.kind.should eq(Regex::Syntax::AST::Group::Kind::NonCapture)
      group.flags.should_not be_nil

      if flags = group.flags
        flags.flag_state('i').should be_true
      end

      # The child should be a literal with bytes "ab"
      group.child.should be_a(Regex::Syntax::AST::Literal)
      literal = group.child.as(Regex::Syntax::AST::Literal)
      literal.bytes.should eq(Bytes[97, 98]) # "ab"
    end

    it "parses (?i) global flags" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("(?i)ab")

      # (?i) should produce a SetFlags node followed by "ab"
      ast.root.should be_a(Regex::Syntax::AST::Concat)
      concat = ast.root.as(Regex::Syntax::AST::Concat)
      concat.children.size.should eq(2)
      concat.children[0].should be_a(Regex::Syntax::AST::SetFlags)
      set_flags = concat.children[0].as(Regex::Syntax::AST::SetFlags)
      set_flags.items.size.should eq(1)
      set_flags.items[0].kind.should eq(Regex::Syntax::AST::FlagsItem::Kind::Flag)
      set_flags.items[0].flag.should eq('i')
      concat.children[1].should be_a(Regex::Syntax::AST::Literal) # "ab"
    end

    it "parses multiple flags (?im:...)" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("(?im:ab)")

      ast.root.should be_a(Regex::Syntax::AST::Group)
      group = ast.root.as(Regex::Syntax::AST::Group)
      group.kind.should eq(Regex::Syntax::AST::Group::Kind::NonCapture)
      group.flags.should_not be_nil
    end

    it "parses negative flags (?-i:...)" do
      parser = Regex::Syntax::AstParser.new
      ast = parser.parse("(?-i:AB)")

      ast.root.should be_a(Regex::Syntax::AST::Group)
      group = ast.root.as(Regex::Syntax::AST::Group)
      group.kind.should eq(Regex::Syntax::AST::Group::Kind::NonCapture)
      group.flags.should_not be_nil

      if flags = group.flags
        flags.flag_state('i').should be_false
      end
    end

    it "rejects duplicate flags" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /duplicate flag/) do
        parser.parse("(?ii:ab)")
      end
    end

    it "rejects repeated negation" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /repeated flag negation/) do
        parser.parse("(?i--m:ab)")
      end
    end

    it "rejects dangling negation" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /dangling flag negation/) do
        parser.parse("(?i-)")
      end
    end

    it "rejects unrecognized flags" do
      parser = Regex::Syntax::AstParser.new

      expect_raises(Regex::Syntax::ParseError, /unrecognized flag/) do
        parser.parse("(?ia:ab)")
      end
    end
  end

  describe "flag application in translator" do
    it "applies case-insensitive flag to literals" do
      translator = Regex::Syntax::Translator.new(ignore_case: true)
      ast = Regex::Syntax::AST::Literal.new(
        Regex::Syntax::AST::Span.new(0, 1),
        Regex::Syntax::AST::Literal::Kind::Verbatim,
        c: 'a'
      )

      hir = translator.translate(ast)
      hir.should be_a(Regex::Syntax::Hir::CharClass)
      char_class = hir.as(Regex::Syntax::Hir::CharClass)
      char_class.intervals.should eq([97_u8..97_u8, 65_u8..65_u8]) # 'a' and 'A'
    end

    it "applies case-insensitive flag to character classes" do
      hir = Regex::Syntax.parse("(?i:[a])")
      hir.node.should be_a(Regex::Syntax::Hir::UnicodeClass)
      hir.node.as(Regex::Syntax::Hir::UnicodeClass).intervals.should eq([
        0x41_u32..0x41_u32,
        0x61_u32..0x61_u32,
      ])
    end
  end
end
