use regex_syntax::hir::LookSet;
fn hex(text: &str) -> String {
    text.as_bytes().iter().map(|b| format!("{b:02x}")).collect()
}
fn main() {
    assert_eq!(u32::MAX, LookSet::full().bits);
    assert_eq!(32, LookSet::full().len());
    assert_eq!(18, LookSet::full().iter().count());
    let masks = [
        0,
        u32::MAX,
        (1 << 18) - 1,
        1 << 18,
        1 << 31,
        0x80000001,
        0xaaaaaaaa,
        0x55555555,
    ];
    for bits in masks.into_iter().chain((0..32).map(|i| 1u32 << i)) {
        let set = LookSet { bits };
        let mut bytes = [0; 4];
        set.write_repr(&mut bytes);
        assert_eq!(set, LookSet::read_repr(&bytes));
        println!(
            "look\t{bits}\t{};{};{};{};{}",
            set.bits,
            set.len(),
            set.iter().count(),
            hex(&format!("{set:?}")),
            bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
        );
    }
    for (start, end) in [(0, 0), (0, 255), (255, 0), (255, 255), (1, 255), (254, 255)] {
        let range = regex_syntax::hir::ClassBytesRange::new(start, end);
        println!(
            "range\tbyte:{start}:{end}\t{};{};{}",
            range.start(),
            range.end(),
            range.len()
        );
    }
    for (start, end) in [(0, 0), (0, 0x10ffff), (0x10ffff, 0), (0xd7ff, 0xe000)] {
        let range = regex_syntax::hir::ClassUnicodeRange::new(
            char::from_u32(start).unwrap(),
            char::from_u32(end).unwrap(),
        );
        println!(
            "range\tunicode:{start}:{end}\t{};{};{}",
            range.start() as u32,
            range.end() as u32,
            range.len()
        );
    }
    for n in 0..=255u32 {
        let c = char::from_u32(n).unwrap();
        println!(
            "char\t{n}\t{};{};{};{}",
            regex_syntax::is_meta_character(c),
            regex_syntax::is_escapeable_character(c),
            regex_syntax::is_word_byte(n as u8),
            regex_syntax::is_word_character(c)
        );
    }
}
