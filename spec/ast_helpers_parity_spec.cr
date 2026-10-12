require "./spec_helper"
require "./support/ast_snapshot"

# Test-only access to private helpers. No parser-internal API is exported by the
# library; reset and cursor access reproduce Rust ParserI's starting state.
class Regex::Syntax::AstParser
  def parity_helper(operation : String, pattern : String, offset : Int32 = 0) : Tuple(String, String)
    reset(pattern)
    while @byte_pos < offset
      advance
    end
    result = begin
      parity_helper_result(operation)
    rescue ex : ParseError
      kind = map_parse_error_kind(ex)
      "error:#{AST::ErrorKind.names[kind.value]};#{AstParitySnapshot.span(ex.span || error_span)};#{ex.auxiliary_span.try { |span| AstParitySnapshot.span(span) } || "-"}"
    end
    {result, AstParitySnapshot.span(AST::Span.splat(current_position))}
  end

  private def parity_helper_result(operation : String) : String
    case operation
    when "parse_escape" then AstParitySnapshot.shape(parse_escape)
    when "parse_flags"
      start = current_position
      items = parse_flags_items
      AstParitySnapshot.flags(AST::Flags.new(AST::Span.new(start, current_position), items))
    when "maybe_parse_ascii_class"
      if ascii = maybe_parse_ascii_class
        AstParitySnapshot.shape(ascii)
      else
        "none"
      end
    when "parse_decimal"   then parse_decimal.to_s
    when "parse_flag"      then AST::Flag.from_char(parse_flag_char).to_s
    when "parse_primitive" then AstParitySnapshot.shape(parse_primitive)
    when "parse_set_class" then AstParitySnapshot.shape(parse_class_bracketed)
    when "parse_set_class_open"
      opening, union = parse_class_open
      "#{AstParitySnapshot.shape(opening)}\n#{AstParitySnapshot.shape(union)}"
    else raise "Unknown helper #{operation}"
    end
  end
end

describe "Pinned Rust private parser helper contracts" do
  File.each_line("#{__DIR__}/fixtures/ast_helpers.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    operation, config, pattern_hex, expected_hex, cursor, offset = line.split('\t')
    limit, octal, empty_min, whitespace = config.split(',')
    pattern = String.new(pattern_hex.hexbytes)
    expected = String.new(expected_hex.hexbytes)
    it "replays #{operation} #{pattern.inspect} (#{config})" do
      parser = Regex::Syntax::AstParser.new(nest_limit: limit.to_i, octal: octal == "true",
        empty_min_range: empty_min == "true", ignore_whitespace: whitespace == "true")
      parser.parity_helper(operation, pattern, offset.to_i).should eq({expected, cursor})
    end
  end
end
