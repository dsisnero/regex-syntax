require "./hir"
require "./unicode_tables"

module Regex::Syntax::Unicode
  # Look up Unicode property class by name
  def self.property_class(name : String, negated : Bool) : Hir::UnicodeClass
    # Normalize property name: case-insensitive, underscore/hyphen equivalence
    normalized = name.downcase.gsub(/[_-]/, "")

    # Try to look up in generated Unicode tables
    if ranges = UnicodeTables.lookup_property_ranges(normalized)
      return Hir::UnicodeClass.new(negated, ranges)
    end

    # Fall back to hardcoded properties for backward compatibility
    # (these should eventually be moved to the generated tables)
    case normalized
    when "whitespace"
      # White_Space property (fallback implementation)
      intervals = whitespace_ranges
    when "greek"
      intervals = greek_ranges
    when "cyrillic"
      intervals = cyrillic_ranges
    when "latin"
      intervals = latin_ranges
    when "han"
      intervals = han_ranges
    else
      # Unknown property - return empty class (matches nothing)
      intervals = [] of Range(UInt32, UInt32)
    end

    Hir::UnicodeClass.new(negated, intervals)
  end

  private def self.greek_ranges : Array(Range(UInt32, UInt32))
    [
      0x0370_u32..0x0373_u32, # Greek and Coptic
      0x0375_u32..0x0377_u32,
      0x037A_u32..0x037D_u32,
      0x037F_u32..0x037F_u32,
      0x0384_u32..0x0384_u32,
      0x0386_u32..0x0386_u32,
      0x0388_u32..0x038A_u32,
      0x038C_u32..0x038C_u32,
      0x038E_u32..0x03A1_u32,
      0x03A3_u32..0x03E1_u32,
      0x03F0_u32..0x03FF_u32,
      0x1D26_u32..0x1D2A_u32,
      0x1D5D_u32..0x1D61_u32,
      0x1D66_u32..0x1D6A_u32,
      0x1DBF_u32..0x1DBF_u32,
      0x1F00_u32..0x1F15_u32,
      0x1F18_u32..0x1F1D_u32,
      0x1F20_u32..0x1F45_u32,
      0x1F48_u32..0x1F4D_u32,
      0x1F50_u32..0x1F57_u32,
      0x1F59_u32..0x1F59_u32,
      0x1F5B_u32..0x1F5B_u32,
      0x1F5D_u32..0x1F5D_u32,
      0x1F5F_u32..0x1F7D_u32,
      0x1F80_u32..0x1FB4_u32,
      0x1FB6_u32..0x1FC4_u32,
      0x1FC6_u32..0x1FD3_u32,
      0x1FD6_u32..0x1FDB_u32,
      0x1FDD_u32..0x1FEF_u32,
      0x1FF2_u32..0x1FF4_u32,
      0x1FF6_u32..0x1FFE_u32,
      0x2126_u32..0x2126_u32,
      0xAB65_u32..0xAB65_u32,
      0x10140_u32..0x1018E_u32,
      0x101A0_u32..0x101A0_u32,
      0x1D200_u32..0x1D245_u32,
    ]
  end

  private def self.cyrillic_ranges : Array(Range(UInt32, UInt32))
    [
      0x0400_u32..0x0484_u32,
      0x0487_u32..0x052F_u32,
      0x1C80_u32..0x1C88_u32,
      0x1D2B_u32..0x1D2B_u32,
      0x1D78_u32..0x1D78_u32,
      0x2DE0_u32..0x2DFF_u32,
      0xA640_u32..0xA69F_u32,
      0xFE2E_u32..0xFE2F_u32,
      0x1E030_u32..0x1E06D_u32,
      0x1E08F_u32..0x1E08F_u32,
    ]
  end

  private def self.latin_ranges : Array(Range(UInt32, UInt32))
    [
      0x0041_u32..0x005A_u32,
      0x0061_u32..0x007A_u32,
      0x00AA_u32..0x00AA_u32,
      0x00BA_u32..0x00BA_u32,
      0x00C0_u32..0x00D6_u32,
      0x00D8_u32..0x00F6_u32,
      0x00F8_u32..0x02B8_u32,
      0x02E0_u32..0x02E4_u32,
      0x1D00_u32..0x1D25_u32,
      0x1D2C_u32..0x1D5C_u32,
      0x1D62_u32..0x1D65_u32,
      0x1D6B_u32..0x1D77_u32,
      0x1D79_u32..0x1DBE_u32,
      0x1E00_u32..0x1EFF_u32,
      0x2071_u32..0x2071_u32,
      0x207F_u32..0x207F_u32,
      0x2090_u32..0x209C_u32,
      0x212A_u32..0x212B_u32,
      0x2132_u32..0x2132_u32,
      0x214E_u32..0x214E_u32,
      0x2160_u32..0x2188_u32,
      0x2C60_u32..0x2C7F_u32,
      0xA722_u32..0xA787_u32,
      0xA78B_u32..0xA7CD_u32,
      0xA7D0_u32..0xA7D1_u32,
      0xA7D3_u32..0xA7D3_u32,
      0xA7D5_u32..0xA7DC_u32,
      0xA7F2_u32..0xA7FF_u32,
      0xAB30_u32..0xAB5A_u32,
      0xAB5C_u32..0xAB64_u32,
      0xAB66_u32..0xAB69_u32,
      0xFB00_u32..0xFB06_u32,
      0xFF21_u32..0xFF3A_u32,
      0xFF41_u32..0xFF5A_u32,
      0x10780_u32..0x10785_u32,
      0x10787_u32..0x107B0_u32,
      0x107B2_u32..0x107BA_u32,
      0x1DF00_u32..0x1DF1E_u32,
      0x1DF25_u32..0x1DF2A_u32,
    ]
  end

  private def self.han_ranges : Array(Range(UInt32, UInt32))
    [
      0x2E80_u32..0x2E99_u32,
      0x2E9B_u32..0x2EF3_u32,
      0x2F00_u32..0x2FD5_u32,
      0x3005_u32..0x3005_u32,
      0x3007_u32..0x3007_u32,
      0x3021_u32..0x3029_u32,
      0x3038_u32..0x303B_u32,
      0x3400_u32..0x4DBF_u32,
      0x4E00_u32..0x9FFF_u32,
      0xF900_u32..0xFA6D_u32,
      0xFA70_u32..0xFAD9_u32,
      0x16FE2_u32..0x16FE3_u32,
      0x16FF0_u32..0x16FF1_u32,
      0x20000_u32..0x2A6DF_u32,
      0x2A700_u32..0x2B739_u32,
      0x2B740_u32..0x2B81D_u32,
      0x2B820_u32..0x2CEA1_u32,
      0x2CEB0_u32..0x2EBE0_u32,
      0x2EBF0_u32..0x2EE5D_u32,
      0x2F800_u32..0x2FA1D_u32,
      0x30000_u32..0x3134A_u32,
      0x31350_u32..0x323AF_u32,
    ]
  end

  private def self.whitespace_ranges : Array(Range(UInt32, UInt32))
    [
      0x0009_u32..0x000D_u32, # \t, \n, \v, \f, \r
      0x0020_u32..0x0020_u32, # space
      0x0085_u32..0x0085_u32, # NEL
      0x00A0_u32..0x00A0_u32, # NBSP
      0x1680_u32..0x1680_u32, # Ogham space mark
      0x2000_u32..0x200A_u32, # en quad..hair space
      0x2028_u32..0x2029_u32, # line/paragraph separator
      0x202F_u32..0x202F_u32, # narrow NBSP
      0x205F_u32..0x205F_u32, # medium mathematical space
      0x3000_u32..0x3000_u32, # ideographic space
    ]
  end
end
