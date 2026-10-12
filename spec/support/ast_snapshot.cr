module AstParitySnapshot
  extend self
  alias A = Regex::Syntax::AST

  def span(value : A::Span) : String
    "#{value.start.offset},#{value.start.line},#{value.start.column},#{value.end.offset},#{value.end.line},#{value.end.column}"
  end

  def flags(value : A::Flags) : String
    "#{span(value.span)};#{value.items.map { |item| "#{span(item.span)}:#{item.negation? ? "Negation" : "Flag(#{item.flag_enum})"}" }.join(';')}"
  end

  def literal(value : A::Literal) : String
    kind = case value.kind
           when .verbatim? then "Verbatim"
           when .octal?    then "Octal"
           when .hex?, .unicode?
             "Hex#{value.form.try(&.brace?) ? "Brace" : "Fixed"}(#{value.hex_kind})"
           else
             if special = value.special_kind
               "Special(#{special})"
             else
               value.c.try { |char| Regex::Syntax.meta_character?(char) } ? "Meta" : "Superfluous"
             end
           end
    "lit(#{span(value.span)};#{kind};#{value.c.try(&.ord)})"
  end

  def unicode(value : A::ClassUnicode) : String
    kind = value.kind
    detail = case kind.kind
             when .one_letter? then "letter:#{kind.value.try(&.ord)}"
             when .named?      then "named:#{kind.name.try(&.to_slice.hexstring)}"
             else                   "value:#{kind.op}:#{kind.property_name.try(&.to_slice.hexstring)}:#{kind.property_value.try(&.to_slice.hexstring)}"
             end
    "unicode(#{span(value.span)};#{value.negated?};#{detail})"
  end

  def perl(value : A::ClassPerl) : String
    kind = value.kind.digit? ? "Digit" : value.kind.space? ? "Space" : "Word"
    "perl(#{span(value.span)};#{kind};#{value.kind.negated?})"
  end

  def set(value : A::ClassSet) : String
    if item = value.item
      shape(item)
    elsif binary = value.binary_op
      "binary(#{span(binary.span)};#{binary.kind};#{set(binary.lhs)};#{set(binary.rhs)})"
    else
      raise "Invalid class set"
    end
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def shape(value : A::Node) : String
    case value
    when A::Ast     then shape(value.root)
    when A::Empty   then "empty(#{span(value.span)})"
    when A::Dot     then "dot(#{span(value.span)})"
    when A::Literal then literal(value)
    when A::Assertion
      kind = case value.kind
             when .start?             then "StartLine"
             when .end?               then "EndLine"
             when .non_word_boundary? then "NotWordBoundary"
             else                          value.kind.to_s
             end
      "assert(#{span(value.span)};#{kind})"
    when A::SetFlags       then "flags(#{span(value.span)};#{flags(value.flags)})"
    when A::ClassUnicode   then unicode(value)
    when A::ClassPerl      then perl(value)
    when A::ClassAscii     then "ascii(#{span(value.span)};#{value.kind};#{value.negated?})"
    when A::ClassBracketed then "bracket(#{span(value.span)};#{value.negated?};#{set(value.kind)})"
    when A::ClassSetItem
      if item_node = value.item
        shape(item_node)
      else
        "empty(#{span(value.span)})"
      end
    when A::ClassSetUnion then "union(#{span(value.span)};#{value.items.map { |item| shape(item) }.join(';')})"
    when A::ClassSetRange then "range(#{span(value.span)};#{literal(value.start)};#{literal(value.end)})"
    when A::Repetition
      kind = value.op.kind.to_s
      if range = value.op.range
        detail = range.kind.bounded? ? "#{range.start}, #{range.end}" : range.start.to_s
        kind = "Range(#{range.kind}(#{detail}))"
      end
      "rep(#{span(value.span)};#{span(value.op.span || value.span)};#{kind};#{value.greedy?};#{shape(value.child)})"
    when A::Group
      kind = if name = value.capture_name
               "name:#{value.starts_with_p?}:#{span(name.span)}:#{name.name.to_slice.hexstring}:#{name.index}"
             elsif value.capturing?
               "index:#{value.capture_index}"
             elsif flags = value.flags
               "flags:#{self.flags(flags)}"
             else
               raise "Invalid group"
             end
      "group(#{span(value.span)};#{kind};#{shape(value.child)})"
    when A::Concat      then "concat(#{span(value.span)};#{value.children.map { |child| shape(child) }.join(';')})"
    when A::Alternation then "alt(#{span(value.span)};#{value.children.map { |child| shape(child) }.join(';')})"
    else                     raise "Unexpected AST node #{value.class}"
    end
  end

  # ameba:enable Metrics/CyclomaticComplexity

  def snapshot(value : A::WithComments) : String
    "#{shape(value.ast)}\n#{value.comments.map { |comment| "#{span(comment.span)}:#{comment.comment.to_slice.hexstring}" }.join(';')}"
  end
end
