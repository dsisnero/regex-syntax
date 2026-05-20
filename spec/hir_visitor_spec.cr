require "./spec_helper"

private class HirVisitRecorder
  include Regex::Syntax::Hir::Visitor

  getter events = [] of String

  def start : Nil
    @events << "start"
  end

  def finish : Array(String)
    @events << "finish"
    @events
  end

  def visit_pre(hir : Regex::Syntax::Hir::Hir) : Nil
    @events << "pre:#{hir.node.class.name.split("::").last}"
  end

  def visit_post(hir : Regex::Syntax::Hir::Hir) : Nil
    @events << "post:#{hir.node.class.name.split("::").last}"
  end

  def visit_alternation_in : Nil
    @events << "alt:in"
  end

  def visit_concat_in : Nil
    @events << "concat:in"
  end
end

private class HirFailingVisitor
  include Regex::Syntax::Hir::Visitor

  getter events = [] of String

  def start : Nil
    @events << "start"
  end

  def finish : Array(String)
    @events << "finish"
    @events
  end

  def visit_pre(hir : Regex::Syntax::Hir::Hir) : Nil
    kind = hir.node.class.name.split("::").last
    @events << "pre:#{kind}"
    raise "boom" if kind == "Alternation"
  end
end

describe Regex::Syntax::Hir do
  it "visits HIR nodes in depth-first order" do
    hir = Regex::Syntax.parse("a(b|c)d")
    events = Regex::Syntax::Hir.visit(hir, HirVisitRecorder.new)

    events.should eq([
      "start",
      "pre:Concat",
      "pre:Literal",
      "post:Literal",
      "concat:in",
      "pre:Capture",
      "pre:Alternation",
      "pre:Literal",
      "post:Literal",
      "alt:in",
      "pre:Literal",
      "post:Literal",
      "post:Alternation",
      "post:Capture",
      "concat:in",
      "pre:Literal",
      "post:Literal",
      "post:Concat",
      "finish",
    ])
  end

  it "visits repetitions without recursion" do
    hir = Regex::Syntax.parse("(ab)+")
    events = Regex::Syntax::Hir.visit(hir, HirVisitRecorder.new)

    events.should eq([
      "start",
      "pre:Repetition",
      "pre:Capture",
      "pre:Literal",
      "post:Literal",
      "post:Capture",
      "post:Repetition",
      "finish",
    ])
  end

  it "stops traversal when a visitor raises" do
    hir = Regex::Syntax.parse("a(b|c)d")
    visitor = HirFailingVisitor.new

    expect_raises(Exception, "boom") do
      Regex::Syntax::Hir.visit(hir, visitor)
    end

    visitor.events.should eq([
      "start",
      "pre:Concat",
      "pre:Literal",
      "pre:Capture",
      "pre:Alternation",
    ])
  end
end
