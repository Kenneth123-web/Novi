"""Placeholder content for the feed.

The plan says to assume the backend already has a scraped content store. It
does not yet, so this generates stand-ins — and it is worth being precise about
what that does and does not mean:

* Every row is written with `is_sample = True`, and the client renders a marker
  on it. The alternative is placeholder content that is indistinguishable from
  ingested content, which makes the app look finished when the hardest part has
  not been built.
* Creator handles are invented and generic (`@calculus.daily`). Nothing is
  attributed to a real person or channel, because a fabricated post credited to
  a real account is a fake record about a real party, not test data.
* `url` is left empty. A plausible-looking bilibili link that 404s is worse
  than an obviously absent one — it invites someone to tap it.
* Engagement numbers are derived from the item's own seed, so they are stable
  across reseeds, and they are not claims about anything real.

Titles are built from the actual concept names, so search, ranking and the
discovery rail are exercised against realistic text rather than lorem ipsum.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

# (platform, media_kind, weight) — roughly how a real mixed feed would look.
PLATFORM_MIX = [
    ("bilibili", "video", 26),
    ("youtube", "video", 18),
    ("douyin", "video", 10),
    ("kuaishou", "video", 5),
    ("xiaohongshu", "image", 16),
    ("zhihu", "article", 14),
    ("weibo", "post", 6),
    ("tieba", "post", 5),
]

VIDEO_TEMPLATES = [
    "{concept} explained in 6 minutes",
    "{concept}: the intuition first, the formula second",
    "Why {concept} confuses everyone (and the fix)",
    "{concept} — worked example, start to finish",
    "I finally understood {concept}. Here's what clicked.",
    "{concept} for {audience}",
    "The one diagram that makes {concept} obvious",
]

ARTICLE_TEMPLATES = [
    "A careful introduction to {concept}",
    "{concept}: what the textbook leaves out",
    "Common mistakes with {concept}, and why they happen",
    "How I'd teach {concept} if I could start over",
    "{concept} from three different angles",
]

IMAGE_TEMPLATES = [
    "{concept} — one page of notes",
    "My {concept} cheat sheet",
    "{concept} visualised",
    "Revision notes: {concept}",
]

POST_TEMPLATES = [
    "Does anyone else find {concept} harder than it should be?",
    "Small realisation about {concept} today",
    "{concept} finally makes sense after this",
]

AUDIENCES = ["beginners", "exam season", "people who hate formulas", "visual thinkers"]

HANDLE_PREFIXES = [
    "study", "notes", "learn", "explain", "daily", "simple", "clear", "revise",
    "tutor", "sketch", "board", "lab",
]

BODY_TEMPLATES = [
    (
        "A short walkthrough of {concept}, built around one example rather than a "
        "definition. Covers where it comes from, what it is actually for, and the "
        "mistake most people make the first time."
    ),
    (
        "Notes on {concept} from a study session. Starts from what you already "
        "know and only introduces new notation when it is needed."
    ),
    (
        "{concept}, explained without assuming you remember the prerequisites. "
        "Includes the step that textbooks usually skip."
    ),
    (
        "A discussion of {concept} with worked examples and the reasoning behind "
        "each step, rather than the answer alone."
    ),
]


@dataclass(frozen=True)
class Sample:
    external_id: str
    platform: str
    media_kind: str
    title: str
    description: str
    creator: str
    topic: str
    tags: list[str]
    likes: int
    comments: int
    quality: float
    difficulty: int
    thumbnail_ratio: float
    duration_seconds: int | None
    language: str


def _rng(seed: str) -> list[int]:
    """A deterministic byte stream from a seed.

    Deterministic on purpose: the same concept produces the same items on every
    reseed, so a screenshot taken today still matches the database tomorrow and
    the feed is a stable grid rather than noise. `random` seeded globally would
    couple every generated item to the order the others were generated in.
    """
    digest = hashlib.sha256(seed.encode()).digest()
    return list(digest + hashlib.sha256(digest).digest())


def _pick(items: list, byte: int):
    return items[byte % len(items)]


def _weighted_platform(byte: int) -> tuple[str, str]:
    total = sum(w for _, _, w in PLATFORM_MIX)
    target = byte % total
    running = 0
    for platform, kind, weight in PLATFORM_MIX:
        running += weight
        if target < running:
            return platform, kind
    return PLATFORM_MIX[0][0], PLATFORM_MIX[0][1]


def build_for_concept(
    concept_slug: str, concept_name: str, difficulty: int, count: int = 4
) -> list[Sample]:
    out: list[Sample] = []
    for i in range(count):
        b = _rng(f"{concept_slug}:{i}")
        # Item 0 is always an English YouTube video. An English-only profile
        # (the only language the client currently offers) must still have
        # something to rank and search; the rest of the mix stays multilingual.
        if i == 0:
            platform, kind = "youtube", "video"
        else:
            platform, kind = _weighted_platform(b[0])

        templates = {
            "video": VIDEO_TEMPLATES,
            "article": ARTICLE_TEMPLATES,
            "image": IMAGE_TEMPLATES,
            "post": POST_TEMPLATES,
        }[kind]
        title = _pick(templates, b[1]).format(
            concept=concept_name, audience=_pick(AUDIENCES, b[2])
        )

        handle = f"@{_pick(HANDLE_PREFIXES, b[3])}.{concept_slug.split('-')[0]}"
        language = "zh" if platform in {"bilibili", "douyin", "kuaishou", "xiaohongshu",
                                        "zhihu", "weibo", "tieba"} else "en"

        # Popularity is heavy-tailed: most items are small, a few are large.
        magnitude = 1 + (b[4] % 4)
        likes = (b[5] + 1) * (10**magnitude) // 40

        out.append(
            Sample(
                external_id=f"{concept_slug}-{i}",
                platform=platform,
                media_kind=kind,
                title=title,
                description=_pick(BODY_TEMPLATES, b[6]).format(concept=concept_name),
                creator=handle,
                topic=concept_name,
                tags=[concept_slug, kind],
                likes=likes,
                comments=max(1, likes // (8 + b[7] % 20)),
                # Centred just above the middle so ranking has something to
                # separate: an all-0.5 store makes the quality term inert.
                quality=round(0.45 + (b[8] % 50) / 100, 2),
                difficulty=max(1, min(5, difficulty + (b[9] % 3) - 1)),
                # 0.75 (portrait) through 1.0 (square) to 1.33 (landscape).
                # The masonry needs the spread or every column lines up.
                thumbnail_ratio=[0.75, 0.8, 1.0, 1.33][b[10] % 4],
                duration_seconds=(60 + (b[11] % 25) * 30) if kind == "video" else None,
                language=language,
            )
        )
    return out


# ── Community discussions ────────────────────────────────────────────────────
# Same rules: invented communities and authors, `is_sample = True`, no URLs.

DISCUSSION_TEMPLATES = [
    (
        "{concept}: why does this feel so unintuitive?",
        (
            "I can do the problems but I don't feel like I understand what is "
            "actually going on with {concept}. Is that normal, or have I missed "
            "something fundamental?"
        ),
        [
            (
                "Completely normal. Procedural fluency comes first and understanding "
                "catches up later. Most people have it the other way round in their head."
            ),
            (
                "What helped me was working one example so slowly it felt stupid, and "
                "asking at every line why that step was allowed."
            ),
            (
                "Honestly a lot of courses teach {concept} in the wrong order. The "
                "motivation usually comes after the mechanics, which is backwards."
            ),
            (
                "Try explaining it out loud to someone who doesn't know it. You find "
                "the gap in about thirty seconds."
            ),
        ],
    ),
    (
        "The explanation of {concept} that finally worked for me",
        (
            "Posting this because I struggled for weeks. The thing that unlocked "
            "{concept} was realising it is answering a question I already cared "
            "about, rather than being a rule to memorise."
        ),
        [
            (
                "This is the framing I wish I'd had. Memorising the rule first is why "
                "it never stuck."
            ),
            (
                "Agreed, though I'd add that the notation genuinely is bad here and "
                "that's not the learner's fault."
            ),
            (
                "Careful with this analogy — it breaks down in the general case, which "
                "trips people up later."
            ),
            "Saving this. The step everyone skips is exactly the one you wrote out.",
        ],
    ),
    (
        "{concept} — learn it properly, or just enough to pass?",
        (
            "Short on time before exams. Wondering whether {concept} is one of "
            "those topics that keeps coming back or one you can get by on."
        ),
        [
            "It comes back. Almost everything after it assumes you actually have it.",
            (
                "Depends what you do next, but the version you learn 'just to pass' "
                "tends to be the version you have to unlearn."
            ),
            "You can pass without it. You'll pay for that later, and with interest.",
            (
                "Learn the intuition properly and the procedure roughly. That ratio has "
                "served me well."
            ),
        ],
    ),
]

# Keyed by subject: a calculus thread landing in r/learnprogramming is the kind
# of detail that makes a demo feel generated rather than real.
COMMUNITIES = {
    "mathematics": ["r/learnmath", "r/calculus", "r/askmath"],
    "physics": ["r/AskPhysics", "r/physicsstudents", "r/askscience"],
    "chemistry": ["r/chemhelp", "r/chemistry", "r/askscience"],
    "biology": ["r/biology", "r/askscience", "r/premed"],
    "computer-science": ["r/learnprogramming", "r/cscareerquestions", "r/algorithms"],
    "economics": ["r/economics", "r/AskEconomics"],
    "history": ["r/AskHistorians", "r/history"],
    "geography": ["r/geography", "r/askscience"],
    "psychology": ["r/psychology", "r/AskPsychology"],
    "languages": ["r/languagelearning", "r/EnglishLearning"],
    "literature": ["r/literature", "r/books"],
    "art": ["r/ArtistLounge", "r/design"],
    "business": ["r/business", "r/startups"],
    "engineering": ["r/engineering", "r/AskEngineers"],
}
DEFAULT_COMMUNITIES = ["r/studytips", "r/explainlikeimfive"]

AUTHOR_WORDS = ["quiet", "late", "curious", "rusty", "second", "half", "plain", "slow"]
AUTHOR_NOUNS = ["reader", "student", "learner", "notebook", "pencil", "draft", "margin"]


@dataclass(frozen=True)
class SampleDiscussion:
    external_id: str
    community: str
    title: str
    body: str
    author: str
    upvotes: int
    comments: list[str]


def build_discussions(
    concept_slug: str, concept_name: str, subject_slug: str = ""
) -> list[SampleDiscussion]:
    out: list[SampleDiscussion] = []
    for i, (title_t, body_t, comment_ts) in enumerate(DISCUSSION_TEMPLATES):
        b = _rng(f"disc:{concept_slug}:{i}")
        author = f"{_pick(AUTHOR_WORDS, b[0])}_{_pick(AUTHOR_NOUNS, b[1])}{b[2] % 90 + 10}"
        out.append(
            SampleDiscussion(
                external_id=f"d-{concept_slug}-{i}",
                community=_pick(COMMUNITIES.get(subject_slug, DEFAULT_COMMUNITIES), b[3]),
                title=title_t.format(concept=concept_name),
                body=body_t.format(concept=concept_name),
                author=author,
                upvotes=(b[4] + 1) * 7,
                comments=[c.format(concept=concept_name) for c in comment_ts],
            )
        )
    return out
