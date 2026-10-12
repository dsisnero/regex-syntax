// Compile directly against the pinned vendored crate; no registry dependencies.
use std::io::{self, BufRead};

fn optional(value: Option<usize>) -> String {
    value.map_or_else(|| "-".to_owned(), |value| value.to_string())
}

fn look_bits(set: regex_syntax::hir::LookSet) -> u32 {
    let mut bytes = [0; 4];
    set.write_repr(&mut bytes);
    u32::from_ne_bytes(bytes)
}

fn properties(hir: &regex_syntax::hir::Hir) -> String {
    let props = hir.properties();
    format!(
        "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
        optional(props.minimum_len()),
        optional(props.maximum_len()),
        props.is_utf8(),
        props.explicit_captures_len(),
        optional(props.static_explicit_captures_len()),
        props.is_literal(),
        props.is_alternation_literal(),
        look_bits(props.look_set()),
        look_bits(props.look_set_prefix()),
        look_bits(props.look_set_prefix_any()),
        look_bits(props.look_set_suffix()),
        look_bits(props.look_set_suffix_any())
    )
}

fn main() {
    let property_mode = std::env::args().any(|arg| arg == "--properties");
    for line in io::stdin().lock().lines() {
        let line = line.unwrap();
        let (mode, encoded) = line.split_once('\t').unwrap();
        let bytes: Vec<u8> = encoded
            .as_bytes()
            .chunks_exact(2)
            .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
            .collect();
        let pattern = String::from_utf8(bytes).unwrap();
        let result = regex_syntax::ParserBuilder::new()
            .octal(true)
            .utf8(mode != "bytes")
            .build()
            .parse(&pattern);
        match result {
            Ok(hir) => println!(
                "{}",
                (if property_mode {
                    properties(&hir)
                } else {
                    hir.to_string()
                })
                .as_bytes()
                .iter()
                .map(|byte| format!("{:02x}", byte))
                .collect::<String>()
            ),
            Err(_) => println!("ERROR"),
        }
    }
}
