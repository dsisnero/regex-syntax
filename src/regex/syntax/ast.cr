module Regex::Syntax::AST
  # A position in a regular expression pattern
  struct Position
    getter offset : Int32 # byte offset in the pattern string

    def initialize(@offset : Int32)
    end

    def to_s(io)
      io << offset
    end

    def inspect(io)
      io << "Position(#{offset})"
    end
  end

  # A span of positions in a regular expression pattern
  struct Span
    getter start : Position
    getter end : Position

    def initialize(@start : Position, @end : Position)
    end

    def initialize(start_offset : Int32, end_offset : Int32)
      @start = Position.new(start_offset)
      @end = Position.new(end_offset)
    end

    def to_s(io)
      io << "Span(#{start.offset}, #{end.offset})"
    end

    def inspect(io)
      to_s(io)
    end
  end

  # Base class for all AST nodes
  abstract class Node
    # Get the span of this node in the original pattern
    abstract def span : Span
  end

  # An empty regex that matches everything
  class Empty < Node
    getter span : Span

    def initialize(@span : Span)
    end
  end

  # A set of flags, e.g., `(?is)`
  class SetFlags < Node
    getter span : Span
    getter flags : String

    def initialize(@span : Span, @flags : String)
    end
  end

  # A single character literal, which includes escape sequences
  class Literal < Node
    enum Kind
      Verbatim # 'a'
      Escaped  # '\n', '\t', etc.
      Hex      # '\x7F'
      Unicode  # '\u{1F600}'
      Octal    # '\177' (deprecated)
    end

    getter span : Span
    getter kind : Kind
    getter c : Char?      # For single character literals
    getter bytes : Bytes? # For byte literals

    def initialize(@span : Span, @kind : Kind, @c : Char? = nil, @bytes : Bytes? = nil)
    end
  end

  # The "any character" class (.)
  class Dot < Node
    getter span : Span

    def initialize(@span : Span)
    end
  end

  # A single zero-width assertion
  class Assertion < Node
    enum Kind
      Start              # ^
      End                # $
      WordBoundary       # \b
      NonWordBoundary    # \B
      StartText          # \A
      EndText            # \z
      EndTextWithNewline # \Z
    end

    getter span : Span
    getter kind : Kind

    def initialize(@span : Span, @kind : Kind)
    end
  end

  # A single Unicode character class, e.g., `\pL` or `\p{Greek}`
  class ClassUnicode < Node
    getter span : Span
    getter? negated : Bool
    getter name : String

    def initialize(@span : Span, negated : Bool, @name : String)
      @negated = negated
    end
  end

  # A single Perl character class, e.g., `\d` or `\W`
  class ClassPerl < Node
    enum Kind
      Digit    # \d
      Space    # \s
      Word     # \w
      DigitNeg # \D
      SpaceNeg # \S
      WordNeg  # \W
    end

    getter span : Span
    getter kind : Kind

    def initialize(@span : Span, @kind : Kind)
    end
  end

  # A bracketed character class set, e.g., `[a-zA-Z\pL]`
  class ClassBracketed < Node
    getter span : Span
    getter? negated : Bool
    # Elements inside this class set. Kept generic to support mixed items
    # (literal chars, perl classes, unicode classes, nested unions, etc.).
    getter items : Array(Node)

    def initialize(@span : Span, negated : Bool, @items : Array(Node) = [] of Node)
      @negated = negated
    end

    def empty? : Bool
      @items.empty?
    end
  end

  # A repetition operator applied to an arbitrary regular expression
  class Repetition < Node
    getter span : Span
    getter op : RepetitionOp
    getter? greedy : Bool
    getter child : Node

    def initialize(@span : Span, @op : RepetitionOp, greedy : Bool, @child : Node)
      @greedy = greedy
    end
  end

  # Repetition operator kind
  class RepetitionOp
    enum Kind
      ZeroOrOne  # ?
      ZeroOrMore # *
      OneOrMore  # +
      Range      # {n}, {n,}, {n,m}
    end

    getter kind : Kind
    getter min : Int32?
    getter max : Int32?

    def initialize(@kind : Kind, @min : Int32? = nil, @max : Int32? = nil)
    end
  end

  # A grouped regular expression
  class Group < Node
    enum Kind
      Capture            # (...)
      NonCapture         # (?:...)
      Atomic             # (?>...)
      Lookahead          # (?=...)
      Lookbehind         # (?<=...)
      NegativeLookahead  # (?!...)
      NegativeLookbehind # (?<!...)
      Flags              # (?is:...)
    end

    getter span : Span
    getter kind : Kind
    getter child : Node
    getter capture_index : Int32? # For capture groups
    getter name : String?         # For named capture groups

    def initialize(@span : Span, @kind : Kind, @child : Node, @capture_index : Int32? = nil, @name : String? = nil)
    end
  end

  # An alternation of regular expressions
  class Alternation < Node
    getter span : Span
    getter children : Array(Node)

    def initialize(@span : Span, @children : Array(Node))
    end
  end

  # A concatenation of regular expressions
  class Concat < Node
    getter span : Span
    getter children : Array(Node)

    def initialize(@span : Span, @children : Array(Node))
    end
  end

  # Main AST type - a wrapper around the root node
  class Ast < Node
    getter root : Node

    def initialize(@root : Node)
    end

    def span : Span
      @root.span
    end
  end
end
