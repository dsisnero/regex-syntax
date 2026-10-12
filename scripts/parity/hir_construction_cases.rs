// Characterization of public Rust smart constructors and their compositions.
#[test]
fn parity_construction_cases() {
    use std::{format, string::String};
    let atoms = vec![
        Hir::empty(),
        Hir::fail(),
        Hir::literal(b"a".as_slice()),
        Hir::literal("β".as_bytes()),
        hir_capture(1, Hir::empty()),
        hir_capture_name(2, "name", hir_lit("ab")),
        hir_look(hir::Look::WordUnicode),
        hir_uclass(&[('a', 'z')]),
        hir_bclass(&[(255, 255)]),
        hir_uclass(&[('c', 'c')]),
        hir_uclass(&[]),
        hir_negate(hir_uclass(&[('\0', 'b'), ('d', '\u{10ffff}')])),
    ];
    let translator = Translator::new();
    let emit = |id: String, hir: Hir| parity_snapshot::record(&translator, &id, &Ok(hir));
    for (i, atom) in atoms.iter().enumerate() {
        emit(format!("atom/{i}"), atom.clone());
        emit(
            format!("singleton-alt/{i}"),
            Hir::alternation(vec![atom.clone()]),
        );
        emit(
            format!("singleton-cat/{i}"),
            Hir::concat(vec![atom.clone()]),
        );
        for (j, other) in atoms.iter().enumerate() {
            parity_snapshot::record_properties(
                &translator,
                &format!("union/{i}/{j}"),
                &Properties::union([atom.properties(), other.properties()]),
            );
            emit(
                format!("alt/{i}/{j}"),
                Hir::alternation(vec![atom.clone(), other.clone()]),
            );
            emit(
                format!("cat/{i}/{j}"),
                Hir::concat(vec![atom.clone(), other.clone()]),
            );
        }
        for (k, (min, max)) in [
            (0, None),
            (1, None),
            (2, None),
            (0, Some(0)),
            (1, Some(1)),
            (2, Some(3)),
            (0, Some(1)),
            (4, Some(9)),
        ]
        .iter()
        .enumerate()
        {
            emit(
                format!("rep/{i}/{k}"),
                hir_range(k % 2 == 0, *min, *max, atom.clone()),
            );
        }
    }
    for i in 0..atoms.len() {
        let nested = hir_quest(false, hir_plus(true, atoms[i].clone()));
        emit(format!("nested/{i}"), nested);
    }
    emit("empty-alt".into(), Hir::alternation(vec![]));
    emit("empty-cat".into(), Hir::concat(vec![]));
    emit("empty-literal".into(), Hir::literal(Vec::<u8>::new()));
    for (i, dot) in [
        hir::Dot::AnyChar,
        hir::Dot::AnyCharExceptLF,
        hir::Dot::AnyCharExceptCRLF,
        hir::Dot::AnyByte,
        hir::Dot::AnyByteExceptLF,
        hir::Dot::AnyByteExceptCRLF,
    ]
    .into_iter()
    .enumerate()
    {
        emit(format!("dot/{i}"), Hir::dot(dot));
    }
    let big = hir_range(true, u32::MAX, Some(u32::MAX), hir_lit("a"));
    let square = hir_range(true, u32::MAX, Some(u32::MAX), big.clone());
    emit(
        "overflow/add".into(),
        hir_cat(vec![square.clone(), square.clone()]),
    );
    emit("overflow/mul".into(), hir_range(true, 2, Some(2), square));
    emit(
        "prefix".into(),
        hir_cat(vec![
            hir_look(Look::Start),
            hir_quest(true, hir_look(Look::WordUnicode)),
            hir_lit("a"),
            hir_look(Look::End),
        ]),
    );
}
