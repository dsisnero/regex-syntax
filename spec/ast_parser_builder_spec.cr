require "./spec_helper"

describe Regex::Syntax::AstParserBuilder do
  it "builds AST parsers with vendored parser options" do
    parser = Regex::Syntax::AstParserBuilder.new
      .ignore_whitespace(true)
      .nest_limit(10)
      .octal(true)
      .build

    ast = parser.parse("(?x)\\141")
    ast.kind.should be_a(Regex::Syntax::AST::Concat)
    children = ast.kind.as(Regex::Syntax::AST::Concat).children
    children.map(&.class).should eq([
      Regex::Syntax::AST::SetFlags,
      Regex::Syntax::AST::Literal,
    ])
    children[1].as(Regex::Syntax::AST::Literal).c.should eq('a')
  end

  it "supports parse_with_comments through the built AST parser" do
    parser = Regex::Syntax::AstParserBuilder.new.ignore_whitespace(true).build
    parsed = parser.parse_with_comments("(?x)a # comment\n b")

    parsed.comments.size.should eq(1)
    parsed.comments.first.comment.should eq(" comment")
    parsed.ast.kind.should be_a(Regex::Syntax::AST::Concat)
  end

  it "supports empty_min_range like Rust" do
    expect_parse_error(/empty repetition count/) do
      Regex::Syntax::AstParserBuilder.new.build.parse("a{,9}")
    end

    ast = Regex::Syntax::AstParserBuilder.new.empty_min_range(true).build.parse("a{,9}")
    ast.kind.should be_a(Regex::Syntax::AST::Repetition)
    repetition = ast.kind.as(Regex::Syntax::AST::Repetition)
    repetition.op.min.should eq(0_u32)
    repetition.op.max.should eq(9_u32)
  end

  it "does not overcount nest depth on long alternation trees" do
    pattern = <<-'REGEX'
    2(?:
      [45]\d{3}|
      7(?:
        1[0-267]|
        2[0-289]|
        3[0-29]|
        4[01]|
        5[1-3]|
        6[013]|
        7[0178]|
        91
      )|
      8(?:
        0[125]|
        [139][1-6]|
        2[0157-9]|
        41|
        6[1-35]|
        7[1-5]|
        8[1-8]|
        90
      )|
      9(?:
        0[0-2]|
        1[0-4]|
        2[568]|
        3[3-6]|
        5[5-7]|
        6[0167]|
        7[15]|
        8[0146-9]
      )
    )\d{4}
    REGEX

    ast = Regex::Syntax::AstParserBuilder.new
      .ignore_whitespace(true)
      .nest_limit(50)
      .build
      .parse(pattern)

    ast.kind.should_not be_a(Regex::Syntax::AST::Empty)
  end
end
