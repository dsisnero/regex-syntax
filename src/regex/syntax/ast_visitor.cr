module Regex::Syntax::AST
  module Visitor
    def start : Nil
    end

    def finish
      nil
    end

    def visit_pre(_node : Node) : Nil
    end

    def visit_post(_node : Node) : Nil
    end

    def visit_alternation_in : Nil
    end

    def visit_concat_in : Nil
    end

    def visit_class_set_item_pre(_node : ClassSetItem) : Nil
    end

    def visit_class_set_item_post(_node : ClassSetItem) : Nil
    end

    def visit_class_set_binary_op_pre(_node : ClassSetBinaryOp) : Nil
    end

    def visit_class_set_binary_op_post(_node : ClassSetBinaryOp) : Nil
    end

    def visit_class_set_binary_op_in(_node : ClassSetBinaryOp) : Nil
    end
  end

  def self.visit(ast : Ast, visitor)
    HeapVisitor.new.visit(ast, visitor)
  end

  private abstract class ExprFrame
    abstract def child : Node
    abstract def advance : ExprFrame?
  end

  private class RepetitionFrame < ExprFrame
    def initialize(@child_node : Node)
    end

    def child : Node
      @child_node
    end

    def advance : ExprFrame?
      nil
    end
  end

  private class GroupFrame < ExprFrame
    def initialize(@child_node : Node)
    end

    def child : Node
      @child_node
    end

    def advance : ExprFrame?
      nil
    end
  end

  private class ConcatFrame < ExprFrame
    def initialize(@children : Array(Node), @index : Int32 = 0)
    end

    def child : Node
      @children[@index]
    end

    def advance : ExprFrame?
      next_index = @index + 1
      return nil if next_index >= @children.size

      ConcatFrame.new(@children, next_index)
    end
  end

  private class AlternationFrame < ExprFrame
    def initialize(@children : Array(Node), @index : Int32 = 0)
    end

    def child : Node
      @children[@index]
    end

    def advance : ExprFrame?
      next_index = @index + 1
      return nil if next_index >= @children.size

      AlternationFrame.new(@children, next_index)
    end
  end

  private alias ClassInduct = ClassSetItem | ClassSetBinaryOp

  private abstract class ClassFrame
    abstract def child : ClassInduct
    abstract def advance : ClassFrame?
  end

  private class UnionClassFrame < ClassFrame
    def initialize(@items : Array(ClassSetItem), @index : Int32 = 0)
    end

    def child : ClassInduct
      @items[@index]
    end

    def advance : ClassFrame?
      next_index = @index + 1
      return nil if next_index >= @items.size

      UnionClassFrame.new(@items, next_index)
    end
  end

  private class BinaryClassFrame < ClassFrame
    getter op : ClassSetBinaryOp

    def initialize(@op : ClassSetBinaryOp)
    end

    def child : ClassInduct
      @op
    end

    def advance : ClassFrame?
      nil
    end
  end

  private class BinaryLHSClassFrame < ClassFrame
    getter op : ClassSetBinaryOp

    def initialize(@op : ClassSetBinaryOp)
    end

    def child : ClassInduct
      AST.class_induct_from_set(@op.lhs)
    end

    def advance : ClassFrame?
      BinaryRHSClassFrame.new(@op)
    end
  end

  private class BinaryRHSClassFrame < ClassFrame
    getter op : ClassSetBinaryOp

    def initialize(@op : ClassSetBinaryOp)
    end

    def child : ClassInduct
      AST.class_induct_from_set(@op.rhs)
    end

    def advance : ClassFrame?
      nil
    end
  end

  def self.class_induct_from_set(set : ClassSet) : ClassInduct
    case set.kind
    when ClassSet::Kind::Item
      set.item.as(ClassSetItem)
    when ClassSet::Kind::BinaryOp
      set.binary_op.as(ClassSetBinaryOp)
    else
      raise "unreachable class set kind: #{set.kind}"
    end
  end

  private class HeapVisitor
    def initialize
      @stack = [] of Tuple(Node, ExprFrame)
      @class_stack = [] of Tuple(ClassInduct, ClassFrame)
    end

    def visit(ast : Ast, visitor)
      @stack.clear
      @class_stack.clear

      visitor.start
      node = ast.root

      loop do
        visitor.visit_pre(node)
        if frame = induct(node, visitor)
          @stack << {node, frame}
          node = frame.child
          next
        end

        visitor.visit_post(node)

        loop do
          popped = @stack.pop?
          return visitor.finish unless popped

          post_node, frame = popped
          if next_frame = frame.advance
            case next_frame
            when AlternationFrame
              visitor.visit_alternation_in
            when ConcatFrame
              visitor.visit_concat_in
            end
            node = next_frame.child
            @stack << {post_node, next_frame}
            break
          end

          visitor.visit_post(post_node)
        end
      end
    end

    private def induct(node : Node, visitor) : ExprFrame?
      case node
      when ClassBracketed
        visit_class(node, visitor)
        nil
      when Repetition
        RepetitionFrame.new(node.child)
      when Group
        GroupFrame.new(node.child)
      when Concat
        return nil if node.children.empty?
        ConcatFrame.new(node.children)
      when Alternation
        return nil if node.children.empty?
        AlternationFrame.new(node.children)
      else
        nil
      end
    end

    private def visit_class(node : ClassBracketed, visitor) : Nil
      induct = AST.class_induct_from_set(node.kind)

      loop do
        visit_class_pre(induct, visitor)
        if frame = induct_class(induct)
          @class_stack << {induct, frame}
          induct = frame.child
          next
        end

        visit_class_post(induct, visitor)

        loop do
          popped = @class_stack.pop?
          return unless popped

          post_induct, frame = popped
          if next_frame = frame.advance
            if next_frame.is_a?(BinaryRHSClassFrame)
              visitor.visit_class_set_binary_op_in(next_frame.op)
            end
            induct = next_frame.child
            @class_stack << {post_induct, next_frame}
            break
          end

          visit_class_post(post_induct, visitor)
        end
      end
    end

    private def visit_class_pre(induct : ClassInduct, visitor) : Nil
      case induct
      when ClassSetItem
        visitor.visit_class_set_item_pre(induct)
      when ClassSetBinaryOp
        visitor.visit_class_set_binary_op_pre(induct)
      end
    end

    private def visit_class_post(induct : ClassInduct, visitor) : Nil
      case induct
      when ClassSetItem
        visitor.visit_class_set_item_post(induct)
      when ClassSetBinaryOp
        visitor.visit_class_set_binary_op_post(induct)
      end
    end

    private def induct_class(induct : ClassInduct) : ClassFrame?
      case induct
      when ClassSetItem
        case induct.kind
        when ClassSetItem::Kind::Bracketed
          bracketed = induct.item.as(ClassBracketed)
          class_frame_from_set(bracketed.kind)
        when ClassSetItem::Kind::Union
          union = induct.item.as(ClassSetUnion)
          return nil if union.items.empty?
          UnionClassFrame.new(union.items)
        else
          nil
        end
      when ClassSetBinaryOp
        BinaryLHSClassFrame.new(induct)
      end
    end

    private def class_frame_from_set(set : ClassSet) : ClassFrame?
      case set.kind
      when ClassSet::Kind::Item
        if item = set.item
          UnionClassFrame.new([item])
        else
          nil
        end
      when ClassSet::Kind::BinaryOp
        if binary_op = set.binary_op
          BinaryClassFrame.new(binary_op)
        else
          nil
        end
      end
    end
  end
end
