//! ffi-core: flat, memory-only FFI facade over `pdf-inspector` (crates.io v1.17).
//!
//! Design rules:
//! - Input is always `&[u8]`; file IO is the host language's job
//!   (Swift `Data`, Elixir binary pass straight through).
//! - Every entry point is wrapped in `catch_unwind`: lopdf can panic on
//!   malformed PDFs, and a panic must never cross the FFI boundary.
//!   A caught panic becomes [`FfiErrorCode::InternalPanic`].
//! - Result types use only the UniFFI / Rustler NifStruct common subset:
//!   `u32`, `u64`, `f32`, `bool`, `String`, `Option<String>`, `Vec<T>`,
//!   and flat field-less enums. No nested records.
//!
//! Indexing note (inherited from upstream): `classify_pdf_mem` and
//! per-page results use **0-indexed** page numbers, while
//! `pages_needing_ocr` / `pages_with_tables` / `pages_with_columns` /
//! `ocr_reasons_by_page` in process-level results are **1-indexed**.

use std::panic::{catch_unwind, AssertUnwindSafe};

uniffi::setup_scaffolding!();

// =========================================================================
// Error type
// =========================================================================

/// Flat error code, FFI-safe counterpart of `pdf_inspector::PdfError`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiErrorCode {
    /// Host-triggered IO error (rare on the mem-only path).
    Io,
    /// PDF parsing error.
    Parse,
    /// PDF is encrypted and no (correct) password was supplied.
    Encrypted,
    /// Structurally invalid PDF (broken xref, bad object ids, ...).
    InvalidStructure,
    /// Bytes are not a PDF at all.
    NotAPdf,
    /// A panic was caught at the FFI boundary (upstream parser bug or
    /// unhandled malformed input). Never unwinds across FFI.
    InternalPanic,
}

/// Error returned by every ffi-core entry point.
///
/// Maps to a UniFFI record / Rustler NifStruct (`:error` tuple payload).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiError {
    pub code: FfiErrorCode,
    pub message: String,
}

impl FfiError {
    fn new(code: FfiErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}

impl From<pdf_inspector::PdfError> for FfiError {
    fn from(e: pdf_inspector::PdfError) -> Self {
        use pdf_inspector::PdfError as E;
        match e {
            E::Io(io) => FfiError::new(FfiErrorCode::Io, io.to_string()),
            E::Parse(msg) => FfiError::new(FfiErrorCode::Parse, msg),
            E::Encrypted => FfiError::new(FfiErrorCode::Encrypted, e.to_string()),
            E::InvalidStructure => FfiError::new(FfiErrorCode::InvalidStructure, e.to_string()),
            E::NotAPdf(msg) => FfiError::new(FfiErrorCode::NotAPdf, msg),
        }
    }
}

impl std::fmt::Display for FfiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}: {}", self.code, self.message)
    }
}

impl std::error::Error for FfiError {}

/// UniFFI-exported error: one variant per [`FfiErrorCode`], each carrying
/// the message. (UniFFI errors must be enums, so the flat `FfiError` record
/// cannot be thrown directly; Swift sees `PdfInspectorError.Parse(message:)`
/// & co., which already conforms to `Swift.Error`.)
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum PdfInspectorError {
    Io { message: String },
    Parse { message: String },
    Encrypted { message: String },
    InvalidStructure { message: String },
    NotAPdf { message: String },
    InternalPanic { message: String },
}

impl From<FfiError> for PdfInspectorError {
    fn from(e: FfiError) -> Self {
        match e.code {
            FfiErrorCode::Io => Self::Io { message: e.message },
            FfiErrorCode::Parse => Self::Parse { message: e.message },
            FfiErrorCode::Encrypted => Self::Encrypted { message: e.message },
            FfiErrorCode::InvalidStructure => Self::InvalidStructure { message: e.message },
            FfiErrorCode::NotAPdf => Self::NotAPdf { message: e.message },
            FfiErrorCode::InternalPanic => Self::InternalPanic { message: e.message },
        }
    }
}

impl std::fmt::Display for PdfInspectorError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let (code, message) = match self {
            Self::Io { message } => (FfiErrorCode::Io, message),
            Self::Parse { message } => (FfiErrorCode::Parse, message),
            Self::Encrypted { message } => (FfiErrorCode::Encrypted, message),
            Self::InvalidStructure { message } => (FfiErrorCode::InvalidStructure, message),
            Self::NotAPdf { message } => (FfiErrorCode::NotAPdf, message),
            Self::InternalPanic { message } => (FfiErrorCode::InternalPanic, message),
        };
        write!(f, "{code:?}: {message}")
    }
}

impl std::error::Error for PdfInspectorError {}

// =========================================================================
// Flat result types
// =========================================================================

/// Flat counterpart of `pdf_inspector::PdfType`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiPdfType {
    TextBased,
    Scanned,
    ImageBased,
    Mixed,
}

impl From<pdf_inspector::PdfType> for FfiPdfType {
    fn from(t: pdf_inspector::PdfType) -> Self {
        use pdf_inspector::PdfType as T;
        match t {
            T::TextBased => FfiPdfType::TextBased,
            T::Scanned => FfiPdfType::Scanned,
            T::ImageBased => FfiPdfType::ImageBased,
            T::Mixed => FfiPdfType::Mixed,
        }
    }
}

/// OCR reasons for a single page (page numbering follows the parent result).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiPageOcrReasons {
    pub page: u32,
    pub reasons: Vec<String>,
}

/// Flat counterpart of `pdf_inspector::PdfProcessResult`.
///
/// Upstream's nested `layout: LayoutComplexity` is flattened into
/// `is_complex` / `pages_with_tables` / `pages_with_columns` so the struct
/// stays in the UniFFI Record / Rustler NifStruct common subset.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiProcessResult {
    pub pdf_type: FfiPdfType,
    pub markdown: Option<String>,
    pub page_count: u32,
    pub processing_time_ms: u64,
    /// 1-indexed.
    pub pages_needing_ocr: Vec<u32>,
    /// 1-indexed pages.
    pub ocr_reasons_by_page: Vec<FfiPageOcrReasons>,
    pub title: Option<String>,
    pub confidence: f32,
    pub is_complex: bool,
    /// 1-indexed.
    pub pages_with_tables: Vec<u32>,
    /// 1-indexed.
    pub pages_with_columns: Vec<u32>,
    pub has_encoding_issues: bool,
}

impl From<pdf_inspector::PdfProcessResult> for FfiProcessResult {
    fn from(r: pdf_inspector::PdfProcessResult) -> Self {
        Self {
            pdf_type: r.pdf_type.into(),
            markdown: r.markdown,
            page_count: r.page_count,
            processing_time_ms: r.processing_time_ms,
            pages_needing_ocr: r.pages_needing_ocr,
            ocr_reasons_by_page: r
                .ocr_reasons_by_page
                .into_iter()
                .map(|p| FfiPageOcrReasons {
                    page: p.page,
                    reasons: p.reasons,
                })
                .collect(),
            title: r.title,
            confidence: r.confidence,
            is_complex: r.layout.is_complex,
            pages_with_tables: r.layout.pages_with_tables,
            pages_with_columns: r.layout.pages_with_columns,
            has_encoding_issues: r.has_encoding_issues,
        }
    }
}

/// Flat counterpart of `pdf_inspector::PdfClassification`.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiClassification {
    pub pdf_type: FfiPdfType,
    pub page_count: u32,
    /// 0-indexed (upstream convention for this entry point).
    pub pages_needing_ocr: Vec<u32>,
    pub confidence: f32,
}

impl From<pdf_inspector::PdfClassification> for FfiClassification {
    fn from(c: pdf_inspector::PdfClassification) -> Self {
        Self {
            pdf_type: c.pdf_type.into(),
            page_count: c.page_count,
            pages_needing_ocr: c.pages_needing_ocr,
            confidence: c.confidence,
        }
    }
}

/// Per-page markdown, flat counterpart of `pdf_inspector::PageMarkdown`.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiPageMarkdown {
    /// 0-indexed.
    pub page: u32,
    pub markdown: String,
    pub needs_ocr: bool,
    pub ocr_reason: Option<String>,
}

/// Flat counterpart of `pdf_inspector::PagesExtractionResult`.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiPagesResult {
    pub pages: Vec<FfiPageMarkdown>,
    /// 1-indexed.
    pub pages_with_tables: Vec<u32>,
    /// 1-indexed.
    pub pages_with_columns: Vec<u32>,
    /// 1-indexed.
    pub pages_needing_ocr: Vec<u32>,
    /// 1-indexed pages.
    pub ocr_reasons_by_page: Vec<FfiPageOcrReasons>,
    pub is_complex: bool,
}

impl From<pdf_inspector::PagesExtractionResult> for FfiPagesResult {
    fn from(r: pdf_inspector::PagesExtractionResult) -> Self {
        Self {
            pages: r
                .pages
                .into_iter()
                .map(|p| FfiPageMarkdown {
                    page: p.page,
                    markdown: p.markdown,
                    needs_ocr: p.needs_ocr,
                    ocr_reason: p.ocr_reason,
                })
                .collect(),
            pages_with_tables: r.pages_with_tables,
            pages_with_columns: r.pages_with_columns,
            pages_needing_ocr: r.pages_needing_ocr,
            ocr_reasons_by_page: r
                .ocr_reasons_by_page
                .into_iter()
                .map(|p| FfiPageOcrReasons {
                    page: p.page,
                    reasons: p.reasons,
                })
                .collect(),
            is_complex: r.is_complex,
        }
    }
}

// =========================================================================
// Entry points (all catch_unwind-guarded)
// =========================================================================

fn guard<T>(
    f: impl FnOnce() -> Result<T, pdf_inspector::PdfError>,
) -> Result<T, FfiError> {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => Ok(v),
        Ok(Err(e)) => Err(e.into()),
        Err(_) => Err(FfiError::new(
            FfiErrorCode::InternalPanic,
            "caught panic from pdf-inspector",
        )),
    }
}

/// Full pipeline: classify + extract markdown for the whole document.
pub fn process_pdf_mem(data: &[u8]) -> Result<FfiProcessResult, FfiError> {
    guard(|| pdf_inspector::process_pdf_mem(data)).map(Into::into)
}

/// Detection-only pipeline (classification + layout, no markdown).
pub fn detect_pdf_mem(data: &[u8]) -> Result<FfiProcessResult, FfiError> {
    guard(|| pdf_inspector::detect_pdf_mem(data)).map(Into::into)
}

/// Lightest routing entry: PDF type + pages needing OCR.
pub fn classify_pdf_mem(data: &[u8]) -> Result<FfiClassification, FfiError> {
    guard(|| pdf_inspector::classify_pdf_mem(data)).map(Into::into)
}

/// Per-page markdown for hybrid pipelines. `pages` is a list of
/// **0-indexed** page numbers; `None` extracts every page in document order.
pub fn extract_pages_markdown_mem(
    data: &[u8],
    pages: Option<&[u32]>,
) -> Result<FfiPagesResult, FfiError> {
    guard(|| pdf_inspector::extract_pages_markdown_mem(data, pages)).map(Into::into)
}

// =========================================================================
// UniFFI-exported entry points (P1)
// =========================================================================
//
// Thin wrappers over the functions above: UniFFI cannot take `&[u8]` /
// `Option<&[u32]>` arguments or throw the `FfiError` record, so these take
// owned `Vec<u8>` / `Option<Vec<u32>>` (Swift `Data` / `[UInt32]?`) and throw
// [`PdfInspectorError`]. Page indexing is unchanged: `classify_pdf` and
// per-page results are 0-indexed, process-level page lists are 1-indexed.

/// Full pipeline: classify + extract markdown for the whole document.
/// Process-level page lists in the result are **1-indexed**.
#[uniffi::export]
pub fn process_pdf(data: Vec<u8>) -> Result<FfiProcessResult, PdfInspectorError> {
    process_pdf_mem(&data).map_err(Into::into)
}

/// Detection-only pipeline (classification + layout, no markdown).
#[uniffi::export]
pub fn detect_pdf(data: Vec<u8>) -> Result<FfiProcessResult, PdfInspectorError> {
    detect_pdf_mem(&data).map_err(Into::into)
}

/// Lightest routing entry: PDF type + pages needing OCR (**0-indexed**).
#[uniffi::export]
pub fn classify_pdf(data: Vec<u8>) -> Result<FfiClassification, PdfInspectorError> {
    classify_pdf_mem(&data).map_err(Into::into)
}

/// Per-page markdown for hybrid pipelines. `pages` is a list of
/// **0-indexed** page numbers; `None` extracts every page in document order.
#[uniffi::export]
pub fn extract_pages_markdown(
    data: Vec<u8>,
    pages: Option<Vec<u32>>,
) -> Result<FfiPagesResult, PdfInspectorError> {
    extract_pages_markdown_mem(&data, pages.as_deref()).map_err(Into::into)
}
