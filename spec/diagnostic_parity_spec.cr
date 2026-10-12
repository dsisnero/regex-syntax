require "./spec_helper"
require "./support/diagnostic_snapshot"

describe "pinned Rust diagnostics, printers and visitor contracts" do
  File.each_line("#{__DIR__}/fixtures/diagnostic.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    domain, config, input_hex, expected_hex = line.split('\t')
    input = String.new(input_hex.hexbytes)
    expected = String.new(expected_hex.hexbytes)
    it "matches #{domain} #{config} #{input.inspect}" do
      DiagnosticSnapshot.result(domain, config, input).should eq(expected)
    end
  end
end
