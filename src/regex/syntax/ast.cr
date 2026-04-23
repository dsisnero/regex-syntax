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

  # An AST plus comments captured while parsing with verbose mode enabled.
  class WithComments
    getter ast : Ast
    getter comments : Array(Comment)

    def initialize(@ast : Ast, @comments : Array(Comment))
    end
  end

  # A single comment captured from a verbose-mode pattern.
  class Comment
    getter span : Span
    getter comment : String

    def initialize(@span : Span, @comment : String)
    end
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
    getter items : Array(FlagsItem)

    def initialize(@span : Span, @items : Array(FlagsItem))
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
      Start                  # ^
      End                    # $
      WordBoundary           # \b
      NonWordBoundary        # \B
      StartText              # \A
      EndText                # \z
      EndTextWithNewline     # \Z
      WordBoundaryStart      # \b{start}
      WordBoundaryEnd        # \b{end}
      WordBoundaryStartHalf  # \b{start-half}
      WordBoundaryEndHalf    # \b{end-half}
      WordBoundaryStartAngle # \<
      WordBoundaryEndAngle   # \>
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

      def digit? : Bool
        self == Digit || self == DigitNeg
      end

      def space? : Bool
        self == Space || self == SpaceNeg
      end

      def word? : Bool
        self == Word || self == WordNeg
      end

      def digit_neg? : Bool
        self == DigitNeg
      end

      def space_neg? : Bool
        self == SpaceNeg
      end

      def word_neg? : Bool
        self == WordNeg
      end

      def negated? : Bool
        digit_neg? || space_neg? || word_neg?
      end
    end

    getter span : Span
    getter kind : Kind

    def initialize(@span : Span, @kind : Kind)
    end
  end

  # A single ASCII character class, e.g., `[[:alpha:]]` or `[[:^digit:]]`
  class ClassAscii < Node
    # The available ASCII character classes
    enum Kind
      Alnum  # `[0-9A-Za-z]`
      Alpha  # `[A-Za-z]`
      Ascii  # `[\x00-\x7F]`
      Blank  # `[ \t]`
      Cntrl  # `[\x00-\x1F\x7F]`
      Digit  # `[0-9]`
      Graph  # `[!-~]`
      Lower  # `[a-z]`
      Print  # `[ -~]`
      Punct  # ``[!-/:-@\[-`{-~]``
      Space  # `[\t\n\v\f\r ]`
      Upper  # `[A-Z]`
      Word   # `[0-9A-Za-z_]`
      Xdigit # `[0-9A-Fa-f]`

      # Return the corresponding Kind variant for the given name
      #
      # The name given should correspond to the lowercase version of the
      # variant name. e.g., "cntrl" for `Kind::Cntrl`.
      #
      # If no variant with the corresponding name exists, returns nil.
      def self.from_name(name : String) : Kind?
        case name
        when "alnum"  then Alnum
        when "alpha"  then Alpha
        when "ascii"  then Ascii
        when "blank"  then Blank
        when "cntrl"  then Cntrl
        when "digit"  then Digit
        when "graph"  then Graph
        when "lower"  then Lower
        when "print"  then Print
        when "punct"  then Punct
        when "space"  then Space
        when "upper"  then Upper
        when "word"   then Word
        when "xdigit" then Xdigit
        else               nil
        end
      end
    end

    getter span : Span
    getter kind : Kind
    getter? negated : Bool

    def initialize(@span : Span, @kind : Kind, negated : Bool)
      @negated = negated
    end
  end

  # A single character class range in a set.
  class ClassSetRange < Node
    getter span : Span
    getter start : Literal
    getter end : Literal

    def initialize(@span : Span, @start : Literal, @end : Literal)
    end
  end

  # A character class set item.
  class ClassSetItem < Node
    enum Kind
      Empty
      Literal
      Range
      Ascii
      Unicode
      Perl
      Bracketed
      Union
    end

    getter span : Span
    getter kind : Kind
    getter item : Node?

    def initialize(@span : Span, @kind : Kind, @item : Node? = nil)
    end
  end

  # A character class set union.
  class ClassSetUnion < Node
    getter span : Span
    getter items : Array(ClassSetItem)

    def initialize(@span : Span, @items : Array(ClassSetItem) = [] of ClassSetItem)
    end

    def empty? : Bool
      @items.empty?
    end
  end

  # A character class set.
  class ClassSet < Node
    enum Kind
      Item
      BinaryOp
    end

    getter span : Span
    getter kind : Kind
    getter item : ClassSetItem?
    getter binary_op : ClassSetBinaryOp?

    def initialize(@span : Span, @kind : Kind, @item : ClassSetItem? = nil, @binary_op : ClassSetBinaryOp? = nil)
    end
  end

  # A character class binary operation, e.g., `\pN&&[a-z]` or `[a-z--h-p]`
  class ClassSetBinaryOp < Node
    # The type of a Unicode character class set operation
    #
    # Note that this doesn't explicitly represent union since there is no
    # explicit union operator. Concatenation inside a character class corresponds
    # to the union operation.
    enum Kind
      Intersection        # The intersection of two sets, e.g., `\pN&&[a-z]`
      Difference          # The difference of two sets, e.g., `\pN--[0-9]`
      SymmetricDifference # The symmetric difference of two sets, e.g., `[\pL~~[:ascii:]]`
    end

    getter span : Span
    getter kind : Kind
    getter lhs : ClassSet
    getter rhs : ClassSet

    def initialize(@span : Span, @kind : Kind, @lhs : ClassSet, @rhs : ClassSet)
    end
  end

  # A bracketed character class set, e.g., `[a-zA-Z\pL]`
  class ClassBracketed < Node
    getter span : Span
    getter? negated : Bool
    getter kind : ClassSet

    def initialize(@span : Span, negated : Bool, @kind : ClassSet)
      @negated = negated
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

  # A flag item in a flag group.
  class FlagsItem < Node
    enum Kind
      Negation # -
      Flag     # i, m, s, x, U
    end

    getter span : Span
    getter kind : Kind
    getter flag : Char?

    def initialize(@span : Span, @kind : Kind, @flag : Char? = nil)
    end
  end

  # A set of flags, e.g., `(?is)` or `(?i:...)`
  class Flags < Node
    getter span : Span
    getter items : Array(FlagsItem)

    def initialize(@span : Span, @items : Array(FlagsItem) = [] of FlagsItem)
    end

    # Get the state of a flag (true, false, or nil if not set)
    def flag_state(flag : Char) : Bool?
      negated = false
      items.each do |item|
        case item.kind
        when FlagsItem::Kind::Negation
          negated = true
        when FlagsItem::Kind::Flag
          if item.flag == flag
            return !negated
          end
        end
      end
      nil
    end
  end

  # A grouped regular expression
  class Group < Node
    enum Kind
      Capture            # (...)
      NonCapture         # (?:...) or (?i:...)
      Atomic             # (?>...)
      Lookahead          # (?=...)
      Lookbehind         # (?<=...)
      NegativeLookahead  # (?!...)
      NegativeLookbehind # (?<!...)
    end

    getter span : Span
    getter kind : Kind
    getter child : Node
    getter capture_index : Int32? # For capture groups
    getter name : String?         # For named capture groups
    getter flags : Flags?         # For non-capturing groups with flags

    def initialize(@span : Span, @kind : Kind, @child : Node, @capture_index : Int32? = nil, @name : String? = nil, @flags : Flags? = nil)
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
