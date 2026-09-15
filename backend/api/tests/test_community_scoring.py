from src.community_scoring import MIN_DECISIVE_VOTES, confidence_score, workflow_status


def test_three_votes_do_not_settle_an_incident():
    confidence = confidence_score(weighted_votes=150, decisive_weight=150, decisive_votes=3)
    assert workflow_status(confidence, 3) == "em_analise"


def test_minimum_votes_and_weighted_consensus_can_validate():
    confidence = confidence_score(weighted_votes=250, decisive_weight=250, decisive_votes=MIN_DECISIVE_VOTES)
    assert confidence >= 70
    assert workflow_status(confidence, MIN_DECISIVE_VOTES) == "validado"


def test_rejection_requires_minimum_votes_too():
    confidence = confidence_score(weighted_votes=-250, decisive_weight=250, decisive_votes=MIN_DECISIVE_VOTES)
    assert workflow_status(confidence, MIN_DECISIVE_VOTES) == "rejeitado"
