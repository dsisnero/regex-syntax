require "./spec_helper"

# Exact assertions from the pinned src/lib.rs and src/hir/mod.rs tests.
describe "Rust public API parity" do
  it "ports escape_meta" do
    Regex::Syntax.escape(%q(\.+*?()|[]{}^$#&-~)).should eq(%q(\\\.\+\*\?\(\)\|\[\]\{\}\^\$\#\&\-\~))
  end

  it "ports word_byte" do
    Regex::Syntax.is_word_byte('a'.ord.to_u8).should be_true
    Regex::Syntax.is_word_byte('-'.ord.to_u8).should be_false
  end

  it "ports word_char with all default Unicode tables" do
    ['a', 'à', 'β', '\u{11011}', '\u{11611}', '\u{11711}', '\u{17828}', '\u{1B1B1}', '\u{16E40}'].each do |char|
      Regex::Syntax.is_word_character(char).should be_true
    end
    Regex::Syntax.is_word_character('-').should be_false
    Regex::Syntax.is_word_character('☃').should be_false
  end

  it "ports look_set_iter" do
    set = Regex::Syntax::Hir::LookSet
    set.empty.iter.to_a.size.should eq(0)
    set.full.iter.to_a.size.should eq(18)
    set.empty.insert(Regex::Syntax::Hir::Look::Kind::StartLF).insert(Regex::Syntax::Hir::Look::Kind::WordUnicode).iter.to_a.size.should eq(2)
    set.empty.insert(Regex::Syntax::Hir::Look::Kind::StartLF).iter.to_a.size.should eq(1)
    set.empty.insert(Regex::Syntax::Hir::Look::Kind::WordAsciiNegate).iter.to_a.size.should eq(1)
  end

  it "ports look_set_debug" do
    Regex::Syntax::Hir::LookSet.empty.inspect.should eq("∅")
    Regex::Syntax::Hir::LookSet.full.inspect.should eq("Az^$rRbB𝛃𝚩<>〈〉◁▷◀▶")
  end

  it "preserves Rust's full 32-bit representation, including reserved bits" do
    set = Regex::Syntax::Hir::LookSet.full
    set.bits.should eq(UInt32::MAX)
    set.len.should eq(32)
    set.iter.to_a.size.should eq(18)
    reserved = Regex::Syntax::Hir::LookSet.new(1_u32 << 31)
    reserved.len.should eq(1)
    reserved.empty?.should be_false
    reserved.iter.to_a.should be_empty
    reserved.inspect.should eq("")
  end

  it "counts all 256 bytes without overflowing the byte endpoint type" do
    Regex::Syntax::Hir::ClassBytesRange.new(0_u8, 255_u8).len.should eq(256)
    Regex::Syntax::Hir::ClassBytesRange.new(255_u8, 0_u8).len.should eq(256)
  end

  it "ports every negative analysis_minimum_len assertion" do
    ["a+", "a{1}", "a{1,}", "a{1,2}", "a{1,10}", "b|a", "a*a+(abcd)*", %q(\P{any}), "[a--a]", "[a&&b]"].each do |pattern|
      Regex::Syntax::ParserBuilder.new.utf8(false).build.parse(pattern).properties.minimum_len.should_not eq(0_u64)
    end
  end

  File.each_line("#{__DIR__}/fixtures/public_api.tsv") do |line|
    next if line.starts_with?('#') || line.empty?
    domain, input, expected = line.split('\t')
    it "matches native #{domain} #{input}" do
      case domain
      when "look"
        set = Regex::Syntax::Hir::LookSet.new(input.to_u32)
        bytes = Bytes.new(6, 0xA5_u8)
        set.write_repr(bytes)
        Regex::Syntax::Hir::LookSet.read_repr(bytes).should eq(set)
        bytes[4, 2].should eq(Bytes[0xA5, 0xA5])
        "#{set.bits};#{set.len};#{set.iter.to_a.size};#{set.inspect.to_slice.hexstring};#{bytes[0, 4].hexstring}".should eq(expected)
      when "range"
        kind, start, finish = input.split(':')
        range = if kind == "byte"
                  Regex::Syntax::Hir::ClassBytesRange.new(start.to_u8, finish.to_u8)
                else
                  Regex::Syntax::Hir::ClassUnicodeRange.new(start.to_u32, finish.to_u32)
                end
        "#{range.start};#{range.end};#{range.len}".should eq(expected)
      when "char"
        char = input.to_i.chr
        "#{Regex::Syntax.is_meta_character(char)};#{Regex::Syntax.is_escapeable_character(char)};#{Regex::Syntax.is_word_byte(input.to_u8)};#{Regex::Syntax.is_word_character(char)}".should eq(expected)
      else
        fail "Unknown public API fixture domain: #{domain}"
      end
    end
  end
end
