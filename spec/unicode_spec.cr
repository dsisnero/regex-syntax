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

  it "supports binary and property-value Unicode class queries like Rust" do
    binary = Regex::Syntax::Unicode.class(Regex::Syntax::Unicode::ClassQuery::Binary.new("Greek"))
    binary.intervals.should eq(Regex::Syntax::Unicode.property_class("Greek", false).intervals)

    by_value = Regex::Syntax::Unicode.class(
      Regex::Syntax::Unicode::ClassQuery::ByValue.new("gc", "Separator")
    )
    by_value.intervals.should eq(Regex::Syntax::Unicode.property_class("gc:Separator", false).intervals)
  end

  it "exposes direct unicode helper classes like Rust" do
    hir = Regex::Syntax::Unicode.hir_class([{'a', 'c'}, {'β', 'δ'}])
    hir.intervals.should eq([
      'a'.ord.to_u32..'c'.ord.to_u32,
      'β'.ord.to_u32..'δ'.ord.to_u32,
    ])

    Regex::Syntax::Unicode.perl_digit.intervals.should eq(
      Regex::Syntax::Unicode.property_class("Decimal_Number", false).intervals
    )
    Regex::Syntax::Unicode.perl_space.intervals.should eq(
      Regex::Syntax::Unicode.property_class("White_Space", false).intervals
    )
    Regex::Syntax::Unicode.perl_word.intervals.should eq(
      Regex::Syntax::UnicodeTables::PerlWord::PERL_WORD
    )
  end

  it "exposes vendored unicode table namespace aliases" do
    Regex::Syntax::UnicodeTables::PerlDecimal::BY_NAME.should eq(
      Regex::Syntax::UnicodeTables::GeneralCategory::BY_NAME
    )
    Regex::Syntax::UnicodeTables::PerlDecimal::DECIMAL_NUMBER.should eq(
      Regex::Syntax::UnicodeTables::GeneralCategory::DECIMAL_NUMBER
    )
    Regex::Syntax::UnicodeTables::PerlSpace::BY_NAME.should eq(
      Regex::Syntax::UnicodeTables::PropertyBool::BY_NAME
    )
    Regex::Syntax::UnicodeTables::PerlSpace::WHITE_SPACE.should eq(
      Regex::Syntax::UnicodeTables::PropertyBool::WHITE_SPACE
    )
    Regex::Syntax::UnicodeTables::PropertyNames::PROPERTY_NAMES.should eq(
      Regex::Syntax::UnicodeTables::PropertyNames::BY_NAME
    )
    Regex::Syntax::UnicodeTables::PropertyValues::PROPERTY_VALUES.should eq(
      Regex::Syntax::UnicodeTables::PropertyValues::BY_PROPERTY
    )
  end

  it "exposes unicode word-character helper aliases and error enums like Rust" do
    Regex::Syntax::Unicode.word_character?('β').should be_true
    Regex::Syntax::Unicode.is_word_character('β').should be_true
    Regex::Syntax::Unicode.word_character?('☃').should be_false
    Regex::Syntax::Unicode.is_word_character('☃').should be_false

    Regex::Syntax::Unicode::Error::PropertyNotFound.to_s.should eq("PropertyNotFound")
    Regex::Syntax::Unicode::Error::PropertyValueNotFound.to_s.should eq("PropertyValueNotFound")
    Regex::Syntax::Unicode::Error::PerlClassNotFound.to_s.should eq("PerlClassNotFound")
    Regex::Syntax::Unicode::CaseFoldError.new.message.should contain("Unicode-aware case folding")
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
