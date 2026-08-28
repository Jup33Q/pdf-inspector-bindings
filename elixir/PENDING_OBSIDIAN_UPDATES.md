# 待应用的 Obsidian 更新（P2 管道 DSL，2026-08-28）

> 应用条件：`~/Documents/Obsidian Vault` 恢复可访问（iCloud 实质化 / TCC 重新授权）后，
> 把以下两处编辑应用到对应文件，然后删除本文件。

## 0. 复验记录（2026-08-28 晚，vault 仍不可写）

- `mix test` 25/25 全绿、`mix format --check-formatted` 通过（复跑确认）。
- `PdfInspector.process(File.read!("fixtures/normal.pdf"))` 的 markdown 与 `pdf2md --raw`
  逐字节一致（sha256 同为 `79a74137…70f`，244 B）。
- NIF 产物 `priv/native/pdf_inspector_nif.so` 实测 6.1 MB（6,107,600 B），rustler 0.38 顺带
  拷贝的 `ffi_core.so` / `pdf_inspector.so` 为未使用的 gitignored 噪音（根 README 已注明）。
- 坑：dev 环境（`mix run` / iex）同样必须 `PDF_INSPECTOR_EX_BUILD=1`——GitHub 还没有
  v0.1.0 release，rustler_precompiled 下载 404 后直接 raise 而非回落源码编译；
  test 环境之前带 env 编译过有缓存所以无感。P3 CI 出产物后此限制自然解除。

## 1. `02-Projects/pdf-inspector/绑定自实现方案与重构计划.md`

在 P2 实施记录末尾「已知事项」一条之后追加：

### P2 追加：管道 DSL（2026-08-28，同日完成）

- **`PdfInspector.Pipeline`**（纯 Elixir，同包 `lib/pdf_inspector/pipeline.ex`，零新依赖、NIF/ffi-core 零改动）：声明式「classify 一次 → 按 pdf_type 路由 → 提取/移交 OCR → 汇总」宏 DSL——`route <pdf_type>, <strategy>` + 可选 `fallback`（默认 `:classify`）；策略五种：`:markdown`（process/1 全文）/ `:pages`（extract_pages/2 逐页，OCR 页留占位）/ `:classify` / `:skip` / `{:ocr, module}`（先逐页提取，再把 needs_ocr 页交给 OCR behaviour 回调 `extract(binary, pages_0_indexed)`，返回文本并入占位页；OCR 报错误记 `result.ocr_errors` 不丢提取结果）。
- **编译期校验**：未知 pdf_type / 重复 route / 非法策略 / OCR 模块缺 `extract/2` 全部编译期 raise。
- **汇总结果** `%PdfInspector.Pipeline.Result{classification, strategy, markdown, pages, ocr_pages, ocr_errors}`；页码索引沿用上游（classify/逐页/ocr_pages 全 0-indexed），`:pages`/`:ocr` 策略的 `markdown` 是按页 `"\n\n"` 拼接的便利字段（权威内容在 `pages`，不保证与 `:markdown` 策略逐字节一致）。
- **验收**：`mix test` 25/25 全绿（原 13 + 新增 12：编译期校验 4、路由表 2、:markdown/:pages 与直调一致性 2、OCR 移交 spy + 错误路径 2、encrypted/garbage 透传 2）+ `mix format` 通过；测试全部复用现有四 fixture，未加新 fixture。
- **明确不做**：并发/流式（宿主自行 Task 编排）、OCR 实现本体（只定 behaviour 移交点）、P2.5 Phoenix 示例暂不接 DSL。

## 2. `00-MOC/项目索引.md` 更新日志顶部插入

- 2026-08-28: pdf-inspector **P2 追加：管道 DSL 完成**（`elixir/lib/pdf_inspector/pipeline.ex`，纯 Elixir 宏 DSL，零新依赖零 NIF 改动）：`use PdfInspector.Pipeline` + `route <pdf_type>, <strategy>`（:markdown/:pages/:classify/:skip/{:ocr, mod}）+ fallback，编译期校验路由表；`{:ocr, mod}` 走 Ocr behaviour 回调并入 needs_ocr 页文本、OCR 错误记 ocr_errors 不丢结果；`run/1` 汇总 `%Pipeline.Result{}`，页码全 0-indexed；验收 mix test 25/25 + mix format 通过，测试复用四 fixture 未加新件

（同文件 pdf-inspector 条目「状态」行可在下次更新时把 P2 管道 DSL 一并写入。）
