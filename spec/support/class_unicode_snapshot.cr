module ClassUnicodeSnapshot
  extend self
  alias H = Regex::Syntax::Hir
  alias U = Regex::Syntax::Unicode
  alias T = Regex::Syntax::UnicodeTables

  TABLES = {
    "age"                    => T::Age::BY_NAME,
    "general_category"       => T::GeneralCategory::BY_NAME,
    "script"                 => T::Script::BY_NAME,
    "script_extension"       => T::ScriptExtension::BY_NAME,
    "property_bool"          => T::PropertyBool::BY_NAME,
    "grapheme_cluster_break" => T::GraphemeClusterBreak::BY_NAME,
    "word_break"             => T::WordBreak::BY_NAME,
    "sentence_break"         => T::SentenceBreak::BY_NAME,
    "perl_word"              => {"perlword" => T::PerlWord::PERL_WORD},
  }

  def expected(kind : String, operation : String, input : String, other : String = "") : String
    prefix = "#{kind}\t#{operation}\t#{input}\t#{other}\t"
    value = File.read_lines("#{__DIR__}/../fixtures/class_unicode.tsv").find!(&.starts_with?(prefix)).split('\t').last
    value == "-" ? "" : value
  end

  def ranges(value : String, type : B.class) : Array(Range(B, B)) forall B
    return [] of Range(B, B) if value.empty?
    value.split(',').map do |pair|
      first, last = pair.split('-').map { |bound| B.new(bound.to_u32) }
      first..last
    end
  end

  def render(intervals) : String
    intervals.map { |range| "#{range.begin}-#{range.end}" }.join(',')
  end

  def properties(klass : H::UnicodeClass) : String
    conversion = klass.to_byte_class.try { |bytes| render(bytes.intervals) } || "none"
    "#{klass.ascii?};#{klass.minimum_len || "-"};#{klass.maximum_len || "-"};#{conversion}"
  end

  def properties(klass : H::CharClass) : String
    conversion = klass.to_unicode_class.try { |unicode| render(unicode.intervals) } || "none"
    "#{klass.ascii?};#{klass.minimum_len || "-"};#{klass.maximum_len || "-"};#{conversion}"
  end

  # The dispatch mirrors the oracle operation names, not its implementation.
  def class_result(klass, other, operation : String) : String
    case operation
    when "new"                  then render(klass.intervals)
    when "case_fold_simple"     then render(klass.case_fold_simple.intervals)
    when "negate"               then render(klass.negate.intervals)
    when "union"                then render(klass.union(other).intervals)
    when "intersect"            then render(klass.intersect(other).intervals)
    when "difference"           then render(klass.difference(other).intervals)
    when "symmetric_difference" then render(klass.symmetric_difference(other).intervals)
    when "properties"           then properties(klass)
    else                             raise "Unknown class operation: #{operation}"
    end
  end

  def state(kind : String, steps : String, input : String) : String
    if kind == "state_b"
      state_result(H::IntervalSet(UInt8).new(ranges(input, UInt8)), steps, UInt8)
    else
      state_result(H::IntervalSet(UInt32).new(ranges(input, UInt32)), steps, UInt32)
    end
  end

  def state_result(set, steps : String, type : B.class) : String forall B
    steps.split(',').each do |step|
      case step
      when "fold"        then set.case_fold_simple!
      when "clone"       then set = set.clone
      when "negate"      then set.negate!
      when "push_same"   then set.push(B.new(65)..B.new(90))
      when "push_subset" then set.push(B.new(65)..B.new(66))
      else                    binary_state(set, step, type)
      end
    end
    "#{render(set.intervals)};#{set.folded?}"
  end

  def binary_state(set, step : String, type : B.class) : Nil forall B
    other = H::IntervalSet(B).new([B.new(66)..B.new(67)]).case_fold_simple!
    case step
    when "union"                then set.union!(other)
    when "intersect"            then set.intersect!(other)
    when "difference"           then set.difference!(other)
    when "symmetric_difference" then set.symmetric_difference!(other)
    else                             raise "Unknown state operation: #{step}"
    end
  end

  def table(name : String, key : String) : String
    normalized = U.normalize_symbolic_name(key)
    render(TABLES[name][normalized])
  end

  def query(name : String, value : String) : String
    query = value.empty? ? U::ClassQuery::Binary.new(name) : U::ClassQuery::ByValue.new(name, value)
    render(U.class(query).intervals)
  rescue error : Regex::Syntax::ParseError
    # Crystal exposes typed parser errors; compare the corresponding Rust category.
    category = error.message.to_s.includes?("property value") ? "PropertyValueNotFound" : "PropertyNotFound"
    "error:#{category}"
  end

  def parsed(pattern : String) : String
    node = Regex::Syntax::Parser.new.parse(pattern).node
    case node
    when H::UnicodeClass then "class:#{render(node.intervals)}"
    when H::Literal      then "literal:#{node.bytes.hexstring}"
    else                      raise "Unexpected parsed property: #{node.class}"
    end
  rescue error : H::Error
    parsed_error("translate", H::ErrorKind.names[error.kind.value], error.span)
  rescue error : Regex::Syntax::AST::Error
    parsed_error("parse", Regex::Syntax::AST::ErrorKind.names[error.kind.value], error.span)
  end

  def parsed_error(stage : String, kind : String, span : Regex::Syntax::AST::Span) : String
    "#{stage}:#{kind};#{span.start.offset};#{span.start.line};#{span.start.column};#{span.end.offset};#{span.end.line};#{span.end.column}"
  end

  def negated_fold(klass) : String
    klass.case_fold_simple
    intervals = klass.negated? ? H::IntervalOps.invert(klass.intervals) : klass.intervals
    render(intervals)
  end

  def unicode_result(operation : String, input : String, other : String) : String
    return negated_fold(H::UnicodeClass.new(true, ranges(input, UInt32))) if operation == "negated_case_fold_simple"
    class_result(H::UnicodeClass.new(false, ranges(input, UInt32)), H::UnicodeClass.new(false, ranges(other, UInt32)), operation)
  end

  def byte_result(operation : String, input : String, other : String) : String
    return negated_fold(H::CharClass.new(true, ranges(input, UInt8))) if operation == "negated_case_fold_simple"
    class_result(H::CharClass.new(false, ranges(input, UInt8)), H::CharClass.new(false, ranges(other, UInt8)), operation)
  end

  def snapshot(kind : String, operation : String, input : String, other : String) : String
    case kind
    when "u"
      unicode_result(operation, input, other)
    when "b"
      byte_result(operation, input, other)
    when "state_u", "state_b"
      state(kind, operation, input)
    when "table"
      table(operation, input)
    when "alias"
      operation == "name" ? T::PropertyNames::BY_NAME[input] : T::PropertyValues::BY_PROPERTY[input][other]
    when "fold"
      U::SimpleCaseFolder.new.mapping(input.to_i.chr).map(&.ord).join(',')
    when "query"
      query(input, other)
    when "parsed"
      parsed(input)
    else
      raise "Unknown fixture kind: #{kind}"
    end
  end
end
