"""Quiz generation and grading.

Grading is server-side and the answer key never leaves the process until the
learner has answered. That is why `QuizQuestionOut` has no `correct_index`:
hiding the answer in the UI while shipping it in the payload is not hiding it.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.ai.gateway import gateway
from novi.ai.prompts import quiz as quiz_prompt
from novi.core.errors import AIUnavailable, Conflict, NotFound
from novi.core.logging import get_logger
from novi.models import (
    Concept,
    LearningProgress,
    Quiz,
    QuizQuestion,
    QuizResult,
    Subject,
    User,
)
from novi.schemas.ai import GradedAnswer, QuizAnswer, StampOut
from novi.services import knowledge

logger = get_logger(__name__)

# Concept mastered once the learner has scored this well.
MASTERY_SCORE = 0.8


def _validate_questions(raw: object, wanted: int) -> list[dict]:
    """Reject anything malformed before it reaches the database.

    A quiz with two correct answers or three options is worse than no quiz: the
    learner gets marked wrong for being right, which destroys trust in the
    mastery number the whole product is built on.
    """
    if not isinstance(raw, list):
        raise AIUnavailable("The quiz could not be generated", details={"reason": "shape"})

    good: list[dict] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        prompt = str(item.get("prompt") or "").strip()
        options = item.get("options")
        index = item.get("correct_index")
        explanation = str(item.get("explanation") or "").strip()
        if not prompt or not isinstance(options, list) or len(options) != 4:
            continue
        if not all(isinstance(o, str) and o.strip() for o in options):
            continue
        if not isinstance(index, int) or not 0 <= index < 4:
            continue
        if len({o.strip().lower() for o in options}) != 4:
            continue  # duplicated options make more than one answer correct
        good.append(
            {
                "prompt": prompt,
                "options": [o.strip() for o in options],
                "correct_index": index,
                "explanation": explanation,
            }
        )

    if len(good) < min(3, wanted):
        raise AIUnavailable(
            "The quiz could not be generated",
            details={"reason": "too_few_valid", "valid": len(good)},
        )
    return good[:wanted]


async def generate(
    db: AsyncSession, *, user: User, concept_id: uuid.UUID, count: int, difficulty: int | None
) -> tuple[Quiz, Concept]:
    concept = await db.get(Concept, concept_id)
    if concept is None:
        raise NotFound("Concept not found")
    subject = await db.get(Subject, concept.subject_id)
    level = difficulty or concept.difficulty

    result = await gateway.complete_json(
        system=quiz_prompt.SYSTEM,
        user=quiz_prompt.build_user_prompt(
            concept=concept.name,
            subject=subject.name if subject else "",
            difficulty=level,
            count=count,
        ),
        required_keys=quiz_prompt.REQUIRED_KEYS,
        temperature=0.7,
    )
    questions = _validate_questions(result.data.get("questions"), count)

    quiz = Quiz(user_id=user.id, concept_id=concept.id, difficulty=level, model=result.model)
    db.add(quiz)
    await db.flush()
    for i, q in enumerate(questions):
        db.add(
            QuizQuestion(
                quiz_id=quiz.id,
                ordinal=i,
                prompt=q["prompt"],
                options=q["options"],
                correct_index=q["correct_index"],
                explanation=q["explanation"],
            )
        )
    await db.flush()
    await db.refresh(quiz)

    await knowledge.record_interaction(
        db, user_id=user.id, kind="QUIZ_START", concept_id=concept.id
    )
    return quiz, concept


async def submit(
    db: AsyncSession, *, user: User, quiz_id: uuid.UUID, answers: list[QuizAnswer]
) -> tuple[Quiz, list[GradedAnswer], float, str, list[StampOut]]:
    quiz = (
        await db.execute(select(Quiz).where(Quiz.id == quiz_id).with_for_update())
    ).scalar_one_or_none()
    if quiz is None or quiz.user_id != user.id:
        raise NotFound("Quiz not found")
    if quiz.completed_at is not None:
        # Re-submitting would overwrite a recorded score with a second attempt
        # made with the answers already revealed.
        raise Conflict("This quiz has already been submitted", code="ALREADY_SUBMITTED")

    questions = {q.id: q for q in quiz.questions}
    graded: list[GradedAnswer] = []
    seen: set[uuid.UUID] = set()

    for answer in answers:
        question = questions.get(answer.question_id)
        if question is None or answer.question_id in seen:
            continue
        seen.add(answer.question_id)
        correct = answer.selected_index == question.correct_index
        db.add(
            QuizResult(
                quiz_id=quiz.id,
                question_id=question.id,
                selected_index=answer.selected_index,
                is_correct=correct,
            )
        )
        graded.append(
            GradedAnswer(
                question_id=question.id,
                selected_index=answer.selected_index,
                correct_index=question.correct_index,
                is_correct=correct,
                explanation=question.explanation,
            )
        )

    total = len(quiz.questions)
    correct_count = sum(1 for g in graded if g.is_correct)
    # Unanswered questions count as wrong: scoring only what was attempted
    # would let a learner "master" a concept by answering one question.
    score = (correct_count / total) if total else 0.0

    quiz.completed_at = datetime.now(UTC)
    quiz.score = score

    mastery = await knowledge.apply_quiz_result(
        db, user_id=user.id, concept_id=quiz.concept_id, score=score
    )
    await knowledge.record_interaction(
        db,
        user_id=user.id,
        kind="QUIZ_COMPLETE",
        concept_id=quiz.concept_id,
        context={"score": round(score, 3)},
    )

    stamps = await _award_for_quiz(db, user=user, quiz=quiz, score=score)
    ordinals = {q.id: q.ordinal for q in quiz.questions}
    graded.sort(key=lambda g: ordinals[g.question_id])
    return quiz, graded, score, mastery, stamps


async def _award_for_quiz(
    db: AsyncSession, *, user: User, quiz: Quiz, score: float
) -> list[StampOut]:
    """Stamps earned by this submission, and nothing else.

    Only newly-earned stamps are returned, so the client can play the
    celebration exactly once rather than every time the passport is opened.
    """
    if score < MASTERY_SCORE:
        return []

    earned: list[StampOut] = []
    concept = await db.get(Concept, quiz.concept_id)
    if concept is None:
        return []

    stamp = await knowledge.award_stamp(
        db,
        user_id=user.id,
        kind="concept",
        key=concept.slug,
        title=concept.name,
        subtitle="Learned",
        icon="checkmark.seal",
    )
    if stamp:
        earned.append(
            StampOut(kind=stamp.kind, key=stamp.key, title=stamp.title,
                     subtitle=stamp.subtitle, icon=stamp.icon)
        )

    # Count milestones. Cheap query, and only run on a passing quiz.
    learned = (
        await db.execute(
            select(LearningProgress).where(
                LearningProgress.user_id == user.id,
                LearningProgress.mastery.in_(("learned", "mastered")),
            )
        )
    ).scalars().all()

    for threshold in (1, 5, 10, 25, 50):
        if len(learned) >= threshold:
            milestone = await knowledge.award_stamp(
                db,
                user_id=user.id,
                kind="milestone",
                key=f"concepts-{threshold}",
                title=f"{threshold} Concept{'s' if threshold > 1 else ''} Learned",
                subtitle="Milestone",
                icon="trophy",
            )
            if milestone:
                earned.append(
                    StampOut(kind=milestone.kind, key=milestone.key, title=milestone.title,
                             subtitle=milestone.subtitle, icon=milestone.icon)
                )
    return earned
