# Unicode property tables automatically generated from Unicode Character Database
# via Rust regex-syntax Unicode tables

require "./unicode_tables/script"
require "./unicode_tables/general_category"
require "./unicode_tables/property_bool"

module Regex::Syntax::UnicodeTables
  # Combined lookup table for all property types
  PROPERTY_TABLES = {
    "script"          => Script::BY_NAME,
    "generalcategory" => GeneralCategory::BY_NAME,
    "propertybool"    => PropertyBool::BY_NAME,
  }

  # Look up Unicode property ranges by normalized property name
  def self.lookup_property_ranges(normalized_name : String) : Array(Range(UInt32, UInt32))?
    # Try each table in order
    PROPERTY_TABLES.each_value do |table|
      if ranges = table[normalized_name]?
        return ranges
      end
    end
    nil
  end

  # Get all available property names (for debugging/inspection)
  def self.property_names : Array(String)
    names = [] of String
    PROPERTY_TABLES.each_value do |table|
      names.concat(table.keys)
    end
    names.uniq.sort!
  end
end
