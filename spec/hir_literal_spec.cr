require "./spec_helper"

alias ExtractedLiteral = Regex::Syntax::Hir::LiteralExtraction::Literal
alias ExtractKind = Regex::Syntax::Hir::LiteralExtraction::ExtractKind
alias Extractor = Regex::Syntax::Hir::LiteralExtraction::Extractor
alias Seq = Regex::Syntax::Hir::LiteralExtraction::Seq

def literal(string : String, exact : Bool = true) : ExtractedLiteral
  exact ? ExtractedLiteral.exact(string) : ExtractedLiteral.inexact(string)
end

def exact_seq(*strings : String) : Seq
  Seq.new(strings.to_a.map { |string| literal(string) })
end

def inexact_seq(*strings : String) : Seq
  Seq.new(strings.to_a.map { |string| literal(string, exact: false) })
end

def extract_pair(pattern : String, *, unicode : Bool = true) : {Seq, Seq}
  hir = Regex::Syntax::Parser.new(unicode: unicode).parse(pattern)
  prefix = Extractor.new.kind(ExtractKind::Prefix).extract(hir)
  suffix = Extractor.new.kind(ExtractKind::Suffix).extract(hir)
  {prefix, suffix}
end

def optimize_pair(literals : Array(ExtractedLiteral)) : {Seq, Seq}
  prefixes = Seq.new(literals.map(&.clone))
  suffixes = Seq.new(literals.map(&.clone))
  prefixes.optimize_for_prefix_by_preference
  suffixes.optimize_for_suffix_by_preference
  {prefixes, suffixes}
end

def bytes_to_string(bytes : Array(UInt8)) : String
  String.new(Bytes.new(bytes.size) { |i| bytes[i] })
end

def vendor_huge_literal_pattern : String
  source = File.read("vendor/regex-syntax/src/hir/literal.rs")
  start_marker = "let pat = r#\"(?-u)"
  finish_marker = "\"#;"
  start = source.index(start_marker)
  raise "missing huge literal pattern start marker" unless start
  finish = source.index(finish_marker, start)
  raise "missing huge literal pattern end marker" unless finish
  pattern_start = start + "let pat = r#\"".size
  source[pattern_start...finish]
end

describe Regex::Syntax::Hir::LiteralExtraction do
  it "extracts exact literals like Rust" do
    extract_pair("a").should eq({exact_seq("a"), exact_seq("a")})
    extract_pair("aaaaa").should eq({exact_seq("aaaaa"), exact_seq("aaaaa")})
    extract_pair("☃").should eq({exact_seq("☃"), exact_seq("☃")})
    extract_pair("(?i)S").should eq({
      exact_seq("S", "s", "ſ"),
      exact_seq("S", "s", "ſ"),
    })
  end

  it "extracts finite class literals like Rust" do
    extract_pair("[abc]").should eq({exact_seq("a", "b", "c"), exact_seq("a", "b", "c")})
    extract_pair("a[123]b").should eq({
      exact_seq("a1b", "a2b", "a3b"),
      exact_seq("a1b", "a2b", "a3b"),
    })
  end

  it "treats look-around like empty strings during extraction" do
    extract_pair(%q(a\Ab)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(\bab)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(ab\B)).should eq({exact_seq("ab"), exact_seq("ab")})
  end

  it "extracts concatenation and alternation like Rust" do
    extract_pair("abc()xyz").should eq({exact_seq("abcxyz"), exact_seq("abcxyz")})
    extract_pair("abc|mno|xyz").should eq({exact_seq("abc", "mno", "xyz"), exact_seq("abc", "mno", "xyz")})
  end

  it "extracts basic repetition exactness like Rust" do
    extract_pair("a?").should eq({exact_seq("a", ""), exact_seq("a", "")})
    extract_pair("a??").should eq({exact_seq("", "a"), exact_seq("", "a")})
    extract_pair("a+").should eq({inexact_seq("a"), inexact_seq("a")})
    extract_pair("a{2}").should eq({exact_seq("aa"), exact_seq("aa")})
    extract_pair("a{2,3}").should eq({inexact_seq("aa"), inexact_seq("aa")})
  end

  it "treats dot and large classes as infinite like Rust" do
    extract_pair(".")[0].finite?.should be_false
    extract_pair("(?s).")[1].finite?.should be_false
    extract_pair("[A-Z]")[0].finite?.should be_false
  end

  it "handles impossible extractor cases like Rust" do
    extract_pair("[a&&b]").should eq({Seq.empty, Seq.empty})
    extract_pair("a[a&&b]").should eq({Seq.empty, Seq.empty})
    extract_pair("[a&&b]b").should eq({Seq.empty, Seq.empty})
    extract_pair("a[a&&b]b").should eq({Seq.empty, Seq.empty})
    extract_pair("a|[a&&b]|b").should eq({exact_seq("a", "b"), exact_seq("a", "b")})
    extract_pair("[a&&b]*").should eq({exact_seq(""), exact_seq("")})
    extract_pair("M[a&&b]*N").should eq({exact_seq("MN"), exact_seq("MN")})
  end

  it "handles small limit extractor cases like Rust" do
    pair = {
      Extractor.new.kind(ExtractKind::Prefix).limit_total(10).extract(Regex::Syntax::Parser.new.parse("[ab]{3}{3}")),
      Extractor.new.kind(ExtractKind::Suffix).limit_total(10).extract(Regex::Syntax::Parser.new.parse("[ab]{3}{3}")),
    }
    expected = inexact_seq("aaa", "aab", "aba", "abb", "baa", "bab", "bba", "bbb")
    pair.should eq({expected, expected})

    infinite = {
      Extractor.new.kind(ExtractKind::Prefix).limit_total(10).extract(Regex::Syntax::Parser.new.parse("ab|cd|ef|gh|ij|kl|mn|op|qr|st|uv|wx|yz")),
      Extractor.new.kind(ExtractKind::Suffix).limit_total(10).extract(Regex::Syntax::Parser.new.parse("ab|cd|ef|gh|ij|kl|mn|op|qr|st|uv|wx|yz")),
    }
    infinite[0].finite?.should be_false
    infinite[1].finite?.should be_false
  end

  it "handles crazy repeats like Rust" do
    exact_empty_inexact = {inexact_seq(""), inexact_seq("")}
    extract_pair("(?:){4294967295}").should eq(exact_empty_inexact)
    extract_pair("(?:){64}{64}{64}{64}{64}{64}").should eq(exact_empty_inexact)
    extract_pair("x{0}{4294967295}").should eq(exact_empty_inexact)
    extract_pair("(?:|){4294967295}").should eq(exact_empty_inexact)
    extract_pair("(?:){8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}").should eq(exact_empty_inexact)

    repeated_a = "a" * 100
    extract_pair("a{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}").should eq({
      inexact_seq(repeated_a),
      inexact_seq(repeated_a),
    })
  end

  it "handles odds and ends extractor cases like Rust" do
    extract_pair(".a").should eq({Seq.infinite, inexact_seq("a")})
    extract_pair("a.").should eq({inexact_seq("a"), Seq.infinite})
    extract_pair("a|.")[0].finite?.should be_false
    extract_pair(".|a")[1].finite?.should be_false
    extract_pair("(?m)^Sherlock Holmes|Sherlock Holmes$").should eq({
      exact_seq("Sherlock Holmes"),
      exact_seq("Sherlock Holmes"),
    })
    extract_pair(%q(\bs(?:[ab]))).should eq({
      exact_seq("sa", "sb"),
      exact_seq("sa", "sb"),
    })
  end

  it "extracts byte literals with unicode disabled like Rust" do
    pair = extract_pair(%q((?-u:\xFF)), unicode: false)
    bytes = [0xFF_u8]
    pair.should eq({
      Seq.singleton(ExtractedLiteral.exact(bytes)),
      Seq.singleton(ExtractedLiteral.exact(bytes)),
    })
  end

  it "minimizes sequences by preference like Rust" do
    seq = exact_seq("sam", "samwise")
    seq.minimize_by_preference
    seq.should eq(Seq.new([literal("sam", exact: false)]))

    seq = exact_seq("samwise", "sam")
    seq.minimize_by_preference
    seq.should eq(exact_seq("samwise", "sam"))

    seq = exact_seq("foo", "bar", "", "quux", "fox")
    seq.minimize_by_preference
    seq.should eq(Seq.new([
      literal("foo"),
      literal("bar"),
      literal("", exact: false),
    ]))
  end

  it "computes longest common prefix and suffix like Rust" do
    seq = exact_seq("foo", "foobar", "fo")
    if prefix = seq.longest_common_prefix
      bytes_to_string(prefix).should eq("fo")
    else
      fail "expected longest common prefix"
    end

    seq = exact_seq("foo", "bar")
    if prefix = seq.longest_common_prefix
      bytes_to_string(prefix).should eq("")
    else
      fail "expected longest common prefix"
    end

    seq = exact_seq("oof", "raboof", "of")
    if suffix = seq.longest_common_suffix
      bytes_to_string(suffix).should eq("of")
    else
      fail "expected longest common suffix"
    end

    seq = exact_seq("foo", "bar")
    if suffix = seq.longest_common_suffix
      bytes_to_string(suffix).should eq("")
    else
      fail "expected longest common suffix"
    end

    Seq.infinite.longest_common_prefix.should be_nil
    Seq.empty.longest_common_suffix.should be_nil
  end

  it "optimizes sequences by preference like Rust" do
    optimize_pair([
      literal("foobarfoobar"),
      literal("foobar"),
      literal("foobarzfoobar"),
      literal("foobarfoobar"),
    ]).should eq({
      Seq.new([literal("foobar", exact: false)]),
      Seq.new([literal("foobar", exact: false)]),
    })

    optimize_pair([
      literal("abba"),
      literal("akka"),
      literal("abccba"),
    ]).should eq({
      exact_seq("abba", "akka", "abccba"),
      exact_seq("abba", "akka", "abccba"),
    })

    optimize_pair([
      literal("sam"),
      literal("samwise"),
    ]).should eq({
      Seq.new([literal("sam")]),
      exact_seq("sam", "samwise"),
    })

    seq = Seq.new([
      literal("foobarfoo"),
      literal("foo", exact: false),
      literal(""),
      literal("foozfoo"),
      literal("foofoo"),
    ])
    seq.optimize_for_prefix_by_preference
    seq.finite?.should be_false

    seq = Seq.new([
      literal("foobarfoo"),
      literal("foo", exact: false),
      literal(" "),
      literal("foofoo"),
    ])
    seq.optimize_for_prefix_by_preference
    seq.finite?.should be_false
  end

  it "handles holmes literal optimization prerequisites like Rust" do
    prefixes, suffixes = extract_pair("(?i)Holmes")
    prefixes.keep_first_bytes(3)
    suffixes.keep_last_bytes(3)
    prefixes.minimize_by_preference
    suffixes.minimize_by_preference

    prefixes.should eq(Seq.new([
      literal("HOL", exact: false),
      literal("HOl", exact: false),
      literal("HoL", exact: false),
      literal("Hol", exact: false),
      literal("hOL", exact: false),
      literal("hOl", exact: false),
      literal("hoL", exact: false),
      literal("hol", exact: false),
    ]))
    suffixes.should eq(Seq.new([
      literal("MES", exact: false),
      literal("MEs", exact: false),
      literal("Eſ", exact: false),
      literal("MeS", exact: false),
      literal("Mes", exact: false),
      literal("eſ", exact: false),
      literal("mES", exact: false),
      literal("mEs", exact: false),
      literal("meS", exact: false),
      literal("mes", exact: false),
    ]))
  end

  it "retains literals for holmes alternation optimization like Rust" do
    pair = extract_pair("(?i)Sherlock|Holmes|Watson|Irene|Adler|John|Baker")
    prefixes = pair[0]
    prefixes.finite?.should be_true
    prefixes.len.should_not eq(0)

    prefixes.optimize_for_prefix_by_preference
    prefixes.finite?.should be_true
    prefixes.len.should_not eq(0)
  end

  it "matches the upstream huge extractor shape" do
    prefixes, suffixes = extract_pair(vendor_huge_literal_pattern)
    suffixes.finite?.should be_false
    prefixes.len.should eq(243)
  end
end
