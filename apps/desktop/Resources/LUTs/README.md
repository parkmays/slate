# SLATE LUTs Directory

This directory contains LUT (Look-Up Table) files for color space conversion during proxy generation.

## Supported Formats

- **.cube** files (3D LUTs)
- Must be 33x33x33 grid size or smaller
- Input/Output color space should be specified in the file header

## Built-in LUTs

- `Rec709_to_Rec709.cube` - Standard Rec.709 gamma correction (applied by default)

## Adding Custom LUTs

1. Place .cube files in this directory
2. LUTs will be automatically loaded at startup
3. Available LUTs can be selected in the proxy generation settings

## Naming Convention

Use descriptive names that include:
- Input color space (e.g., "LogC", "SLog3", "VLog")
- Output color space (e.g., "Rec709", "P3")
- Intended use (e.g., "Preview", "Editing")

Example: `ARRI_LogC_to_Rec709_Preview.cube`

## Notes

- LUTs are applied during proxy generation only
- Original media files are never modified
- Proxy files maintain the same frame rate and audio as the source
