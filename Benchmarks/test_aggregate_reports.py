import unittest

from aggregate_reports import metrics, percentile, summarize, systems_for_mode


class AggregateReportsTests(unittest.TestCase):
    def test_micro_average_counts_instances_not_document_percentages(self):
        def report(name, tp, fp, fn, negative_pages):
            p, r, f1 = metrics(tp, fp, fn)
            evaluation = {
                "system": "Cauchy production extractor",
                "truePositives": tp,
                "falsePositives": fp,
                "falseNegatives": fn,
                "precision": p,
                "recall": r,
                "f1": f1,
                "correctAbstentions": negative_pages,
                "negativePages": negative_pages,
            }
            return {
                "summary": {"pdfPath": name, "evaluations": [
                    {**evaluation, "system": system}
                    for system in (
                        "Cauchy production extractor",
                        "All syntactic mentions",
                        "Declaration heuristic",
                    )
                ]},
                "pages": [{
                    "succeeded": True,
                    "seconds": 2.0,
                    "expectedReferences": ["x"] * (tp + fn),
                    "modelAcceptedCount": tp,
                    "sourceFallbackCount": 0,
                    "disposition": "processed",
                }],
            }

        result = summarize([
            report("a.pdf", 1, 0, 0, 2),
            report("b.pdf", 8, 1, 1, 1),
        ])

        production = result["systems"]["Cauchy production extractor"]
        self.assertEqual((production["tp"], production["fp"], production["fn"]), (9, 1, 1))
        self.assertEqual(production["precision"], 0.9)
        self.assertEqual(production["correctAbstentions"], 3)

    def test_duplicate_document_is_rejected(self):
        report = {"summary": {"pdfPath": "same.pdf", "evaluations": []}, "pages": []}
        with self.assertRaisesRegex(ValueError, "duplicate document"):
            summarize([report, report])

    def test_interpolated_latency_percentile(self):
        self.assertEqual(percentile([1.0, 3.0], 0.5), 2.0)
        self.assertEqual(percentile([], 0.95), 0.0)

    def test_source_only_mode_is_labelled_and_cannot_mix_with_model_runs(self):
        self.assertEqual(systems_for_mode("source-only")[0], "Source-only extractor")
        source = {"summary": {"pdfPath": "a.pdf", "indexingMode": "source-only"}, "pages": []}
        model = {"summary": {"pdfPath": "b.pdf", "indexingMode": "on-device model"}, "pages": []}
        with self.assertRaisesRegex(ValueError, "different indexing modes"):
            summarize([source, model])


if __name__ == "__main__":
    unittest.main()
