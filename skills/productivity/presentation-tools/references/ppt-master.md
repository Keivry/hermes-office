# ppt-master — Full Presentation Generation Workflow

## Prerequisites
Repository at /opt/tools/ppt-master. Enter its root before working.

### Install
```bash
pip install -r /opt/tools/ppt-master/requirements.txt
```

## Standard Sequence (Strictly Serial)
1. **Prepare source** — convert PDF/DOCX/URL/Markdown to markdown:
   ```bash
   python3 skills/ppt-master/scripts/source_to_md/pdf_to_md.py <PDF>
   python3 skills/ppt-master/scripts/source_to_md/doc_to_md.py <DOCX>
   python3 skills/ppt-master/scripts/source_to_md/web_to_md.py <URL>
   ```
2. **Init project**: `python3 skills/ppt-master/scripts/project_manager.py init <name> --format ppt169`
3. **Import sources**: `python3 skills/ppt-master/scripts/project_manager.py import-sources <path> <files...> --move`
4. **Strategist phase**: Read `skills/ppt-master/SKILL.md` and complete the strategist stage
5. **Generate images** (if needed): `python3 skills/ppt-master/scripts/image_gen.py 'prompt' --aspect_ratio 16:9 -o <path>/images`
6. **Generate SVGs**: One page at a time — sequential, NOT parallel
7. **Quality check**: `python3 skills/ppt-master/scripts/svg_quality_checker.py <path>`
8. **Export (sequential steps, one at a time)**:
   ```bash
   python3 skills/ppt-master/scripts/total_md_split.py <path>
   python3 skills/ppt-master/scripts/finalize_svg.py <path>
   python3 skills/ppt-master/scripts/svg_to_pptx.py <path> -s final
   ```

## Output
- Two files: native shapes .pptx + _svg.pptx snapshot
- Located in exports/

## Pitfalls
- SVG page generation must be by the main agent — cannot delegate to subagents
- Post-processing requires one command at a time
- Default: free design; template path only if user mentions template/style
