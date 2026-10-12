require "./spec_helper"
require "./support/hir_snapshot"

private def runtime_translation(test : String, config : String, pattern : String) : String
  utf8, terminator, ignore_case, multi_line, dot_all, swap, unicode, crlf = config.split(',')
  unless test.ends_with?("::regression_alt_empty_concat") || test.ends_with?("::regression_empty_alt") || test.ends_with?("::regression_singleton_alt")
    hir = Regex::Syntax::Parser.new(octal: true,
      ignore_whitespace: test.ends_with?("::regression_fuzz_match"),
      utf8: utf8 == "true", line_terminator: terminator.to_u8,
      ignore_case: ignore_case == "true", multi_line: multi_line == "true",
      dot_matches_new_line: dot_all == "true", swap_greed: swap == "true",
      unicode: unicode == "true", crlf: crlf == "true").parse(pattern)
    return HirParitySnapshot.snapshot(hir)
  end
  ast = if test.ends_with?("::regression_alt_empty_concat")
          span = Regex::Syntax::AST::Span.new(0, 0)
          Regex::Syntax::AST::Alternation.new(span, [Regex::Syntax::AST::Concat.new(span, [] of Regex::Syntax::AST::Node)] of Regex::Syntax::AST::Node)
        elsif test.ends_with?("::regression_empty_alt")
          span = Regex::Syntax::AST::Span.new(0, 0)
          Regex::Syntax::AST::Concat.new(span, [Regex::Syntax::AST::Alternation.new(span, [] of Regex::Syntax::AST::Node)] of Regex::Syntax::AST::Node)
        elsif test.ends_with?("::regression_singleton_alt")
          span = Regex::Syntax::AST::Span.new(0, 0)
          Regex::Syntax::AST::Concat.new(span, [Regex::Syntax::AST::Alternation.new(span, [Regex::Syntax::AST::Dot.new(span)] of Regex::Syntax::AST::Node)] of Regex::Syntax::AST::Node)
        else
          Regex::Syntax::AstParser.new(octal: true, ignore_whitespace: test.ends_with?("::regression_fuzz_match")).parse(pattern).root
        end
  translator = Regex::Syntax::Translator.new(utf8: utf8 == "true", line_terminator: terminator.to_u8,
    ignore_case: ignore_case == "true", multi_line: multi_line == "true",
    dot_matches_new_line: dot_all == "true", swap_greed: swap == "true",
    unicode: unicode == "true", crlf: crlf == "true")
  HirParitySnapshot.snapshot(Regex::Syntax::Hir::Hir.new(translator.translate(ast)))
rescue error : Regex::Syntax::Hir::Error
  span = error.span
  "error(#{Regex::Syntax::Hir::ErrorKind.names[error.kind.value]},#{span.start.offset},#{span.start.line},#{span.start.column},#{span.end.offset},#{span.end.line},#{span.end.column})"
end

describe "Pinned Rust translator runtime assertions" do
  File.each_line("#{__DIR__}/fixtures/hir_runtime.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    test, config, pattern_hex, expected_hex = line.split('\t')
    pattern = String.new(pattern_hex.hexbytes)
    expected = String.new(expected_hex.hexbytes)
    it "replays #{test} #{pattern.inspect} (#{config})" do
      runtime_translation(test, config, pattern).should eq(expected)
    end
  end
end
