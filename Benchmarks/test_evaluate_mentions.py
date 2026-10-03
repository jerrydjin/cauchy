import unittest

from evaluate_mentions import score_pages


class MentionScoringTests(unittest.TestCase):
    def test_keeps_multiple_mentions_on_one_page(self):
        self.assertEqual(score_pages([4, 4, 7], [4, 7, 7]), (2, 1, 1))

    def test_negative_case_penalizes_spurious_mention(self):
        self.assertEqual(score_pages([], [9]), (0, 1, 0))


if __name__ == "__main__":
    unittest.main()
