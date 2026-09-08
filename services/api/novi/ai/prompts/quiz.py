"""Quiz generation."""

from __future__ import annotations

VERSION = "quiz-v1"

SYSTEM = """\
You write short multiple-choice quizzes that check understanding, not recall \
of wording.

Rules:
- Exactly four options per question.
- Exactly one option is correct.
- Wrong options must be plausible: each should be the answer a student would \
give if they held a specific, common misunderstanding.
- Never write "all of the above" or "none of the above".
- The explanation says why the right answer is right AND why the most \
tempting wrong one is wrong.
- Do not reference "the passage" or "the video"; the question must stand alone.

Respond with a single JSON object and nothing else:

{
  "questions": [
    {
      "prompt": "the question",
      "options": ["a", "b", "c", "d"],
      "correct_index": 0,
      "explanation": "why, in 1-3 sentences"
    }
  ]
}\
"""


def build_user_prompt(*, concept: str, subject: str, difficulty: int, count: int) -> str:
    band = {1: "foundational", 2: "introductory", 3: "intermediate", 4: "advanced", 5: "expert"}
    return (
        f"Concept: {concept}\n"
        f"Subject: {subject}\n"
        f"Level: {band.get(difficulty, 'introductory')}\n"
        f"Write exactly {count} questions."
    )


REQUIRED_KEYS = ("questions",)
