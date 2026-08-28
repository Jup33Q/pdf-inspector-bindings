//! memcli: thin CLI over ffi-core's mem-only API, used to verify output
//! alignment with the official `pdf2md` / `detect-pdf` CLIs.
//!
//! File IO happens here (host-language side); ffi-core itself only sees `&[u8]`.
//!
//! Usage:
//!   memcli md       <file>          -> raw markdown (aligns with `pdf2md --raw`)
//!   memcli detect   <file>          -> JSON  (aligns with `detect-pdf --json` core fields)
//!   memcli classify <file>          -> JSON
//!   memcli pages    <file> [p ...]  -> JSON per-page markdown (0-indexed args)

use ffi_core::{FfiError, FfiPdfType};
use std::{env, fs, process};

fn pdf_type_str(t: FfiPdfType) -> &'static str {
    match t {
        FfiPdfType::TextBased => "text_based",
        FfiPdfType::Scanned => "scanned",
        FfiPdfType::ImageBased => "image_based",
        FfiPdfType::Mixed => "mixed",
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 16);
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c < '\x20' => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn fail(e: FfiError) -> ! {
    println!(
        r#"{{"error":"{}","code":"{:?}"}}"#,
        json_escape(&e.message),
        e.code
    );
    process::exit(1)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: memcli <md|detect|classify|pages> <file> [pages...]");
        process::exit(2);
    }
    let cmd = &args[1];
    let data = fs::read(&args[2]).unwrap_or_else(|e| {
        eprintln!("read {}: {e}", args[2]);
        process::exit(2);
    });

    match cmd.as_str() {
        "md" => match ffi_core::process_pdf_mem(&data) {
            Ok(r) => print!("{}", r.markdown.unwrap_or_default()),
            Err(e) => fail(e),
        },
        "detect" => match ffi_core::detect_pdf_mem(&data) {
            Ok(r) => println!(
                concat!(
                    r#"{{"pdf_type":"{}","page_count":{},"confidence":{},"#,
                    r#""pages_needing_ocr":{:?},"is_complex":{},"#,
                    r#""pages_with_tables":{:?},"pages_with_columns":{:?},"#,
                    r#""has_encoding_issues":{},"processing_time_ms":{}}}"#
                ),
                pdf_type_str(r.pdf_type),
                r.page_count,
                r.confidence,
                r.pages_needing_ocr,
                r.is_complex,
                r.pages_with_tables,
                r.pages_with_columns,
                r.has_encoding_issues,
                r.processing_time_ms,
            ),
            Err(e) => fail(e),
        },
        "classify" => match ffi_core::classify_pdf_mem(&data) {
            Ok(c) => println!(
                r#"{{"pdf_type":"{}","page_count":{},"confidence":{},"pages_needing_ocr":{:?}}}"#,
                pdf_type_str(c.pdf_type),
                c.page_count,
                c.confidence,
                c.pages_needing_ocr,
            ),
            Err(e) => fail(e),
        },
        "pages" => {
            let pages: Option<Vec<u32>> = if args.len() > 3 {
                Some(args[3..].iter().map(|a| a.parse().unwrap()).collect())
            } else {
                None
            };
            match ffi_core::extract_pages_markdown_mem(&data, pages.as_deref()) {
                Ok(r) => {
                    let items: Vec<String> = r
                        .pages
                        .iter()
                        .map(|p| {
                            format!(
                                r#"{{"page":{},"needs_ocr":{},"ocr_reason":{},"markdown":"{}"}}"#,
                                p.page,
                                p.needs_ocr,
                                p.ocr_reason
                                    .as_ref()
                                    .map(|r| format!(r#""{}""#, json_escape(r)))
                                    .unwrap_or_else(|| "null".into()),
                                json_escape(&p.markdown),
                            )
                        })
                        .collect();
                    println!(
                        r#"{{"pages":[{}],"is_complex":{},"pages_needing_ocr":{:?}}}"#,
                        items.join(","),
                        r.is_complex,
                        r.pages_needing_ocr,
                    );
                }
                Err(e) => fail(e),
            }
        }
        _ => {
            eprintln!("unknown command: {cmd}");
            process::exit(2);
        }
    }
}
