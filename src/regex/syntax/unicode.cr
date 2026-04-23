require "./hir"
require "./unicode_tables"

module Regex::Syntax::Unicode
  AGE_ORDER = [
    {"V1_1", UnicodeTables::Age::V1_1},
    {"V2_0", UnicodeTables::Age::V2_0},
    {"V2_1", UnicodeTables::Age::V2_1},
    {"V3_0", UnicodeTables::Age::V3_0},
    {"V3_1", UnicodeTables::Age::V3_1},
    {"V3_2", UnicodeTables::Age::V3_2},
    {"V4_0", UnicodeTables::Age::V4_0},
    {"V4_1", UnicodeTables::Age::V4_1},
    {"V5_0", UnicodeTables::Age::V5_0},
    {"V5_1", UnicodeTables::Age::V5_1},
    {"V5_2", UnicodeTables::Age::V5_2},
    {"V6_0", UnicodeTables::Age::V6_0},
    {"V6_1", UnicodeTables::Age::V6_1},
    {"V6_2", UnicodeTables::Age::V6_2},
    {"V6_3", UnicodeTables::Age::V6_3},
    {"V7_0", UnicodeTables::Age::V7_0},
    {"V8_0", UnicodeTables::Age::V8_0},
    {"V9_0", UnicodeTables::Age::V9_0},
    {"V10_0", UnicodeTables::Age::V10_0},
    {"V11_0", UnicodeTables::Age::V11_0},
    {"V12_0", UnicodeTables::Age::V12_0},
    {"V12_1", UnicodeTables::Age::V12_1},
    {"V13_0", UnicodeTables::Age::V13_0},
    {"V14_0", UnicodeTables::Age::V14_0},
    {"V15_0", UnicodeTables::Age::V15_0},
    {"V15_1", UnicodeTables::Age::V15_1},
    {"V16_0", UnicodeTables::Age::V16_0},
  ]

  def self.property_class(name : String, negated : Bool) : Hir::UnicodeClass
    if index = name.index("!=")
      property_name = name[...index]
      property_value = name[(index + 2)..]
      return query_property_class(property_name, property_value, negated: !negated)
    end

    if index = name.index(':')
      property_name = name[...index]
      property_value = name[(index + 1)..]
      return query_property_class(property_name, property_value, negated: negated)
    end

    if index = name.index('=')
      property_name = name[...index]
      property_value = name[(index + 1)..]
      return query_property_class(property_name, property_value, negated: negated)
    end

    Hir::UnicodeClass.new(negated, binary_property_ranges(name))
  end

  private def self.query_property_class(property_name : String, property_value : String, negated : Bool) : Hir::UnicodeClass
    canonical_property_name = canonical_property_name(property_name) || raise ParseError.new("invalid Unicode property: #{property_name}")
    ranges = query_property_ranges(canonical_property_name, property_name, property_value)
    Hir::UnicodeClass.new(negated, ranges)
  end

  private def self.query_property_ranges(canonical_property_name : String, property_name : String, property_value : String) : Array(Range(UInt32, UInt32))
    canonical_value = query_property_value(canonical_property_name, property_value)

    case canonical_property_name
    when "General_Category"
      general_category_ranges(canonical_value)
    when "Script"
      script_ranges(canonical_value)
    when "Age"
      age_ranges(canonical_value)
    when "Script_Extensions"
      script_extension_ranges(canonical_value)
    when "Grapheme_Cluster_Break"
      grapheme_cluster_break_ranges(canonical_value)
    when "Word_Break"
      word_break_ranges(canonical_value)
    when "Sentence_Break"
      sentence_break_ranges(canonical_value)
    else
      raise ParseError.new("invalid Unicode property: #{property_name}")
    end
  end

  private def self.binary_property_ranges(name : String) : Array(Range(UInt32, UInt32))
    normalized = normalize_symbolic_name(name)

    if ranges = UnicodeTables.lookup_property_ranges(normalized)
      return ranges
    end

    unless {"cf", "sc", "lc"}.includes?(normalized)
      if canonical_name = canonical_property_name_from_normalized(normalized)
        return property_ranges_for_canonical_binary(canonical_name) || raise ParseError.new("invalid Unicode property: #{name}")
      end
    end

    if canonical_name = canonical_general_category_from_normalized(normalized)
      return general_category_ranges(canonical_name)
    end

    if canonical_name = canonical_script_from_normalized(normalized)
      return script_ranges(canonical_name)
    end

    raise ParseError.new("invalid Unicode property: #{name}")
  end

  private def self.property_ranges_for_canonical_binary(canonical_name : String) : Array(Range(UInt32, UInt32))?
    UnicodeTables.lookup_property_ranges(normalize_symbolic_name(canonical_name))
  end

  private def self.canonical_property_name(name : String) : String?
    canonical_property_name_from_normalized(normalize_symbolic_name(name))
  end

  private def self.canonical_property_name_from_normalized(normalized_name : String) : String?
    UnicodeTables::PropertyNames::BY_NAME[normalized_name]?
  end

  private def self.canonical_property_value(canonical_property_name : String, value : String) : String?
    canonical_property_value_from_normalized(canonical_property_name, normalize_symbolic_name(value))
  end

  private def self.canonical_property_value_from_normalized(canonical_property_name : String, normalized_value : String) : String?
    UnicodeTables::PropertyValues::BY_PROPERTY[canonical_property_name]?.try(&.[normalized_value]?)
  end

  private def self.canonical_general_category(value : String) : String?
    canonical_general_category_from_normalized(normalize_symbolic_name(value))
  end

  private def self.canonical_general_category_from_normalized(normalized_value : String) : String?
    case normalized_value
    when "any"
      "Any"
    when "assigned"
      "Assigned"
    when "ascii"
      "ASCII"
    else
      canonical_property_value_from_normalized("General_Category", normalized_value)
    end
  end

  private def self.canonical_script(value : String) : String?
    canonical_script_from_normalized(normalize_symbolic_name(value))
  end

  private def self.canonical_script_from_normalized(normalized_value : String) : String?
    canonical_property_value_from_normalized("Script", normalized_value)
  end

  private def self.query_property_value(canonical_property_name : String, property_value : String) : String
    case canonical_property_name
    when "General_Category"
      canonical_general_category(property_value)
    when "Script"
      canonical_script(property_value)
    else
      canonical_property_value(canonical_property_name, property_value)
    end || raise ParseError.new("invalid Unicode property value: #{property_value}")
  end

  private def self.general_category_ranges(canonical_name : String) : Array(Range(UInt32, UInt32))
    case canonical_name
    when "ASCII"
      [0x0000_u32..0x007F_u32]
    when "Any"
      [0x0000_u32..0x10FFFF_u32]
    when "Assigned"
      invert_intervals(UnicodeTables::GeneralCategory::BY_NAME["unassigned"])
    else
      UnicodeTables::GeneralCategory::BY_NAME[normalize_symbolic_name(canonical_name)]? || raise ParseError.new("invalid Unicode property value: #{canonical_name}")
    end
  end

  private def self.script_ranges(canonical_name : String) : Array(Range(UInt32, UInt32))
    UnicodeTables::Script::BY_NAME[normalize_symbolic_name(canonical_name)]? || raise ParseError.new("invalid Unicode property value: #{canonical_name}")
  end

  private def self.script_extension_ranges(canonical_name : String) : Array(Range(UInt32, UInt32))
    UnicodeTables::ScriptExtension::BY_NAME[normalize_symbolic_name(canonical_name)]? || raise ParseError.new("invalid Unicode property value: #{canonical_name}")
  end

  private def self.age_ranges(canonical_name : String) : Array(Range(UInt32, UInt32))
    intervals = [] of Range(UInt32, UInt32)
    found = false

    AGE_ORDER.each do |version, ranges|
      intervals.concat(ranges)
      if version == canonical_name
        found = true
        break
      end
    end

    raise ParseError.new("invalid Unicode property value: #{canonical_name}") unless found

    canonicalize_intervals(intervals)
  end

  private def self.grapheme_cluster_break_ranges(canonical_name : String) : Array(Range(UInt32, UInt32))
    UnicodeTables::GraphemeClusterBreak::BY_NAME[normalize_symbolic_name(canonical_name)]? || raise ParseError.new("invalid Unicode property value: #{canonical_name}")
  end

  private def self.word_break_ranges(canonical_name : String) : Array(Range(UInt32, UInt32))
    UnicodeTables::WordBreak::BY_NAME[normalize_symbolic_name(canonical_name)]? || raise ParseError.new("invalid Unicode property value: #{canonical_name}")
  end

  private def self.sentence_break_ranges(canonical_name : String) : Array(Range(UInt32, UInt32))
    UnicodeTables::SentenceBreak::BY_NAME[normalize_symbolic_name(canonical_name)]? || raise ParseError.new("invalid Unicode property value: #{canonical_name}")
  end

  private def self.normalize_symbolic_name(name : String) : String
    chars = name.chars
    start = 0
    starts_with_is = false

    if chars.size >= 2
      starts_with_is = ascii_i?(chars[0]) && ascii_s?(chars[1])
      start = 2 if starts_with_is
    end

    normalized = String.build do |io|
      chars.each_with_index do |char, index|
        next if index < start
        next if char == ' ' || char == '_' || char == '-'
        next unless char.ascii?

        io << ascii_lowercase(char)
      end
    end

    starts_with_is && normalized == "c" ? "isc" : normalized
  end

  private def self.ascii_i?(char : Char) : Bool
    char == 'i' || char == 'I'
  end

  private def self.ascii_s?(char : Char) : Bool
    char == 's' || char == 'S'
  end

  private def self.ascii_lowercase(char : Char) : Char
    char >= 'A' && char <= 'Z' ? (char.ord + 32).chr : char
  end

  private def self.invert_intervals(intervals : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
    result = [] of Range(UInt32, UInt32)
    next_start = 0_u32
    canonical = canonicalize_intervals(intervals)

    canonical.each do |range|
      if next_start < range.begin
        result << (next_start..(range.begin - 1).to_u32)
      end
      next_start = range.end == 0x10FFFF_u32 ? 0x10FFFF_u32 : (range.end + 1).to_u32
    end

    if canonical.last.end < 0x10FFFF_u32
      result << (next_start..0x10FFFF_u32)
    end

    result
  end

  private def self.canonicalize_intervals(intervals : Array(Range(UInt32, UInt32))) : Array(Range(UInt32, UInt32))
    return [] of Range(UInt32, UInt32) if intervals.empty?

    sorted = intervals.sort_by(&.begin)
    merged = [] of Range(UInt32, UInt32)
    current = sorted.first

    sorted[1..].each do |range|
      if range.begin <= current.end + 1
        current = current.begin..Math.max(current.end, range.end)
      else
        merged << current
        current = range
      end
    end
    merged << current
    merged
  end
end
