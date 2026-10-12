module HirParitySnapshot
  extend self
  alias H = Regex::Syntax::Hir

  # ameba:disable Metrics/CyclomaticComplexity
  def shape(node : H::Node) : String
    case node
    when H::Empty
      "empty"
    when H::Literal
      "lit(#{node.bytes.hexstring})"
    when H::Look
      "look(#{node.kind.as_repr})"
    when H::UnicodeClass
      intervals = node.negated? ? H::IntervalOps.invert(node.intervals) : node.intervals
      "unicode(#{intervals.map { |range| "#{range.begin}-#{range.end}" }.join(',')})"
    when H::CharClass
      intervals = node.negated? ? H::IntervalOps.invert(node.intervals) : node.intervals
      "bytes(#{intervals.map { |range| "#{range.begin}-#{range.end}" }.join(',')})"
    when H::Capture
      "cap(#{node.index},#{node.name.try(&.to_slice.hexstring) || "-"},#{shape(node.sub)})"
    when H::Repetition
      "rep(#{node.min},#{node.max.try(&.to_s) || "-"},#{node.greedy?},#{shape(node.sub)})"
    when H::Concat
      "cat(#{node.children.map { |child| shape(child) }.join(',')})"
    when H::Alternation
      "alt(#{node.children.map { |child| shape(child) }.join(',')})"
    else
      raise "Unexpected HIR node: #{node.class}"
    end
  end

  # ameba:enable Metrics/CyclomaticComplexity

  def properties(props : H::Properties) : String
    fields = [props.minimum_len.try(&.to_s) || "-", props.maximum_len.try(&.to_s) || "-",
              props.utf8?.to_s, props.explicit_captures_len.to_s,
              props.static_explicit_captures_len.try(&.to_s) || "-", props.literal?.to_s,
              props.alternation_literal?.to_s, props.look_set.bits.to_s,
              props.look_set_prefix.bits.to_s, props.look_set_prefix_any.bits.to_s,
              props.look_set_suffix.bits.to_s, props.look_set_suffix_any.bits.to_s]
    fields.join('|')
  end

  def snapshot(hir : H::Hir) : String
    "#{shape(hir.node)}\n#{hir}\n#{properties(hir.properties)}"
  end
end
