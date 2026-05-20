module Regex::Syntax::Hir
  module Visitor
    def start : Nil
    end

    def finish
      nil
    end

    def visit_pre(_hir : Hir) : Nil
    end

    def visit_post(_hir : Hir) : Nil
    end

    def visit_alternation_in : Nil
    end

    def visit_concat_in : Nil
    end
  end

  def self.visit(hir : Hir, visitor)
    HeapVisitor.new.visit(hir, visitor)
  end

  private abstract class VisitorFrame
    abstract def child : Node
    abstract def advance : VisitorFrame?
  end

  private class RepetitionFrame < VisitorFrame
    def initialize(@rep : Repetition)
    end

    def child : Node
      @rep.sub
    end

    def advance : VisitorFrame?
      nil
    end
  end

  private class CaptureFrame < VisitorFrame
    def initialize(@capture : Capture)
    end

    def child : Node
      @capture.sub
    end

    def advance : VisitorFrame?
      nil
    end
  end

  private class ConcatFrame < VisitorFrame
    def initialize(@children : Array(Node), @index : Int32 = 0)
    end

    def child : Node
      @children[@index]
    end

    def advance : VisitorFrame?
      next_index = @index + 1
      return nil if next_index >= @children.size

      ConcatFrame.new(@children, next_index)
    end
  end

  private class AlternationFrame < VisitorFrame
    def initialize(@children : Array(Node), @index : Int32 = 0)
    end

    def child : Node
      @children[@index]
    end

    def advance : VisitorFrame?
      next_index = @index + 1
      return nil if next_index >= @children.size

      AlternationFrame.new(@children, next_index)
    end
  end

  private class HeapVisitor
    def initialize
      @stack = [] of Tuple(Node, VisitorFrame)
    end

    def visit(hir : Hir, visitor)
      @stack.clear
      visitor.start
      node = hir.node

      loop do
        visitor.visit_pre(Hir.new(node))
        if frame = induct(node)
          @stack << {node, frame}
          node = frame.child
          next
        end

        visitor.visit_post(Hir.new(node))

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

          visitor.visit_post(Hir.new(post_node))
        end
      end
    end

    private def induct(node : Node) : VisitorFrame?
      case node
      when Repetition
        RepetitionFrame.new(node)
      when Capture
        CaptureFrame.new(node)
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
  end
end
