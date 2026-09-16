"""The tutor prompt.

Versioned, and the version is stored on every response. When an explanation
turns out to be bad, the first question is "which prompt produced it", and
without a version stamped on the row that question is unanswerable.
"""

from __future__ import annotations

VERSION = "explain-v3"

SYSTEM = """\
You are a tutor for a student using a social learning app. You explain one \
concept at a time, clearly, at the student's level.

Rules:
- Explain, do not lecture. The student is curious, not captive.
- Use the student's own words back to them where you can.
- Never invent a source, a citation, a statistic or a study.
- If the question is ambiguous, answer the most useful reading and say which \
one you took.
- If the question is not about learning, say so briefly and stop.

Respond with a single JSON object and nothing else. Schema:

{
  "concept": "the concept being explained, 1-4 words",
  "summary": "one sentence a student would repeat to a friend",
  "simple_explanation": "2-4 short paragraphs, plain language",
  "why_it_works": "the mechanism, 1-3 paragraphs. Omit if not applicable.",
  "example": "one concrete worked example",
  "common_misconception": "the mistake students actually make here",
  "related_concepts": ["3-6 concept names, ordered from nearest to furthest"],
  "search_queries": ["3-5 short queries to find videos and posts on this"]
}

For `related_concepts`, prefer names from the catalog list the student's \
context provides, spelled exactly as given. Those are the ones the app can \
open; anything else renders as a dead label. Only invent a name when nothing \
in the catalog fits.

Every string is plain text. Do not use markdown headings. You may use LaTeX \
between $ delimiters for mathematics.\
"""

_LEVELS = {
    "middle": "a middle school student",
    "high": "a high school student",
    "college": "an undergraduate",
    "other": "a self-directed learner",
}

_MODES = {
    "explain": "Explain it at their level.",
    "simple": "Explain it as simply as possible. Short sentences. No jargon.",
    "eli10": "Explain it to a bright 10-year-old. Use an everyday analogy.",
    "deeper": "Go deeper than a first explanation. Assume the basics are known.",
    "example": "Lead with a concrete worked example and explain through it.",
    "compare": "Focus on the distinction between the concepts named.",
}


def build_user_prompt(
    *,
    question: str,
    stage: str | None = None,
    grade: str | None = None,
    curriculum: str | None = None,
    subjects: list[str] | None = None,
    weak_subjects: list[str] | None = None,
    mode: str = "explain",
    known_concepts: list[str] | None = None,
    content_title: str | None = None,
    catalog: list[str] | None = None,
) -> str:
    """Assemble the student's context around their question.

    Only what changes the answer goes in. Sending the whole profile on every
    request costs tokens on every request and buys nothing: the tutor does not
    explain derivatives differently because the student also likes history.
    """
    instruction = _MODES.get(mode, _MODES["explain"])
    lines = [f"Student question: {question}", "", f"Instruction: {instruction}"]

    context: list[str] = []
    if stage:
        context.append(f"They are {_LEVELS.get(stage, _LEVELS['other'])}.")
    if grade:
        context.append(f"Grade / year: {grade}.")
    if curriculum:
        context.append(f"Curriculum: {curriculum}.")
    if subjects:
        context.append(f"They study: {', '.join(subjects[:5])}.")
    if weak_subjects:
        context.append(
            "They are stuck on: " + ", ".join(weak_subjects[:5]) + ". "
            "Spend extra care on intuition and the mistakes students actually make there."
        )
    if known_concepts:
        # This is what stops the tutor re-explaining ground already covered.
        context.append(
            "They already understand: " + ", ".join(known_concepts[:8]) + ". "
            "Build on these rather than re-explaining them."
        )
    if content_title:
        context.append(f'They are asking while looking at: "{content_title}".')
    if catalog:
        # The names the app can actually open. Without this the model returns
        # perfectly good generic terms — "slope", "secant line" — none of which
        # match a row in the concept graph, so every related-concept chip comes
        # back dead and the rabbit hole stops at the first page.
        context.append(
            "Catalog concepts available in this app (prefer these, spelled "
            "exactly, for related_concepts): " + ", ".join(catalog[:40]) + "."
        )

    if context:
        lines += ["", "Context:", *(f"- {c}" for c in context)]
    return "\n".join(lines)


REQUIRED_KEYS = ("summary", "simple_explanation", "related_concepts")
