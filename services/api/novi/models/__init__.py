"""Every model is imported here so `Base.metadata` is complete.

Alembic compares the live database against this metadata; a model no module
imports is invisible to it and gets emitted as a DROP.
"""

from novi.models.base import Base
from novi.models.catalog import Concept, ConceptEdge, Subject
from novi.models.content import (
    PLATFORMS,
    Content,
    ContentConcept,
    Discussion,
    DiscussionComment,
)
from novi.models.learning import (
    INTERACTION_TYPES,
    MASTERY_RANK,
    MASTERY_STATES,
    AIResponse,
    ContentLike,
    Interaction,
    LearningProgress,
    PassportStamp,
    Project,
    ProjectConcept,
    Question,
    Quiz,
    QuizQuestion,
    QuizResult,
    SavedContent,
)
from novi.models.user import Profile, RateLimitBucket, Session, User

__all__ = [
    "INTERACTION_TYPES",
    "MASTERY_RANK",
    "MASTERY_STATES",
    "PLATFORMS",
    "AIResponse",
    "Base",
    "Concept",
    "ConceptEdge",
    "Content",
    "ContentConcept",
    "ContentLike",
    "Discussion",
    "DiscussionComment",
    "Interaction",
    "LearningProgress",
    "PassportStamp",
    "Profile",
    "Project",
    "ProjectConcept",
    "Question",
    "Quiz",
    "QuizQuestion",
    "QuizResult",
    "RateLimitBucket",
    "SavedContent",
    "Session",
    "Subject",
    "User",
]
