require "./spec_helper"
require "./support/ast_snapshot"

private def ast_runtime_parse(config : String, pattern : String) : String
  limit, octal, empty_min, whitespace = config.split(',')
  parser = Regex::Syntax::AstParser.new(nest_limit: limit.to_i, octal: octal == "true",
    empty_min_range: empty_min == "true", ignore_whitespace: whitespace == "true")
  AstParitySnapshot.snapshot(parser.parse_with_comments(pattern))
rescue error : Regex::Syntax::AST::Error
  "error:#{Regex::Syntax::AST::ErrorKind.names[error.kind.value]};#{AstParitySnapshot.span(error.span)};#{error.auxiliary_span.try { |span| AstParitySnapshot.span(span) } || "-"}"
end

describe "Pinned Rust public AST results for parser-test inputs" do
  File.each_line("#{__DIR__}/fixtures/ast_runtime.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    test, config, pattern_hex, expected_hex = line.split('\t')
    pattern = String.new(pattern_hex.hexbytes)
    expected = String.new(expected_hex.hexbytes)
    it "replays #{test} #{pattern.inspect} (#{config})" do
      ast_runtime_parse(config, pattern).should eq(expected)
    end
  end
end

# Exact ports of the generated loops in Rust parse_hex_two/four/eight. Keep
# every scalar rather than committing 127,232 redundant fixture rows.
describe "Rust generated fixed-width hexadecimal escape assertions" do
  {'x' => {256, 2, Regex::Syntax::AST::Literal::HexLiteralKind::X},
   'u' => {65536, 4, Regex::Syntax::AST::Literal::HexLiteralKind::UnicodeShort},
   'U' => {65536, 8, Regex::Syntax::AST::Literal::HexLiteralKind::UnicodeLong}}.each do |prefix, (limit, digits, kind)|
    it "parses every upstream scalar for \\#{prefix}" do
      parser = Regex::Syntax::AstParser.new
      limit.times do |codepoint|
        next if (0xD800..0xDFFF).includes?(codepoint)
        pattern = "\\#{prefix}#{codepoint.to_s(16).rjust(digits, '0')}"
        literal = parser.parse(pattern).root.as(Regex::Syntax::AST::Literal)
        literal.c.should eq(codepoint.chr)
        literal.hex_kind.should eq(kind)
        literal.form.should eq(Regex::Syntax::AST::Literal::Form::Fixed)
        literal.span.should eq(Regex::Syntax::AST::Span.new(0, pattern.bytesize))
      end
    end
  end
end

describe "Rust default parser nesting limit" do
  it "rejects 251 nested groups through each public default constructor" do
    pattern = "(" * 251 + "a" + ")" * 251
    parsers = [Regex::Syntax::AstParser.new, Regex::Syntax::AstParserBuilder.new.build,
               Regex::Syntax::Parser.new, Regex::Syntax::ParserBuilder.new.build]
    parsers.each do |parser|
      parser.parse("(" * 250 + "a" + ")" * 250)
      expect_ast_error(Regex::Syntax::AST::ErrorKind::NestLimitExceeded,
        Regex::Syntax::AST::Span.new(250, 253)) { parser.parse(pattern) }
    end
  end
end
