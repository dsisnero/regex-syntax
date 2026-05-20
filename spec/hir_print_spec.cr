require "./spec_helper"

def print_hir(pattern : String, *, unicode : Bool = true, utf8 : Bool = true) : String
  hir = Regex::Syntax::Parser.new(unicode: unicode, utf8: utf8).parse(pattern)
  hir.to_s
end

describe Regex::Syntax::Hir::Printer do
  it "prints literals like Rust" do
    print_hir("a").should eq("a")
    print_hir(%q(\xff)).should eq("ÿ")
    print_hir(%q((?-u)\xff), unicode: false, utf8: false).should eq(%q((?-u:\xFF)))
    print_hir("☃").should eq("☃")
  end

  it "prints classes like Rust" do
    print_hir(%q([a])).should eq("a")
    print_hir(%q([ab])).should eq("[ab]")
    print_hir(%q([a-z])).should eq("[a-z]")
    print_hir(%q([a-z--b-c--x-y])).should eq("[ad-wz]")
    print_hir(%q([^\x01-\u{10FFFF}])).should eq("\u{0}")
    print_hir(%q([-])).should eq(%q(\-))
    print_hir("[☃-⛄]").should eq("[☃-⛄]")
    print_hir(%q((?-u)[ab]), unicode: false, utf8: false).should eq(%q((?-u:[ab])))
    print_hir(%q((?-u)[a]), unicode: false, utf8: false).should eq("a")
    print_hir(%q((?-u)[a-z]), unicode: false, utf8: false).should eq(%q((?-u:[a-z])))
    print_hir(%q((?-u)[\[]), unicode: false, utf8: false).should eq(%q(\[))
    print_hir(%q((?-u)[Z-_]), unicode: false, utf8: false).should eq(%q((?-u:[Z-_])))
    print_hir(%q((?-u)[Z-_--Z]), unicode: false, utf8: false).should eq(%q((?-u:[\[-_])))
    Regex::Syntax::Hir::Hir.new(
      Regex::Syntax::Hir::CharClass.new(false, [0x61_u8..0xFF_u8])
    ).to_s.should eq(%q((?-u:[a-\xFF])))
    print_hir(%q([\[])).should eq(%q(\[))
    print_hir("[Z-_]").should eq("[Z-_]")
    print_hir("[Z-_--Z]").should eq("[\\[-_]")
    print_hir(%q(\P{any})).should eq("[a&&b]")
    Regex::Syntax::Hir::Hir.new(
      Regex::Syntax::Hir::CharClass.new(true, [0x00_u8..0xFF_u8])
    ).to_s.should eq("[a&&b]")
  end

  it "prints anchors and word boundaries like Rust" do
    print_hir("^").should eq(%q(\A))
    print_hir("$").should eq(%q(\z))
    print_hir(%q((?m)^)).should eq("(?m:^)")
    print_hir(%q((?m)$)).should eq("(?m:$)")
    print_hir(%q(\b)).should eq(%q(\b))
    print_hir(%q((?-u)\b), unicode: false, utf8: false).should eq(%q((?-u:\b)))
    print_hir(%q((?-u)\B), unicode: false, utf8: false).should eq(%q((?-u:\B)))
  end

  it "prints repetitions and groups like Rust" do
    print_hir("a?").should eq("a?")
    print_hir("a??").should eq("a??")
    print_hir("a*").should eq("a*")
    print_hir("a*?").should eq("a*?")
    print_hir("a+").should eq("a+")
    print_hir("a+?").should eq("a+?")
    print_hir("(?U)a?").should eq("a??")
    print_hir("(?U)a*").should eq("a*?")
    print_hir("(?U)a+").should eq("a+?")
    print_hir("a{1}").should eq("a")
    print_hir("a{2}").should eq("a{2}")
    print_hir("a{1,}").should eq("a+")
    print_hir("a{1,5}").should eq("a{1,5}")
    print_hir("a{1}?").should eq("a")
    print_hir("a{2}?").should eq("a{2}")
    print_hir("a{1,}?").should eq("a+?")
    print_hir("a{1,5}?").should eq("a{1,5}?")
    print_hir("(?U)a{1}").should eq("a")
    print_hir("(?U)a{2}").should eq("a{2}")
    print_hir("(?U)a{1,}").should eq("a+?")
    print_hir("(?U)a{1,5}").should eq("a{1,5}?")
    print_hir("a{0}").should eq("(?:)")
    print_hir("(?:ab){0}").should eq("(?:)")
    print_hir(%q(\p{any}{0})).should eq("(?:)")
    print_hir(%q(\P{any}{0})).should eq("(?:)")
    print_hir("()").should eq("((?:))")
    print_hir("(?P<foo>)").should eq("(?P<foo>(?:))")
    print_hir("(?:)").should eq("(?:)")
    print_hir("(?P<foo>a)").should eq("(?P<foo>a)")
    print_hir("(?:a)").should eq("a")
    print_hir("((((a))))").should eq("((((a))))")
  end

  it "prints alternations like Rust" do
    print_hir("|").should eq("(?:(?:)|(?:))")
    print_hir("||").should eq("(?:(?:)|(?:)|(?:))")
    print_hir("a|b").should eq("[ab]")
    print_hir("a|b|c").should eq("[a-c]")
    print_hir("ab|cd").should eq("(?:(?:ab)|(?:cd))")
    print_hir("ab|cd|ef").should eq("(?:(?:ab)|(?:cd)|(?:ef))")
    print_hir("foo|bar|quux").should eq("(?:(?:foo)|(?:bar)|(?:quux))")
  end

  it "handles repetition over concat regressions like Rust" do
    expr = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Literal.new("x".to_slice),
      Regex::Syntax::Hir::Repetition.new(
        Regex::Syntax::Hir::Literal.new("ab".to_slice),
        1_u32,
        nil,
        greedy: true
      ),
      Regex::Syntax::Hir::Literal.new("y".to_slice),
    ] of Regex::Syntax::Hir::Node)
    expr.to_s.should eq(%q((?:x(?:ab)+y)))

    look_concat = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::StartText),
      Regex::Syntax::Hir::Hir.repetition(
        Regex::Syntax::Hir::Hir.concat([
          Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::StartText),
          Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::EndText),
        ] of Regex::Syntax::Hir::Node).node,
        1_u32,
        nil,
        greedy: true
      ).node,
      Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::EndText),
    ] of Regex::Syntax::Hir::Node)
    look_concat.to_s.should eq(%q((?:\A\A\z\z)))
  end

  it "handles repetition over alternation regressions like Rust" do
    expr = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Literal.new("ab".to_slice),
      Regex::Syntax::Hir::Repetition.new(
        Regex::Syntax::Hir::Hir.alternation([
          Regex::Syntax::Hir::Literal.new("cd".to_slice),
          Regex::Syntax::Hir::Literal.new("ef".to_slice),
        ] of Regex::Syntax::Hir::Node).node,
        1_u32,
        nil,
        greedy: true
      ),
      Regex::Syntax::Hir::Literal.new("gh".to_slice),
    ] of Regex::Syntax::Hir::Node)
    expr.to_s.should eq(%q((?:(?:ab)(?:(?:cd)|(?:ef))+(?:gh))))

    look_alt = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::StartText),
      Regex::Syntax::Hir::Hir.repetition(
        Regex::Syntax::Hir::Hir.alternation([
          Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::StartText),
          Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::EndText),
        ] of Regex::Syntax::Hir::Node).node,
        1_u32,
        nil,
        greedy: true
      ).node,
      Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::EndText),
    ] of Regex::Syntax::Hir::Node)
    look_alt.to_s.should eq(%q((?:\A(?:\A|\z)\z)))
  end

  it "handles alternation inside concat regressions like Rust" do
    expr = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Literal.new("ab".to_slice),
      Regex::Syntax::Hir::Hir.alternation([
        Regex::Syntax::Hir::Literal.new("mn".to_slice),
        Regex::Syntax::Hir::Literal.new("xy".to_slice),
      ] of Regex::Syntax::Hir::Node).node,
    ] of Regex::Syntax::Hir::Node)
    expr.to_s.should eq(%q((?:(?:ab)(?:(?:mn)|(?:xy)))))

    look_expr = Regex::Syntax::Hir::Hir.concat([
      Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::StartText),
      Regex::Syntax::Hir::Hir.alternation([
        Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::StartText),
        Regex::Syntax::Hir::Look.new(Regex::Syntax::Hir::Look::Kind::EndText),
      ] of Regex::Syntax::Hir::Node).node,
    ] of Regex::Syntax::Hir::Node)
    look_expr.to_s.should eq(%q((?:\A(?:\A|\z))))
  end
end
