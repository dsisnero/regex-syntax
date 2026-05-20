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

def extract_pair(pattern : String, *, unicode : Bool = true, utf8 : Bool = true) : {Seq, Seq}
  hir = Regex::Syntax::Parser.new(unicode: unicode, utf8: utf8).parse(pattern)
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
    extract_pair("(?i-u)a", unicode: false).should eq({
      exact_seq("A", "a"),
      exact_seq("A", "a"),
    })
    extract_pair("(?i-u)ab", unicode: false).should eq({
      exact_seq("AB", "Ab", "aB", "ab"),
      exact_seq("AB", "Ab", "aB", "ab"),
    })
    extract_pair("ab(?i-u)c", unicode: false).should eq({
      exact_seq("abC", "abc"),
      exact_seq("abC", "abc"),
    })
    extract_pair("(?i)S").should eq({
      exact_seq("S", "s", "ſ"),
      exact_seq("S", "s", "ſ"),
    })
    extract_pair("(?i)s").should eq({
      exact_seq("S", "s", "ſ"),
      exact_seq("S", "s", "ſ"),
    })
    greek_letters = "ͱͳͷΐάέήίΰαβγδεζηθικλμνξοπρςστυφχψωϊϋ"
    extract_pair(greek_letters).should eq({
      exact_seq(greek_letters),
      exact_seq(greek_letters),
    })
  end

  it "extracts finite class literals like Rust" do
    extract_pair("[abc]").should eq({exact_seq("a", "b", "c"), exact_seq("a", "b", "c")})
    extract_pair("a[123]b").should eq({
      exact_seq("a1b", "a2b", "a3b"),
      exact_seq("a1b", "a2b", "a3b"),
    })
    extract_pair("[εδ]").should eq({
      exact_seq("δ", "ε"),
      exact_seq("δ", "ε"),
    })
    extract_pair("(?i)[εδ]").should eq({
      exact_seq("Δ", "Ε", "δ", "ε", "ϵ"),
      exact_seq("Δ", "Ε", "δ", "ε", "ϵ"),
    })
  end

  it "treats look-around like empty strings during extraction" do
    extract_pair(%q(a\Ab)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(a\zb)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("a(?m:^)b").should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("a(?m:$)b").should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(\bab)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(\Bab)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(ab\B)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(a(?-u:\b)b)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair(%q(a(?-u:\B)b)).should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("^ab").should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("$ab").should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("ab^").should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("ab$").should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("^aZ*b").should eq({
      Seq.new([literal("aZ", exact: false), literal("ab")]),
      Seq.new([literal("Zb", exact: false), literal("ab")]),
    })
  end

  it "extracts concatenation and alternation like Rust" do
    extract_pair("abc()xyz").should eq({exact_seq("abcxyz"), exact_seq("abcxyz")})
    extract_pair("(abc)(xyz)").should eq({exact_seq("abcxyz"), exact_seq("abcxyz")})
    extract_pair("abc()mno()xyz").should eq({exact_seq("abcmnoxyz"), exact_seq("abcmnoxyz")})
    extract_pair("abc[a&&b]xyz").should eq({Seq.empty, Seq.empty})
    extract_pair("abc[a&&b]*xyz").should eq({exact_seq("abcxyz"), exact_seq("abcxyz")})
    extract_pair("abc|mno|xyz").should eq({exact_seq("abc", "mno", "xyz"), exact_seq("abc", "mno", "xyz")})
    extract_pair("abc|mZ*o|xyz").should eq({
      Seq.new([literal("abc"), literal("mZ", exact: false), literal("mo"), literal("xyz")]),
      Seq.new([literal("abc"), literal("Zo", exact: false), literal("mo"), literal("xyz")]),
    })
    extract_pair("abc|M[a&&b]N|xyz").should eq({exact_seq("abc", "xyz"), exact_seq("abc", "xyz")})
    extract_pair("abc|M[a&&b]*N|xyz").should eq({exact_seq("abc", "MN", "xyz"), exact_seq("abc", "MN", "xyz")})
    extract_pair("(?:|aa)aaa").should eq({exact_seq("aaa", "aaaaa"), exact_seq("aaa", "aaaaa")})
    extract_pair("(?:|aa)(?:aaa)*").should eq({
      Seq.new([literal("aaa", exact: false), literal(""), literal("aaaaa", exact: false), literal("aa")]),
      Seq.new([literal("aaa", exact: false), literal(""), literal("aa")]),
    })
    extract_pair("(?:|aa)(?:aaa)*?").should eq({
      Seq.new([literal(""), literal("aaa", exact: false), literal("aa"), literal("aaaaa", exact: false)]),
      Seq.new([literal(""), literal("aaa", exact: false), literal("aa")]),
    })
    extract_pair("a|b*").should eq({
      Seq.new([literal("a"), literal("b", exact: false), literal("")]),
      Seq.new([literal("a"), literal("b", exact: false), literal("")]),
    })
    extract_pair("a|b+").should eq({
      Seq.new([literal("a"), literal("b", exact: false)]),
      Seq.new([literal("a"), literal("b", exact: false)]),
    })
    extract_pair("a*b|c").should eq({
      Seq.new([literal("a", exact: false), literal("b"), literal("c")]),
      Seq.new([literal("ab", exact: false), literal("b"), literal("c")]),
    })
    extract_pair("a|(?:b|c*)").should eq({
      Seq.new([literal("a"), literal("b"), literal("c", exact: false), literal("")]),
      Seq.new([literal("a"), literal("b"), literal("c", exact: false), literal("")]),
    })
    extract_pair("(a|b)*c|(a|ab)*c").should eq({
      Seq.new([
        literal("a", exact: false),
        literal("b", exact: false),
        literal("c"),
        literal("a", exact: false),
        literal("ab", exact: false),
        literal("c"),
      ]),
      Seq.new([
        literal("ac", exact: false),
        literal("bc", exact: false),
        literal("c"),
        literal("ac", exact: false),
        literal("abc", exact: false),
        literal("c"),
      ]),
    })
    extract_pair("(ab|cd)(ef|gh)").should eq({
      exact_seq("abef", "abgh", "cdef", "cdgh"),
      exact_seq("abef", "abgh", "cdef", "cdgh"),
    })
    extract_pair("(ab|cd)(ef|gh)(ij|kl)").should eq({
      exact_seq("abefij", "abefkl", "abghij", "abghkl", "cdefij", "cdefkl", "cdghij", "cdghkl"),
      exact_seq("abefij", "abefkl", "abghij", "abghkl", "cdefij", "cdefkl", "cdghij", "cdghkl"),
    })
    extract_pair("(ab){2}").should eq({exact_seq("abab"), exact_seq("abab")})
    extract_pair("(ab){2,3}").should eq({
      Seq.new([literal("abab", exact: false)]),
      Seq.new([literal("abab", exact: false)]),
    })
    extract_pair("(ab){2,}").should eq({
      Seq.new([literal("abab", exact: false)]),
      Seq.new([literal("abab", exact: false)]),
    })
  end

  it "extracts basic repetition exactness like Rust" do
    extract_pair("a?").should eq({exact_seq("a", ""), exact_seq("a", "")})
    extract_pair("a??").should eq({exact_seq("", "a"), exact_seq("", "a")})
    extract_pair("a*").should eq({
      Seq.new([literal("a", exact: false), literal("")]),
      Seq.new([literal("a", exact: false), literal("")]),
    })
    extract_pair("a*?").should eq({
      Seq.new([literal(""), literal("a", exact: false)]),
      Seq.new([literal(""), literal("a", exact: false)]),
    })
    extract_pair("a+").should eq({inexact_seq("a"), inexact_seq("a")})
    extract_pair("(a+)+").should eq({inexact_seq("a"), inexact_seq("a")})
    extract_pair("a{2}").should eq({exact_seq("aa"), exact_seq("aa")})
    extract_pair("a{2,3}").should eq({inexact_seq("aa"), inexact_seq("aa")})
    extract_pair("aZ{0}b").should eq({exact_seq("ab"), exact_seq("ab")})
    extract_pair("aZ?b").should eq({exact_seq("aZb", "ab"), exact_seq("aZb", "ab")})
    extract_pair("aZ??b").should eq({exact_seq("ab", "aZb"), exact_seq("ab", "aZb")})
    extract_pair("aZ*b").should eq({
      Seq.new([literal("aZ", exact: false), literal("ab")]),
      Seq.new([literal("Zb", exact: false), literal("ab")]),
    })
    extract_pair("aZ*?b").should eq({
      Seq.new([literal("ab"), literal("aZ", exact: false)]),
      Seq.new([literal("ab"), literal("Zb", exact: false)]),
    })
    extract_pair("aZ+b").should eq({
      inexact_seq("aZ"),
      inexact_seq("Zb"),
    })
    extract_pair("aZ+?b").should eq({
      inexact_seq("aZ"),
      inexact_seq("Zb"),
    })
    extract_pair("aZ{2}b").should eq({exact_seq("aZZb"), exact_seq("aZZb")})
    extract_pair("aZ{2,3}b").should eq({
      inexact_seq("aZZ"),
      inexact_seq("ZZb"),
    })
    extract_pair("(abc)?").should eq({exact_seq("abc", ""), exact_seq("abc", "")})
    extract_pair("(abc)??").should eq({exact_seq("", "abc"), exact_seq("", "abc")})
    extract_pair("a*b").should eq({
      Seq.new([literal("a", exact: false), literal("b")]),
      Seq.new([literal("ab", exact: false), literal("b")]),
    })
    extract_pair("a*?b").should eq({
      Seq.new([literal("b"), literal("a", exact: false)]),
      Seq.new([literal("b"), literal("ab", exact: false)]),
    })
    extract_pair("ab+").should eq({
      inexact_seq("ab"),
      inexact_seq("b"),
    })
    extract_pair("a*b+").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false)]),
      Seq.new([literal("b", exact: false)]),
    })
    extract_pair("a*b*c").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false), literal("c")]),
      Seq.new([literal("bc", exact: false), literal("ac", exact: false), literal("c")]),
    })
    extract_pair("(a+)?(b+)?c").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false), literal("c")]),
      Seq.new([literal("bc", exact: false), literal("ac", exact: false), literal("c")]),
    })
    extract_pair("(a+|)(b+|)c").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false), literal("c")]),
      Seq.new([literal("bc", exact: false), literal("ac", exact: false), literal("c")]),
    })
    extract_pair("a*b*c*").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false), literal("c", exact: false), literal("")]),
      Seq.new([literal("c", exact: false), literal("b", exact: false), literal("a", exact: false), literal("")]),
    })
    extract_pair("a*b*c+").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false), literal("c", exact: false)]),
      Seq.new([literal("c", exact: false)]),
    })
    extract_pair("a*b+c").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false)]),
      Seq.new([literal("bc", exact: false)]),
    })
    extract_pair("a*b+c*").should eq({
      Seq.new([literal("a", exact: false), literal("b", exact: false)]),
      Seq.new([literal("c", exact: false), literal("b", exact: false)]),
    })
    extract_pair("ab*").should eq({
      Seq.new([literal("ab", exact: false), literal("a")]),
      Seq.new([literal("b", exact: false), literal("a")]),
    })
    extract_pair("ab*c").should eq({
      Seq.new([literal("ab", exact: false), literal("ac")]),
      Seq.new([literal("bc", exact: false), literal("ac")]),
    })
    extract_pair("ab+c").should eq({
      inexact_seq("ab"),
      inexact_seq("bc"),
    })
    extract_pair("z*azb").should eq({
      Seq.new([literal("z", exact: false), literal("azb")]),
      Seq.new([literal("zazb", exact: false), literal("azb")]),
    })

    expected = exact_seq("aaa", "aab", "aba", "abb", "baa", "bab", "bba", "bbb")
    extract_pair("[ab]{3}").should eq({expected, expected})
    inexact_expected = Seq.new([
      literal("aaa", exact: false),
      literal("aab", exact: false),
      literal("aba", exact: false),
      literal("abb", exact: false),
      literal("baa", exact: false),
      literal("bab", exact: false),
      literal("bba", exact: false),
      literal("bbb", exact: false),
    ])
    extract_pair("[ab]{3,4}").should eq({inexact_expected, inexact_expected})
  end

  it "treats dot and large classes as infinite like Rust" do
    extract_pair(".")[0].finite?.should be_false
    extract_pair("(?s).")[1].finite?.should be_false
    extract_pair("[A-Z]")[0].finite?.should be_false
    extract_pair("[A-Za-z]")[1].finite?.should be_false
    extract_pair("[A-Z]{0}").should eq({exact_seq(""), exact_seq("")})
    extract_pair("[A-Z]?")[0].finite?.should be_false
    extract_pair("[A-Z]*")[1].finite?.should be_false
    extract_pair("[A-Z]+").should eq({Seq.infinite, Seq.infinite})
    extract_pair("1[A-Z]").should eq({
      Seq.new([literal("1", exact: false)]),
      Seq.infinite,
    })
    extract_pair("1[A-Z]2").should eq({
      Seq.new([literal("1", exact: false)]),
      Seq.new([literal("2", exact: false)]),
    })
    extract_pair("[A-Z]+123").should eq({
      Seq.infinite,
      Seq.new([literal("123", exact: false)]),
    })
    extract_pair("[A-Z]+123[A-Z]+").should eq({Seq.infinite, Seq.infinite})
    extract_pair("1|[A-Z]|3").should eq({Seq.infinite, Seq.infinite})
    extract_pair("1|2[A-Z]|3").should eq({
      Seq.new([literal("1"), literal("2", exact: false), literal("3")]),
      Seq.infinite,
    })
    extract_pair("1|[A-Z]2|3").should eq({
      Seq.infinite,
      Seq.new([literal("1"), literal("2", exact: false), literal("3")]),
    })
    extract_pair("1|2[A-Z]3|4").should eq({
      Seq.new([literal("1"), literal("2", exact: false), literal("4")]),
      Seq.new([literal("1"), literal("3", exact: false), literal("4")]),
    })
    extract_pair("(?:|1)[A-Z]2").should eq({
      Seq.infinite,
      Seq.new([literal("2", exact: false)]),
    })
    extract_pair("a.z").should eq({
      Seq.new([literal("a", exact: false)]),
      Seq.new([literal("z", exact: false)]),
    })
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
    extract_pair("foo[A-Z]+bar[A-Z]+quux").should eq({
      inexact_seq("foo"),
      inexact_seq("quux"),
    })
    extract_pair("[A-Z]+bar[A-Z]+").should eq({Seq.infinite, Seq.infinite})
    pat = "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]"
    extract_pair(pat).should eq({
      Seq.new([
        literal("Mo'am", exact: false),
        literal("Moam", exact: false),
        literal("Mu'am", exact: false),
        literal("Muam", exact: false),
      ]),
      Seq.new([
        literal("ddafi", exact: false),
        literal("ddafy", exact: false),
        literal("dhafi", exact: false),
        literal("dhafy", exact: false),
        literal("dzafi", exact: false),
        literal("dzafy", exact: false),
        literal("dafi", exact: false),
        literal("dafy", exact: false),
        literal("tdafi", exact: false),
        literal("tdafy", exact: false),
        literal("thafi", exact: false),
        literal("thafy", exact: false),
        literal("tzafi", exact: false),
        literal("tzafy", exact: false),
        literal("tafi", exact: false),
        literal("tafy", exact: false),
        literal("zdafi", exact: false),
        literal("zdafy", exact: false),
        literal("zhafi", exact: false),
        literal("zhafy", exact: false),
        literal("zzafi", exact: false),
        literal("zzafy", exact: false),
        literal("zafi", exact: false),
        literal("zafy", exact: false),
      ]),
    })
    extract_pair("fn is_([A-Z]+)|fn as_([A-Z]+)").should eq({
      Seq.new([literal("fn is_", exact: false), literal("fn as_", exact: false)]),
      Seq.infinite,
    })
  end

  it "extracts byte literals with unicode disabled like Rust" do
    pair = extract_pair(%q((?-u:\xFF)), unicode: false, utf8: false)
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

  it "splices literals into the first empty slot like Rust" do
    seq1 = Seq.new([
      literal("a"),
      literal(""),
      literal("f"),
      literal(""),
    ])
    seq2 = exact_seq("foo")

    seq1.union_into_empty(seq2)

    seq1.should eq(exact_seq("a", "foo", "f"))
    seq2.should eq(Seq.empty)
  end

  it "drains union_into_empty inputs even when no splice happens like Rust" do
    seq1 = exact_seq("foo", "bar")
    seq2 = exact_seq("bar", "quux", "foo")

    seq1.union_into_empty(seq2)

    seq1.should eq(exact_seq("foo", "bar"))
    seq2.should eq(Seq.empty)
  end

  it "infects empty-containing sequences when union_into_empty receives infinity" do
    seq1 = Seq.new([
      literal("foo"),
      literal(""),
      literal("bar", exact: false),
    ])
    seq1.union_into_empty(Seq.infinite)
    seq1.finite?.should be_false
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
