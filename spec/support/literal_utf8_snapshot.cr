module LiteralUtf8Snapshot
  extend self
  alias L = Regex::Syntax::Hir::LiteralExtraction

  def hex(bytes : Array(UInt8)) : String
    bytes.map(&.to_s(16).rjust(2, '0')).join
  end

  def literal(value : String) : L::Literal
    bytes = value[1..].hexbytes.to_a
    value.starts_with?('E') ? L::Literal.exact(bytes) : L::Literal.inexact(bytes)
  end

  def sequence(value : String) : L::Seq
    return L::Seq.infinite if value == "inf"
    return L::Seq.empty if value == "empty"
    L::Seq.new(value.split(',').map { |item| literal(item) })
  end

  def shape(seq : L::Seq) : String
    return "inf" unless literals = seq.literals
    return "empty" if literals.empty?
    literals.map { |lit| "#{lit.exact? ? 'E' : 'I'}#{hex(lit.bytes)}" }.join(',')
  end

  def optional_bytes(bytes : Array(UInt8)?) : String
    bytes ? "x#{hex(bytes)}" : "-"
  end

  def snapshot(seq : L::Seq) : String
    "#{shape(seq)};#{seq.finite?};#{seq.exact?};#{seq.inexact?};#{seq.len || "-"};#{seq.min_literal_len || "-"};#{seq.max_literal_len || "-"};#{optional_bytes(seq.longest_common_prefix)};#{optional_bytes(seq.longest_common_suffix)}"
  end

  def binary(seq : L::Seq, op : String, other : L::Seq) : Nil
    case op
    when "cross_forward"    then seq.cross_forward(other)
    when "cross_reverse"    then seq.cross_reverse(other)
    when "union"            then seq.union(other)
    when "union_into_empty" then seq.union_into_empty(other)
    else                         raise "Unknown binary operation: #{op}"
    end
  end

  def unary(seq : L::Seq, op : String) : Nil
    case op
    when "make_inexact"                      then seq.make_inexact
    when "make_infinite"                     then seq.make_infinite
    when "dedup"                             then seq.dedup
    when "sort"                              then seq.sort
    when "reverse_literals"                  then seq.reverse_literals
    when "minimize_by_preference"            then seq.minimize_by_preference
    when "optimize_for_prefix_by_preference" then seq.optimize_for_prefix_by_preference
    when "optimize_for_suffix_by_preference" then seq.optimize_for_suffix_by_preference
    when "properties"                        then nil
    else                                          raise "Unknown unary operation: #{op}"
    end
  end

  def mutate(op : String, input : String, argument : String) : {String, String}
    seq = sequence(input)
    case op
    when "cross_forward", "cross_reverse", "union", "union_into_empty"
      other = sequence(argument)
      binary(seq, op, other)
      return {snapshot(seq), snapshot(other)}
    when "keep_first_bytes" then seq.keep_first_bytes(argument.to_i)
    when "keep_last_bytes"  then seq.keep_last_bytes(argument.to_i)
    when "push"             then seq.push(literal(argument))
    else                         unary(seq, op)
    end
    {snapshot(seq), "-"}
  end

  def extract(config : String, pattern_hex : String) : String
    kind, klass, repeat, length, total = config.split(',')
    extractor = L::Extractor.new.kind(L::ExtractKind.parse(kind))
      .limit_class(klass.to_i).limit_repeat(repeat.to_i)
      .limit_literal_len(length.to_i).limit_total(total.to_i)
    snapshot(extractor.extract(Regex::Syntax::Parser.new(utf8: false).parse(String.new(pattern_hex.hexbytes))))
  end

  def utf8(start : String, finish : String) : String
    sequences = Regex::Syntax::Utf8::Utf8Sequences.new(start.to_i.chr, finish.to_i.chr).to_a
    return "empty" if sequences.empty?
    sequences.map do |seq|
      seq.as_slice.map { |range| "#{range.start}-#{range.end}" }.join(',')
    end.join(';')
  end

  def primitive(op : String, input : String, argument : String) : String
    lit = literal(input)
    case op
    when "make_inexact"     then lit.make_inexact
    when "reverse"          then lit.reverse
    when "extend"           then lit.extend(literal(argument))
    when "keep_first_bytes" then lit.keep_first_bytes(argument.to_i)
    when "keep_last_bytes"  then lit.keep_last_bytes(argument.to_i)
    when "properties"       then nil
    else                         raise "Unknown literal operation: #{op}"
    end
    "#{lit.exact? ? 'E' : 'I'}#{hex(lit.bytes)};#{lit.len};#{lit.empty?};#{lit.poisonous?}"
  end

  def direct(input : String, negated : String, type : B.class) : String forall B
    ranges = input == "empty" ? [] of Range(B, B) : input.split(',').map do |pair|
      first, last = pair.split('-').map { |bound| B.new(bound.to_u32) }
      first..last
    end
    klass = {% if B == UInt8 %}
              Regex::Syntax::Hir::CharClass.new(negated == "true", ranges)
            {% else %}
              Regex::Syntax::Hir::UnicodeClass.new(negated == "true", ranges)
            {% end %}
    snapshot(L::Extractor.new.extract(klass))
  end

  def reset_utf8(start : String, finish : String) : String
    sequences = Regex::Syntax::Utf8::Utf8Sequences.new('\u{0}', '\u{10FFFF}')
    sequences.next
    sequences.reset(start.to_i.chr, finish.to_i.chr)
    result = sequences.to_a
    return "empty" if result.empty?
    result.map(&.as_slice.map { |range| "#{range.start}-#{range.end}" }.join(',')).join(';')
  end

  def helper(kind : String, op : String, input : String, argument : String) : String
    case kind
    when "literal"    then primitive(op, input, argument)
    when "rank"       then L.rank(input.to_u8).to_s
    when "direct_u"   then direct(input, argument, UInt32)
    when "direct_b"   then direct(input, argument, UInt8)
    when "utf8_reset" then reset_utf8(input, argument)
    else                   raise "Unknown fixture kind: #{kind}"
    end
  end

  def result(kind : String, op : String, input : String, argument : String) : {String, String}
    case kind
    when "extract" then {extract(op, input), "-"}
    when "seq"     then mutate(op, input, argument)
    when "bounds"
      left, right = sequence(input), sequence(argument)
      {"#{left.max_union_len(right) || "-"};#{left.max_cross_len(right) || "-"}", "-"}
    when "utf8" then {utf8(input, argument), "-"}
    else             {helper(kind, op, input, argument), "-"}
    end
  end
end
