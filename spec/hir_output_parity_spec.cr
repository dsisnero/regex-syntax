require "./spec_helper"

# The fixture contains every literal t/t_bytes call in the pinned Rust
# src/hir/translate.rs tests. Generate it with the Rust oracle, never from
# Crystal's implementation. Exact node-shape assertions live separately in
# hir_alternation_spec.cr; equivalent printed patterns alone cannot prove them.
describe "Vendored translator output parity" do
  File.each_line("#{__DIR__}/fixtures/hir_translate.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    mode, pattern_hex, expected_hex = line.split('\t')
    pattern = String.new(pattern_hex.hexbytes)
    expected = String.new(expected_hex.hexbytes)

    it "prints Rust's exact HIR for #{mode} #{pattern.inspect}" do
      hir = Regex::Syntax::Parser.new(octal: true, utf8: mode != "bytes").parse(pattern)
      hir.to_s.should eq(expected)
    end
  end
end
