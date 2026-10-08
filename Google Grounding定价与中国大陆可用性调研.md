# Google Grounding 定价与中国大陆可用性调研

调研日期：2026-10-08。资料均来自 Google 官方文档。

## 结论

- **不是完全免费。** Gemini Developer API 的免费层通常不能通过 API 使用 Google Search Grounding（部分场景可在 Google AI Studio 试用）。付费层目前包含每月 **5,000 次**免费 Search requests（Gemini 3.x 模型共享）；超出后为 **US$14 / 1,000 次搜索请求**。模型本身的输入、输出 token 费用仍另计。
- 一次 Sidecar 的“联网回答”可能让模型实际执行多条 Google 搜索；Gemini 3 按实际执行的每条 query 计费，而非简单按用户点击一次计费。因此产品必须显示用量说明并设置预算/上限。
- **中国大陆不是 Gemini API / Google AI Studio 的官方支持区域。** Google 的官方可用地区清单中列出台湾、香港等地区，但不含“中国/中国大陆”。因此，对物理位于中国大陆的用户，不能承诺 Gemini API 或 Google Grounding 可用，也不应把它做成大陆版 Sidecar 唯一或默认的搜索后端。
- 即使某些用户通过境外账号、网络与计费条件偶尔能调用，也属于非官方支持情形，稳定性、合规性和支持性都不能保证。

## 产品建议

1. 若接入 Google Grounding，应只把它作为已启用 Gemini 且所在地区受官方支持的用户的可选搜索后端。
2. 面向中国大陆用户，提供独立、可配置且在该区域可用的搜索后端；不要将 Google Grounding 设为默认或唯一回退。
3. 每次实际联网搜索前显示确认提示；注明搜索词会发送给搜索服务，且一次请求可能产生多次可计费查询。

## 官方来源

- [Gemini Developer API pricing](https://ai.google.dev/gemini-api/docs/pricing)：Grounding 的免费/付费可用性、5,000 次月度额度、超额价格，以及按实际 query 计费的说明。
- [Grounding with Google Search](https://ai.google.dev/gemini-api/docs/google-search/)：Gemini 3 按模型实际执行的搜索 query 计费；Gemini 2.5 及更早模型按 prompt 计费。
- [Available regions for Google AI Studio and Gemini API](https://ai.google.dev/gemini-api/docs/available-regions)：官方支持地区清单及地区限制说明；清单不含中国大陆。
