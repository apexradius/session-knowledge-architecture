# Skills-MCP Gap Analysis
**Date:** 2026-04-16
**Audit:** 125 skills vs 354 MCP tools

## Critical Gap: 15+ Skills Ignore Available MCP Tools

| Skill | Should Use | MCP Tools Available |
|-------|-----------|-------------------|
| `/shopify-store` | Shopify Admin API | `create_product`, `list_products`, `search_products` (72 tools) — **DONE** |
| `/social-post` | Meta posting API | `meta_create_post`, `meta_schedule_post`, `meta_upload_media` |
| `/ai-ad` | Meta Ads API | `meta_create_campaign`, `meta_create_adset`, `meta_create_ad` |
| `/scheduled-report` | n8n workflows | `n8n_create_workflow`, `n8n_list_templates` |
| `/monitor` | SSH health tools | `ssh_health_check`, `ssh_monitor`, `ssh_service_status` |
| `/deploy-verify` | SSH + browser | `ssh_execute`, `browser_performance` |
| `/perf-audit` | Browser perf | `browser_performance`, `browser_take_screenshot` |
| `/cro-audit` | Browser automation | `browser_snapshot`, `browser_take_screenshot` |
| `/data-migrate` | SSH database | `ssh_db_dump`, `ssh_db_import`, `ssh_db_query` |
| `/seo-audit` | GSC tools | `gsc_search_analytics`, `gsc_inspect_url` |
| `/component-gen` | UI tools | `21st_magic_component_builder`, `21st_magic_component_inspiration` — **DONE** |
| `/pr-review` | GitHub MCP | `get_pull_request`, `get_pull_request_files` |
| `/automation-audit` | n8n + SSH | `n8n_workflow_health`, `n8n_workflow_stats` |
| `/release` | GitHub MCP | `create_pull_request`, `merge_pull_request` |
| `/docs-search` | Core docs tools | `resolve-library-id`, `query-docs` — **DONE** |

## Merge: Debug (3→1), Planning (3→2), Remove /full-audit
## Dead: 10 vague skills to fold into parents or deprecate
## Phase 1 priority: component-gen, seo-audit, social-post, deploy-verify, perf-audit

## Sebintel Research Takeaways

1. **21st.dev component pipeline is underused** — we have the MCP tools (`mcp__apex-tools-mcp__21st_magic_component_builder`, `mcp__apex-tools-mcp__21st_magic_component_inspiration`, `mcp__apex-tools-mcp__21st_magic_component_refiner`) but skills didn't reference them. Now wired into component-gen.
2. **"Single prompt to deployed app" narrative** — we have stronger capabilities than Blink (Claude Code + SSH deploy + PostgreSQL + n8n). Package as a Keystone demo showing full stack from prompt to production.
3. **AI video from product images** — gap in `/create` skill tree for generating short product showcase clips. No MCP tool exists yet; evaluate RunwayML or Kling APIs as future integration candidates.
