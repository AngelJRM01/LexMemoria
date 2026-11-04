"""SM-2, algorithm version sm2-1. FSRS is not claimed.
Intervals: again=10 min, hard=1 day/1.2x, good=1/6/EF days,
easy=4 days/1.3*EF. Ease is bounded at 1.3. All dates are UTC.
"""
from datetime import datetime, timedelta, timezone


def schedule(state, rating, at=None):
    if rating not in (1, 2, 3, 4):
        raise ValueError('rating must be 1..4')
    at = at or datetime.now(timezone.utc)
    old = dict(state or {})
    reps = old.get('repetitions', 0)
    interval = old.get('interval', 0)
    ease = old.get('ease', 2.5)
    if rating == 1:
        reps, interval = 0, 10 / 1440
        ease = max(1.3, ease - .2)
    elif rating == 2:
        interval = max(1, interval * 1.2)
        ease = max(1.3, ease - .15)
        reps += 1
    elif rating == 3:
        interval = 1 if reps == 0 else 6 if reps == 1 else max(1, interval * ease)
        reps += 1
    else:
        interval = max(4, interval * ease * 1.3)
        ease += .15
        reps += 1
    return dict(repetitions=reps, interval=interval, ease=ease,
                dueAt=(at + timedelta(days=interval)).isoformat(),
                reviewedAt=at.isoformat(), algorithm='sm2-1',
                lapses=old.get('lapses', 0) + (1 if rating == 1 else 0))


def score(questions, answers, penalty):
    correct = wrong = blank = 0
    for q in questions:
        response = answers.get(q['id'])
        if response is None:
            blank += 1
        elif response == q['correct']:
            correct += 1
        else:
            wrong += 1
    return dict(correct=correct, wrong=wrong, blank=blank,
                score=round(correct - wrong * penalty, 4), total=len(questions))
