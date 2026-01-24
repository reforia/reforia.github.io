# Blog Writing Guide for reforia.github.io

This is a Jekyll blog using the Chirpy theme with bilingual support (English and Simplified Chinese).

## Project Structure

```
_posts/
├── ai/genai/                    # AI/GenAI posts
├── guildhall/                   # Guildhall archived projects
├── misc/level-design/           # Miscellaneous posts
├── ubisoft/aaa-title/           # Ubisoft project posts
├── unreal/
│   ├── engine/                  # Unreal Engine internals
│   │   └── bpvm-snack-pack/     # BPVM series posts
│   ├── gameplay/                # Gameplay programming
│   ├── network/                 # Networking
│   └── render/                  # Rendering
└── zh-CN/                       # Chinese translations (mirror structure)
    ├── ai/genai/
    └── unreal/
        ├── engine/bpvm-snack-pack/
        └── gameplay/

assets/img/post-data/            # Post images, mirrors category structure
_tabs/                           # Navigation tabs (English)
_tabs/zh-CN/                     # Navigation tabs (Chinese)
```

## Blog File Naming Convention

**Format**: `YYYY-MM-DD-slug-name.md`

- Use hyphens for word separation
- No spaces in filenames
- For series: include sequence number (e.g., `bpvm-snack-01`, `bpvm-bytecode-I`)

**Examples**:
- `2025-10-28-bpvm-snack-01-what-is-blueprint.md`
- `2025-08-23-fluent-fsm-macros.md`

## Required Frontmatter

```yaml
---
layout: post
title: "Post Title"
description: >-
  A brief description of the post content.
  Can span multiple lines with >- syntax.
date: YYYY-MM-DD HH:MM +0800
categories: [Category1, Category2]
tags: [tag1, tag2, tag3]
published: true
lang: en
media_subpath: /assets/img/post-data/category/subcategory/slug-name/
---
```

### Field Details

| Field | Required | Description |
|-------|----------|-------------|
| `layout` | Yes | Always `post` |
| `title` | Yes | Post title in quotes |
| `description` | Yes | Brief summary, use `>-` for multiline |
| `date` | Yes | Format: `YYYY-MM-DD HH:MM +0800` (Shanghai timezone) |
| `categories` | Yes | Array format: `[Main, Sub]` |
| `tags` | Yes | Array format: `[tag1, tag2]` |
| `published` | Yes | `true` or `false` |
| `lang` | Yes | `en` for English, `zh-CN` for Chinese |
| `media_subpath` | Yes | Path to post's image folder |
| `math` | No | Set `true` if using LaTeX notation |

### Common Categories

- `[Unreal, Engine]`
- `[Unreal, Gameplay]`
- `[Unreal, Network]`
- `[Unreal, Render]`
- `[AI, GenAI]`
- `[Archived Projects, Guildhall]`

## Image/Asset Organization

**Path**: `/assets/img/post-data/[category]/[subcategory]/[post-slug]/`

- Create folder matching post slug (without date prefix)
- Prefix image names with context identifier (e.g., `bytecode_`, `fsm_`)
- Reference images using relative path: `![Alt Text](image.png)`

**Example**:
- Post: `_posts/unreal/gameplay/2025-08-23-fluent-fsm-macros.md`
- Assets: `/assets/img/post-data/unreal/gameplay/fluent-fsm/`
- Frontmatter: `media_subpath: /assets/img/post-data/unreal/gameplay/fluent-fsm/`

## Translation Workflow (zh-CN)

1. **Write English post first** in `_posts/[category]/[subcategory]/`
2. **Create Chinese translation** in `_posts/zh-CN/[category]/[subcategory]/`
3. **Use same filename** for both versions
4. **Update `lang` field**: `lang: zh-CN` for Chinese version
5. **Share same asset folder** - no need to duplicate images

**Example pair**:
- English: `_posts/unreal/engine/2025-01-15-my-post.md` with `lang: en`
- Chinese: `_posts/zh-CN/unreal/engine/2025-01-15-my-post.md` with `lang: zh-CN`

## Special Includes & Styling

### Unreal Engine Version Disclaimer
```liquid
{% include ue_version_disclaimer.html version="5.6.0" %}
```

### Engine Post Disclaimer
```liquid
{% include ue_engine_post_disclaimer.html %}
```

### Prompt Blocks (Notes/Tips/Warnings)
```markdown
> This is an informational note.
{: .prompt-info }

> This is a helpful tip.
{: .prompt-tip }

> This is a warning message.
{: .prompt-warning }
```

## Writing Checklist

- [ ] Create post file with correct naming: `YYYY-MM-DD-slug.md`
- [ ] Add all required frontmatter fields
- [ ] Set correct `lang` value (`en` or `zh-CN`)
- [ ] Create asset folder at correct path
- [ ] Set `media_subpath` in frontmatter
- [ ] Add version disclaimers for Unreal posts
- [ ] Set `math: true` if using LaTeX
- [ ] Create zh-CN translation with same filename structure
- [ ] Verify `published: true` when ready to publish

## Local Development

```bash
bundle exec jekyll serve
```

Site URL: https://www.jaydengames.com
