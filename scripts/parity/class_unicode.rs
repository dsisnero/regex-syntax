use crate::hir::{ClassUnicode, ClassBytes, ClassUnicodeRange, ClassBytesRange};
use std::{format, string::{String,ToString},vec::Vec,io::Write};
pub fn record(kind:&str, op:&str, a:String, b:String, expected:String) {
    let mut f=std::fs::OpenOptions::new().append(true).open(std::env::var("REGEX_CLASS_CAPTURE").unwrap()).unwrap();
    writeln!(f,"{kind}\t{op}\t{a}\t{b}\t{expected}").unwrap();
}
pub fn assertion(path:&str,line:u32) {
    let path=path.split("/src/").last().unwrap();
    let mut f=std::fs::OpenOptions::new().append(true).open(std::env::var("REGEX_CLASS_ASSERTIONS").unwrap()).unwrap();
    writeln!(f,"{path}:{line}").unwrap();
}
pub fn uraw(r:&[(char,char)])->String {r.iter().map(|&(s,e)|format!("{}-{}",s as u32,e as u32)).collect::<Vec<_>>().join(",")}
pub fn braw(r:&[(u8,u8)])->String {r.iter().map(|&(s,e)|format!("{s}-{e}")).collect::<Vec<_>>().join(",")}
pub fn uranges(c:&ClassUnicode)->String {c.iter().map(|r|format!("{}-{}",r.start() as u32,r.end() as u32)).collect::<Vec<_>>().join(",")}
pub fn branges(c:&ClassBytes)->String {c.iter().map(|r|format!("{}-{}",r.start(),r.end())).collect::<Vec<_>>().join(",")}
fn optional(v:Option<usize>)->String {v.map_or_else(||"-".into(),|n|n.to_string())}
fn uclass(r:&[(char,char)])->ClassUnicode {ClassUnicode::new(r.iter().map(|&(s,e)|ClassUnicodeRange::new(s,e)))}
fn bclass(r:&[(u8,u8)])->ClassBytes {ClassBytes::new(r.iter().map(|&(s,e)|ClassBytesRange::new(s,e)))}
fn query(p:&str,v:Option<&str>) {
    use crate::unicode::{class,ClassQuery};
    let q=match v {Some(value)=>ClassQuery::ByValue{property_name:p,property_value:value},None=>ClassQuery::Binary(p)};
    let result=match class(q) {Ok(c)=>uranges(&c),Err(e)=>format!("error:{e:?}")};
    record("query","class",p.into(),v.unwrap_or("").into(),result);
    let pattern=match v {Some(value)=>format!("\\p{{{p}={value}}}"),None=>format!("\\p{{{p}}}")};
    let parsed=match crate::Parser::new().parse(&pattern) {
        Ok(h)=>match h.kind() {
            crate::hir::HirKind::Class(crate::hir::Class::Unicode(c))=>format!("class:{}",uranges(c)),
            crate::hir::HirKind::Literal(l)=>format!("literal:{}",l.0.iter().map(|b|format!("{b:02x}")).collect::<String>()),
            other=>panic!("Unexpected parsed property: {other:?}"),
        },
        Err(crate::Error::Translate(e))=>format!("translate:{:?};{};{};{};{};{};{}",e.kind(),e.span().start.offset,e.span().start.line,e.span().start.column,e.span().end.offset,e.span().end.line,e.span().end.column),
        Err(crate::Error::Parse(e))=>format!("parse:{:?};{};{};{};{};{};{}",e.kind(),e.span().start.offset,e.span().start.line,e.span().start.column,e.span().end.offset,e.span().end.line,e.span().end.column),
    };
    record("parsed","class",pattern,"".into(),parsed);
}
#[test]
fn tables_and_queries() {
    use crate::unicode_tables as t;
    for (name,tables) in [("age",t::age::BY_NAME),("general_category",t::general_category::BY_NAME),("script",t::script::BY_NAME),("script_extension",t::script_extension::BY_NAME),("property_bool",t::property_bool::BY_NAME),("grapheme_cluster_break",t::grapheme_cluster_break::BY_NAME),("word_break",t::word_break::BY_NAME),("sentence_break",t::sentence_break::BY_NAME)] {
        for &(key,ranges) in tables {record("table",name,key.into(),"".into(),uraw(ranges));}
    }
    record("table","perl_word","PERL_WORD".into(),"".into(),uraw(t::perl_word::PERL_WORD));
    for &(alias,name) in t::property_names::PROPERTY_NAMES {
        record("alias","name",alias.into(),"".into(),name.into());
        query(alias,None);
        query(alias,Some("__invalid__"));
    }
    for &(property,values) in t::property_values::PROPERTY_VALUES {
        for &(alias,value) in values {
            record("alias","value",property.into(),alias.into(),value.into());
            query(property,Some(alias));
            if property=="General_Category" || property=="Script" {query(alias,None);}
        }
    }
    for name in ["C","Other","Any","Assigned","ASCII","Is_Greek","isc","is c","Word","word","__invalid__"] {query(name,None);}
    for (p,v) in [("gc","Any"),("gc","ASCII"),("gc","Assigned"),("unknown","Greek"),("scx","Greek"),("age","unassigned")] {query(p,Some(v));}
    let mut folder=crate::unicode::SimpleCaseFolder::new().unwrap();
    for &(c,mapping) in t::case_folding_simple::CASE_FOLDING_SIMPLE {
        assert_eq!(folder.mapping(c),mapping);
        record("fold","mapping",(c as u32).to_string(),"".into(),mapping.iter().map(|c|(*c as u32).to_string()).collect::<Vec<_>>().join(","));
    }
}
#[test]
fn class_boundaries_and_conversion() {
    for ch in ['k','K','K','☃'] {
        let mut c=uclass(&[(ch,ch)]); c.negate();c.case_fold_simple();
        record("u","negated_case_fold_simple",uraw(&[(ch,ch)]),"".into(),uranges(&c));
    }
    for byte in [b'k',b'K',b'!'] {
        let mut c=bclass(&[(byte,byte)]);c.negate();c.case_fold_simple();
        record("b","negated_case_fold_simple",braw(&[(byte,byte)]),"".into(),branges(&c));
    }
    let unicode=[std::vec![],std::vec![('\0','\u{10FFFF}')],std::vec![('\0','\u{7f}')],std::vec![('\u{80}','\u{80}')],std::vec![('\u{7ff}','\u{800}')],std::vec![('\u{d7ff}','\u{e000}')],std::vec![('\u{ffff}','\u{10000}')],std::vec![('k','k')],std::vec![('\u{10ffff}','\u{10ffff}')]];
    for r in &unicode {
        let c=uclass(r);
        let props=format!("{};{};{};{}",c.is_ascii(),optional(c.minimum_len()),optional(c.maximum_len()),c.to_byte_class().map_or_else(||"none".into(),|c|branges(&c)));
        record("u","properties",uraw(r),"".into(),props);
        for other in &unicode {
            for op in ["union","intersect","difference","symmetric_difference"] {
                let mut result=c.clone();let b=uclass(other);
                match op {"union"=>result.union(&b),"intersect"=>result.intersect(&b),"difference"=>result.difference(&b),_=>result.symmetric_difference(&b)};
                record("u",op,uraw(r),uraw(other),uranges(&result));
            }
        }
    }
    for r in [std::vec![],std::vec![(0,255)],std::vec![(0,127)],std::vec![(128,128)],std::vec![(255,255)],std::vec![(b'k',b'k')]] {
        let c=bclass(&r);
        let props=format!("{};{};{};{}",c.is_ascii(),optional(c.minimum_len()),optional(c.maximum_len()),c.to_unicode_class().map_or_else(||"none".into(),|c|uranges(&c)));
        record("b","properties",braw(&r),"".into(),props);
    }
}
