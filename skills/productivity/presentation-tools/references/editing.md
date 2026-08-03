# Direct .pptx Editing

## Workflow
1. Analyze template with `python scripts/thumbnail.py presentation.pptx`
2. Unpack to raw XML: `python3 -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall('unpacked')" presentation.pptx`
3. Manipulate slides, edit content
4. Clean: `python scripts/clean.py unpacked/` (remove orphaned slides, media, rels)
5. Re-pack from INSIDE the dir: `(cd unpacked && rm -f ../out.pptx && zip -Xr ../out.pptx .)`
6. Validate: `python scripts/office/validate.py out.pptx --original presentation.pptx`

## Reading Content
```bash
python -m markitdown presentation.pptx
python scripts/thumbnail.py presentation.pptx
```

## Creating from Templates
Use python-pptx to manipulate existing .pptx files — add slides, modify shapes, update text, apply styles.
