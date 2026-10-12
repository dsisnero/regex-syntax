// Included only by the temporary pinned Rust source copy. Serialize every AST
// field explicitly; byte offsets and Unicode line/column positions are distinct.
use super::*;
use std::{
    format,
    io::Write,
    string::{String, ToString},
    vec::Vec,
};
fn hex(s: &str) -> String {
    s.as_bytes().iter().map(|b| format!("{b:02x}")).collect()
}
pub fn span(s: &Span) -> String {
    format!(
        "{},{},{},{},{},{}",
        s.start.offset, s.start.line, s.start.column, s.end.offset, s.end.line, s.end.column
    )
}
pub fn flags(f: &ast::Flags) -> String {
    format!(
        "{};{}",
        span(&f.span),
        f.items
            .iter()
            .map(|i| format!("{}:{:?}", span(&i.span), i.kind))
            .collect::<Vec<_>>()
            .join(";")
    )
}
fn lit(l: &ast::Literal) -> String {
    format!("lit({};{:?};{})", span(&l.span), l.kind, l.c as u32)
}
fn unicode(c: &ast::ClassUnicode) -> String {
    let k = match &c.kind {
        ast::ClassUnicodeKind::OneLetter(c) => format!("letter:{}", *c as u32),
        ast::ClassUnicodeKind::Named(n) => format!("named:{}", hex(n)),
        ast::ClassUnicodeKind::NamedValue { op, name, value } => {
            format!("value:{:?}:{}:{}", op, hex(name), hex(value))
        }
    };
    format!("unicode({};{};{})", span(&c.span), c.negated, k)
}
fn perl(c: &ast::ClassPerl) -> String {
    format!("perl({};{:?};{})", span(&c.span), c.kind, c.negated)
}
fn item(i: &ast::ClassSetItem) -> String {
    match i {
        ast::ClassSetItem::Empty(s) => format!("empty({})", span(s)),
        ast::ClassSetItem::Literal(l) => lit(l),
        ast::ClassSetItem::Range(r) => {
            format!("range({};{};{})", span(&r.span), lit(&r.start), lit(&r.end))
        }
        ast::ClassSetItem::Ascii(c) => {
            format!("ascii({};{:?};{})", span(&c.span), c.kind, c.negated)
        }
        ast::ClassSetItem::Unicode(c) => unicode(c),
        ast::ClassSetItem::Perl(c) => perl(c),
        ast::ClassSetItem::Bracketed(c) => bracket(c),
        ast::ClassSetItem::Union(u) => format!(
            "union({};{})",
            span(&u.span),
            u.items.iter().map(item).collect::<Vec<_>>().join(";")
        ),
    }
}
fn set(s: &ast::ClassSet) -> String {
    match s {
        ast::ClassSet::Item(i) => item(i),
        ast::ClassSet::BinaryOp(b) => format!(
            "binary({};{:?};{};{})",
            span(&b.span),
            b.kind,
            set(&b.lhs),
            set(&b.rhs)
        ),
    }
}
pub fn bracket(c: &ast::ClassBracketed) -> String {
    format!("bracket({};{};{})", span(&c.span), c.negated, set(&c.kind))
}
fn shape(a: &Ast) -> String {
    match a {
        Ast::Empty(s) => format!("empty({})", span(s)),
        Ast::Dot(s) => format!("dot({})", span(s)),
        Ast::Literal(l) => lit(l),
        Ast::Assertion(a) => format!("assert({};{:?})", span(&a.span), a.kind),
        Ast::Flags(f) => format!("flags({};{})", span(&f.span), flags(&f.flags)),
        Ast::ClassUnicode(c) => unicode(c),
        Ast::ClassPerl(c) => perl(c),
        Ast::ClassBracketed(c) => bracket(c),
        Ast::Repetition(r) => format!(
            "rep({};{};{:?};{};{})",
            span(&r.span),
            span(&r.op.span),
            r.op.kind,
            r.greedy,
            shape(&r.ast)
        ),
        Ast::Group(g) => {
            let k = match &g.kind {
                ast::GroupKind::CaptureIndex(i) => format!("index:{i}"),
                ast::GroupKind::CaptureName {
                    starts_with_p,
                    name,
                } => format!(
                    "name:{}:{}:{}:{}",
                    starts_with_p,
                    span(&name.span),
                    hex(&name.name),
                    name.index
                ),
                ast::GroupKind::NonCapturing(f) => format!("flags:{}", flags(f)),
            };
            format!("group({};{};{})", span(&g.span), k, shape(&g.ast))
        }
        Ast::Concat(c) => format!(
            "concat({};{})",
            span(&c.span),
            c.asts.iter().map(shape).collect::<Vec<_>>().join(";")
        ),
        Ast::Alternation(c) => format!(
            "alt({};{})",
            span(&c.span),
            c.asts.iter().map(shape).collect::<Vec<_>>().join(";")
        ),
    }
}
std::thread_local! {static BUSY: std::cell::Cell<bool> = const {std::cell::Cell::new(false)};}
pub fn record(p: &Parser, pattern: &str) {
    let thread = std::thread::current();
    let test = thread.name().unwrap_or("-");
    let loop_case = (test.ends_with("::parse_hex_two")
        && pattern.len() == 4
        && pattern.starts_with("\\x"))
        || (test.ends_with("::parse_hex_four") && pattern.len() == 6 && pattern.starts_with("\\u"))
        || (test.ends_with("::parse_hex_eight")
            && pattern.len() == 10
            && pattern.starts_with("\\U"));
    if loop_case
        && pattern[2..]
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return;
    }
    if BUSY.with(|b| b.replace(true)) {
        return;
    }
    let mut parser = ParserBuilder::new()
        .nest_limit(p.nest_limit)
        .octal(p.octal)
        .empty_min_range(p.empty_min_range)
        .ignore_whitespace(p.initial_ignore_whitespace)
        .build();
    let result = match parser.parse_with_comments(pattern) {
        Ok(c) => format!(
            "{}\n{}",
            shape(&c.ast),
            c.comments
                .iter()
                .map(|c| format!("{}:{}", span(&c.span), hex(&c.comment)))
                .collect::<Vec<_>>()
                .join(";")
        ),
        Err(e) => format!(
            "error:{};{};{}",
            format!("{:?}", e.kind()).split(['(', ' ']).next().unwrap(),
            span(e.span()),
            e.auxiliary_span()
                .map(span)
                .unwrap_or_else(|| "-".to_string())
        ),
    };
    if let Ok(path) = std::env::var("REGEX_AST_CAPTURE") {
        let mut file = std::fs::OpenOptions::new().append(true).open(path).unwrap();
        writeln!(
            file,
            "{}\t{},{},{},{}\t{}\t{}",
            std::thread::current().name().unwrap_or("-"),
            p.nest_limit,
            p.octal,
            p.empty_min_range,
            p.initial_ignore_whitespace,
            hex(pattern),
            hex(&result)
        )
        .unwrap();
    }
    BUSY.with(|b| b.set(false));
}
std::thread_local! {static SEEN: std::cell::RefCell<std::collections::HashSet<u32>> = std::cell::RefCell::new(std::collections::HashSet::new());}
pub fn assertion(line: u32) {
    if !SEEN.with(|s| s.borrow_mut().insert(line)) {
        return;
    }
    if let Ok(path) = std::env::var("REGEX_AST_ASSERTIONS") {
        let mut f = std::fs::OpenOptions::new().append(true).open(path).unwrap();
        writeln!(
            f,
            "{}\t{}",
            std::thread::current().name().unwrap_or("-"),
            line
        )
        .unwrap();
    }
}
pub fn helper<P: Borrow<Parser>>(
    p: &ParserI<'_, P>,
    operation: &str,
    result: &str,
    before: Position,
) {
    if BUSY.with(|b| b.get()) {
        return;
    }
    let thread = std::thread::current();
    let name = thread.name().unwrap_or("-");
    let target = if operation == "parse_primitive" {
        "parse_primitive_non_escape"
    } else {
        operation
    };
    if operation == "parse_escape" {
        if !(name.contains("::parse_hex_")
            || name.ends_with("::parse_escape")
            || name.ends_with("::parse_octal")
            || name.ends_with("::parse_perl_class")
            || name.ends_with("::parse_unicode_class")
            || name.ends_with("::parse_unsupported_backreference"))
        {
            return;
        }
        let pattern = p.pattern();
        let loop_case =
            (name.ends_with("::parse_hex_two") && pattern.len() == 4 && pattern.starts_with("\\x"))
                || (name.ends_with("::parse_hex_four")
                    && pattern.len() == 6
                    && pattern.starts_with("\\u"))
                || (name.ends_with("::parse_hex_eight")
                    && pattern.len() == 10
                    && pattern.starts_with("\\U"));
        if loop_case
            && pattern[2..]
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        {
            return;
        }
    } else if !name.ends_with(&format!("::{target}")) {
        return;
    }
    let parser = p.parser();
    let mut f = std::fs::OpenOptions::new()
        .append(true)
        .open(std::env::var("REGEX_AST_HELPERS").unwrap())
        .unwrap();
    writeln!(
        f,
        "{}\t{},{},{},{}\t{}\t{}\t{}\t{}",
        operation,
        parser.nest_limit,
        parser.octal,
        parser.empty_min_range,
        parser.ignore_whitespace.get(),
        hex(p.pattern()),
        hex(result),
        span(&Span::splat(p.pos())),
        before.offset
    )
    .unwrap();
}
pub fn error(e: &ast::Error) -> String {
    format!(
        "error:{};{};{}",
        format!("{:?}", e.kind()).split(['(', ' ']).next().unwrap(),
        span(e.span()),
        e.auxiliary_span()
            .map(span)
            .unwrap_or_else(|| "-".to_string())
    )
}
pub fn primitive(p: &Primitive) -> String {
    shape(&p.clone().into_ast())
}
pub fn opening(pair: &(ast::ClassBracketed, ast::ClassSetUnion)) -> String {
    format!(
        "{}\n{}",
        bracket(&pair.0),
        format!(
            "union({};{})",
            span(&pair.1.span),
            pair.1.items.iter().map(item).collect::<Vec<_>>().join(";")
        )
    )
}
