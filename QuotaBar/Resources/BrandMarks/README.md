# Provider marks

Official brand artwork bundled in `QuotaBar/Assets.xcassets/Brand*.imageset/`. Used only to identify those services in Settings (sidebar, provider wells, account rows, empty states) and the popover header. Marks are trademarks of their owners.

Files are copied from official brand pages, press kits, or official repos. They are not invented, approximated, or geometrically recreated. Catalog imagesets use `template-rendering-intent: original` so official colors (including light-on-dark kit variants) are preserved.

| Asset | File | Mark | Official source |
| --- | --- | --- | --- |
| `BrandCursor` | `Cursor.svg` | 2D cube logomark (light on dark) | [cursor.com/brand](https://cursor.com/brand) kit `General Logos/Cube/SVG/CUBE_2D_DARK.svg` (also [logo.svg](https://www.cursor.com/assets/images/logo.svg)) |
| `BrandChatGPT` | `ChatGPT.svg` | Classic ChatGPT blossom (hexagonal knot), white inverse | [openai.com/brand](https://openai.com/brand/); Wikimedia [ChatGPT-Logo.svg](https://commons.wikimedia.org/wiki/File:ChatGPT-Logo.svg) sourced from OpenAI |
| `BrandOpenCode` | `OpenCode.svg` | Square O mark (dark) | [opencode.ai/brand](https://opencode.ai/brand) — [`opencode-logo-dark-square.svg`](https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/console/app/src/asset/brand/opencode-logo-dark-square.svg) |
| `BrandGLM` | `GLM.svg` | Z.ai logomark | [z-cdn.chatglm.cn/z-ai/static/logo.svg](https://z-cdn.chatglm.cn/z-ai/static/logo.svg); Wikimedia [Z.ai (company logo).svg](https://commons.wikimedia.org/wiki/File:Z.ai_(company_logo).svg) from [chat.z.ai](https://chat.z.ai/) |
| `BrandGrok` | `Grok.svg` | Grok logomark (light) | [xAI_Grok_Assets.zip](https://data.x.ai/logos/xAI_Grok_Assets.zip) `Grok_Logomark_Light.svg`; guidelines: [x.ai/legal/brand-guidelines](https://x.ai/legal/brand-guidelines) |

Not fetched at runtime. Unused Illustrator CSS in the Z.ai source file was stripped so AppKit can paint the official fills; paths and colors are unchanged. Cursor cube CSS class fills were written as presentation attributes for the same reason.
