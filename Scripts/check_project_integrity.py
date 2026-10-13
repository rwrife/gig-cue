import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

p = Path("GigCue.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
refs = set(re.findall(r"\b[A-F0-9]{24}\b", p))
defs = set(re.findall(r"([A-F0-9]{24})(?: /\*.*?\*/)? = \{", p))
assert refs == defs, (f"Missing defs: {refs - defs}", f"Extra defs: {defs - refs}")

ET.parse("GigCue.xcodeproj/xcshareddata/xcschemes/GigCue.xcscheme")
json.loads(Path("toolchain.json").read_text(encoding="utf-8"))
print("Project ID closure, scheme XML, and toolchain JSON: PASS")
