# -*- coding: utf-8 -*-
"""Extract visible and dynamic marketing copy from landing/index.html -> JSON."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / "index.html"
OUT = ROOT / "index-copy-analysis.json"


def extract_role_benefits_js(html: str) -> dict:
    marker = "var ROLE_BENEFITS = "
    idx = html.find(marker)
    if idx < 0:
        return {}
    i = idx + len(marker)
    while i < len(html) and html[i] in " \t\r\n":
        i += 1
    if i >= len(html) or html[i] != "{":
        return {}
    depth = 0
    start = i
    for j in range(i, len(html)):
        c = html[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                obj_literal = html[start : j + 1]
                break
    else:
        return {}
    code = (
        "const ROLE_BENEFITS = "
        + obj_literal
        + ";\nprocess.stdout.write(JSON.stringify(ROLE_BENEFITS));"
    )
    r = subprocess.run(
        ["node", "-e", code],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
        encoding="utf-8",
    )
    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        return {}
    return json.loads(r.stdout)


def norm_ws(s: str) -> str:
    return " ".join(s.split())


class LandingCopyParser(HTMLParser):
    SKIP = frozenset({"script", "style", "noscript", "template"})

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._skip = 0
        self._in_head = False
        self.title: str | None = None
        self.meta_description: str | None = None
        self._in_title = False
        self.header: dict = {"logo_text": None, "nav": []}
        self._in_header = False
        self._header_a_href: str | None = None
        self._slide_stack: list[dict] = []
        self.slides: list[dict] = []
        self.image_alts: list[str] = []
        self._collect_attrs: dict | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        ad = {k: v or "" for k, v in attrs}
        if tag in self.SKIP:
            self._skip += 1
            return
        if self._skip:
            return
        if tag == "head":
            self._in_head = True
        if tag == "title" and self._in_head:
            self._in_title = True
        if tag == "meta" and self._in_head:
            if ad.get("name", "").lower() == "description":
                self.meta_description = ad.get("content", "").strip() or None
        if tag == "header" and "site-header" in ad.get("class", ""):
            self._in_header = True
        if self._in_header and tag == "a":
            self._header_a_href = ad.get("href", "")
        if tag == "img":
            alt = ad.get("alt", "").strip()
            if alt:
                self.image_alts.append(alt)
        if tag == "section":
            classes = ad.get("class", "")
            if "landing-slide" in classes.split():
                self._slide_stack.append(
                    {
                        "id": ad.get("id"),
                        "data_slide": ad.get("data-slide"),
                        "text_chunks": [],
                    }
                )
        aria = ad.get("aria-label", "").strip()
        if aria and not self._slide_stack and tag in ("button", "a", "nav"):
            if self._in_header or tag == "nav":
                pass  # captured via text for nav
        title_attr = ad.get("title", "").strip()
        if title_attr and self._slide_stack:
            self._slide_stack[-1]["text_chunks"].append(title_attr)

    def handle_endtag(self, tag: str) -> None:
        if tag in self.SKIP and self._skip:
            self._skip -= 1
            return
        if self._skip:
            return
        if tag == "head":
            self._in_head = False
        if tag == "title":
            self._in_title = False
        if tag == "header":
            self._in_header = False
            self._header_a_href = None
        if tag == "section" and self._slide_stack:
            slide = self._slide_stack.pop()
            chunks = [norm_ws(c) for c in slide["text_chunks"] if norm_ws(c)]
            slide["text_joined"] = norm_ws(" ".join(chunks))
            del slide["text_chunks"]
            if slide.get("id") == "how":
                broken = "2 . В ы б о р ы и в е т в л е н и я"
                if broken in slide["text_joined"]:
                    slide["text_joined"] = slide["text_joined"].replace(
                        broken, "2. Выборы и ветвления"
                    )
            self.slides.append(slide)

    def handle_data(self, data: str) -> None:
        if self._skip:
            return
        if self._in_title:
            t = norm_ws(data)
            if t:
                self.title = t
            return
        if self._in_header and self._header_a_href is not None:
            t = norm_ws(data)
            if t and self._header_a_href:
                self.header["nav"].append({"href": self._header_a_href, "text": t})
            return
        if self._slide_stack:
            t = norm_ws(data)
            if t:
                self._slide_stack[-1]["text_chunks"].append(t)


def main() -> None:
    raw = INDEX.read_text(encoding="utf-8")
    p = LandingCopyParser()
    p.feed(raw)
    p.close()

    if p.header["nav"]:
        logo = p.header["nav"][0]
        if logo.get("href") == "#hero":
            p.header["logo_text"] = logo.get("text")
            p.header["nav"] = p.header["nav"][1:]

    out = {
        "source": str(INDEX.as_posix()),
        "page": {
            "title": p.title,
            "meta_description": p.meta_description,
        },
        "header": p.header,
        "slides": p.slides,
        "image_alts": list(dict.fromkeys(p.image_alts)),
        "dynamic_role_benefits": extract_role_benefits_js(raw),
        "notes": [
            "Текст слайдов — текстовые узлы внутри <section class=\"... landing-slide\"> (без содержимого <script>/<style>).",
            "Слайд «Для вас» в разметке почти пустой; буллеты по ролям подставляются из JS — см. dynamic_role_benefits.",
            "В text_joined возможны повторы подписей кнопок (например «Войти», «Оставить заявку») — так устроена вёрстка.",
            "Заголовок шага «2. Выборы и ветвления» на слайде «Как это работает» восстановлен из буквенных <span> для читаемости.",
        ],
    }

    OUT.write_text(
        json.dumps(out, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
