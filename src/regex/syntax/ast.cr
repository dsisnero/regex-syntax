module Regex::Syntax::AST
  alias AssertionKind = Assertion::Kind
  alias ClassAsciiKind = ClassAscii::Kind
  alias ClassPerlKind = ClassPerl::Kind
  alias ClassSetBinaryOpKind = ClassSetBinaryOp::Kind
  alias ClassSetItemKind = ClassSetItem::Kind
  alias FlagsItemKind = FlagsItem::Kind
  alias GroupKind = Group::Kind
  alias LiteralKind = Literal::Kind
  alias RepetitionKind = RepetitionOp::Kind

  enum Flag
    CaseInsensitive
    MultiLine
    DotMatchesNewLine
    SwapGreed
    Unicode
    CRLF
    IgnoreWhitespace

    def self.from_char(char : Char) : self?
      case char
      when 'i' then CaseInsensitive
      when 'm' then MultiLine
      when 's' then DotMatchesNewLine
      when 'U' then SwapGreed
      when 'u' then Unicode
      when 'R' then CRLF
      when 'x' then IgnoreWhitespace
      else          nil
      end
    end

    def to_char : Char
      case self
      when CaseInsensitive   then 'i'
      when MultiLine         then 'm'
      when DotMatchesNewLine then 's'
      when SwapGreed         then 'U'
      when Unicode           then 'u'
      when CRLF              then 'R'
      when IgnoreWhitespace  then 'x'
      else                        raise "unreachable"
      end
    end
  end

  # A position in a regular expression pattern
  struct Position
    getter offset : Int32
    getter line : Int32
    getter column : Int32

    def initialize(@offset : Int32, @line : Int32, @column : Int32)
    end

    def initialize(offset : Int32)
      @offset = offset
      @line = 1
      @column = offset + 1
    end

    def to_s(io)
      io << "Position(o: #{offset}, l: #{line}, c: #{column})"
    end

    def inspect(io)
      to_s(io)
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
      io << "Span(#{start}, #{end})"
    end

    def inspect(io)
      to_s(io)
    end

    def one_line? : Bool
      @start.line == @end.line
    end

    # ameba:disable Naming/PredicateName
    def is_one_line : Bool
      one_line?
    end

    # ameba:enable Naming/PredicateName

    def empty? : Bool
      @start.offset == @end.offset
    end

    # ameba:disable Naming/PredicateName
    def is_empty : Bool
      empty?
    end

    # ameba:enable Naming/PredicateName

    def with_start(start : Position) : Span
      Span.new(start, @end)
    end

    def with_end(finish : Position) : Span
      Span.new(@start, finish)
    end

    def self.splat(pos : Position) : Span
      Span.new(pos, pos)
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

    def flags : Flags
      Flags.new(@span, @items)
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

    enum Form
      Fixed
      Brace
    end

    enum SpecialLiteralKind
      Bell
      FormFeed
      Tab
      LineFeed
      CarriageReturn
      VerticalTab
      Space
    end

    enum HexLiteralKind
      X
      UnicodeShort
      UnicodeLong

      def digits : UInt32
        case self
        when X            then 2_u32
        when UnicodeShort then 4_u32
        when UnicodeLong  then 8_u32
        else                   raise "unreachable"
        end
      end
    end

    getter span : Span
    getter kind : Kind
    getter c : Char?      # For single character literals
    getter bytes : Bytes? # For byte literals
    getter form : Form?
    getter fixed_digits : Int32?
    getter escape_prefix : Char?

    def initialize(@span : Span, @kind : Kind, @c : Char? = nil, @bytes : Bytes? = nil, @form : Form? = nil, @fixed_digits : Int32? = nil, @escape_prefix : Char? = nil)
    end

    def byte : UInt8?
      return nil unless bytes = @bytes
      return nil unless bytes.size == 1
      bytes[0]
    end

    def hex_kind : HexLiteralKind?
      return nil unless @kind.hex? || @kind.unicode?
      case @escape_prefix
      when 'x' then HexLiteralKind::X
      when 'u' then HexLiteralKind::UnicodeShort
      when 'U' then HexLiteralKind::UnicodeLong
      else          nil
      end
    end

    def special_kind : SpecialLiteralKind?
      return nil unless @kind.escaped?
      case @c
      when '\a' then SpecialLiteralKind::Bell
      when '\f' then SpecialLiteralKind::FormFeed
      when '\t' then SpecialLiteralKind::Tab
      when '\n' then SpecialLiteralKind::LineFeed
      when '\r' then SpecialLiteralKind::CarriageReturn
      when '\v' then SpecialLiteralKind::VerticalTab
      when ' '  then SpecialLiteralKind::Space
      else           nil
      end
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
    enum ClassUnicodeOpKind
      Equal
      Colon
      NotEqual

      # ameba:disable Naming/PredicateName
      def is_equal : Bool
        equal? || colon?
      end
      # ameba:enable Naming/PredicateName
    end

    class ClassUnicodeKind
      enum Kind
        OneLetter
        Named
        NamedValue
      end

      getter kind : Kind
      getter value : Char?
      getter name : String?
      getter op : ClassUnicodeOpKind?
      getter property_name : String?
      getter property_value : String?

      private def initialize(
        @kind : Kind,
        @value : Char? = nil,
        @name : String? = nil,
        @op : ClassUnicodeOpKind? = nil,
        @property_name : String? = nil,
        @property_value : String? = nil,
      )
      end

      def self.one_letter(value : Char) : self
        new(Kind::OneLetter, value: value)
      end

      def self.named(name : String) : self
        new(Kind::Named, name: name)
      end

      def self.named_value(op : ClassUnicodeOpKind, name : String, value : String) : self
        new(Kind::NamedValue, op: op, property_name: name, property_value: value)
      end
    end

    getter span : Span
    getter? negated : Bool
    getter name : String

    def initialize(@span : Span, negated : Bool, @name : String)
      @negated = negated
    end

    def kind : ClassUnicodeKind
      if @name.size == 1
        return ClassUnicodeKind.one_letter(@name[0])
      end

      if index = @name.index("!=")
        return ClassUnicodeKind.named_value(
          ClassUnicodeOpKind::NotEqual,
          @name[0, index],
          @name[(index + 2)..]
        )
      end

      if index = @name.index('=')
        return ClassUnicodeKind.named_value(
          ClassUnicodeOpKind::Equal,
          @name[0, index],
          @name[(index + 1)..]
        )
      end

      if index = @name.index(':')
        return ClassUnicodeKind.named_value(
          ClassUnicodeOpKind::Colon,
          @name[0, index],
          @name[(index + 1)..]
        )
      end

      ClassUnicodeKind.named(@name)
    end

    # ameba:disable Naming/PredicateName
    def is_negated : Bool
      unicode_kind = kind
      if unicode_kind.kind.named_value? && (op = unicode_kind.op)
        op.not_equal? ? !@negated : @negated
      else
        @negated
      end
    end
    # ameba:enable Naming/PredicateName
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

    def valid? : Bool
      return false unless start_char = @start.c
      return false unless end_char = @end.c
      start_char <= end_char
    end

    # ameba:disable Naming/PredicateName
    def is_valid : Bool
      valid?
    end
    # ameba:enable Naming/PredicateName
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

    def push(item : ClassSetItem) : self
      if @items.empty?
        @span = @span.with_start(item.span.start)
      end
      @span = @span.with_end(item.span.end)
      @items << item
      self
    end

    def into_item : ClassSetItem
      case @items.size
      when 0
        ClassSetItem.new(@span, ClassSetItem::Kind::Empty)
      when 1
        @items.first
      else
        ClassSetItem.new(@span, ClassSetItem::Kind::Union, self)
      end
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

    def self.union(ast : ClassSetUnion) : self
      span = ast.span
      item = ast.into_item
      new(span, Kind::Item, item: item)
    end

    def union(item : ClassSetItem) : self
      union_items = [] of ClassSetItem
      case @kind
      when Kind::Item
        if existing = @item
          union_items << existing
        end
        union_items << item
      when Kind::BinaryOp
        current_item = ClassSetItem.new(@span, ClassSetItem::Kind::Bracketed, ClassBracketed.new(@span, false, self))
        union_items << current_item
        union_items << item
      end
      union = ClassSetUnion.new(@span, union_items)
      @kind = Kind::Item
      @item = ClassSetItem.new(@span, ClassSetItem::Kind::Union, union)
      @binary_op = nil
      self
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
    getter min : UInt32?
    getter max : UInt32?

    def initialize(@kind : Kind, @min : UInt32? = nil, @max : UInt32? = nil)
    end

    def valid? : Bool
      return true unless @kind.range?
      return false unless min = @min
      max = @max
      max.nil? || min <= max
    end

    # ameba:disable Naming/PredicateName
    def is_valid : Bool
      valid?
    end

    # ameba:enable Naming/PredicateName

    def range : RepetitionRange?
      return nil unless @kind.range?
      if min = @min
        case max = @max
        when Nil
          RepetitionRange.at_least(min)
        when UInt32
          min == max ? RepetitionRange.exactly(min) : RepetitionRange.bounded(min, max)
        end
      end
    end
  end

  class RepetitionRange
    enum Kind
      Exactly
      AtLeast
      Bounded
    end

    getter kind : Kind
    getter start : UInt32
    getter end : UInt32?

    private def initialize(@kind : Kind, @start : UInt32, @end : UInt32? = nil)
    end

    def self.exactly(count : UInt32) : self
      new(Kind::Exactly, count, count)
    end

    def self.at_least(count : UInt32) : self
      new(Kind::AtLeast, count)
    end

    def self.bounded(start : UInt32, finish : UInt32) : self
      new(Kind::Bounded, start, finish)
    end

    def valid? : Bool
      return true unless @kind.bounded?
      return false unless finish = @end
      @start <= finish
    end
  end

  # A flag item in a flag group.
  class FlagsItem < Node
    enum Kind
      Negation # -
      Flag     # i, m, s, x, U

      # ameba:disable Naming/PredicateName
      def is_negation : Bool
        negation?
      end
      # ameba:enable Naming/PredicateName
    end

    getter span : Span
    getter kind : Kind
    getter flag : Char?

    def initialize(@span : Span, @kind : Kind, @flag : Char? = nil)
    end

    def negation? : Bool
      @kind.negation?
    end

    # ameba:disable Naming/PredicateName
    def is_negation : Bool
      negation?
    end

    # ameba:enable Naming/PredicateName

    def flag_enum : Flag?
      return nil unless flag = @flag
      Flag.from_char(flag)
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

    def flag_state(flag : Flag) : Bool?
      flag_state(flag.to_char)
    end

    def add_item(item : FlagsItem) : Int32?
      @items.each_with_index do |existing, index|
        if existing.kind == item.kind && existing.flag == item.flag
          return index
        end
      end
      @items << item
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
    getter? starts_with_p : Bool?

    def initialize(@span : Span, @kind : Kind, @child : Node, @capture_index : Int32? = nil, @name : String? = nil, @flags : Flags? = nil, @starts_with_p : Bool? = nil)
    end

    def capturing? : Bool
      @kind.capture?
    end

    # ameba:disable Naming/PredicateName
    def is_capturing : Bool
      capturing?
    end

    # ameba:enable Naming/PredicateName

    def capture_name : CaptureName?
      return nil unless name = @name
      return nil unless index = @capture_index
      CaptureName.new(Span.splat(@span.start), name, index.to_u32)
    end
  end

  class CaptureName
    getter span : Span
    getter name : String
    getter index : UInt32

    def initialize(@span : Span, @name : String, @index : UInt32)
    end
  end

  # An alternation of regular expressions
  class Alternation < Node
    getter span : Span
    getter children : Array(Node)

    def initialize(@span : Span, @children : Array(Node))
    end

    def into_ast : Ast
      case @children.size
      when 0
        Ast.empty(@span)
      when 1
        Ast.new(@children.first)
      else
        Ast.alternation(self)
      end
    end
  end

  # A concatenation of regular expressions
  class Concat < Node
    getter span : Span
    getter children : Array(Node)

    def initialize(@span : Span, @children : Array(Node))
    end

    def into_ast : Ast
      case @children.size
      when 0
        Ast.empty(@span)
      when 1
        Ast.new(@children.first)
      else
        Ast.concat(self)
      end
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

    def self.empty(span : Span = Span.new(0, 0)) : Ast
      Ast.new(Empty.new(span))
    end

    def self.flags(node : SetFlags) : Ast
      Ast.new(node)
    end

    def self.literal(node : Literal) : Ast
      Ast.new(node)
    end

    def self.dot(span : Span) : Ast
      Ast.new(Dot.new(span))
    end

    def self.assertion(node : Assertion) : Ast
      Ast.new(node)
    end

    def self.class_unicode(node : ClassUnicode) : Ast
      Ast.new(node)
    end

    def self.class_perl(node : ClassPerl) : Ast
      Ast.new(node)
    end

    def self.class_bracketed(node : ClassBracketed) : Ast
      Ast.new(node)
    end

    def self.repetition(node : Repetition) : Ast
      Ast.new(node)
    end

    def self.group(node : Group) : Ast
      Ast.new(node)
    end

    def self.alternation(node : Alternation) : Ast
      Ast.new(node)
    end

    def self.concat(node : Concat) : Ast
      Ast.new(node)
    end

    def kind : Node
      @root
    end

    def empty? : Bool
      @root.is_a?(Empty)
    end

    # ameba:disable Naming/PredicateName
    def is_empty : Bool
      empty?
    end
    # ameba:enable Naming/PredicateName
  end
end
