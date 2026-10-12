require "../../src/regex-syntax"

STDIN.each_line do |line|
  mode, encoded = line.split('\t', 2)
  pattern = String.new(encoded.hexbytes)
  begin
    hir = Regex::Syntax::Parser.new(octal: true, utf8: mode != "bytes").parse(pattern)
    puts hir.to_s.to_slice.hexstring
  rescue Regex::Syntax::ParseError
    puts "ERROR"
  rescue error
    puts "PANIC:#{error.class}"
  end
end
