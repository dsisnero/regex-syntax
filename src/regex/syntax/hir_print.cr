module Regex::Syntax::Hir
  class Printer
    LOOK_PATTERNS = {
      Look::Kind::StartText            => "\\A",
      Look::Kind::EndText              => "\\z",
      Look::Kind::EndTextOptionalLF    => "\\z",
      Look::Kind::StartLF              => "(?m:^)",
      Look::Kind::EndLF                => "(?m:$)",
      Look::Kind::StartCRLF            => "(?mR:^)",
      Look::Kind::EndCRLF              => "(?mR:$)",
      Look::Kind::WordAscii            => "(?-u:\\b)",
      Look::Kind::WordAsciiNegate      => "(?-u:\\B)",
      Look::Kind::WordUnicode          => "\\b",
      Look::Kind::WordUnicodeNegate    => "\\B",
      Look::Kind::WordStartAscii       => "(?-u:\\b{start})",
      Look::Kind::WordEndAscii         => "(?-u:\\b{end})",
      Look::Kind::WordStartUnicode     => "\\b{start}",
      Look::Kind::WordEndUnicode       => "\\b{end}",
      Look::Kind::WordStartHalfAscii   => "(?-u:\\b{start-half})",
      Look::Kind::WordEndHalfAscii     => "(?-u:\\b{end-half})",
      Look::Kind::WordStartHalfUnicode => "\\b{start-half}",
      Look::Kind::WordEndHalfUnicode   => "\\b{end-half}",
    }

    def self.new : self
      allocate.tap(&.initialize)
    end

    def initialize
    end

    def print(hir : Hir, io : IO) : Nil
      write_node(hir.node, io)
    end

    private def write_node(node : Node, io : IO) : Nil
      raise "unsupported HIR node for printing: #{node.class}"
    end

    private def write_node(node : Empty, io : IO) : Nil
      io << "(?:)"
    end

    private def write_node(node : Literal, io : IO) : Nil
      write_literal(node.bytes, io)
    end

    private def write_node(node : UnicodeClass, io : IO) : Nil
      write_unicode_class(node, io)
    end

    private def write_node(node : CharClass, io : IO) : Nil
      write_byte_class(node, io)
    end

    private def write_node(node : Look, io : IO) : Nil
      write_look(node.kind, io)
    end

    private def write_node(node : Capture, io : IO) : Nil
      write_capture(node, io)
    end

    private def write_node(node : Concat, io : IO) : Nil
      write_concat(node.children, io)
    end

    private def write_node(node : Alternation, io : IO) : Nil
      write_alternation(node.children, io)
    end

    private def write_node(node : Repetition, io : IO) : Nil
      write_repetition(node, io)
    end

    private def write_node(node : DotNode, io : IO) : Nil
      write_dot(node.kind, io)
    end

    private def write_capture(node : Capture, io : IO) : Nil
      io << "("
      if name = node.name
        io << "?P<" << name << ">"
      end
      write_node(node.sub, io)
      io << ")"
    end

    private def write_concat(children : Array(Node), io : IO) : Nil
      io << "(?:"
      children.each { |child| write_node(child, io) }
      io << ")"
    end

    private def write_alternation(children : Array(Node), io : IO) : Nil
      if singleton_class = singleton_alternation_class(children)
        write_unicode_class(singleton_class, io)
        return
      end
      io << "(?:"
      children.each_with_index do |child, i|
        io << "|" if i > 0
        write_node(child, io)
      end
      io << ")"
    end

    private def write_repetition(node : Repetition, io : IO) : Nil
      write_node(node.sub, io)
      write_repetition_suffix(node, io)
    end

    private def write_literal(bytes : Bytes, io : IO) : Nil
      if ::Unicode.valid?(bytes)
        string = String.new(bytes)
        len = string.size
        io << "(?:" if len > 1
        string.each_char { |char| write_literal_char(char, io) }
        io << ")" if len > 1
      else
        io << "(?:" if bytes.size > 1
        bytes.each { |byte| write_literal_byte(byte, io) }
        io << ")" if bytes.size > 1
      end
    end

    private def write_unicode_class(node : UnicodeClass, io : IO) : Nil
      intervals = node.negated? ? IntervalOps.invert(node.ranges) : node.ranges
      if intervals.size == 1 && intervals[0].begin == intervals[0].end
        char = intervals[0].begin.chr
        write_literal(char.to_s.to_slice, io)
        return
      end
      if !node.negated? && (bytes = node.literal)
        write_literal(bytes, io)
        return
      end
      if intervals.empty?
        io << "[a&&b]"
        return
      end
      io << "["
      intervals.each do |range|
        if range.begin == range.end
          write_literal_char(range.begin.chr, io)
        elsif range.begin + 1 == range.end
          write_literal_char(range.begin.chr, io)
          write_literal_char(range.end.chr, io)
        else
          write_literal_char(range.begin.chr, io)
          io << "-"
          write_literal_char(range.end.chr, io)
        end
      end
      io << "]"
    end

    private def write_byte_class(node : CharClass, io : IO) : Nil
      ranges = node.negated? ? IntervalOps.invert(node.ranges) : node.ranges
      if ranges.size == 1 && ranges[0].begin == ranges[0].end
        write_literal(Bytes[ranges[0].begin], io)
        return
      end
      if !node.negated? && (bytes = node.literal)
        write_literal(bytes, io)
        return
      end
      if ranges.empty?
        io << "[a&&b]"
        return
      end
      io << "(?-u:["
      ranges.each do |range|
        if range.begin == range.end
          write_literal_class_byte(range.begin, io)
        elsif range.begin + 1 == range.end
          write_literal_class_byte(range.begin, io)
          write_literal_class_byte(range.end, io)
        else
          write_literal_class_byte(range.begin, io)
          io << "-"
          write_literal_class_byte(range.end, io)
        end
      end
      io << "])"
    end

    private def write_look(kind : Look::Kind, io : IO) : Nil
      io << LOOK_PATTERNS[kind]
    end

    private def write_repetition_suffix(node : Repetition, io : IO) : Nil
      case {node.min, node.max}
      when {0_u32, 1_u32}
        io << "?"
      when {0_u32, nil}
        io << "*"
      when {1_u32, nil}
        io << "+"
      when {1_u32, 1_u32}
        return
      else
        if max = node.max
          if node.min == max
            io << '{' << node.min << '}'
            return
          else
            io << '{' << node.min << ',' << max << '}'
          end
        else
          io << '{' << node.min << ",}"
        end
      end
      io << "?" unless node.greedy?
    end

    private def write_dot(kind : Dot, io : IO) : Nil
      case kind
      when Dot::AnyCharExceptLF
        io << "."
      when Dot::AnyChar
        io << "(?s:.)"
      when Dot::AnyCharExceptCRLF
        io << "(?R:.)"
      when Dot::AnyByteExceptLF
        io << "(?-u:.)"
      when Dot::AnyByte
        io << "(?s-u:.)"
      when Dot::AnyByteExceptCRLF
        io << "(?R-u:.)"
      end
    end

    private def write_literal_char(char : Char, io : IO) : Nil
      io << "\\" if meta_character?(char)
      io << char
    end

    private def write_literal_byte(byte : UInt8, io : IO) : Nil
      char = byte.chr
      if byte <= 0x7F_u8 && !char.control? && !char.whitespace?
        write_literal_char(byte.chr, io)
      else
        io << "(?-u:\\x" << byte.to_s(16).upcase.rjust(2, '0') << ")"
      end
    end

    private def write_literal_class_byte(byte : UInt8, io : IO) : Nil
      char = byte.chr
      if byte <= 0x7F_u8 && !char.control? && !char.whitespace?
        write_literal_char(byte.chr, io)
      else
        io << "\\x" << byte.to_s(16).upcase.rjust(2, '0')
      end
    end

    private def meta_character?(char : Char) : Bool
      {'\\', '.', '+', '*', '?', '(', ')', '|', '[', ']', '{', '}', '^', '$', '#', '&', '-', '~'}.includes?(char)
    end

    private def singleton_alternation_class(children : Array(Node)) : UnicodeClass?
      ranges = [] of Range(UInt32, UInt32)
      children.each do |child|
        case child
        when Literal
          return nil unless ::Unicode.valid?(child.bytes)
          string = String.new(child.bytes)
          return nil unless string.size == 1
          codepoint = string.each_char.first.ord.to_u32
          ranges << (codepoint..codepoint)
        when UnicodeClass
          return nil unless child.ranges.size == 1 && child.ranges[0].begin == child.ranges[0].end
          ranges << child.ranges[0]
        else
          return nil
        end
      end
      UnicodeClass.new(false, ranges)
    end
  end

  class Hir
    def to_s(io : IO) : Nil
      Printer.new.print(self, io)
    end
  end
end
