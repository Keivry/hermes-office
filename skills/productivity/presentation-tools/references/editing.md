# Direct .pptx Editing

## Workflow
1. Analyze template with `python scripts/thumbnail.py presentation.pptx`
2. Unpack to raw XML: `python scripts/office/unpack.py presentation.pptx unpacked/`
3. Manipulate slides, edit content
4. Clean up
5. Re-pack

## Reading Content
```bash
python -m markitdown presentation.pptx
python scripts/thumbnail.py presentation.pptx
python scripts/office/unpack.py presentation.pptx unpacked/
```

## Creating from Templates
Use python-pptx to manipulate existing .pptx files — add slides, modify shapes, update text, apply styles.
