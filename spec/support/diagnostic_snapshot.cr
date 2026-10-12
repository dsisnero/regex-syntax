module DiagnosticSnapshot
  extend self
  alias A = Regex::Syntax::AST
  alias H = Regex::Syntax::Hir

  def ast_parser(config : String) : Regex::Syntax::AstParser
    limit, octal, empty_min, whitespace = config.split(',')
    Regex::Syntax::AstParser.new(nest_limit: limit.to_i, octal: octal == "true",
      empty_min_range: empty_min == "true", ignore_whitespace: whitespace == "true")
  end

  def hir_parser(config : String) : Regex::Syntax::Parser
    utf8, terminator, ignore_case, multi_line, dot_all, swap, unicode, crlf = config.split(',')
    Regex::Syntax::Parser.new(octal: true, utf8: utf8 == "true", line_terminator: terminator.to_u8,
      ignore_case: ignore_case == "true", multi_line: multi_line == "true",
      dot_matches_new_line: dot_all == "true", swap_greed: swap == "true",
      unicode: unicode == "true", crlf: crlf == "true")
  end

  def span(value : A::Span) : String
    "#{value.start.offset},#{value.start.line},#{value.start.column},#{value.end.offset},#{value.end.line},#{value.end.column}"
  end

  def diagnostic(config : String, input : String, domain : String) : String
    if domain == "ast_error"
      ast_parser(config).parse(input)
    else
      hir_parser(config).parse(input)
    end
    raise "Expected error for #{input.inspect}"
  rescue error : A::Error
    auxiliary = error.auxiliary_span.try { |value| span(value) } || "-"
    "#{A::ErrorKind.names[error.kind.value]}\n#{span(error.span)}\n#{auxiliary}\n#{error.kind_message}\n#{error}"
  rescue error : H::Error
    "#{H::ErrorKind.names[error.kind.value]}\n#{span(error.span)}\n-\n#{error.kind}\n#{error}"
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def tree(tokens : Array(String)) : H::Node
    parts = tokens.shift.split(':')
    case parts[0]
    when "empty" then H::Empty.new
    when "lit"   then H::Literal.new(parts[1].hexbytes)
    when "look"  then H::Look.new((H::Look::Kind.from_repr(parts[1].to_u32) || raise "Unknown look kind"))
    when "unicode"
      H::UnicodeClass.new(false, parts[1].split(',', remove_empty: true).map do |range|
        first, last = range.split('-')
        first.to_u32..last.to_u32
      end)
    when "bytes"
      H::CharClass.new(false, parts[1].split(',', remove_empty: true).map do |range|
        first, last = range.split('-')
        first.to_u8..last.to_u8
      end)
    when "cap"
      H::Capture.new(tree(tokens), parts[1].to_i, parts[2] == "-" ? nil : String.new(parts[2].hexbytes))
    when "rep"
      H::Repetition.new(tree(tokens), parts[1].to_u32, parts[2] == "-" ? nil : parts[2].to_u32, parts[3] == "true")
    when "cat", "alt"
      children = Array(H::Node).new(parts[1].to_i) { tree(tokens) }
      parts[0] == "cat" ? H::Concat.new(children) : H::Alternation.new(children)
    else
      raise "Unknown HIR recipe #{parts}"
    end
  end

  # ameba:enable Metrics/CyclomaticComplexity

  def visit(domain : String, config : String, input : String) : String
    if domain == "ast_visit"
      visitor = AstTrace.new(config.to_i)
      trace_result(visitor) { A.visit(Regex::Syntax::AstParser.new.parse(input), visitor) }
    else
      visitor = HirTrace.new(config.to_i)
      trace_result(visitor) { H.visit(Regex::Syntax::Parser.new(utf8: false).parse(input), visitor) }
    end
  end

  def trace_result(visitor, &) : String
    status = "ok"
    begin
      yield
    rescue TraceError
      status = "error"
    end
    "#{status}\n#{visitor.events.join('\n')}"
  end

  def result(domain : String, config : String, input : String) : String
    case domain
    when "ast_error", "hir_error"   then diagnostic(config, input, domain)
    when "ast_print"                then Regex::Syntax::AstParser.new(octal: true).parse(input).to_s
    when "hir_print"                then Regex::Syntax::Parser.new(octal: true, utf8: false).parse(input).to_s
    when "hir_tree"                 then H::Hir.new(tree(input.split(';'))).to_s
    when "ast_visit", "hir_visit"   then visit(domain, config, input)
    when "format"                   then format_error(config, input)
    when "ast_deep", "hir_deep"     then deep(domain, input.to_i)
    when "ast_kind", "hir_kind"     then kind_message(domain, input)
    when "ast_writer", "hir_writer" then writer(domain, config, input)
    else                                 raise "Unknown case #{domain}"
    end
  end

  def kind_message(domain : String, input : String) : String
    domain == "ast_kind" ? A::ErrorKind.parse(input).to_s : H::ErrorKind.parse(input).to_s
  end

  def fixture_span(value : String) : A::Span
    values = value.split(',').map(&.to_i)
    A::Span.new(A::Position.new(values[0], values[1], values[2]),
      A::Position.new(values[3], values[4], values[5]))
  end

  def format_error(config : String, input : String) : String
    primary, auxiliary = config.split(';')
    secondary = auxiliary == "-" ? nil : fixture_span(auxiliary)
    kind = secondary ? A::ErrorKind::FlagDuplicate : A::ErrorKind::ClassUnclosed
    A::Error.new(kind, input, fixture_span(primary), secondary).to_s
  end

  def deep(domain : String, count : Int32) : String
    if domain == "ast_deep"
      node = A::Literal.new(A::Span.new(0, 0), A::Literal::Kind::Verbatim, 'a').as(A::Node)
      count.times { node = A::Group.new(A::Span.new(0, 0), A::Group::Kind::Capture, node, 1) }
      ast = A::Ast.new(node)
      visitor = AstTrace.new(0)
      A.visit(ast, visitor)
      "#{ast}\n#{visitor.events.size}"
    else
      node = H::Literal.new(Bytes[97]).as(H::Node)
      count.times { node = H::Capture.new(node, 1) }
      hir = H::Hir.new(node)
      visitor = HirTrace.new(0)
      H.visit(hir, visitor)
      "#{hir}\n#{visitor.events.size}"
    end
  end

  def writer(domain : String, config : String, input : String) : String
    io = LimitedWriter.new(config.to_i)
    status = "ok"
    begin
      if domain == "ast_writer"
        A::Printer.new.print(Regex::Syntax::AstParser.new.parse(input), io)
      else
        H::Printer.new.print(Regex::Syntax::Parser.new(utf8: false).parse(input), io)
      end
    rescue IO::Error
      status = "error"
    end
    "#{status}\n#{io.bytes.map(&.to_s(16).rjust(2, '0')).join}"
  end

  class LimitedWriter < IO
    getter bytes = [] of UInt8

    def initialize(@remaining : Int32)
    end

    def read(slice : Bytes) : Int32
      raise IO::Error.new("write only")
    end

    def write(slice : Bytes) : Nil
      count = {slice.size, @remaining}.min
      @bytes.concat(slice[0, count].to_a)
      @remaining -= count
      raise IO::Error.new("full") if count < slice.size
    end
  end

  class TraceError < Exception
  end

  abstract class Trace
    getter events = [] of String

    def initialize(@fail : Int32)
    end

    def event(value : String) : Nil
      @events << value
      raise TraceError.new if @events.size == @fail
    end
  end

  class AstTrace < Trace
    include A::Visitor

    def start : Nil
      @events << "start"
    end

    def finish : Nil
      event("finish")
    end

    def visit_pre(node : A::Node) : Nil
      event("pre:#{node.class.name.split("::").last}")
    end

    def visit_post(node : A::Node) : Nil
      event("post:#{node.class.name.split("::").last}")
    end

    def visit_alternation_in : Nil
      event("alt:in")
    end

    def visit_concat_in : Nil
      event("concat:in")
    end

    def visit_class_set_item_pre(node : A::ClassSetItem) : Nil
      event("item-pre:#{node.kind}")
    end

    def visit_class_set_item_post(node : A::ClassSetItem) : Nil
      event("item-post:#{node.kind}")
    end

    def visit_class_set_binary_op_pre(node : A::ClassSetBinaryOp) : Nil
      event("op-pre:#{node.kind}")
    end

    def visit_class_set_binary_op_post(node : A::ClassSetBinaryOp) : Nil
      event("op-post:#{node.kind}")
    end

    def visit_class_set_binary_op_in(node : A::ClassSetBinaryOp) : Nil
      event("op-in:#{node.kind}")
    end
  end

  class HirTrace < Trace
    include H::Visitor

    def start : Nil
      @events << "start"
    end

    def finish : Nil
      event("finish")
    end

    def visit_pre(hir : H::Hir) : Nil
      event("pre:#{hir.node.class.name.split("::").last}")
    end

    def visit_post(hir : H::Hir) : Nil
      event("post:#{hir.node.class.name.split("::").last}")
    end

    def visit_alternation_in : Nil
      event("alt:in")
    end

    def visit_concat_in : Nil
      event("concat:in")
    end
  end
end
