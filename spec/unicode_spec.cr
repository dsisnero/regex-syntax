require "./spec_helper"

describe Regex::Syntax::Unicode do
  describe Regex::Syntax::Unicode::SimpleCaseFolder do
    it "returns the vendored simple fold mappings for Kelvin sign classes" do
      Regex::Syntax::Unicode::SimpleCaseFolder.new.mapping('k').should eq(['K', 'K'])
      Regex::Syntax::Unicode::SimpleCaseFolder.new.mapping('K').should eq(['k', 'K'])
      Regex::Syntax::Unicode::SimpleCaseFolder.new.mapping('K').should eq(['K', 'k'])
    end

    it "returns the vendored simple fold mappings for ASCII a/A" do
      Regex::Syntax::Unicode::SimpleCaseFolder.new.mapping('a').should eq(['A'])
      Regex::Syntax::Unicode::SimpleCaseFolder.new.mapping('A').should eq(['a'])
    end

    it "detects whether a range overlaps the case folding table" do
      folder = Regex::Syntax::Unicode::SimpleCaseFolder.new

      folder.overlaps('A', 'A').should be_true
      folder.overlaps('Z', 'Z').should be_true
      folder.overlaps('A', 'Z').should be_true
      folder.overlaps('@', 'A').should be_true
      folder.overlaps('Z', '[').should be_true
      folder.overlaps('☃', 'Ⰰ').should be_true

      folder.overlaps('[', '[').should be_false
      folder.overlaps('[', '`').should be_false
      folder.overlaps('☃', '☃').should be_false
    end
  end

  it "canonicalizes one-letter general category queries like Rust regression 466" do
    klass = Regex::Syntax::Unicode.class(Regex::Syntax::Unicode::ClassQuery::OneLetter.new('C'))
    expected = Regex::Syntax::Unicode.property_class("Other", false)
    klass.intervals.should eq(expected.intervals)
  end

  it "normalizes symbolic names like the vendored unicode helper" do
    Regex::Syntax::Unicode.normalize_symbolic_name("Line_Break").should eq("linebreak")
    Regex::Syntax::Unicode.normalize_symbolic_name("Line-break").should eq("linebreak")
    Regex::Syntax::Unicode.normalize_symbolic_name("linebreak").should eq("linebreak")
    Regex::Syntax::Unicode.normalize_symbolic_name("BA").should eq("ba")
    Regex::Syntax::Unicode.normalize_symbolic_name("ba").should eq("ba")
    Regex::Syntax::Unicode.normalize_symbolic_name("Greek").should eq("greek")
    Regex::Syntax::Unicode.normalize_symbolic_name("isGreek").should eq("greek")
    Regex::Syntax::Unicode.normalize_symbolic_name("IS_Greek").should eq("greek")
    Regex::Syntax::Unicode.normalize_symbolic_name("isc").should eq("isc")
    Regex::Syntax::Unicode.normalize_symbolic_name("is c").should eq("isc")
    Regex::Syntax::Unicode.normalize_symbolic_name("is_c").should eq("isc")
  end

  it "keeps normalized symbolic byte slices valid UTF-8" do
    bytes = Bytes['a'.ord.to_u8, 'b'.ord.to_u8, 'c'.ord.to_u8, 0xFF_u8, 'x'.ord.to_u8, 'y'.ord.to_u8, 'z'.ord.to_u8]
    normalized = Regex::Syntax::Unicode.normalize_symbolic_name_bytes(bytes)
    String.new(normalized).should eq("abcxyz")
  end
end
