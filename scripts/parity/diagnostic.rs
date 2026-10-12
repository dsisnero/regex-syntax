use crate::{ast, hir};
use std::{
    cell::RefCell,
    format,
    io::Write,
    rc::Rc,
    string::{String, ToString},
    vec::Vec,
};
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn unhex(s: &str) -> String {
    String::from_utf8(
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect(),
    )
    .unwrap()
}
pub fn emit(kind: &str, config: &str, input: &str, value: &str) {
    let path = std::env::var("REGEX_DIAGNOSTIC_CAPTURE").unwrap();
    let mut file = std::fs::OpenOptions::new().append(true).open(path).unwrap();
    writeln!(
        file,
        "{kind}\t{config}\t{}\t{}",
        hex(input.as_bytes()),
        hex(value.as_bytes())
    )
    .unwrap();
}
pub fn assertion(file: &str, line: u32) {
    let name = file.split("/src/").last().unwrap();
    let mut out = std::fs::OpenOptions::new()
        .append(true)
        .open(std::env::var("REGEX_DIAGNOSTIC_ASSERTIONS").unwrap())
        .unwrap();
    writeln!(out, "{name}:{line}").unwrap();
}
fn span(s: &ast::Span) -> String {
    format!(
        "{},{},{},{},{},{}",
        s.start.offset, s.start.line, s.start.column, s.end.offset, s.end.line, s.end.column
    )
}
fn ast_error(e: &ast::Error) -> String {
    let kind = format!("{:?}", e.kind())
        .split([' ', '(', '{'])
        .next()
        .unwrap()
        .to_string();
    format!(
        "{kind}\n{}\n{}\n{}\n{}",
        span(e.span()),
        e.auxiliary_span().map_or_else(|| "-".into(), span),
        e.kind(),
        e
    )
}
fn hir_error(e: &hir::Error) -> String {
    format!("{:?}\n{}\n-\n{}\n{}", e.kind(), span(e.span()), e.kind(), e)
}
fn recipe(h: &hir::Hir) -> String {
    use hir::{Class, HirKind::*};
    match h.kind() {
        Empty => "empty".into(),
        Literal(l) => format!("lit:{}", hex(&l.0)),
        Look(l) => format!("look:{}", *l as u32),
        Class(Class::Unicode(c)) => format!(
            "unicode:{}",
            c.iter()
                .map(|r| format!("{}-{}", r.start() as u32, r.end() as u32))
                .collect::<Vec<_>>()
                .join(",")
        ),
        Class(Class::Bytes(c)) => format!(
            "bytes:{}",
            c.iter()
                .map(|r| format!("{}-{}", r.start(), r.end()))
                .collect::<Vec<_>>()
                .join(",")
        ),
        Capture(c) => format!(
            "cap:{}:{};{}",
            c.index,
            c.name
                .as_ref()
                .map_or_else(|| "-".into(), |n| hex(n.as_bytes())),
            recipe(&c.sub)
        ),
        Repetition(r) => format!(
            "rep:{}:{}:{};{}",
            r.min,
            r.max.map_or_else(|| "-".into(), |v| v.to_string()),
            r.greedy,
            recipe(&r.sub)
        ),
        Concat(c) => format!(
            "cat:{};{}",
            c.len(),
            c.iter().map(recipe).collect::<Vec<_>>().join(";")
        ),
        Alternation(c) => format!(
            "alt:{};{}",
            c.len(),
            c.iter().map(recipe).collect::<Vec<_>>().join(";")
        ),
    }
}
pub fn hir_tree(h: &hir::Hir) {
    emit("hir_tree", "-", &recipe(h), &h.to_string());
}
fn fixture(name: &str) -> Vec<Vec<String>> {
    let root = std::env::var("REGEX_PARITY_ROOT").unwrap();
    std::fs::read_to_string(format!("{root}/spec/fixtures/{name}.tsv"))
        .unwrap()
        .lines()
        .filter(|l| !l.starts_with('#'))
        .map(|l| l.split('\t').map(ToString::to_string).collect())
        .collect()
}
#[test]
fn diagnostic_inputs() {
    for row in fixture("ast_runtime") {
        let c = row[1].split(',').collect::<Vec<_>>();
        let p = unhex(&row[2]);
        let mut b = ast::parse::ParserBuilder::new();
        b.nest_limit(c[0].parse().unwrap())
            .octal(c[1] == "true")
            .empty_min_range(c[2] == "true")
            .ignore_whitespace(c[3] == "true");
        if let Err(e) = b.build().parse(&p) {
            emit("ast_error", &row[1], &p, &ast_error(&e));
        }
    }
    for row in fixture("hir_runtime") {
        let c = row[1].split(',').collect::<Vec<_>>();
        let p = unhex(&row[2]);
        let mut b = crate::ParserBuilder::new();
        b.octal(true)
            .ignore_whitespace(row[0].ends_with("regression_fuzz_match"))
            .utf8(c[0] == "true")
            .line_terminator(c[1].parse().unwrap())
            .case_insensitive(c[2] == "true")
            .multi_line(c[3] == "true")
            .dot_matches_new_line(c[4] == "true")
            .swap_greed(c[5] == "true")
            .unicode(c[6] == "true")
            .crlf(c[7] == "true");
        if let Err(crate::Error::Translate(e)) = b.build().parse(&p) {
            emit("hir_error", &row[1], &p, &hir_error(&e));
        }
    }
    for p in [
        "a{\n",
        "☃\\q",
        "β(?ii)",
        "(?P<β>a)(?P<β>b)",
        "(?x)(?P<β>a)\n(?P<β>b)",
        "\r\n[",
        "abc\r[",
        "[\n",
        "\n)",
        "(?x)\n\n\n\n\n\n\n\n\n\n)",
        "β{3,2}",
        "(?x)[a\n-\\w]",
        "(?x)(\n",
        "(?x)☃\n\\q",
        "",
        "a",
    ] {
        if let Err(e) = ast::parse::Parser::new().parse(p) {
            emit("ast_error", "250,false,false,false", p, &ast_error(&e));
        }
    }
}
#[derive(Clone)]
struct Trace {
    events: Rc<RefCell<Vec<String>>>,
    fail: usize,
}
impl Trace {
    fn event(&self, e: String) -> Result<(), ()> {
        let mut events = self.events.borrow_mut();
        events.push(e);
        if events.len() == self.fail {
            Err(())
        } else {
            Ok(())
        }
    }
}
fn ast_kind(a: &ast::Ast) -> &'static str {
    use ast::Ast::*;
    match a {
        Empty(_) => "Empty",
        Flags(_) => "SetFlags",
        Literal(_) => "Literal",
        Dot(_) => "Dot",
        Assertion(_) => "Assertion",
        ClassUnicode(_) => "ClassUnicode",
        ClassPerl(_) => "ClassPerl",
        ClassBracketed(_) => "ClassBracketed",
        Repetition(_) => "Repetition",
        Group(_) => "Group",
        Alternation(_) => "Alternation",
        Concat(_) => "Concat",
    }
}
fn item_kind(i: &ast::ClassSetItem) -> &'static str {
    use ast::ClassSetItem::*;
    match i {
        Empty(_) => "Empty",
        Literal(_) => "Literal",
        Range(_) => "Range",
        Ascii(_) => "Ascii",
        Unicode(_) => "Unicode",
        Perl(_) => "Perl",
        Bracketed(_) => "Bracketed",
        Union(_) => "Union",
    }
}
fn hir_kind(h: &hir::Hir) -> &'static str {
    use hir::HirKind::*;
    match h.kind() {
        Empty => "Empty",
        Literal(_) => "Literal",
        Class(hir::Class::Unicode(_)) => "UnicodeClass",
        Class(hir::Class::Bytes(_)) => "CharClass",
        Look(_) => "Look",
        Repetition(_) => "Repetition",
        Capture(_) => "Capture",
        Concat(_) => "Concat",
        Alternation(_) => "Alternation",
    }
}
impl ast::Visitor for Trace {
    type Output = ();
    type Err = ();
    fn start(&mut self) {
        self.events.borrow_mut().push("start".into());
    }
    fn finish(self) -> Result<(), ()> {
        self.event("finish".into())
    }
    fn visit_pre(&mut self, a: &ast::Ast) -> Result<(), ()> {
        self.event(format!("pre:{}", ast_kind(a)))
    }
    fn visit_post(&mut self, a: &ast::Ast) -> Result<(), ()> {
        self.event(format!("post:{}", ast_kind(a)))
    }
    fn visit_alternation_in(&mut self) -> Result<(), ()> {
        self.event("alt:in".into())
    }
    fn visit_concat_in(&mut self) -> Result<(), ()> {
        self.event("concat:in".into())
    }
    fn visit_class_set_item_pre(&mut self, a: &ast::ClassSetItem) -> Result<(), ()> {
        self.event(format!("item-pre:{}", item_kind(a)))
    }
    fn visit_class_set_item_post(&mut self, a: &ast::ClassSetItem) -> Result<(), ()> {
        self.event(format!("item-post:{}", item_kind(a)))
    }
    fn visit_class_set_binary_op_pre(&mut self, a: &ast::ClassSetBinaryOp) -> Result<(), ()> {
        self.event(format!("op-pre:{:?}", a.kind))
    }
    fn visit_class_set_binary_op_post(&mut self, a: &ast::ClassSetBinaryOp) -> Result<(), ()> {
        self.event(format!("op-post:{:?}", a.kind))
    }
    fn visit_class_set_binary_op_in(&mut self, a: &ast::ClassSetBinaryOp) -> Result<(), ()> {
        self.event(format!("op-in:{:?}", a.kind))
    }
}
impl hir::Visitor for Trace {
    type Output = ();
    type Err = ();
    fn start(&mut self) {
        self.events.borrow_mut().push("start".into());
    }
    fn finish(self) -> Result<(), ()> {
        self.event("finish".into())
    }
    fn visit_pre(&mut self, h: &hir::Hir) -> Result<(), ()> {
        self.event(format!("pre:{}", hir_kind(h)))
    }
    fn visit_post(&mut self, h: &hir::Hir) -> Result<(), ()> {
        self.event(format!("post:{}", hir_kind(h)))
    }
    fn visit_alternation_in(&mut self) -> Result<(), ()> {
        self.event("alt:in".into())
    }
    fn visit_concat_in(&mut self) -> Result<(), ()> {
        self.event("concat:in".into())
    }
}
#[test]
fn visitor_contracts() {
    for p in [
        "",
        "a",
        ".",
        "(?i)",
        "\\pL",
        "\\d",
        "^a$",
        "a(b|c)*d",
        "ab|cd|ef",
        "(ab)+",
        "[a&&[b-c]]",
        "[ab[:ascii:]\\pL\\d[^x-z]~~[a-z--b]]",
        "[a&&]",
        "[&&a]",
        "(?-u)[a-z]",
        "\\b{start-half}",
    ] {
        let ast = ast::parse::Parser::new().parse(p).unwrap();
        let hir = crate::ParserBuilder::new()
            .utf8(false)
            .build()
            .parse(p)
            .unwrap();
        for domain in ["ast_visit", "hir_visit"] {
            let mut size = 0;
            for fail in 0..1000 {
                if fail == 1 {
                    continue;
                } // start is infallible in Rust.
                if fail > 0 && fail > size {
                    break;
                }
                let events = Rc::new(RefCell::new(Vec::new()));
                let trace = Trace {
                    events: events.clone(),
                    fail,
                };
                let result = if domain == "ast_visit" {
                    ast::visit(&ast, trace)
                } else {
                    hir::visit(&hir, trace)
                };
                let e = events.borrow();
                if fail == 0 {
                    size = e.len();
                }
                assert_eq!(result.is_err(), fail > 0);
                emit(
                    domain,
                    &fail.to_string(),
                    p,
                    &format!(
                        "{}\n{}",
                        if result.is_err() { "error" } else { "ok" },
                        e.join("\n")
                    ),
                );
            }
        }
    }
}
#[test]
fn printer_characterization() {
    for byte in 0..=255u8 {
        hir_tree(&hir::Hir::literal([byte]));
    }
    for p in [
        "(?mR)^.$",
        "\\b{start}|\\b{end}|\\b{start-half}|\\b{end-half}",
        "(?-u)\\b{start}|\\b{end}|\\b{start-half}|\\b{end-half}",
        "(?x)a #comment\n b",
        "(?x:[ a-z ])",
        "(?<β>a)",
    ] {
        let ast = ast::parse::Parser::new().parse(p).unwrap();
        emit("ast_print", "-", p, &ast.to_string());
        let hir = crate::ParserBuilder::new()
            .utf8(false)
            .build()
            .parse(p)
            .unwrap();
        emit("hir_print", "-", p, &hir.to_string());
    }
}
#[test]
fn error_kind_messages() {
    let p = ast::Position::new(0, 1, 1);
    let s = ast::Span::splat(p);
    use ast::ErrorKind::*;
    let kinds = [
        CaptureLimitExceeded,
        ClassEscapeInvalid,
        ClassRangeInvalid,
        ClassRangeLiteral,
        ClassUnclosed,
        DecimalEmpty,
        DecimalInvalid,
        EscapeHexEmpty,
        EscapeHexInvalid,
        EscapeHexInvalidDigit,
        EscapeUnexpectedEof,
        EscapeUnrecognized,
        FlagDanglingNegation,
        FlagDuplicate {
            original: s.clone(),
        },
        FlagRepeatedNegation {
            original: s.clone(),
        },
        FlagUnexpectedEof,
        FlagUnrecognized,
        GroupNameDuplicate {
            original: s.clone(),
        },
        GroupNameEmpty,
        GroupNameInvalid,
        GroupNameUnexpectedEof,
        GroupUnclosed,
        GroupUnopened,
        RepetitionCountInvalid,
        RepetitionCountDecimalEmpty,
        RepetitionCountUnclosed,
        RepetitionMissing,
        SpecialWordBoundaryUnclosed,
        SpecialWordBoundaryUnrecognized,
        SpecialWordOrRepetitionUnexpectedEof,
        UnicodeClassInvalid,
        UnsupportedBackreference,
        UnsupportedLookAround,
    ];
    for k in kinds {
        let name = format!("{k:?}")
            .split([' ', '{'])
            .next()
            .unwrap()
            .to_string();
        emit("ast_kind", "-", &name, &k.to_string());
    }
    use hir::ErrorKind::*;
    for k in [
        UnicodeNotAllowed,
        InvalidUtf8,
        InvalidLineTerminator,
        UnicodePropertyNotFound,
        UnicodePropertyValueNotFound,
        UnicodePerlClassNotFound,
        UnicodeCaseUnavailable,
    ] {
        emit("hir_kind", "-", &format!("{k:?}"), &k.to_string());
    }
}
struct LimitedWriter {
    remaining: usize,
    bytes: Vec<u8>,
}
impl std::fmt::Write for LimitedWriter {
    fn write_str(&mut self, s: &str) -> std::fmt::Result {
        let n = s.len().min(self.remaining);
        self.bytes.extend_from_slice(&s.as_bytes()[..n]);
        self.remaining -= n;
        if n < s.len() {
            Err(std::fmt::Error)
        } else {
            Ok(())
        }
    }
}
#[test]
fn printer_errors() {
    for p in [
        "a(b|c)+[a-z&&[^xy]]",
        "(?<β>☃{2,4}?)",
        "\\p{ASCII}",
        "(?-u)[a-\\xFF]",
    ] {
        let ast = ast::parse::Parser::new().parse(p).unwrap();
        let hir = crate::ParserBuilder::new()
            .utf8(false)
            .build()
            .parse(p)
            .unwrap();
        for domain in ["ast_writer", "hir_writer"] {
            let text = if domain == "ast_writer" {
                ast.to_string()
            } else {
                hir.to_string()
            };
            for n in 0..=text.len() + 1 {
                let mut w = LimitedWriter {
                    remaining: n,
                    bytes: Vec::new(),
                };
                let result = if domain == "ast_writer" {
                    ast::print::Printer::new().print(&ast, &mut w)
                } else {
                    hir::print::Printer::new().print(&hir, &mut w)
                };
                assert_eq!(result.is_err(), n < text.len());
                emit(
                    domain,
                    &n.to_string(),
                    p,
                    &format!(
                        "{}\n{}",
                        if result.is_err() { "error" } else { "ok" },
                        hex(&w.bytes)
                    ),
                );
            }
        }
    }
}
#[test]
fn deep_print_and_visit() {
    let count = 50000;
    let s = ast::Span::splat(ast::Position::new(0, 1, 1));
    let mut a = ast::Ast::Literal(std::boxed::Box::new(ast::Literal {
        span: s.clone(),
        kind: ast::LiteralKind::Verbatim,
        c: 'a',
    }));
    let mut h = hir::Hir::literal([b'a']);
    for _ in 0..count {
        a = ast::Ast::Group(std::boxed::Box::new(ast::Group {
            span: s.clone(),
            kind: ast::GroupKind::CaptureIndex(1),
            ast: std::boxed::Box::new(a),
        }));
        h = hir::Hir::capture(hir::Capture {
            index: 1,
            name: None,
            sub: std::boxed::Box::new(h),
        });
    }
    let events = Rc::new(RefCell::new(Vec::new()));
    ast::visit(
        &a,
        Trace {
            events: events.clone(),
            fail: 0,
        },
    )
    .unwrap();
    emit(
        "ast_deep",
        "-",
        &count.to_string(),
        &format!("{}\n{}", a, events.borrow().len()),
    );
    events.borrow_mut().clear();
    hir::visit(
        &h,
        Trace {
            events: events.clone(),
            fail: 0,
        },
    )
    .unwrap();
    emit(
        "hir_deep",
        "-",
        &count.to_string(),
        &format!("{}\n{}", h, events.borrow().len()),
    );
}
#[test]
fn formatter_positions() {
    for (p, coords, aux) in [
        ("abc", [0, 1, 2, 1, 1, 3], None),
        ("abc\n☃d\n", [4, 2, 1, 8, 2, 3], Some([1, 1, 2, 2, 1, 3])),
        ("abc\nx\ny", [0, 1, 1, 6, 3, 1], Some([1, 1, 2, 3, 1, 4])),
        ("abc\nx\ny", [1, 1, 2, 6, 3, 1], Some([0, 1, 1, 5, 2, 2])),
        ("abc\r\nx", [5, 2, 1, 6, 2, 2], None),
        ("abc\r", [0, 1, 1, 1, 1, 2], None),
    ] {
        let make = |c: [usize; 6]| {
            ast::Span::new(
                ast::Position::new(c[0], c[1], c[2]),
                ast::Position::new(c[3], c[4], c[5]),
            )
        };
        let kind = aux.map_or(ast::ErrorKind::ClassUnclosed, |c| {
            ast::ErrorKind::FlagDuplicate { original: make(c) }
        });
        let e = ast::parity_error(kind, p.to_string(), make(coords));
        let config = format!(
            "{};{}",
            span(e.span()),
            e.auxiliary_span().map_or_else(|| "-".into(), span)
        );
        emit("format", &config, p, &e.to_string());
    }
}
#[test]
fn class_range_prints() {
    for p in [
        r"(?-u)[a-\xFF]",
        r"(?i-u)[a-\xFF]",
        r"(?i-u)[Z-\x7F]",
        r"(?-u)[\x00-z]",
        r"(?i-u)[\x00-z]",
        r"(?i-u)[\x41-z]",
        r"(?i-u)[a-\x5A]",
        r"(?i-u)[\x80-\xFF]",
    ] {
        // Reversed bounds deliberately exercise diagnostic formatting too.
        let mut b = crate::ParserBuilder::new();
        b.utf8(false);
        match b.build().parse(p) {
            Ok(h) => emit("hir_print", "-", p, &h.to_string()),
            Err(crate::Error::Parse(e)) => {
                emit("ast_error", "250,false,false,false", p, &ast_error(&e))
            }
            Err(e) => panic!("unexpected translation error: {e}"),
        }
    }
}
#[test]
fn verbose_unicode_diagnostics() {
    for whitespace in [
        '\u{85}', '\u{A0}', '\u{1680}', '\u{2003}', '\u{2028}', '\u{2029}', '\u{202F}', '\u{205F}',
        '\u{3000}',
    ] {
        for p in [
            format!("(?x)a{whitespace}\\q"),
            format!("(?x)[a{whitespace}-\\w]"),
            format!("(?x)[a-{whitespace}]"),
            format!("(?x)a{whitespace}b"),
        ] {
            match ast::parse::Parser::new().parse(&p) {
                Ok(a) => emit("ast_print", "-", &p, &a.to_string()),
                Err(e) => emit("ast_error", "250,false,false,false", &p, &ast_error(&e)),
            }
        }
    }
}
