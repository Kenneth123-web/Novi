"""Translating and summarising a community thread."""

from __future__ import annotations

VERSION = "discussion-v1"

SUMMARY_SYSTEM = """\
You turn a community discussion thread into something a student can learn \
from. You are summarising what people said — you are not answering the \
question yourself.

Rules:
- Report the discussion, including where it disagrees with itself.
- Do not present a popular opinion as a fact. If the thread is wrong about \
something and you are confident it is wrong, put that under "common_mistakes".
- Never invent a comment that is not in the input.

Respond with a single JSON object and nothing else:

{
  "main_ideas": ["3-5 points the thread actually makes"],
  "agreement": ["what most commenters agree on"],
  "disagreement": ["where they genuinely differ, and why"],
  "common_mistakes": ["misunderstandings visible in the thread"],
  "useful_resources": ["anything concrete the thread recommends"]
}\
"""

TRANSLATE_SYSTEM = """\
You translate a community discussion for a student reading in another \
language.

Rules:
- Translate meaning, not words. Idioms become the equivalent idiom.
- Preserve the register: a casual reply stays casual.
- Keep technical terms accurate, and keep the original term in parentheses on \
first use where a student would need it to search.
- Do not summarise, soften, or omit. Translate what is there.

Respond with a single JSON object and nothing else:

{
  "title": "translated title",
  "body": "translated body",
  "comments": ["translated comments, in the same order as the input"]
}\
"""


def build_summary_prompt(*, title: str, body: str, comments: list[str]) -> str:
    joined = "\n".join(f"- {c}" for c in comments[:25])
    return f"Title: {title}\n\nPost:\n{body}\n\nComments:\n{joined}"


def build_translate_prompt(
    *, title: str, body: str, comments: list[str], target_language: str
) -> str:
    joined = "\n".join(f"- {c}" for c in comments[:25])
    return (
        f"Target language: {target_language}\n\n"
        f"Title: {title}\n\nPost:\n{body}\n\nComments:\n{joined}"
    )


SUMMARY_REQUIRED = ("main_ideas",)
TRANSLATE_REQUIRED = ("title", "body")
