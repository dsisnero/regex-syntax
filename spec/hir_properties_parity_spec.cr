require "./spec_helper"

private def hir_property_snapshot(hir : Regex::Syntax::Hir::Hir) : Array(String)
  props = hir.properties
  [props.minimum_len.try(&.to_s) || "-", props.maximum_len.try(&.to_s) || "-",
   props.utf8?.to_s, props.explicit_captures_len.to_s,
   props.static_explicit_captures_len.try(&.to_s) || "-",
   props.literal?.to_s, props.alternation_literal?.to_s,
   props.look_set.bits.to_s, props.look_set_prefix.bits.to_s,
   props.look_set_prefix_any.bits.to_s, props.look_set_suffix.bits.to_s,
   props.look_set_suffix_any.bits.to_s]
end

describe "Vendored HIR property parity" do
  it "preserves Rust's unknown static capture count for an empty property union" do
    props = Regex::Syntax::Hir::Properties.union([] of Regex::Syntax::Hir::Properties)
    props.static_explicit_captures_len.should be_nil
    props.minimum_len.should be_nil
    props.maximum_len.should be_nil
    props.utf8?.should be_true
    props.explicit_captures_len.should eq(0)
  end

  File.each_line("#{__DIR__}/fixtures/hir_properties.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    mode, pattern_hex, expected_hex = line.split('\t')
    pattern = String.new(pattern_hex.hexbytes)
    expected = String.new(expected_hex.hexbytes).split('|')

    it "matches all Rust properties for #{mode} #{pattern.inspect}" do
      hir = Regex::Syntax::Parser.new(octal: true, utf8: mode != "bytes").parse(pattern)
      hir_property_snapshot(hir).should eq(expected)
    end
  end
end
