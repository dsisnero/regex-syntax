require "./spec_helper"
require "./support/class_unicode_snapshot"

describe "pinned Rust Unicode and class assertions" do
  File.each_line("#{__DIR__}/fixtures/class_unicode.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    kind, operation, input, other, expected = line.split('\t')
    expected = "" if expected == "-"
    it "matches #{kind} #{operation} #{input} #{other}" do
      ClassUnicodeSnapshot.snapshot(kind, operation, input, other).should eq(expected)
    end
  end

  it "ports class_range_canonical_unicode and class_range_canonical_bytes exactly" do
    unicode = Regex::Syntax::Hir::ClassUnicodeRange.new(0xFF_u32, 0_u32)
    unicode.start.should eq(0_u32)
    unicode.end.should eq(0xFF_u32)
    bytes = Regex::Syntax::Hir::ClassBytesRange.new(0xFF_u8, 0_u8)
    bytes.start.should eq(0_u8)
    bytes.end.should eq(0xFF_u8)
  end

  it "preserves increasing SimpleCaseFolder cursor mappings across unmapped scalars" do
    folder = Regex::Syntax::Unicode::SimpleCaseFolder.new
    folder.mapping('@').should eq([] of Char)
    folder.mapping('A').should eq(['a'])
    folder.mapping('B').should eq(['b'])
    folder.mapping('K').should eq(['K', 'k'])
    folder.mapping('☃').should eq([] of Char)
  end
end

it "matches the complete ordered folder traversal, including unmapped scalars" do
  expected = {} of Int32 => Array(Char)
  File.each_line("#{__DIR__}/fixtures/class_unicode.tsv") do |line|
    next unless line.starts_with?("fold\t")
    _, _, scalar, _, mapping = line.split('\t')
    expected[scalar.to_i] = mapping.split(',').map(&.to_i.chr)
  end
  folder = Regex::Syntax::Unicode::SimpleCaseFolder.new
  (0..0x10FFFF).each do |scalar|
    next if (0xD800..0xDFFF).includes?(scalar)
    folder.mapping(scalar.chr).should eq(expected[scalar]? || [] of Char)
  end
  Regex::Syntax::UnicodeTables::CaseFoldingSimple::CASE_FOLDING_SIMPLE.size.should eq(expected.size)
end

describe "complete Unicode table inventories" do
  it "has exactly the pinned range tables, property aliases, and value aliases" do
    table_names = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
    property_names = [] of String
    value_names = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
    File.each_line("#{__DIR__}/fixtures/class_unicode.tsv") do |line|
      next if line.starts_with?('#')
      kind, operation, input, other, _ = line.split('\t')
      if kind == "table"
        table_names[operation] << Regex::Syntax::Unicode.normalize_symbolic_name(input)
      elsif kind == "alias" && operation == "name"
        property_names << input
      elsif kind == "alias" && operation == "value"
        value_names[input] << other
      end
    end
    ClassUnicodeSnapshot::TABLES.keys.sort!.should eq(table_names.keys.sort!)
    table_names.each do |name, keys|
      ClassUnicodeSnapshot::TABLES[name].keys.sort!.should eq(keys.sort)
    end
    Regex::Syntax::UnicodeTables::PropertyNames::BY_NAME.keys.sort!.should eq(property_names.sort)
    values = Regex::Syntax::UnicodeTables::PropertyValues::BY_PROPERTY
    values.keys.sort!.should eq(value_names.keys.sort!)
    value_names.each { |name, keys| values[name].keys.sort!.should eq(keys.sort) }
  end
end
