// Compile directly against the pinned vendored crate; no registry dependencies.
use std::io::{self, BufRead};
fn main() {
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
                hir.to_string()
                    .as_bytes()
                    .iter()
                    .map(|byte| format!("{:02x}", byte))
                    .collect::<String>()
            ),
            Err(_) => println!("ERROR"),
        }
    }
}
