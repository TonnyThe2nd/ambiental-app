MIN_DECISIVE_VOTES = 5


def confidence_score(*, weighted_votes: float, decisive_weight: float, decisive_votes: int) -> float:
    if decisive_weight <= 0:
        return 50.0
    evidence = min(decisive_votes / 8.0, 1.0)
    return round(max(0.0, min(100.0, 50.0 + (weighted_votes / decisive_weight) * 40.0 * evidence)), 2)


def workflow_status(confidence: float, decisive_votes: int) -> str:
    if decisive_votes < MIN_DECISIVE_VOTES:
        return "em_analise"
    if confidence >= 70:
        return "validado"
    if confidence <= 30:
        return "rejeitado"
    return "em_analise"
