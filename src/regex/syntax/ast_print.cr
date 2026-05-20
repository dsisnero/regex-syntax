module Regex::Syntax::AST
  class Printer
    ASSERTION_PATTERNS = {
      Assertion::Kind::Start                  => "^",
      Assertion::Kind::End                    => "$",
      Assertion::Kind::WordBoundary           => "\\b",
      Assertion::Kind::NonWordBoundary        => "\\B",
      Assertion::Kind::StartText              => "\\A",
      Assertion::Kind::EndText                => "\\z",
      Assertion::Kind::EndTextWithNewline     => "\\Z",
      Assertion::Kind::WordBoundaryStart      => "\\b{start}",
      Assertion::Kind::WordBoundaryEnd        => "\\b{end}",
      Assertion::Kind::WordBoundaryStartHalf  => "\\b{start-half}",
      Assertion::Kind::WordBoundaryEndHalf    => "\\b{end-half}",
      Assertion::Kind::WordBoundaryStartAngle => "\\<",
      Assertion::Kind::WordBoundaryEndAngle   => "\\>",
    }

    ASCII_CLASS_NAMES = {
      ClassAscii::Kind::Alnum  => "alnum",
      ClassAscii::Kind::Alpha  => "alpha",
      ClassAscii::Kind::Ascii  => "ascii",
      ClassAscii::Kind::Blank  => "blank",
      ClassAscii::Kind::Cntrl  => "cntrl",
      ClassAscii::Kind::Digit  => "digit",
      ClassAscii::Kind::Graph  => "graph",
      ClassAscii::Kind::Lower  => "lower",
      ClassAscii::Kind::Print  => "print",
      ClassAscii::Kind::Punct  => "punct",
      ClassAscii::Kind::Space  => "space",
      ClassAscii::Kind::Upper  => "upper",
      ClassAscii::Kind::Word   => "word",
      ClassAscii::Kind::Xdigit => "xdigit",
    }

    def self.new : self
      allocate.tap(&.initialize)
    end

    def initialize
    end

    def print(ast : Ast, io : IO) : Nil
      write_node(ast.root, io)
    end

    private def write_node(node : Node, io : IO) : Nil
      raise "unsupported AST node for printing: #{node.class}"
    end

    private def write_node(node : Empty, io : IO) : Nil
    end

    private def write_node(node : SetFlags, io : IO) : Nil
      io << "(?"
      write_flags_items(node.items, io)
      io << ")"
    end

    private def write_node(node : Literal, io : IO) : Nil
      write_literal(node, io)
    end

    private def write_node(node : Dot, io : IO) : Nil
      io << "."
    end

    private def write_node(node : Assertion, io : IO) : Nil
      io << ASSERTION_PATTERNS[node.kind]
    end

    private def write_node(node : ClassUnicode, io : IO) : Nil
      io << (node.negated? ? "\\P" : "\\p")
      if node.name.size == 1
        io << node.name
      else
        io << "{" << node.name << "}"
      end
    end

    private def write_node(node : ClassPerl, io : IO) : Nil
      case node.kind
      when ClassPerl::Kind::Digit    then io << "\\d"
      when ClassPerl::Kind::DigitNeg then io << "\\D"
      when ClassPerl::Kind::Space    then io << "\\s"
      when ClassPerl::Kind::SpaceNeg then io << "\\S"
      when ClassPerl::Kind::Word     then io << "\\w"
      when ClassPerl::Kind::WordNeg  then io << "\\W"
      end
    end

    private def write_node(node : ClassAscii, io : IO) : Nil
      io << "[:"
      io << "^" if node.negated?
      io << ASCII_CLASS_NAMES[node.kind]
      io << ":]"
    end

    private def write_node(node : ClassBracketed, io : IO) : Nil
      io << "["
      io << "^" if node.negated?
      write_class_set(node.kind, io)
      io << "]"
    end

    private def write_node(node : Repetition, io : IO) : Nil
      write_node(node.child, io)
      write_repetition_suffix(node, io)
    end

    private def write_node(node : Group, io : IO) : Nil
      write_group_prefix(node, io)
      write_node(node.child, io)
      io << ")"
    end

    private def write_node(node : Alternation, io : IO) : Nil
      node.children.each_with_index do |child, i|
        io << "|" if i > 0
        write_node(child, io)
      end
    end

    private def write_node(node : Concat, io : IO) : Nil
      node.children.each do |child|
        write_node(child, io)
      end
    end

    private def write_group_prefix(node : Group, io : IO) : Nil
      case node.kind
      when Group::Kind::Capture
        if name = node.name
          io << "(?P<" << name << ">"
        else
          io << "("
        end
      when Group::Kind::NonCapture
        if flags = node.flags
          io << "(?"
          write_flags_items(flags.items, io)
          io << ":"
        else
          io << "(?:"
        end
      when Group::Kind::Atomic
        io << "(?>"
      when Group::Kind::Lookahead
        io << "(?="
      when Group::Kind::Lookbehind
        io << "(?<="
      when Group::Kind::NegativeLookahead
        io << "(?!"
      when Group::Kind::NegativeLookbehind
        io << "(?<!"
      end
    end

    private def write_flags_items(items : Array(FlagsItem), io : IO) : Nil
      items.each do |item|
        case item.kind
        when FlagsItem::Kind::Negation
          io << "-"
        when FlagsItem::Kind::Flag
          if flag = item.flag
            io << flag
          else
            raise "flag item missing flag value"
          end
        end
      end
    end

    private def write_repetition_suffix(node : Repetition, io : IO) : Nil
      case node.op.kind
      when RepetitionOp::Kind::ZeroOrOne
        io << "?"
      when RepetitionOp::Kind::ZeroOrMore
        io << "*"
      when RepetitionOp::Kind::OneOrMore
        io << "+"
      when RepetitionOp::Kind::Range
        min = node.op.min
        raise "range repetition missing min" unless min
        max = node.op.max
        if max.nil?
          io << "{" << min << ",}"
        elsif max == min
          io << "{" << min << "}"
        else
          io << "{" << min << "," << max << "}"
        end
      end
      io << "?" unless node.greedy?
    end

    private def write_literal(node : Literal, io : IO) : Nil
      if bytes = node.bytes
        write_literal_bytes(node.kind, bytes, io)
        return
      end

      char = node.c
      raise "literal missing char value" unless char
      case node.kind
      when Literal::Kind::Verbatim
        write_literal_char(char, io)
      when Literal::Kind::Escaped
        write_escaped_literal_char(char, io)
      when Literal::Kind::Hex
        write_hex_literal("\\x", char.ord, node, io)
      when Literal::Kind::Unicode
        write_unicode_literal(char.ord, node, io)
      when Literal::Kind::Octal
        io << "\\" << char.ord.to_s(8)
      end
    end

    private def write_literal_bytes(kind : Literal::Kind, bytes : Bytes, io : IO) : Nil
      if bytes.size == 1
        write_single_literal_byte(kind, bytes[0], io)
      else
        String.new(bytes).each_char { |char| write_literal_char(char, io) }
      end
    end

    private def write_single_literal_byte(kind : Literal::Kind, byte : UInt8, io : IO) : Nil
      if kind.octal?
        io << "\\" << byte.to_s(8)
      elsif kind.hex?
        io << "\\x" << byte.to_s(16).upcase.rjust(2, '0')
      else
        write_literal_char(byte.chr, io)
      end
    end

    private def write_escaped_literal_char(char : Char, io : IO) : Nil
      case char
      when '\a' then io << "\\a"
      when '\f' then io << "\\f"
      when '\n' then io << "\\n"
      when '\r' then io << "\\r"
      when '\t' then io << "\\t"
      when '\v' then io << "\\v"
      when ' '  then io << "\\ "
      else
        io << "\\" << char
      end
    end

    private def write_literal_char(char : Char, io : IO) : Nil
      io << "\\" if meta_character?(char)
      io << char
    end

    private def meta_character?(char : Char) : Bool
      {'\\', '.', '+', '*', '?', '(', ')', '|', '[', ']', '{', '}', '^', '$', '#', '&', '-', '~'}.includes?(char)
    end

    private def write_class_set(set : ClassSet, io : IO) : Nil
      case set.kind
      when ClassSet::Kind::Item
        if item = set.item
          write_class_set_item(item, io)
        else
          raise "class set item missing item value"
        end
      when ClassSet::Kind::BinaryOp
        if binary_op = set.binary_op
          write_class_set_binary_op(binary_op, io)
        else
          raise "class set binary op missing op value"
        end
      end
    end

    private def write_class_set_binary_op(node : ClassSetBinaryOp, io : IO) : Nil
      write_class_set(node.lhs, io)
      case node.kind
      when ClassSetBinaryOp::Kind::Intersection
        io << "&&"
      when ClassSetBinaryOp::Kind::Difference
        io << "--"
      when ClassSetBinaryOp::Kind::SymmetricDifference
        io << "~~"
      end
      write_class_set(node.rhs, io)
    end

    private def write_class_set_item(node : ClassSetItem, io : IO) : Nil
      case node.kind
      when ClassSetItem::Kind::Empty
      when ClassSetItem::Kind::Literal
        write_class_literal(node.item.as(Literal), io)
      when ClassSetItem::Kind::Range
        range = node.item.as(ClassSetRange)
        write_class_literal(range.start, io)
        io << "-"
        write_class_literal(range.end, io)
      when ClassSetItem::Kind::Ascii
        write_node(node.item.as(ClassAscii), io)
      when ClassSetItem::Kind::Unicode
        write_node(node.item.as(ClassUnicode), io)
      when ClassSetItem::Kind::Perl
        write_node(node.item.as(ClassPerl), io)
      when ClassSetItem::Kind::Bracketed
        write_node(node.item.as(ClassBracketed), io)
      when ClassSetItem::Kind::Union
        node.item.as(ClassSetUnion).items.each do |item|
          write_class_set_item(item, io)
        end
      end
    end

    private def write_class_literal(node : Literal, io : IO) : Nil
      if bytes = node.bytes
        write_class_literal_bytes(node.kind, bytes, io)
        return
      end

      char = node.c
      raise "class literal missing char value" unless char
      case node.kind
      when Literal::Kind::Verbatim
        write_class_literal_char(char, io)
      when Literal::Kind::Escaped
        write_escaped_literal_char(char, io)
      when Literal::Kind::Hex
        write_hex_literal("\\x", char.ord, node, io)
      when Literal::Kind::Unicode
        write_unicode_literal(char.ord, node, io)
      when Literal::Kind::Octal
        io << "\\" << char.ord.to_s(8)
      end
    end

    private def write_class_literal_bytes(kind : Literal::Kind, bytes : Bytes, io : IO) : Nil
      if bytes.size == 1
        write_single_class_literal_byte(kind, bytes[0], io)
      else
        String.new(bytes).each_char { |char| write_class_literal_char(char, io) }
      end
    end

    private def write_single_class_literal_byte(kind : Literal::Kind, byte : UInt8, io : IO) : Nil
      if kind.octal?
        io << "\\" << byte.to_s(8)
      elsif kind.hex?
        io << "\\x" << byte.to_s(16).upcase.rjust(2, '0')
      else
        write_class_literal_char(byte.chr, io)
      end
    end

    private def write_class_literal_char(char : Char, io : IO) : Nil
      io << "\\" if class_meta_character?(char)
      io << char
    end

    private def class_meta_character?(char : Char) : Bool
      {'\\', ']', '^'}.includes?(char)
    end

    private def write_hex_literal(prefix : String, codepoint : Int32, node : Literal, io : IO) : Nil
      actual_prefix = "\\#{node.escape_prefix || prefix[-1]}"
      case node.form
      when Literal::Form::Brace
        io << actual_prefix << '{' << codepoint.to_s(16).upcase << '}'
      else
        width = node.fixed_digits || 2
        io << actual_prefix << codepoint.to_s(16).upcase.rjust(width, '0')
      end
    end

    private def write_unicode_literal(codepoint : Int32, node : Literal, io : IO) : Nil
      actual_prefix = "\\#{node.escape_prefix || (node.fixed_digits == 8 ? 'U' : 'u')}"
      case node.form
      when Literal::Form::Fixed
        width = node.fixed_digits || 4
        io << actual_prefix << codepoint.to_s(16).upcase.rjust(width, '0')
      else
        io << actual_prefix << '{' << codepoint.to_s(16).upcase << '}'
      end
    end
  end

  class Ast
    def to_s(io : IO) : Nil
      Printer.new.print(self, io)
    end
  end
end
