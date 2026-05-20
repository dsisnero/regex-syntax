require "./spec_helper"

private class AstVisitRecorder
  include Regex::Syntax::AST::Visitor

  getter events = [] of String

  def start : Nil
    @events << "start"
  end

  def finish : Array(String)
    @events << "finish"
    @events
  end

  def visit_pre(node : Regex::Syntax::AST::Node) : Nil
    @events << "pre:#{node.class.name.split("::").last}"
  end

  def visit_post(node : Regex::Syntax::AST::Node) : Nil
    @events << "post:#{node.class.name.split("::").last}"
  end

  def visit_alternation_in : Nil
    @events << "alt:in"
  end

  def visit_concat_in : Nil
    @events << "concat:in"
  end

  def visit_class_set_item_pre(node : Regex::Syntax::AST::ClassSetItem) : Nil
    @events << "class-item-pre:#{node.kind}"
  end

  def visit_class_set_item_post(node : Regex::Syntax::AST::ClassSetItem) : Nil
    @events << "class-item-post:#{node.kind}"
  end

  def visit_class_set_binary_op_pre(node : Regex::Syntax::AST::ClassSetBinaryOp) : Nil
    @events << "class-op-pre:#{node.kind}"
  end

  def visit_class_set_binary_op_post(node : Regex::Syntax::AST::ClassSetBinaryOp) : Nil
    @events << "class-op-post:#{node.kind}"
  end

  def visit_class_set_binary_op_in(node : Regex::Syntax::AST::ClassSetBinaryOp) : Nil
    @events << "class-op-in:#{node.kind}"
  end
end

private class AstFailingVisitor
  include Regex::Syntax::AST::Visitor

  getter events = [] of String

  def start : Nil
    @events << "start"
  end

  def finish : Array(String)
    @events << "finish"
    @events
  end

  def visit_pre(node : Regex::Syntax::AST::Node) : Nil
    kind = node.class.name.split("::").last
    @events << "pre:#{kind}"
    raise "boom" if kind == "Alternation"
  end
end

describe Regex::Syntax::AST do
  it "visits AST nodes in depth-first order" do
    ast = Regex::Syntax::AstParser.new.parse("a(b|c)d")
    events = Regex::Syntax::AST.visit(ast, AstVisitRecorder.new)

    events.should eq([
      "start",
      "pre:Concat",
      "pre:Literal",
      "post:Literal",
      "concat:in",
      "pre:Group",
      "pre:Alternation",
      "pre:Literal",
      "post:Literal",
      "alt:in",
      "pre:Literal",
      "post:Literal",
      "post:Alternation",
      "post:Group",
      "concat:in",
      "pre:Literal",
      "post:Literal",
      "post:Concat",
      "finish",
    ])
  end

  it "visits class set items and binary operators in depth-first order" do
    ast = Regex::Syntax::AstParser.new.parse("[a&&[b-c]]")
    events = Regex::Syntax::AST.visit(ast, AstVisitRecorder.new)

    events.should eq([
      "start",
      "pre:ClassBracketed",
      "class-op-pre:Intersection",
      "class-item-pre:Literal",
      "class-item-post:Literal",
      "class-op-in:Intersection",
      "class-item-pre:Bracketed",
      "class-item-pre:Range",
      "class-item-post:Range",
      "class-item-post:Bracketed",
      "class-op-post:Intersection",
      "post:ClassBracketed",
      "finish",
    ])
  end

  it "stops traversal when a visitor raises" do
    ast = Regex::Syntax::AstParser.new.parse("a(b|c)d")
    visitor = AstFailingVisitor.new

    expect_raises(Exception, "boom") do
      Regex::Syntax::AST.visit(ast, visitor)
    end

    visitor.events.should eq([
      "start",
      "pre:Concat",
      "pre:Literal",
      "pre:Group",
      "pre:Alternation",
    ])
  end
end
