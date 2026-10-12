require "../../src/regex-syntax"

def property_output(hir : Regex::Syntax::Hir::Hir) : String
  props = hir.properties
  [props.minimum_len.try(&.to_s) || "-", props.maximum_len.try(&.to_s) || "-",
   props.utf8?.to_s, props.explicit_captures_len.to_s,
   props.static_explicit_captures_len.try(&.to_s) || "-",
   props.literal?.to_s, props.alternation_literal?.to_s,
   props.look_set.bits.to_s, props.look_set_prefix.bits.to_s,
   props.look_set_prefix_any.bits.to_s, props.look_set_suffix.bits.to_s,
   props.look_set_suffix_any.bits.to_s].join('|')
end

STDIN.each_line do |line|
  mode, encoded = line.split('\t', 2)
  pattern = String.new(encoded.hexbytes)
  begin
    hir = Regex::Syntax::Parser.new(octal: true, utf8: mode != "bytes").parse(pattern)
    output = ARGV.includes?("--properties") ? property_output(hir) : hir.to_s
    puts output.to_slice.hexstring
  rescue Regex::Syntax::ParseError
    puts "ERROR"
  rescue error
    puts "PANIC:#{error.class}"
  end
end
