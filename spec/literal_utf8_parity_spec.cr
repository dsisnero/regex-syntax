require "./spec_helper"
require "./support/literal_utf8_snapshot"

describe "pinned Rust literal and UTF-8 assertions" do
  File.each_line("#{__DIR__}/fixtures/literal_utf8.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    kind, operation, input, argument, expected, other = line.split('\t')
    it "matches #{kind} #{operation} #{input} #{argument}" do
      LiteralUtf8Snapshot.result(kind, operation, input, argument).should eq({expected, other})
    end
  end
end
