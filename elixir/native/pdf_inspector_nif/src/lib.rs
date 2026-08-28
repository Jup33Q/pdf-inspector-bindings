//! Rustler NIFs over `ffi-core` (reused as an rlib path dependency).
//!
//! Every entry point is scheduled `DirtyCpu`: extraction takes 10–200 ms,
//! far beyond the 1 ms NIF budget — running it on a normal scheduler would
//! stall the BEAM. Input is an Elixir binary passed straight through to
//! ffi-core as `&[u8]`; file IO stays in Elixir.
//!
//! Indexing note (inherited from upstream, documented in `PdfInspector`):
//! `classify/1` and per-page results use **0-indexed** page numbers, while
//! process-level page lists (`pages_needing_ocr`, `pages_with_tables`, ...)
//! are **1-indexed**. Out-of-range pages yield empty markdown +
//! `needs_ocr: true` placeholders (upstream behaviour, kept as-is).

use rustler::{Binary, NifStruct, NifUnitEnum};

// =========================================================================
// Error (maps to {:error, %PdfInspector.Error{}})
// =========================================================================

/// Atom counterpart of `ffi_core::FfiErrorCode`.
#[derive(NifUnitEnum)]
pub enum ErrorCode {
    Io,
    Parse,
    Encrypted,
    InvalidStructure,
    NotAPdf,
    InternalPanic,
}

impl From<ffi_core::FfiErrorCode> for ErrorCode {
    fn from(c: ffi_core::FfiErrorCode) -> Self {
        use ffi_core::FfiErrorCode as C;
        match c {
            C::Io => ErrorCode::Io,
            C::Parse => ErrorCode::Parse,
            C::Encrypted => ErrorCode::Encrypted,
            C::InvalidStructure => ErrorCode::InvalidStructure,
            C::NotAPdf => ErrorCode::NotAPdf,
            C::InternalPanic => ErrorCode::InternalPanic,
        }
    }
}

/// Flat error struct; the NIF returns it as the `{:error, ...}` payload.
#[derive(NifStruct)]
#[module = "PdfInspector.Error"]
pub struct Error {
    pub code: ErrorCode,
    pub message: String,
}

impl From<ffi_core::FfiError> for Error {
    fn from(e: ffi_core::FfiError) -> Self {
        Self {
            code: e.code.into(),
            message: e.message,
        }
    }
}

// =========================================================================
// Result structs (field shapes mirror ffi-core, unchanged)
// =========================================================================

/// Atom counterpart of `ffi_core::FfiPdfType`.
#[derive(NifUnitEnum)]
pub enum PdfType {
    TextBased,
    Scanned,
    ImageBased,
    Mixed,
}

impl From<ffi_core::FfiPdfType> for PdfType {
    fn from(t: ffi_core::FfiPdfType) -> Self {
        use ffi_core::FfiPdfType as T;
        match t {
            T::TextBased => PdfType::TextBased,
            T::Scanned => PdfType::Scanned,
            T::ImageBased => PdfType::ImageBased,
            T::Mixed => PdfType::Mixed,
        }
    }
}

#[derive(NifStruct)]
#[module = "PdfInspector.PageOcrReasons"]
pub struct PageOcrReasons {
    pub page: u32,
    pub reasons: Vec<String>,
}

impl From<ffi_core::FfiPageOcrReasons> for PageOcrReasons {
    fn from(p: ffi_core::FfiPageOcrReasons) -> Self {
        Self {
            page: p.page,
            reasons: p.reasons,
        }
    }
}

#[derive(NifStruct)]
#[module = "PdfInspector.Result"]
pub struct ProcessResult {
    pub pdf_type: PdfType,
    pub markdown: Option<String>,
    pub page_count: u32,
    pub processing_time_ms: u64,
    /// 1-indexed.
    pub pages_needing_ocr: Vec<u32>,
    /// 1-indexed pages.
    pub ocr_reasons_by_page: Vec<PageOcrReasons>,
    pub title: Option<String>,
    pub confidence: f32,
    pub is_complex: bool,
    /// 1-indexed.
    pub pages_with_tables: Vec<u32>,
    /// 1-indexed.
    pub pages_with_columns: Vec<u32>,
    pub has_encoding_issues: bool,
}

impl From<ffi_core::FfiProcessResult> for ProcessResult {
    fn from(r: ffi_core::FfiProcessResult) -> Self {
        Self {
            pdf_type: r.pdf_type.into(),
            markdown: r.markdown,
            page_count: r.page_count,
            processing_time_ms: r.processing_time_ms,
            pages_needing_ocr: r.pages_needing_ocr,
            ocr_reasons_by_page: r.ocr_reasons_by_page.into_iter().map(Into::into).collect(),
            title: r.title,
            confidence: r.confidence,
            is_complex: r.is_complex,
            pages_with_tables: r.pages_with_tables,
            pages_with_columns: r.pages_with_columns,
            has_encoding_issues: r.has_encoding_issues,
        }
    }
}

#[derive(NifStruct)]
#[module = "PdfInspector.Classification"]
pub struct Classification {
    pub pdf_type: PdfType,
    pub page_count: u32,
    /// 0-indexed (upstream convention for this entry point).
    pub pages_needing_ocr: Vec<u32>,
    pub confidence: f32,
}

impl From<ffi_core::FfiClassification> for Classification {
    fn from(c: ffi_core::FfiClassification) -> Self {
        Self {
            pdf_type: c.pdf_type.into(),
            page_count: c.page_count,
            pages_needing_ocr: c.pages_needing_ocr,
            confidence: c.confidence,
        }
    }
}

#[derive(NifStruct)]
#[module = "PdfInspector.PageMarkdown"]
pub struct PageMarkdown {
    /// 0-indexed.
    pub page: u32,
    pub markdown: String,
    pub needs_ocr: bool,
    pub ocr_reason: Option<String>,
}

impl From<ffi_core::FfiPageMarkdown> for PageMarkdown {
    fn from(p: ffi_core::FfiPageMarkdown) -> Self {
        Self {
            page: p.page,
            markdown: p.markdown,
            needs_ocr: p.needs_ocr,
            ocr_reason: p.ocr_reason,
        }
    }
}

#[derive(NifStruct)]
#[module = "PdfInspector.PagesResult"]
pub struct PagesResult {
    pub pages: Vec<PageMarkdown>,
    /// 1-indexed.
    pub pages_with_tables: Vec<u32>,
    /// 1-indexed.
    pub pages_with_columns: Vec<u32>,
    /// 1-indexed.
    pub pages_needing_ocr: Vec<u32>,
    /// 1-indexed pages.
    pub ocr_reasons_by_page: Vec<PageOcrReasons>,
    pub is_complex: bool,
}

impl From<ffi_core::FfiPagesResult> for PagesResult {
    fn from(r: ffi_core::FfiPagesResult) -> Self {
        Self {
            pages: r.pages.into_iter().map(Into::into).collect(),
            pages_with_tables: r.pages_with_tables,
            pages_with_columns: r.pages_with_columns,
            pages_needing_ocr: r.pages_needing_ocr,
            ocr_reasons_by_page: r.ocr_reasons_by_page.into_iter().map(Into::into).collect(),
            is_complex: r.is_complex,
        }
    }
}

// =========================================================================
// NIFs (all DirtyCpu — see module docs)
// =========================================================================

#[rustler::nif(schedule = "DirtyCpu")]
fn process(data: Binary) -> Result<ProcessResult, Error> {
    ffi_core::process_pdf_mem(data.as_slice())
        .map(Into::into)
        .map_err(Into::into)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn detect(data: Binary) -> Result<ProcessResult, Error> {
    ffi_core::detect_pdf_mem(data.as_slice())
        .map(Into::into)
        .map_err(Into::into)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn classify(data: Binary) -> Result<Classification, Error> {
    ffi_core::classify_pdf_mem(data.as_slice())
        .map(Into::into)
        .map_err(Into::into)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn extract_pages(data: Binary, pages: Option<Vec<u32>>) -> Result<PagesResult, Error> {
    ffi_core::extract_pages_markdown_mem(data.as_slice(), pages.as_deref())
        .map(Into::into)
        .map_err(Into::into)
}

rustler::init!("Elixir.PdfInspector.Native");
