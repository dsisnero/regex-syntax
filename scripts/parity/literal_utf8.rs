use super::{ExtractKind, Extractor, Literal, Seq};
use std::{
    cell::{Cell, RefCell},
    format,
    io::Write,
    string::{String, ToString},
    vec::Vec,
};
std::thread_local! {
    static DEPTH:Cell<usize>=const {Cell::new(0)};
    static PATTERN:RefCell<String>=const {RefCell::new(String::new())};
    static ASSERTIONS:RefCell<std::collections::BTreeSet<String>>=const {RefCell::new(std::collections::BTreeSet::new())};
}
pub fn enter() -> bool {
    DEPTH.with(|d| {
        let old = d.get();
        d.set(old + 1);
        old == 0
    })
}
pub fn leave() {
    DEPTH.with(|d| d.set(d.get() - 1));
}
pub fn set_pattern(pattern: &str) {
    PATTERN.with(|p| *p.borrow_mut() = pattern.into());
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
pub fn literal(l: &Literal) -> String {
    format!(
        "{}{}",
        if l.is_exact() { "E" } else { "I" },
        hex(l.as_bytes())
    )
}
pub fn shape(s: &Seq) -> String {
    match s.literals() {
        None => "inf".into(),
        Some(l) if l.is_empty() => "empty".into(),
        Some(l) => l.iter().map(literal).collect::<Vec<_>>().join(","),
    }
}
fn optional(n: Option<usize>) -> String {
    n.map_or_else(|| "-".into(), |n| n.to_string())
}
fn optional_bytes(b: Option<&[u8]>) -> String {
    b.map_or_else(|| "-".into(), |b| format!("x{}", hex(b)))
}
pub fn snapshot(s: &Seq) -> String {
    format!(
        "{};{};{};{};{};{};{};{};{}",
        shape(s),
        s.is_finite(),
        s.is_exact(),
        s.is_inexact(),
        optional(s.len()),
        optional(s.min_literal_len()),
        optional(s.max_literal_len()),
        optional_bytes(s.longest_common_prefix()),
        optional_bytes(s.longest_common_suffix())
    )
}
fn record(kind: &str, op: &str, input: String, arg: String, expected: String, other: String) {
    let mut f = std::fs::OpenOptions::new()
        .append(true)
        .open(std::env::var("REGEX_LITERAL_CAPTURE").unwrap())
        .unwrap();
    writeln!(f, "{kind}\t{op}\t{input}\t{arg}\t{expected}\t{other}").unwrap();
}
pub fn assertion(path: &str, line: u32) {
    let key = format!("{}:{line}", path.split("/src/").last().unwrap());
    // The native single-scalar loop executes this assertion over a million times.
    if !ASSERTIONS.with(|seen| seen.borrow_mut().insert(key.clone())) {
        return;
    }
    let mut f = std::fs::OpenOptions::new()
        .append(true)
        .open(std::env::var("REGEX_LITERAL_ASSERTIONS").unwrap())
        .unwrap();
    writeln!(f, "{key}").unwrap();
}
pub fn extract(e: &Extractor, result: &Seq) {
    let config = format!(
        "{:?},{},{},{},{}",
        e.kind, e.limit_class, e.limit_repeat, e.limit_literal_len, e.limit_total
    );
    PATTERN.with(|p| {
        record(
            "extract",
            &config,
            hex(p.borrow().as_bytes()),
            "-".into(),
            snapshot(result),
            "-".into(),
        )
    });
}
pub fn operation(op: &str, before: String, arg: String, result: &Seq, other: String) {
    if DEPTH.with(|d| d.get() > 0) {
        return;
    }
    record("seq", op, before, arg, snapshot(result), other);
}
fn parse(pattern: &str) -> crate::hir::Hir {
    set_pattern(pattern);
    crate::ParserBuilder::new()
        .utf8(false)
        .build()
        .parse(pattern)
        .unwrap()
}
#[test]
fn extraction_limits() {
    for limit in [2049, 2050, 4096] {
        for kind in [ExtractKind::Prefix, ExtractKind::Suffix] {
            Extractor::new()
                .kind(kind)
                .limit_class(limit)
                .extract(&parse(r"[\u{D7FF}-\u{E000}]"));
        }
    }
    for (negated, ranges) in [
        (false, std::vec![]),
        (false, std::vec![('a', 'a')]),
        (true, std::vec![('\0', '\u{10ffff}')]),
        (true, std::vec![('\0', '`'), ('b', '\u{10ffff}')]),
    ] {
        let mut class = crate::hir::ClassUnicode::new(
            ranges
                .iter()
                .map(|&(a, b)| crate::hir::ClassUnicodeRange::new(a, b)),
        );
        if negated {
            class.negate();
        }
        let hir = crate::hir::Hir::class(crate::hir::Class::Unicode(class));
        let result = Extractor::new().parity_original_extract(&hir);
        record(
            "direct_u",
            "extract",
            if ranges.is_empty() {
                "empty".into()
            } else {
                ranges
                    .iter()
                    .map(|&(a, b)| format!("{}-{}", a as u32, b as u32))
                    .collect::<Vec<_>>()
                    .join(",")
            },
            negated.to_string(),
            snapshot(&result),
            "-".into(),
        );
    }
    for (negated, ranges) in [
        (false, std::vec![]),
        (false, std::vec![(255, 255)]),
        (true, std::vec![(0, 255)]),
        (true, std::vec![(0, 254)]),
    ] {
        let mut class = crate::hir::ClassBytes::new(
            ranges
                .iter()
                .map(|&(a, b)| crate::hir::ClassBytesRange::new(a, b)),
        );
        if negated {
            class.negate();
        }
        let result = Extractor::new()
            .parity_original_extract(&crate::hir::Hir::class(crate::hir::Class::Bytes(class)));
        record(
            "direct_b",
            "extract",
            if ranges.is_empty() {
                "empty".into()
            } else {
                ranges
                    .iter()
                    .map(|&(a, b)| format!("{a}-{b}"))
                    .collect::<Vec<_>>()
                    .join(",")
            },
            negated.to_string(),
            snapshot(&result),
            "-".into(),
        );
    }

    for pattern in [
        "",
        "abc",
        "a|ab",
        "a|",
        "[ab]{2}{2}",
        "[abc]+z",
        "a{0,3}",
        "a{1,3}?",
        "(?:a|bc){2,4}",
        "(?i)Holmes",
        "☃[ab]☃",
        r"(?-u:\xFF)[ab]",
        "[a&&b]",
        "x.*y",
        "a.*|bc",
        "a(?:|b)c",
    ] {
        for kind in [ExtractKind::Prefix, ExtractKind::Suffix] {
            for limit in [0, 1, 2, 3, 10, 100, 250] {
                for setting in 0..4 {
                    let mut e = Extractor::new();
                    e.kind(kind.clone());
                    match setting {
                        0 => {
                            e.limit_class(limit);
                        }
                        1 => {
                            e.limit_repeat(limit);
                        }
                        2 => {
                            e.limit_literal_len(limit);
                        }
                        _ => {
                            e.limit_total(limit);
                        }
                    };
                    e.extract(&parse(pattern));
                }
            }
        }
    }
}
#[test]
fn sequence_algebra() {
    for byte in 0..=255u8 {
        record(
            "rank",
            "rank",
            byte.to_string(),
            "-".into(),
            super::rank(byte).to_string(),
            "-".into(),
        );
        for exact in [false, true] {
            let lit = if exact {
                Literal::exact(std::vec![byte])
            } else {
                Literal::inexact(std::vec![byte])
            };
            for op in [
                "properties",
                "make_inexact",
                "reverse",
                "keep_first_bytes",
                "keep_last_bytes",
                "extend",
            ] {
                let mut result = lit.clone();
                let arg = Literal::inexact(std::vec![0xff, 0]);
                match op {
                    "make_inexact" => result.make_inexact(),
                    "reverse" => result.reverse(),
                    "keep_first_bytes" => result.keep_first_bytes(0),
                    "keep_last_bytes" => result.keep_last_bytes(0),
                    "extend" => result.extend(&arg),
                    _ => {}
                };
                record(
                    "literal",
                    op,
                    literal(&lit),
                    if op == "extend" {
                        literal(&arg)
                    } else {
                        "0".into()
                    },
                    format!(
                        "{};{};{};{}",
                        literal(&result),
                        result.len(),
                        result.is_empty(),
                        result.is_poisonous()
                    ),
                    "-".into(),
                );
            }
        }
    }

    let states = [
        Seq::infinite(),
        Seq::empty(),
        Seq::singleton(Literal::exact("")),
        Seq::singleton(Literal::inexact("")),
        Seq::new(["a"]),
        Seq::singleton(Literal::inexact("a")),
        Seq::new(["a", "ab", "a"]),
        Seq::from_iter([Literal::exact("a"), Literal::inexact("a")]),
        Seq::new(["foobar", "foobaz"]),
        Seq::new(["☃", "☃a"]),
        Seq::new([&b"\xff\x00"[..], &b"\xff\x01"[..]]),
    ];
    for a in &states {
        operation("properties", shape(a), "-".into(), a, "-".into());
        for b in &states {
            record(
                "bounds",
                "max_lengths",
                shape(a),
                shape(b),
                format!(
                    "{};{}",
                    optional(a.max_union_len(b)),
                    optional(a.max_cross_len(b))
                ),
                "-".into(),
            );
            for op in 0..4 {
                let (mut a, mut b) = (a.clone(), b.clone());
                match op {
                    0 => a.cross_forward(&mut b),
                    1 => a.cross_reverse(&mut b),
                    2 => a.union(&mut b),
                    _ => a.union_into_empty(&mut b),
                };
            }
        }
        for length in [0, 1, 2, 3, 6, 100] {
            let mut copy = a.clone();
            copy.keep_first_bytes(length);
            let mut copy = a.clone();
            copy.keep_last_bytes(length);
        }
        for op in 0..8 {
            let mut copy = a.clone();
            match op {
                0 => copy.make_inexact(),
                1 => copy.make_infinite(),
                2 => copy.dedup(),
                3 => copy.sort(),
                4 => copy.reverse_literals(),
                5 => copy.minimize_by_preference(),
                6 => copy.optimize_for_prefix_by_preference(),
                _ => copy.optimize_for_suffix_by_preference(),
            };
        }
        for lit in [
            Literal::exact(""),
            Literal::exact("a"),
            Literal::inexact("a"),
            Literal::exact("ab"),
        ] {
            a.clone().push(lit);
        }
    }
}
#[test]
fn utf8_boundaries() {
    let points = [
        0, 1, 0x3f, 0x40, 0x7e, 0x7f, 0x80, 0x81, 0xbf, 0xc0, 0x7fe, 0x7ff, 0x800, 0x801, 0xfff,
        0x1000, 0xd7fe, 0xd7ff, 0xe000, 0xe001, 0xfffe, 0xffff, 0x10000, 0x10001, 0x3ffff, 0x40000,
        0xfffff, 0x100000, 0x10fffe, 0x10ffff,
    ];
    for start in points {
        for end in points {
            let result = crate::utf8::Utf8Sequences::new(
                char::from_u32(start).unwrap(),
                char::from_u32(end).unwrap(),
            )
            .map(|s| {
                s.as_slice()
                    .iter()
                    .map(|r| format!("{}-{}", r.start, r.end))
                    .collect::<Vec<_>>()
                    .join(",")
            })
            .collect::<Vec<_>>()
            .join(";");
            record(
                "utf8",
                "ranges",
                start.to_string(),
                end.to_string(),
                if result.is_empty() {
                    "empty".into()
                } else {
                    result.clone()
                },
                "-".into(),
            );
            let mut iterator = crate::utf8::Utf8Sequences::new('\0', '\u{10ffff}');
            let _ = iterator.next();
            iterator.reset(char::from_u32(start).unwrap(), char::from_u32(end).unwrap());
            let reset = iterator
                .map(|s| {
                    s.as_slice()
                        .iter()
                        .map(|r| format!("{}-{}", r.start, r.end))
                        .collect::<Vec<_>>()
                        .join(",")
                })
                .collect::<Vec<_>>()
                .join(";");
            record(
                "utf8_reset",
                "ranges",
                start.to_string(),
                end.to_string(),
                if reset.is_empty() {
                    "empty".into()
                } else {
                    reset
                },
                "-".into(),
            );
        }
    }
    for scalar in (0..=0x10ffff).filter_map(char::from_u32) {
        let sequences: Vec<_> = crate::utf8::Utf8Sequences::new(scalar, scalar).collect();
        let mut buffer = [0; 4];
        let bytes = scalar.encode_utf8(&mut buffer).as_bytes();
        assert_eq!(sequences.len(), 1);
        assert_eq!(sequences[0].as_slice().len(), bytes.len());
        for (range, byte) in sequences[0].as_slice().iter().zip(bytes) {
            assert_eq!((range.start, range.end), (*byte, *byte));
        }
    }
}
