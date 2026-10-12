require "./spec_helper"
require "./support/hir_snapshot"

alias ConstructionHir = Regex::Syntax::Hir

describe "Rust HIR constructor semantics" do
  it "clamps repetitions of empty captured expressions using maximum length" do
    sub = ConstructionHir::Capture.new(ConstructionHir::Empty.new, 1)
    hir = ConstructionHir::Hir.repetition(sub, 2_u32, nil)
    HirParitySnapshot.shape(hir.node).should eq("cap(1,-,empty)")
  end

  it "includes impossible branches when computing static capture counts" do
    fail = ConstructionHir::Hir.fail.node
    capture = ConstructionHir::Capture.new(ConstructionHir::Literal.new(Bytes[97]), 1)
    hir = ConstructionHir::Hir.alternation([fail, capture] of ConstructionHir::Node)
    hir.static_explicit_captures_len.should be_nil
  end

  it "poisons alternation length properties with impossible branches" do
    fail = ConstructionHir::Hir.fail.node
    capture = ConstructionHir::Capture.new(ConstructionHir::Literal.new(Bytes[97]), 1)
    hir = ConstructionHir::Hir.alternation([fail, capture] of ConstructionHir::Node)
    hir.minimum_len.should be_nil
    hir.maximum_len.should be_nil
  end
end

# ameba:disable Metrics/CyclomaticComplexity
private def construction_atom(index : Int32) : ConstructionHir::Hir
  node = case index
         when  0 then ConstructionHir::Empty.new
         when  1 then ConstructionHir::Hir.fail.node
         when  2 then ConstructionHir::Literal.new(Bytes[97])
         when  3 then ConstructionHir::Literal.new("β".to_slice)
         when  4 then ConstructionHir::Capture.new(ConstructionHir::Empty.new, 1)
         when  5 then ConstructionHir::Capture.new(ConstructionHir::Literal.new("ab".to_slice), 2, "name")
         when  6 then ConstructionHir::Look.new(ConstructionHir::Look::Kind::WordUnicode)
         when  7 then ConstructionHir::UnicodeClass.new(false, [97_u32..122_u32])
         when  8 then ConstructionHir::CharClass.new(false, [255_u8..255_u8])
         when  9 then ConstructionHir::UnicodeClass.new(false, [99_u32..99_u32])
         when 10 then ConstructionHir::UnicodeClass.empty
         when 11 then ConstructionHir::UnicodeClass.new(true, [0_u32..98_u32, 100_u32..0x10ffff_u32])
         else         raise "Unknown atom #{index}"
         end
  case node
  when ConstructionHir::UnicodeClass, ConstructionHir::CharClass
    ConstructionHir::Hir.character_class(node)
  else
    ConstructionHir::Hir.new(node)
  end
end

# ameba:enable Metrics/CyclomaticComplexity

# ameba:disable Metrics/CyclomaticComplexity
private def construct_recipe(recipe : String) : ConstructionHir::Hir
  parts = recipe.split('/')
  return construction_atom(parts[1].to_i) if parts[0] == "atom"
  case parts[0]
  when "empty-alt"
    ConstructionHir::Hir.alternation([] of ConstructionHir::Node)
  when "empty-cat"
    ConstructionHir::Hir.concat([] of ConstructionHir::Node)
  when "empty-literal"
    ConstructionHir::Hir.literal(Bytes.empty)
  when "dot"
    kind = [ConstructionHir::Dot::AnyChar, ConstructionHir::Dot::AnyCharExceptLF,
            ConstructionHir::Dot::AnyCharExceptCRLF, ConstructionHir::Dot::AnyByte,
            ConstructionHir::Dot::AnyByteExceptLF, ConstructionHir::Dot::AnyByteExceptCRLF][parts[1].to_i]
    ConstructionHir::Hir.dot(kind)
  when "singleton-alt", "singleton-cat"
    children = [construction_atom(parts[1].to_i)]
    parts[0] == "singleton-alt" ? ConstructionHir::Hir.alternation(children) : ConstructionHir::Hir.concat(children)
  when "alt", "cat"
    children = [construction_atom(parts[1].to_i), construction_atom(parts[2].to_i)]
    parts[0] == "alt" ? ConstructionHir::Hir.alternation(children) : ConstructionHir::Hir.concat(children)
  when "rep"
    repetition_index = parts[2].to_i
    min, max = [{0_u32, nil}, {1_u32, nil}, {2_u32, nil}, {0_u32, 0_u32},
                {1_u32, 1_u32}, {2_u32, 3_u32}, {0_u32, 1_u32}, {4_u32, 9_u32}][repetition_index]
    ConstructionHir::Hir.repetition(construction_atom(parts[1].to_i).node, min, max, greedy: repetition_index.even?)
  when "nested"
    inner = ConstructionHir::Hir.repetition(construction_atom(parts[1].to_i).node, 1_u32, nil)
    ConstructionHir::Hir.repetition(inner.node, 0_u32, 1_u32, greedy: false)
  when "overflow"
    big = ConstructionHir::Hir.repetition(ConstructionHir::Literal.new(Bytes[97]), UInt32::MAX, UInt32::MAX)
    square = ConstructionHir::Hir.repetition(big.node, UInt32::MAX, UInt32::MAX)
    parts[1] == "add" ? ConstructionHir::Hir.concat([square, square]) : ConstructionHir::Hir.repetition(square.node, 2_u32, 2_u32)
  when "prefix"
    ConstructionHir::Hir.concat([
      ConstructionHir::Hir.look(ConstructionHir::Look::Kind::StartText),
      ConstructionHir::Hir.repetition(ConstructionHir::Look.new(ConstructionHir::Look::Kind::WordUnicode), 0_u32, 1_u32),
      construction_atom(2), ConstructionHir::Hir.look(ConstructionHir::Look::Kind::EndText),
    ])
  else
    raise "Unknown constructor recipe #{recipe}"
  end
end

# ameba:enable Metrics/CyclomaticComplexity

describe "Rust smart constructor composition snapshots" do
  File.each_line("#{__DIR__}/fixtures/hir_construction.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    _, _, recipe_hex, expected_hex = line.split('\t')
    recipe = String.new(recipe_hex.hexbytes)
    expected = String.new(expected_hex.hexbytes)
    it "matches all fields for #{recipe}" do
      if recipe.starts_with?("union/")
        parts = recipe.split('/')
        props = ConstructionHir::Properties.union([
          construction_atom(parts[1].to_i).properties, construction_atom(parts[2].to_i).properties,
        ])
        HirParitySnapshot.properties(props).should eq(expected)
      else
        HirParitySnapshot.snapshot(construct_recipe(recipe)).should eq(expected)
      end
    end
  end

  it "uses the effective set for negated class helper queries" do
    unicode = ConstructionHir::UnicodeClass.new(true, [128_u32..0x10ffff_u32])
    unicode.minimum_len.should eq(1)
    unicode.maximum_len.should eq(1)
    unicode.ascii?.should be_true
    unicode.to_byte_class.should_not be_nil
    unicode.to_byte_class.try(&.intervals).should eq([0_u8..127_u8])
    ConstructionHir::UnicodeClass.new(true, [97_u32..97_u32]).literal.should be_nil
    ConstructionHir::CharClass.new(true, [97_u8..97_u8]).literal.should be_nil
    ConstructionHir::CharClass.new(true, [] of Range(UInt8, UInt8)).minimum_len.should eq(1)
  end
end

describe "Translator flags preserve Rust negation scope" do
  it "keeps every flag after the minus sign disabled" do
    HirParitySnapshot.shape(Regex::Syntax.parse("(?i-ux)a ").node).should eq("cat(bytes(65-65,97-97),lit(20))")
    HirParitySnapshot.shape(Regex::Syntax.parse("(?i-ux:a )").node).should eq("cat(bytes(65-65,97-97),lit(20))")
  end
end

describe "Rust smart class wrapper construction" do
  it "normalizes wrapped classes through the same constructor" do
    singleton = ConstructionHir::Class.new(ConstructionHir::UnicodeClass.new(false, [99_u32..99_u32]))
    HirParitySnapshot.shape(ConstructionHir::Hir.character_class(singleton).node).should eq("lit(63)")
    empty = ConstructionHir::Class.new(ConstructionHir::CharClass.empty)
    HirParitySnapshot.shape(ConstructionHir::Hir.character_class(empty).node).should eq("bytes()")
    complement = ConstructionHir::Class.new(ConstructionHir::CharClass.new(true, [] of Range(UInt8, UInt8)))
    complement.empty?.should be_false
    complement.utf8?.should be_false
    complement.minimum_len.should eq(1)
    complement.maximum_len.should eq(1)
    complement.literal.should be_nil
    complement.bytes.should_not be_nil
    complement.bytes.try(&.to_unicode_class).should be_nil
  end
end
