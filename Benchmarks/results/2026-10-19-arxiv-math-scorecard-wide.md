# arXiv maths scorecard

**31 of 60 random papers work with no fixes on main.**
**27 of 60 pass if the open hover and chat branches are both applied.**
**original-20:** main 15 of 20, hover+chat 12 of 20, hover reference-only 7 of 20.
**added-40:** main 16 of 40, hover+chat 15 of 40, hover reference-only 7 of 40.

A paper works with no fixes when all of these hold:

- At least 8 theorem, lemma, definition, equation, or section references are recoverable.
- At least 90% of them resolve. A statement resolves when the detector names the right kind and number and the source-fallback index contains that key. A section reference resolves when “what is section N about” lands on the page that prints the heading.
- There is no wrong link: no citation span opens an indexed statement, no printed reference opens a different statement, and the index contains no statement the HTML does not declare.
- No bracket or author–year citation is emitted as a local reference.
- Every probed “what is section N about” question lands on the heading page.

Main locates a section written as “N. Title” or “N.N. Title.” A run-in heading such as “2.4. Small cases. Let G be a graph” is that section; the sentence after the title period is the paragraph. A longer title with no following sentence, such as “6. Discriminants of minor-free graphs and completable cycles in the plane”, is still a heading. “Subsection 2.3” and “Subsubsection 6.2.1” are references to those units. An HTML link whose target is an enumerated item, such as #S4.I1.i2, is not a section. A TeX annotation nested in a heading is not part of the title, and “SL 2” matches a bookmark “SL2”. Main also drops a local reference inside [12], [IK99, Lemma 1.15], (Smith 2019), or Smith et al. [2019]; an interval such as [0, 1] is not a citation. A bare integer with text to its right, such as “(1) f ∈ W”, is an enumerated item and is not indexed as an equation. A number alone on its line is an equation when the next line is a formula, as in “(1)” followed by “xn+m xn = P(...)”. A dotted tag alone on its line, such as “(2.4)”, is an equation even when the math font extracts no equals sign; a bare integer on its own line is not. A section number on its own line joins the next line when both are emphasized: bold for a section, italic for a dotted subsection. “Lemmas 4.6” is lemma 4.6, and “Lemma 2” retrieves a lemma numbered 2.1. A parenthetical printed on the declaration, such as “(Zorn)”, is stored as the statement name. Dropping only the section-question condition, 31 of 60 pass on main and 14 of 60 pass on the hover branch. The headline above keeps the section question.

A bracket that the detector does not open is not a wrong link. The heading page for a section question is the PDF outline entry whose title matches the HTML heading, or else a title-shaped line. A numbered sentence is not that heading. An outline bookmark that reads “Introduction” rather than “1. Introduction” is still section 1 when it is the first section bookmark. A citation bracket may be split by a line break, as in “[17, Theorem 3.31(c)]”. The HTML declaration list includes a plural tag such as “Examples 6.7” and a bold run-in such as “Remark 3.13.” When every HTML equation tag is a bare integer but the PDF prints “(1.1)”, and every HTML statement uses one counter but the PDF prints “Remark 2.1”, the score uses the printed number.

Shared counters, such as a theorem followed by a lemma with the next number, appear on 41 of 60 papers. The index key is the kind plus the full number, so the pair resolves when both declarations are indexed.

Text comes from PyMuPDF’s content stream, the stand-in for `PDFPage.string`. Equation x-positions are glyph-box fractions, the stand-in for PDFKit selection bounds. No model is called; index time is the deterministic source fallback. Token estimates are input size only and were not billed.

An exact printed query such as “Lemma 2.1” is served from the existing index on 56/58 comparable papers (the key must already be indexed). A shortened query such as “Lemma 2” retrieves the full number on 46/47 of those papers. Literal “Lemma 4” hits a lemma numbered exactly 4 on 2 papers: these papers print dotted numbers, so 4.1 is not lemma 4. A parenthetical name is stored when the PDF prints one; this corpus does not put that name in the HTML theorem tag.

## What the failing papers hit first

29 of 60 random papers fail on main. The first check is the earliest gate in the pass rule: enough references, then 90% resolution, wrong links, citation emissions, false declarations, and section questions. A later gate can still fail the same paper; the blocking count is every paper that fails that check.

| First failing check | Papers | Blocking count |
|---|---:|---:|
| fewer than 8 in-scope references | 3 | 3 |
| resolution under 90% | 17 | 17 |
| wrong link | 1 | 1 |
| indexed statement absent from the HTML | 8 | 13 |
| section question missed the heading page | 0 | 4 |

Papers by the first check they fail:

- **fewer than 8 in-scope references** (3): 2201.01371, 2202.01959, 2301.09975
- **resolution under 90%** (17): 2610.04096, 2610.19333, 2101.03789, 2201.01481, 2601.02568, 2401.01030, 2101.04000, 2501.06662, 2601.08804, 2401.01475, 2501.07680, 2301.06347, 2601.16295, 2601.16548, 2201.03733, 2101.03716, 2201.01899
- **wrong link** (1): 2501.05947
- **indexed statement absent from the HTML** (8): 2610.14417, 2610.21864, 2610.14991, 2401.03709, 2101.08227, 2401.06100, 2601.05136, 2401.09156

## Author–year citations in the PDF text

Across the 60 random papers, the text layer contains 1 parenthetical citations of the form (Smith 2019) and 7 of the form Smith et al. [2019]. It contains 1469 alphanumeric keys such as [IK99], 189 of them qualified with a theorem, lemma, or equation, on 14 papers: 2610.21544, 2610.04096, 2610.21303, 2610.19333, 2610.19307, 2610.21864, 2601.08804, 2401.01475, 2301.06347, 2401.03520, 2102.00901, 2501.05947, 2601.05136, 2401.09156. Main emits 0 of those spans as local references; the hover profile, which still only suppresses numeric brackets, emits 248. A count of 0 on main is the suppression firing. The HTML citation-style label does not say author–year, because the HTML cite element often omits the key the PDF prints.

## Random papers

| arXiv | cat | pages | class | main | hover | chat | both | index s | model toks |
|---|---|---:|---|---|---|---|---|---:|---:|
| 2610.21544 | AG | 12 | amsart | pass | 97% (57/59) | pass | 98% (58/59) | 0.2 | 13355 |
| 2610.11671 | AT | 27 | amsart | pass | 93% (62/67) | pass | pass | 0.3 | 26453 |
| 2610.20976 | AP | 42 | article | pass | 88% (349/395) | pass | pass | 0.7 | 50978 |
| 2610.21341 | CO | 29 | amsart | pass | 78% (100/128) | pass | pass | 0.6 | 36924 |
| 2610.04096 | CT | 23 | amsart | 87% (20/23) | 70% (16/23) | 87% (20/23) | 87% (20/23) | 0.4 | 30252 |
| 2610.21303 | DG | 54 | scrartcl | pass | 91% (100/110) | pass | 100% (110/110) | 0.6 | 56907 |
| 2610.21627 | DS | 20 | amsart | pass | 100% (90/90) | pass | pass | 0.3 | 21567 |
| 2610.18041 | FA | 25 | amsart | pass | 96% (217/225) | pass | pass | 0.5 | 31551 |
| 2610.20306 | GR | 14 | amsart | pass | 84% (47/56) | pass | pass | 0.3 | 17071 |
| 2610.19333 | GT | 36 | amsart | 74% (43/58) | 48% (30/63) | 74% (43/58) | 68% (43/63) | 0.6 | 35071 |
| 2610.14417 | LO | 19 | amsart | 95% (55/58) | 95% (55/58) | 95% (55/58) | 95% (55/58) | 0.5 | 24257 |
| 2610.16227 | CA | 16 | amsart | pass | 97% (122/126) | pass | pass | 0.2 | 16309 |
| 2610.19307 | NT | 27 | amsart | pass | 85% (40/47) | pass | 98% (46/47) | 0.4 | 20456 |
| 2610.18580 | NA | 29 | siamart251216 | pass | 98% (119/121) | pass | pass | 0.8 | 27773 |
| 2610.13792 | OA | 41 | amsart | pass | 90% (88/98) | pass | pass | 0.5 | 44349 |
| 2610.19840 | OC | 22 | article | pass | 84% (103/122) | pass | pass | 0.3 | 17474 |
| 2610.21864 | PR | 40 | article | 98% (188/192) | 96% (184/192) | 98% (188/192) | 98% (188/192) | 0.8 | 52248 |
| 2610.15448 | QA | 17 | article | pass | 98% (79/81) | pass | pass | 0.4 | 18592 |
| 2610.14991 | RT | 30 | amsart | 96% (117/122) | 86% (105/122) | 96% (117/122) | 96% (117/122) | 0.4 | 34278 |
| 2610.11661 | RA | 25 | amsart | pass | 100% (44/44) | pass | pass | 0.4 | 29710 |
| 2101.03789 | AG | 62 | article | 76% (92/121) | 60% (73/121) | 76% (92/121) | 76% (92/121) | 0.9 | 49299 |
| 2401.03709 | AG | 20 | amsart | 100% (46/46) | 100% (46/46) | 100% (46/46) | 100% (46/46) | 0.3 | 22727 |
| 2201.01481 | AT | 14 | journal | 48% (24/50) | 34% (17/50) | 48% (24/50) | 48% (24/50) | 0.3 | 15295 |
| 2501.15569 | AT | 29 | amsart | pass | 94% (112/119) | pass | pass | 0.3 | 35651 |
| 2301.04601 | AP | 31 | not-found | pass | 92% (154/167) | pass | pass | 0.5 | 34554 |
| 2601.02568 | AP | 49 | article | 68% (86/127) | 65% (82/127) | 68% (86/127) | 68% (86/127) | 0.9 | 37314 |
| 2401.01030 | CO | 10 | article | 89% (41/46) | 89% (41/46) | 89% (41/46) | 89% (41/46) | 0.2 | 6580 |
| 2101.04000 | CO | 4 | amsart | 89% (24/27) | 89% (24/27) | 89% (24/27) | 89% (24/27) | 0.0 | 4411 |
| 2501.06662 | CT | 26 | tac | 84% (71/85) | 64% (54/85) | 84% (71/85) | 84% (71/85) | 0.3 | 12485 |
| 2202.07067 | CT | 28 | article | pass | 90% (36/40) | pass | pass | 0.4 | 31234 |
| 2601.08804 | DG | 17 | article | 81% (50/62) | 73% (45/62) | 81% (50/62) | 81% (50/62) | 0.2 | 16643 |
| 2301.02591 | DG | 39 | article | pass | 98% (277/284) | pass | pass | 0.7 | 35806 |
| 2101.08227 | DS | 31 | article | 94% (204/216) | 77% (167/216) | 94% (204/216) | 94% (204/216) | 0.5 | 34321 |
| 2401.01475 | DS | 41 | amsart | 78% (295/377) | 75% (283/377) | 78% (295/377) | 78% (295/377) | 0.8 | 48488 |
| 2201.01371 | FA | 9 | amsart | 100% (6/6) | 100% (6/6) | 100% (6/6) | 100% (6/6) | 0.1 | 8601 |
| 2501.07680 | FA | 25 | siamart251216 | 76% (62/82) | 71% (58/82) | 76% (62/82) | 76% (62/82) | 0.5 | 29089 |
| 2301.06347 | GR | 17 | amsart | 82% (75/92) | 74% (68/92) | 82% (75/92) | 82% (75/92) | 0.5 | 16955 |
| 2601.16295 | GR | 27 | amsart | 86% (95/110) | 74% (81/110) | 86% (95/110) | 86% (95/110) | 0.3 | 27466 |
| 2401.03520 | GT | 10 | amsart | pass | 96% (26/27) | pass | 96% (26/27) | 0.3 | 11060 |
| 2102.00901 | GT | 20 | amsart | pass | 78% (42/54) | pass | 93% (50/54) | 0.4 | 21854 |
| 2502.05733 | LO | 9 | article | pass | 60% (6/10) | pass | pass | 0.2 | 11353 |
| 2202.01959 | LO | 14 | article | 100% (4/4) | 100% (4/4) | 100% (4/4) | 100% (4/4) | 0.3 | 14172 |
| 2601.16548 | CA | 19 | article | 84% (234/278) | 84% (234/278) | 84% (234/278) | 84% (234/278) | 0.2 | 19983 |
| 2301.09975 | CA | 13 | article | 100% (0/0) | 100% (0/0) | 100% (0/0) | 100% (0/0) | 0.2 | 13861 |
| 2101.05480 | NT | 55 | ipart | pass | 81% (107/132) | pass | pass | 2.0 | 55541 |
| 2401.06100 | NT | 20 | sn-jnl | 97% (56/58) | 91% (53/58) | 97% (56/58) | 97% (56/58) | 0.3 | 13000 |
| 2201.03733 | NA | 52 | article | 85% (351/411) | 84% (344/411) | 85% (351/411) | 85% (351/411) | 1.2 | 52709 |
| 2501.06373 | NA | 25 | amsart | pass | 89% (159/178) | pass | pass | 0.9 | 27832 |
| 2301.13423 | OA | 41 | amsart | pass | 92% (152/166) | pass | pass | 0.5 | 43303 |
| 2601.14873 | OA | 29 | amsart | pass | 89% (78/88) | pass | pass | 0.4 | 24794 |
| 2401.05617 | OC | 15 | optica-article | pass | 81% (63/78) | pass | pass | 0.6 | 18352 |
| 2101.03716 | OC | 25 | article | 49% (48/98) | 44% (43/98) | 49% (48/98) | 49% (48/98) | 0.5 | 21905 |
| 2501.05947 | PR | 20 | article | 99% (123/124) | 99% (123/124) | 99% (123/124) | 99% (123/124) | 0.2 | 21398 |
| 2201.01899 | PR | 30 | not-found | 88% (179/203) | 92% (187/203) | 88% (179/203) | pass | 0.4 | 30363 |
| 2601.05136 | QA | 19 | sl2art | 97% (34/35) | 94% (34/36) | 97% (34/35) | 94% (34/36) | 0.1 | 21533 |
| 2301.02670 | QA | 41 | article | pass | 61% (49/80) | pass | pass | 0.5 | 39644 |
| 2101.04091 | RT | 11 | amsart | pass | 83% (57/69) | pass | pass | 0.2 | 16523 |
| 2401.09156 | RT | 120 | amsart | 92% (321/349) | 64% (223/349) | 92% (321/349) | 92% (321/349) | 1.8 | 129251 |
| 2201.09321 | RA | 29 | article | pass | 60% (12/20) | pass | pass | 0.7 | 30169 |
| 2501.19379 | RA | 21 | amsart | pass | 96% (45/47) | pass | pass | 0.4 | 27430 |

## Per paper

### 2610.21544 — On the variety of sum of powers of certain complete intersection forms

math.AG, 12 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (29). Role: random.
Shared counters: Lemma 2.1 then Theorem 2.2; Theorem 3.22 then Proposition 3.23.
HTML declaration strings found in the PDF: 16/16 named, 14/14 equations.
Main resolves 98% (58/59); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.22s extraction. A model pass would send about 13355 input tokens across 9 pages.
Main fails: .
Hover+chat fails: 7 citation spans emitted as local refs.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.3 (heading on p.3, Computation of VSP)
- ok `what is section 4 about` → p.10 (heading on p.10, Final remarks)

### 2610.11671 — A complete classification of the rational realization of gap-two products of Eilenberg--MacLane spaces as classifying spaces

math.AT, 27 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (19). Role: random.
Shared counters: Lemma 4.2 then Proposition 4.3; Proposition 4.3 then Lemma 4.4; Lemma 4.4 then Proposition 4.5; Proposition 4.5 then Lemma 4.6; Lemma 4.10 then Proposition 4.11; Proposition 5.2 then Lemma 5.3.
HTML declaration strings found in the PDF: 23/23 named, 9/9 equations.
Main resolves 99% (66/67); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.31s extraction. A model pass would send about 26453 input tokens across 20 pages.
Main fails: .
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.5 (heading on p.5, Reduction to two cases)
- ok `what is section 5 about` → p.20 (heading on p.20, The branch n ≤ 4)
- ok `what is section 4.5 about` → p.17 (heading on p.17, Realization when n ≥ 5)

### 2610.20976 — Chemotaxis models with signal-dependent sensitivity and a logistic-type source, III: Bifurcation and spike-like solutions

math.AP, 42 pages, 0 two-column pages, class `article`, citations numeric+qualified (27). Role: random.
HTML declaration strings found in the PDF: 14/14 named, 111/113 equations.
Main resolves 92% (363/395); misses 5, extraction gaps 27, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.06s plus 0.65s extraction. A model pass would send about 50978 input tokens across 37 pages.
Main fails: .
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 '(2.18)': not in the statement index
- p.22 '(2.18)': not in the statement index
- p.19 '(2.28)': not in the statement index
- p.20 '(2.28)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 4 about` → p.27 (heading on p.27, Extension of the local bifurcation branches and proof of The)
- ok `what is section 6 about` → p.36 (heading on p.36, Numerical analysis of the bifurcation and spike-like solutio)
- ok `what is section 4.1 about` → p.30 (heading on p.30, Proof of Theorem 1.3 (1))

### 2610.21341 — Matrix Completion Discriminants

math.CO, 29 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (29). Role: random.
Shared counters: Proposition 2.1 then Lemma 2.2; Lemma 2.2 then Proposition 2.3; Proposition 2.3 then Theorem 2.4; Corollary 3.2 then Proposition 3.3; Proposition 4.3 then Lemma 4.4; Lemma 4.5 then Proposition 4.6.
HTML declaration strings found in the PDF: 33/33 named, 16/16 equations.
Main resolves 97% (124/128); misses 0, extraction gaps 4, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.05s plus 0.54s extraction. A model pass would send about 36924 input tokens across 24 pages.
Main fails: .
Number search `Lemma 2.2` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.11 (heading on p.11, Clique-sum)
- ok `what is section 6 about` → p.19 (heading on p.19, MC discriminants of K 4 -minor-free graphs and cycle-complet)
- ok `what is section 3.3 about` → p.10 (heading on p.10, Coincidence beyond cycle-completable graphs)

### 2610.04096 — The Benson--Etingof--Ostrik conjecture for finite tensor categories

math.CT, 23 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (32). Role: random.
Shared counters: Lemma 3.4 then Proposition 3.5; Proposition 3.5 then Corollary 3.6; Lemma 3.16 then Theorem 3.17; Theorem 3.17 then Lemma 3.18; Theorem 4.1 then Lemma 4.2; Proposition 4.5 then Lemma 4.6.
HTML declaration strings found in the PDF: 37/37 named, 10/10 equations.
Main resolves 87% (20/23); misses 0, extraction gaps 3, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.04s plus 0.38s extraction. A model pass would send about 30252 input tokens across 20 pages.
Main fails: resolution 87.0% is under 90%; 1 indexed statement is not in the HTML declarations.
Hover+chat fails: resolution 87.0% is under 90%; 30 citation spans emitted as local refs; 1 indexed statement is not in the HTML declarations.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.6 (heading on p.6, The refined Steinberg splitting conjecture)
- ok `what is section 4 about` → p.17 (heading on p.17, The Benson–Etingof–Ostrik conjecture)
- ok `what is section 3.3 about` → p.16 (heading on p.16, Steinberg splitting for elementary abelian groups)

### 2610.21303 — Asymptotics of the Moduli Spaces of Parabolic $\mathrm{SL}(3,\mathbb C)$-Higgs Bundles

math.DG, 54 pages, 0 two-column pages, class `scrartcl`, citations qualified (68). Role: random.
Shared counters: Proposition 2.7 then Lemma 2.8; Lemma 2.8 then Proposition 2.9; Proposition 4.3 then Lemma 4.4; Proposition 4.6 then Theorem 4.7; Theorem 4.7 then Lemma 4.8; Lemma 4.8 then Proposition 4.9.
HTML declaration strings found in the PDF: 37/37 named, 80/80 equations.
Main resolves 100% (110/110); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.06s plus 0.52s extraction. A model pass would send about 56907 input tokens across 43 pages.
Main fails: .
Hover+chat fails: 58 citation spans emitted as local refs.
Number search `Lemma 2.8` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 4 about` → p.21 (heading on p.21, Approximate and exact solutions)
- ok `what is section 6 about` → p.43 (heading on p.43, ALG asymptotics and compactification)
- ok `what is section 4.2 about` → p.24 (heading on p.24, The linearized equation)

### 2610.21627 — Degree Growth of Rational Maps with Laurent Property

math.DS, 20 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (18). Role: random.
HTML declaration strings found in the PDF: 24/24 named, 19/19 equations.
Main resolves 100% (90/90); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.25s extraction. A model pass would send about 21567 input tokens across 16 pages.
Main fails: .
Number search `Lemma 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.7 (heading on p.7, Computing Algebraic Entropy)
- ok `what is section 4 about` → p.14 (heading on p.14, Growth Rate Sequences of Gale–Robinson)
- ok `what is section 3.3 about` → p.11 (heading on p.11, Proof of Theorem 2)

### 2610.18041 — Completely symmetric subspaces of noncommutative $L_p$-spaces

math.FA, 25 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (62). Role: random.
Shared counters: Theorem 1.1 then Corollary 1.2; Corollary 1.2 then Theorem 1.3.
HTML declaration strings found in the PDF: 10/10 named, 65/65 equations.
Main resolves 97% (219/225); misses 6, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.45s extraction. A model pass would send about 31551 input tokens across 23 pages.
Main fails: .
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 '(39)': not in the statement index
- p.19 '(39)': not in the statement index
- p.17 '(41)': not in the statement index
- p.24 '(64)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 2 about` → p.3 (heading on p.3, Preliminaries)
- ok `what is section 3 about` → p.5 (heading on p.5, Proofs of the main results)
- ok `what is section 3.2 about` → p.8 (heading on p.8, Upper estimate by interpolation)

### 2610.20306 — The zero divisor and augmentation conjectures for medial quandle rings

math.GR, 14 pages, 0 two-column pages, class `amsart`, citations numeric (51). Role: random.
Shared counters: Proposition 3.3 then Lemma 3.4; Lemma 3.4 then Proposition 3.5; Proposition 5.1 then Lemma 5.2; Lemma 6.5 then Proposition 6.6; Proposition 6.6 then Theorem 6.7.
HTML declaration strings found in the PDF: 38/38 named, 2/2 equations.
Main resolves 93% (52/56); misses 0, extraction gaps 4, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.30s extraction. A model pass would send about 17071 input tokens across 11 pages.
Main fails: .
Number search `Lemma 3.4` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.7 (heading on p.7, The zero divisor conjecture)
- ok `what is section 6 about` → p.10 (heading on p.10, The augmentation conjecture)
- ok `what is section 3.2 about` → p.6 (heading on p.6, Retracts)

### 2610.19333 — Algebraic overtwistedness of contact $(+1)$-surgeries via augmented Floer theories

math.GT, 36 pages, 0 two-column pages, class `amsart`, citations qualified (84). Role: random.
Shared counters: Theorem 1.1 then Corollary 1.2; Proposition 3.3 then Corollary 3.4.
HTML declaration strings found in the PDF: 25/28 named, 10/15 equations.
Main resolves 74% (43/58); misses 0, extraction gaps 15, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 8. Index built in 0.06s plus 0.54s extraction. A model pass would send about 35071 input tokens across 23 pages.
Main fails: resolution 74.1% is under 90%; 8 indexed statements are not in the HTML declarations.
Hover+chat fails: resolution 68.3% is under 90%; 5 wrong links; 40 citation spans emitted as local refs; 8 indexed statements are not in the HTML declarations.
Number search `Lemma 3.6` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.8 (heading on p.8, Symplectic cohomology, wrapped Floer cohomology, and contact)
- ok `what is section 5 about` → p.30 (heading on p.30, Proof of the main results)
- ok `what is section 3.3 about` → p.14 (heading on p.14, Structures on symplectic cohomology and wrapped Floer cohomo)

### 2610.14417 — A Nullstellensatz for the field of complex Laurent series

math.LO, 19 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (34). Role: random.
Shared counters: Lemma 4.2 then Theorem 4.3; Lemma 5.2 then Theorem 5.3; Theorem 5.3 then Lemma 5.4; Lemma 5.4 then Proposition 5.5; Proposition 5.5 then Corollary 5.6; Proposition 6.3 then Lemma 6.4.
HTML declaration strings found in the PDF: 38/39 named, 1/1 equations.
Main resolves 95% (55/58); misses 3, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.04s plus 0.48s extraction. A model pass would send about 24257 input tokens across 15 pages.
Main fails: 1 indexed statement is not in the HTML declarations.
Hover+chat fails: 1 indexed statement is not in the HTML declarations.
Number search `Lemma 3.2` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 'Theorem 8.3': not in the statement index
- p.17 'Theorem 8.3': not in the statement index
- p.18 'Theorem 8.3': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 5 about` → p.7 (heading on p.7, Formally T -adic fields)
- ok `what is section 9 about` → p.18 (heading on p.18, Open questions)
- ok `what is section 2.2 about` → p.4 (heading on p.4, Radicals and zero sets)

### 2610.16227 — Contractivity of Rudin's diagonal restriction operator for $H^p$ of the polydisc

math.CA, 16 pages, 0 two-column pages, class `amsart`, citations numeric (22). Role: random.
Shared counters: Theorem 1.1 then Lemma 1.2; Lemma 2.1 then Theorem 2.2; Theorem 2.2 then Lemma 2.3; Theorem 3.2 then Lemma 3.3.
HTML declaration strings found in the PDF: 15/15 named, 14/14 equations.
Main resolves 99% (125/126); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.22s extraction. A model pass would send about 16309 input tokens across 12 pages.
Main fails: .
Number search `Lemma 1.2` served: True. Short query `Lemma 1` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.7 (heading on p.7, Extension to the polydisc)
- ok `what is section 4 about` → p.11 (heading on p.11, Applications)
- ok `what is section 4.2 about` → p.12 (heading on p.12, Khinchin’s inequality for Steinhaus variables)

### 2610.19307 — Zero-cycles and Brauer groups on certain Enriques surfaces

math.NT, 27 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (49). Role: random.
Shared counters: Proposition 2.10 then Lemma 2.11; Lemma 2.11 then Theorem 2.12; Theorem 3.2 then Proposition 3.3; Lemma 3.7 then Theorem 3.8; Theorem 4.6 then Lemma 4.7; Lemma 4.8 then Corollary 4.9.
HTML declaration strings found in the PDF: 31/31 named, 0/0 equations.
Main resolves 100% (46/46); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.41s extraction. A model pass would send about 20456 input tokens across 14 pages.
Main fails: .
Hover+chat fails: 1 wrong link; 18 citation spans emitted as local refs.
Number search `Lemma 2.7` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.8 (heading on p.8, Brauer Groups of K3 and Enriques Surfaces)
- ok `what is section 5 about` → p.24 (heading on p.24, Example and Application to Weak Approximation)
- ok `what is section 2.4 about` → p.7 (heading on p.7, Upper Bounds on Chow Groups of Enriques Surfaces)

### 2610.18580 — A two-level preconditioner for discontinuous virtual element methods with irregular subdomains

math.NA, 29 pages, 0 two-column pages, class `siamart251216`, citations numeric+qualified (25). Role: random.
HTML declaration strings found in the PDF: 18/18 named, 33/33 equations.
Main resolves 98% (119/121); misses 0, extraction gaps 2, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.80s extraction. A model pass would send about 27773 input tokens across 21 pages.
Main fails: .
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.10 (heading on p.10, Two level overlapping Schwarz methods)
- ok `what is section 7 about` → p.25 (heading on p.25, Conclusions and final remarks)
- ok `what is section 4.2 about` → p.10 (heading on p.10, Continuous reduced coarse space)

### 2610.13792 — The generator problem for C*-algebras with comparison

math.OA, 41 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (68). Role: random.
Shared counters: Lemma 2.8 then Corollary 2.9; Theorem 2.11 then Proposition 2.12; Proposition 3.4 then Lemma 3.5; Lemma 3.5 then Theorem 3.6; Lemma 4.7 then Theorem 4.8; Theorem 4.8 then Lemma 4.9.
HTML declaration strings found in the PDF: 39/39 named, 146/146 equations.
Main resolves 94% (92/98); misses 0, extraction gaps 6, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.06s plus 0.49s extraction. A model pass would send about 44349 input tokens across 33 pages.
Main fails: .
Number search `Lemma 2.3` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.10 (heading on p.10, Tracially AF algebras)
- ok `what is section 4 about` → p.20 (heading on p.20, C ∗ -algebras with a Cantor spectrum subalgebra)
- ok `what is section 3.1 about` → p.10 (heading on p.10, Properties of tracially AF algebras)

### 2610.19840 — GPU-Accelerated Preprocessing for Large-Scale Linear Programming

math.OC, 22 pages, 0 two-column pages, class `article`, citations numeric (36). Role: random.
HTML declaration strings found in the PDF: 9/9 named, 13/13 equations.
Main resolves 96% (117/122); misses 0, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.24s extraction. A model pass would send about 17474 input tokens across 12 pages.
Main fails: .
Number search `Theorem 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.5 (heading on p.5, GPU-Preprocessor)
- ok `what is section 5 about` → p.15 (heading on p.15, Conclusion)
- ok `what is section 4.1 about` → p.10 (heading on p.10, Experimental Setup)

### 2610.21864 — Localisation of the monkey walk with an "impurity" at the origin

math.PR, 40 pages, 0 two-column pages, class `article`, citations qualified (26). Role: random.
Shared counters: Lemma 3.6 then Theorem 3.7; Theorem 3.7 then Lemma 3.8; Proposition 4.1 then Lemma 4.2; Lemma 4.4 then Theorem 4.5; Theorem 4.5 then Lemma 4.6; Lemma 4.11 then Proposition 4.12.
HTML declaration strings found in the PDF: 31/31 named, 62/62 equations.
Main resolves 98% (188/192); misses 0, extraction gaps 4, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 4. Index built in 0.07s plus 0.77s extraction. A model pass would send about 52248 input tokens across 36 pages.
Main fails: 4 indexed statements are not in the HTML declarations.
Hover+chat fails: 1 citation span emitted as a local ref; 4 indexed statements are not in the HTML declarations.
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.6 (heading on p.6, Our MVPP satisfies “most of” (A1-3))
- ok `what is section 4 about` → p.18 (heading on p.18, Proof of Theorem 1.1)
- ok `what is section 3.1 about` → p.6 (heading on p.6, Assumption (A1))

### 2610.15448 — The First Modular Zhu Algebra of $L(\frac12,0)_F$ in Characteristic Seven

math.QA, 17 pages, 0 two-column pages, class `article`, citations numeric (12). Role: random.
Shared counters: Theorem 2.2 then Lemma 2.3; Theorem 3.1 then Lemma 3.2; Lemma 3.8 then Theorem 3.9; Theorem 3.9 then Lemma 3.10; Lemma 3.10 then Proposition 3.11; Proposition 3.12 then Theorem 3.13.
HTML declaration strings found in the PDF: 16/16 named, 4/4 equations.
Main resolves 100% (81/81); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.34s extraction. A model pass would send about 18592 input tokens across 12 pages.
Main fails: .
Number search `Lemma 2.3` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 2 about` → p.2 (heading on p.2, Preliminaries)
- ok `what is section 3 about` → p.4 (heading on p.4, Proof of the main result)
- ok `what is section 3.1 about` → p.4 (heading on p.4, Low homogeneous subspaces and PBW straightening)

### 2610.14991 — Affine realization of tilted Richardson varieties

math.RT, 30 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (53). Role: random.
Shared counters: Theorem 2.1 then Proposition 2.2; Lemma 3.2 then Theorem 3.3; Theorem 3.5 then Lemma 3.6; Lemma 3.6 then Proposition 3.7; Proposition 3.7 then Theorem 3.8; Theorem 5.3 then Proposition 5.4.
HTML declaration strings found in the PDF: 48/48 named, 22/22 equations.
Main resolves 96% (117/122); misses 0, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.04s plus 0.36s extraction. A model pass would send about 34278 input tokens across 25 pages.
Main fails: 1 indexed statement is not in the HTML declarations.
Hover+chat fails: 1 indexed statement is not in the HTML declarations.
Number search `Lemma 1.2` served: True. Short query `Lemma 1` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.5 (heading on p.5, Preliminaries)
- ok `what is section 4 about` → p.17 (heading on p.17, Tilted R -polynomials)
- ok `what is section 6 about` → p.26 (heading on p.26, Fundamental classes and quantum cohomology)
- ok `what is section 2.2 about` → p.10 (heading on p.10, Affine realizations of tilted Bruhat intervals)

### 2610.11661 — BiHom-Poisson conformal superalgebras arising from related algebraic structures

math.RA, 25 pages, 0 two-column pages, class `amsart`, citations numeric (10). Role: random.
Shared counters: Theorem 2.7 then Proposition 2.8; Proposition 2.17 then Theorem 2.18; Theorem 2.18 then Proposition 2.19; Proposition 2.19 then Theorem 2.20; Proposition 2.22 then Theorem 2.23; Theorem 2.28 then Proposition 2.29.
HTML declaration strings found in the PDF: 67/67 named, 61/61 equations.
Main resolves 100% (44/44); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.39s extraction. A model pass would send about 29710 input tokens across 22 pages.
Main fails: .
Number search `Lemma 3.26` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 2 about` → p.2 (heading on p.2, Preliminaries and some results)
- ok `what is section 3 about` → p.14 (heading on p.14, Construction theorems)
- ok `what is section 3.1 about` → p.15 (heading on p.15, From BiHom-associative conformal superalgebras)

### 2101.03789 — A tree-based algorithm for the integration of monomials in the Chow ring of the moduli space of stable marked curves of genus zero

math.AG, 62 pages, 0 two-column pages, class `article`, citations numeric+qualified (26). Role: random.
Shared counters: Lemma 4.11 then Proposition 4.12; Proposition 4.12 then Lemma 4.13; Lemma 4.13 then Proposition 4.14; Proposition 5.5 then Corollary 5.6; Lemma 5.8 then Theorem 5.9; Lemma 8.3 then Proposition 8.4.
HTML declaration strings found in the PDF: 55/85 named, 3/3 equations.
Main resolves 76% (92/121); misses 0, extraction gaps 29, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.07s plus 0.83s extraction. A model pass would send about 49299 input tokens across 36 pages.
Main fails: resolution 76.0% is under 90%.
Hover+chat fails: resolution 76.0% is under 90%.
Number search `Lemma 2.10` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 5 about` → p.29 (heading on p.29, Sun-like trees)
- ok `what is section 8 about` → p.52 (heading on p.52, Proof of the identity)
- ok `what is section 5.1 about` → p.32 (heading on p.32, The value of a sun-like tree)

### 2401.03709 — Brauer and Neron-Severi groups of surfaces over finite fields

math.AG, 20 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (26). Role: random.
Shared counters: Theorem 1.1 then Corollary 1.2; Corollary 1.2 then Proposition 1.3; Proposition 1.3 then Theorem 1.4; Theorem 1.4 then Proposition 1.5; Lemma 2.1 then Theorem 2.2; Theorem 2.2 then Corollary 2.3.
HTML declaration strings found in the PDF: 34/34 named, 10/10 equations.
Main resolves 100% (46/46); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.03s plus 0.31s extraction. A model pass would send about 22727 input tokens across 17 pages.
Main fails: 1 indexed statement is not in the HTML declarations; a section question missed its heading page.
Hover+chat fails: 1 indexed statement is not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.9 (heading on p.9, The invariants of the Brauer group)
- ok `what is section 6 about` → p.13 (heading on p.13, Abelian surfaces)
- miss `what is section 6.2 about` → p.None (heading on p.None, ρ ⁡ ( A ¯ ) = 4)

### 2201.01481 — Quandles over a hyperboloid of one sheet and the longitudinal mapping knot invariant for $SL(2,\mathbb{R})$

math.AT, 14 pages, 0 two-column pages, class `journal`, citations numeric+qualified (21). Role: random.
Shared counters: Proposition 3.2 then Lemma 3.3; Lemma 3.3 then Proposition 3.4; Lemma 4.1 then Proposition 4.2; Theorem 5.1 then Lemma 5.2; Theorem 6.1 then Lemma 6.2; Lemma 6.2 then Corollary 6.3.
HTML declaration strings found in the PDF: 36/40 named, 1/1 equations.
Main resolves 48% (24/50); misses 5, extraction gaps 21, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.28s extraction. A model pass would send about 15295 input tokens across 12 pages.
Main fails: resolution 48.0% is under 90%; a section question missed its heading page.
Hover+chat fails: resolution 48.0% is under 90%; a section question missed its heading page.
Number search `Lemma 3.3` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 'section 5' did not locate section 5
- p.2 'section 7' did not locate section 7
- p.2 'section 8' did not locate section 8
- p.7 'section 8' did not locate section 8
- p.9 'section 8' did not locate section 8
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- miss `what is section 5 about` → p.6 (heading on p.None, S 1 2 ​ ( r ) -Colorings of ( 2 , n ) -torus knots)
- miss `what is section 8 about` → p.9 (heading on p.None, The longitudinal mapping knot invariant for S ​ L ​ ( 2 , ℝ )
- ok `what is section 2.2 about` → p.4 (heading on p.4, Properties of S ​ L ​ ( 2 , ℝ ))

### 2501.15569 — Symmetric quasi-coherent sheaves

math.AT, 29 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (28). Role: random.
Shared counters: Lemma 2.2 then Proposition 2.3; Theorem 3.1 then Lemma 3.2; Lemma 3.3 then Proposition 3.4; Proposition 3.4 then Corollary 3.5; Corollary 3.5 then Lemma 3.6; Lemma 3.6 then Proposition 3.7.
HTML declaration strings found in the PDF: 48/50 named, 10/10 equations.
Main resolves 99% (118/119); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.30s extraction. A model pass would send about 35651 input tokens across 24 pages.
Main fails: .
Number search `Lemma 2.2` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.9 (heading on p.9, Symmetric graded modules)
- ok `what is section 7 about` → p.20 (heading on p.20, The topology of symmetric projective spaces)

### 2301.04601 — On Fractional Musielak-Sobolev spaces and applications to nonlocal problems

math.AP, 31 pages, 0 two-column pages, class `not-found`, citations numeric+qualified (60). Role: random.
Shared counters: Proposition 3.7 then Corollary 3.8; Lemma 3.10 then Proposition 3.11; Theorem 3.16 then Proposition 3.17; Proposition 4.6 then Theorem 4.7; Theorem 4.7 then Lemma 4.8.
HTML declaration strings found in the PDF: 34/44 named, 40/40 equations.
Main resolves 97% (162/167); misses 2, extraction gaps 3, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.41s extraction. A model pass would send about 34554 input tokens across 26 pages.
Main fails: .
Number search `Lemma 2.4` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.15 '(3.8)': not in the statement index
- p.16 '(3.8)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 3 about` → p.9 (heading on p.9, Monotonicity and convergence results for operators in fracti)
- ok `what is section 5 about` → p.25 (heading on p.25, Some classes of problems)
- ok `what is section 5.1 about` → p.25 (heading on p.25, Double phase problem)

### 2601.02568 — Travelling Waves in a Mathematical Model for Oncolytic Virotherapy

math.AP, 49 pages, 0 two-column pages, class `article`, citations numeric (29). Role: random.
Shared counters: Lemma 3.5 then Theorem 3.6; Theorem 3.6 then Lemma 3.7; Lemma 4.3 then Theorem 4.4.
HTML declaration strings found in the PDF: 12/12 named, 53/314 equations. Most HTML equation numbers are not printed in the PDF, so equation mentions inflate the miss count.
Main resolves 68% (86/127); misses 4, extraction gaps 37, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.05s plus 0.83s extraction. A model pass would send about 37314 input tokens across 30 pages.
Main fails: resolution 67.7% is under 90%.
Hover+chat fails: resolution 67.7% is under 90%.
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 '(30)': not in the statement index
- p.16 'Theorem (3.6)': detector labelled it differently and the label is not indexed
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.27 (heading on p.27, Proof of Theorem 3.6)
- ok `what is section 6 about` → p.46 (heading on p.46, Conclusion)
- ok `what is section 3.2 about` → p.8 (heading on p.8, Dispersion relation for the invasion wave speed)

### 2401.01030 — Spectral conditions for factor-criticality of graphs

math.CO, 10 pages, 0 two-column pages, class `article`, citations numeric+qualified (10). Role: random.
HTML declaration strings found in the PDF: 11/11 named, 0/0 equations.
Main resolves 89% (41/46); misses 0, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.01s plus 0.14s extraction. A model pass would send about 6580 input tokens across 5 pages.
Main fails: resolution 89.1% is under 90%.
Hover+chat fails: resolution 89.1% is under 90%.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 2 about` → p.2 (heading on p.2, Preliminaries)
- ok `what is section 3 about` → p.4 (heading on p.4, Results)
- ok `what is section 3.2 about` → p.8 (heading on p.8, Signless Laplacian spectral radius)

### 2101.04000 — A variety of Steiner loops satisfying Moufang's theorem: A solution to Rajah's Problem

math.CO, 4 pages, 0 two-column pages, class `amsart`, citations numeric (7). Role: random.
Shared counters: Proposition 2.1 then Lemma 2.2; Lemma 2.2 then Theorem 2.3.
HTML declaration strings found in the PDF: 3/3 named, 6/6 equations.
Main resolves 89% (24/27); misses 0, extraction gaps 3, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.01s plus 0.04s extraction. A model pass would send about 4411 input tokens across 3 pages.
Main fails: resolution 88.9% is under 90%.
Hover+chat fails: resolution 88.9% is under 90%.
Number search `Lemma 2.2` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 2 about` → p.2 (heading on p.2, Solution to Rajah’s problem)

### 2501.06662 — The magnitude of categories of texts enriched by language models

math.CT, 26 pages, 0 two-column pages, class `tac`, citations author-year+numeric+qualified (54). Role: random.
HTML declaration strings found in the PDF: 0/15 named, 14/15 equations. Named statement numbers in the HTML do not match the PDF, so this resolution rate is not a fair Cauchy score.
Main resolves 84% (71/85); misses 1, extraction gaps 13, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.30s extraction. A model pass would send about 12485 input tokens across 9 pages.
Main fails: resolution 83.5% is under 90%; a section question missed its heading page.
Hover+chat fails: resolution 83.5% is under 90%; a section question missed its heading page.
Number search `Lemma 4` served: False. Short query `None` serves the full number: None. `Lemma 4` hits lemma 4: None. Printed name served: None (None).
Missed:
- p.22 'Sec. 3.3' did not locate section 3.3
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.12 (heading on p.12, Magnitude)
- ok `what is section 4 about` → p.22 (heading on p.22, Final remarks)
- miss `what is section 2.5 about` → p.8 (heading on p.None, Every LM defines a [ 0 , ∞ ] -category)

### 2202.07067 — Torsion theories of simplicial groups with truncated Moore complex

math.CT, 28 pages, 0 two-column pages, class `article`, citations numeric (22). Role: random.
Shared counters: Lemma 2.3 then Proposition 2.4; Theorem 2.9 then Corollary 2.10; Corollary 2.10 then Lemma 2.11; Lemma 2.11 then Theorem 2.12; Theorem 2.12 then Lemma 2.13; Lemma 2.13 then Theorem 2.14.
HTML declaration strings found in the PDF: 40/49 named, 9/9 equations.
Main resolves 90% (36/40); misses 0, extraction gaps 4, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.33s extraction. A model pass would send about 31234 input tokens across 23 pages.
Main fails: .
Number search `Lemma 2.3` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.13 (heading on p.13, Homology)
- ok `what is section 7 about` → p.23 (heading on p.23, Homotopy groups and torsion subobjects)

### 2601.08804 — Price Inequality and the Growth of Harmonic Functions on Non-Positively Curved Manifolds

math.DG, 17 pages, 0 two-column pages, class `article`, citations qualified (19). Role: random.
HTML declaration strings found in the PDF: 10/10 named, 16/16 equations.
Main resolves 81% (50/62); misses 12, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.14s extraction. A model pass would send about 16643 input tokens across 13 pages.
Main fails: resolution 80.6% is under 90%.
Hover+chat fails: resolution 80.6% is under 90%; 12 citation spans emitted as local refs.
Number search `Lemma 23` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 '(1)': not in the statement index
- p.3 'Equation (1)': not in the statement index
- p.5 '(1)': not in the statement index
- p.6 '(1)': not in the statement index
- p.7 '(1)': not in the statement index
- p.11 '(18)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction and Organization)
- ok `what is section 3 about` → p.8 (heading on p.8, On the Singer Conjecture in Degree One)
- ok `what is section 4 about` → p.10 (heading on p.10, Estimates for Positive Harmonic Functions)

### 2301.02591 — A new proof of gluing formula for analytic torsion forms

math.DG, 39 pages, 0 two-column pages, class `article`, citations numeric+qualified (43). Role: random.
Shared counters: Theorem 3.6 then Proposition 3.7; Proposition 3.9 then Theorem 3.10; Theorem 3.10 then Proposition 3.11; Proposition 3.11 then Theorem 3.12; Lemma 4.2 then Corollary 4.3; Corollary 4.3 then Lemma 4.4.
HTML declaration strings found in the PDF: 35/40 named, 97/97 equations.
Main resolves 98% (279/284); misses 0, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.05s plus 0.66s extraction. A model pass would send about 35806 input tokens across 29 pages.
Main fails: .
Number search `Lemma 4.1` served: True. Short query `Lemma 4` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 4 about` → p.19 (heading on p.19, Convergence of Eigenvalues)
- ok `what is section 6 about` → p.27 (heading on p.27, Small Eigenvalues and Mayer-Vietoris Sequences)
- ok `what is section 3.1 about` → p.15 (heading on p.15, A short exact sequence induced by small eigenvalues)

### 2101.08227 — Decision Theory and Large Deviations for Dynamical Hypotheses Tests: Neyman-Pearson, Min-Max and Bayesian Tests

math.DS, 31 pages, 0 two-column pages, class `article`, citations numeric (33). Role: random.
HTML declaration strings found in the PDF: 6/6 named, 97/97 equations.
Main resolves 94% (204/216); misses 7, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.04s plus 0.48s extraction. A model pass would send about 34321 input tokens across 25 pages.
Main fails: 1 indexed statement is not in the HTML declarations.
Hover+chat fails: 1 indexed statement is not in the HTML declarations.
Number search `Theorem 4.1` served: True. Short query `Theorem 4` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.19 '(5.9)': not in the statement index
- p.21 '(5.9)': not in the statement index
- p.7 '(6.22)': not in the statement index
- p.23 '(6.22)': not in the statement index
- p.27 '(6.22)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.13 (heading on p.13, Dynamical Hypotheses Test)
- ok `what is section 7 about` → p.28 (heading on p.28, An Example)
- ok `what is section 4.1 about` → p.15 (heading on p.15, The Optimality Property)

### 2401.01475 — Smooth invariant foliations and Koopman eigenfunctions about stable equilibria of semiflows

math.DS, 41 pages, 0 two-column pages, class `amsart`, citations none (48). Role: random.
Shared counters: Lemma 3.6 then Corollary 3.7; Corollary 3.9 then Theorem 3.10; Lemma 5.4 then Theorem 5.5; Theorem 5.5 then Lemma 5.6.
HTML declaration strings found in the PDF: 33/38 named, 86/88 equations.
Main resolves 78% (295/377); misses 58, extraction gaps 24, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.07s plus 0.74s extraction. A model pass would send about 48488 input tokens across 33 pages.
Main fails: resolution 78.2% is under 90%.
Hover+chat fails: resolution 78.2% is under 90%.
Number search `Lemma 3.5` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.3 '(1.1)': not in the statement index
- p.7 '(1.1)': not in the statement index
- p.8 '(1.1)': not in the statement index
- p.6 '(2.3)': not in the statement index
- p.7 '(2.3)': not in the statement index
- p.20 '(2.3)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.11 (heading on p.11, Koopman eigenfunctions)
- ok `what is section 5 about` → p.19 (heading on p.19, Proof of the main results)
- ok `what is section 3.1 about` → p.14 (heading on p.14, Stable case)

### 2201.01371 — Various notions of point derivations in Banach algebras

math.FA, 9 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (15). Role: random.
Shared counters: Proposition 2.3 then Lemma 2.4; Lemma 2.4 then Proposition 2.5; Proposition 2.5 then Corollary 2.6; Corollary 2.6 then Proposition 2.7; Proposition 2.8 then Theorem 2.9; Theorem 2.12 then Proposition 2.13.
HTML declaration strings found in the PDF: 14/17 named, 0/0 equations.
Main resolves 100% (6/6); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.01s plus 0.12s extraction. A model pass would send about 8601 input tokens across 6 pages.
Main fails: only 6 in-scope refs (need 8).
Hover+chat fails: only 6 in-scope refs (need 8).
Number search `Lemma 2.4` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction and Preliminaries)
- ok `what is section 2 about` → p.3 (heading on p.3, some algabraic properties of point derivation)

### 2501.07680 — Input-to-state stability in integral norms for linear infinite-dimensional systems

math.FA, 25 pages, 0 two-column pages, class `siamart251216`, citations numeric+qualified (73). Role: random.
HTML declaration strings found in the PDF: 1/35 named, 21/21 equations. Named statement numbers in the HTML do not match the PDF, so this resolution rate is not a fair Cauchy score.
Main resolves 76% (62/82); misses 1, extraction gaps 19, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 35. Index built in 0.04s plus 0.45s extraction. A model pass would send about 29089 input tokens across 20 pages.
Main fails: resolution 75.6% is under 90%; 35 indexed statements are not in the HTML declarations.
Hover+chat fails: resolution 75.6% is under 90%; 34 indexed statements are not in the HTML declarations.
Number search `Lemma 34` served: False. Short query `None` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.6 '(2.5)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.11 (heading on p.11, Input-to-state stability in integral norms)
- ok `what is section 4 about` → p.13 (heading on p.13, Lyapunov method)
- ok `what is section 4.1 about` → p.14 (heading on p.14, Linear systems with bounded control operators)

### 2301.06347 — A modular idealizer chain and unrefinability of partitions with repeated parts

math.GR, 17 pages, 0 two-column pages, class `amsart`, citations none (12). Role: random.
Shared counters: Lemma 2.11 then Proposition 2.12; Proposition 2.12 then Theorem 2.13; Lemma 3.3 then Theorem 3.4.
HTML declaration strings found in the PDF: 22/31 named, 16/16 equations.
Main resolves 82% (75/92); misses 0, extraction gaps 17, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.43s extraction. A model pass would send about 16955 input tokens across 11 pages.
Main fails: resolution 81.5% is under 90%.
Hover+chat fails: resolution 81.5% is under 90%; 1 citation span emitted as a local ref.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.8 (heading on p.8, An explicit correspondence in the case m = 2)
- ok `what is section 5 about` → p.16 (heading on p.16, Conclusions and open problems)
- ok `what is section 2.3 about` → p.5 (heading on p.5, The idealizer chain)

### 2601.16295 — Local limit theorems for random isometries of the plane

math.GR, 27 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (23). Role: random.
HTML declaration strings found in the PDF: 0/0 named, 34/34 equations.
Main resolves 86% (95/110); misses 2, extraction gaps 13, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 23. Index built in 0.03s plus 0.28s extraction. A model pass would send about 27466 input tokens across 21 pages.
Main fails: resolution 86.4% is under 90%; 23 indexed statements are not in the HTML declarations.
Hover+chat fails: resolution 86.4% is under 90%; 23 indexed statements are not in the HTML declarations.
Number search `Lemma 4` served: False. Short query `None` serves the full number: None. `Lemma 4` hits lemma 4: None. Printed name served: None (None).
Missed:
- p.24 '(A.1)': detector missed it
- p.25 '(A.1)': detector missed it
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.15 (heading on p.15, Random isometries with irrational rotations)
- ok `what is section 6 about` → p.21 (heading on p.21, Asymmetric random isometries with rational cosines)
- ok `what is section 4.1 about` → p.16 (heading on p.16, Proof of Proposition 1.1.1)

### 2401.03520 — Fundamental groups of 2-complexes with nonpositive planar sectional curvature

math.GT, 10 pages, 0 two-column pages, class `amsart`, citations qualified (11). Role: random.
Shared counters: Theorem 3.6 then Lemma 3.7.
HTML declaration strings found in the PDF: 25/25 named, 1/1 equations.
Main resolves 96% (26/27); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.28s extraction. A model pass would send about 11060 input tokens across 7 pages.
Main fails: .
Hover+chat fails: 1 citation span emitted as a local ref.
Number search `Lemma 2.13` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.4 (heading on p.4, Collapsibility)
- ok `what is section 4 about` → p.8 (heading on p.8, Conformally negatively curved complexes with fundamental gro)

### 2102.00901 — Tangles, relative character varieties, and holonomy perturbed traceless flat moduli spaces

math.GT, 20 pages, 0 two-column pages, class `amsart`, citations qualified (38). Role: random.
Shared counters: Proposition 3.2 then Corollary 3.3; Corollary 3.3 then Lemma 3.4; Lemma 3.4 then Corollary 3.5; Corollary 4.2 then Theorem 4.3; Theorem 4.4 then Corollary 4.5; Lemma 6.1 then Proposition 6.2.
HTML declaration strings found in the PDF: 18/20 named, 27/27 equations.
Main resolves 93% (50/54); misses 0, extraction gaps 4, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.33s extraction. A model pass would send about 21854 input tokens across 14 pages.
Main fails: .
Hover+chat fails: 2 citation spans emitted as local refs.
Number search `Lemma 3.4` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, introduction)
- ok `what is section 4 about` → p.10 (heading on p.10, Character varieties, relative character varieties, and their)
- ok `what is section 6 about` → p.15 (heading on p.15, Perturbations)
- ok `what is section 4.3 about` → p.10 (heading on p.10, Regular points)

### 2502.05733 — On definable J-sets

math.LO, 9 pages, 0 two-column pages, class `article`, citations numeric (7). Role: random.
Shared counters: Proposition 2.3 then Corollary 2.4; Corollary 2.4 then Proposition 2.5; Theorem 3.1 then Proposition 3.2; Proposition 4.1 then Lemma 4.2; Lemma 4.2 then Proposition 4.3; Proposition 4.3 then Lemma 4.4.
HTML declaration strings found in the PDF: 17/19 named, 0/0 equations.
Main resolves 100% (10/10); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.01s plus 0.15s extraction. A model pass would send about 11353 input tokens across 8 pages.
Main fails: .
Number search `Lemma 4.2` served: True. Short query `Lemma 4` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.4 (heading on p.4, Positive results for commutative groups)
- ok `what is section 4 about` → p.6 (heading on p.6, An example without J-property)

### 2202.01959 — Finite Relation Algebras

math.LO, 14 pages, 0 two-column pages, class `article`, citations numeric (25). Role: random.
HTML declaration strings found in the PDF: 21/34 named, 0/0 equations.
Main resolves 100% (4/4); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.23s extraction. A model pass would send about 14172 input tokens across 9 pages.
Main fails: only 4 in-scope refs (need 8).
Hover+chat fails: only 4 in-scope refs (need 8).
Number search `Lemma 25` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Abstract)
- ok `what is section 4 about` → p.6 (heading on p.6, Main results)
- ok `what is section 6 about` → p.12 (heading on p.12, Acknowledgements)

### 2601.16548 — Painlevé IV, bi-confluent Heun equations and the Hankel determinant generated by a discontinuous semi-classical Laguerre weight

math.CA, 19 pages, 0 two-column pages, class `article`, citations numeric (19). Role: random.
Shared counters: Lemma 2.2 then Theorem 2.3; Proposition 3.1 then Lemma 3.2; Lemma 3.2 then Theorem 3.3; Theorem 5.1 then Lemma 5.2.
HTML declaration strings found in the PDF: 13/13 named, 114/119 equations.
Main resolves 84% (234/278); misses 0, extraction gaps 44, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.17s extraction. A model pass would send about 19983 input tokens across 16 pages.
Main fails: resolution 84.2% is under 90%.
Hover+chat fails: resolution 84.2% is under 90%.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 5 about` → p.12 (heading on p.12, Asymptotics for the recurrence coefficients and the Hankel d)
- ok `what is section 8 about` → p.17 (heading on p.17, Data availability)

### 2301.09975 — Kamenev type conditions for oscillation of third order linear ordinary differential equations

math.CA, 13 pages, 0 two-column pages, class `article`, citations none (0). Role: random.
Shared counters: Corollary 3.1 then Theorem 3.2.
HTML declaration strings found in the PDF: 10/11 named, 28/30 equations.
Main resolves 100% (0/0); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 4. Index built in 0.01s plus 0.16s extraction. A model pass would send about 13861 input tokens across 12 pages.
Main fails: only 0 in-scope refs (need 8); 4 indexed statements are not in the HTML declarations; a section question missed its heading page.
Hover+chat fails: only 0 in-scope refs (need 8); 4 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False ({'kind': 'lemma', 'number': '2.1', 'name': '[1, Lemma 2.2]'}).

### 2101.05480 — Gauss lattices and complex continued fractions

math.NT, 55 pages, 0 two-column pages, class `ipart`, citations numeric (28). Role: random.
HTML declaration strings found in the PDF: 52/58 named, 4/4 equations.
Main resolves 93% (123/132); misses 3, extraction gaps 6, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.08s plus 1.94s extraction. A model pass would send about 55541 input tokens across 39 pages.
Main fails: .
Number search `Lemma 4` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: True. Printed name served: False (None).
Missed:
- p.4 'subsection 4.3' did not locate section 4.3
- p.33 'subsection 4.3' did not locate section 4.3
- p.41 'subsection\n4.3' did not locate section 4.3
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 8 about` → p.31 (heading on p.31, Parametrization of the open transversal and the first return)
- ok `what is section 14 about` → p.53 (heading on p.53, Appendix 2, computing the distance to 𝒟)
- ok `what is section 6.3 about` → p.28 (heading on p.28, Properties of the open transversal)

### 2401.06100 — Special values of $p$-adic $L$-functions and Iwasawa $λ$-invariants of Dirichlet characters

math.NT, 20 pages, 0 two-column pages, class `sn-jnl`, citations author-year (17). Role: random.
Shared counters: Proposition 2.1 then Corollary 2.2; Corollary 2.2 then Proposition 2.3; Proposition 3.1 then Theorem 3.2; Theorem 3.2 then Corollary 3.3; Corollary 3.3 then Proposition 3.4; Proposition 5.1 then Theorem 5.2.
HTML declaration strings found in the PDF: 13/13 named, 15/15 equations.
Main resolves 97% (56/58); misses 2, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.02s plus 0.31s extraction. A model pass would send about 13000 input tokens across 10 pages.
Main fails: 1 indexed statement is not in the HTML declarations.
Hover+chat fails: 1 indexed statement is not in the HTML declarations.
Number search `Theorem 3.2` served: True. Short query `Theorem 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.8 'Section 2' did not locate section 2
- p.13 'Section 2' did not locate section 2
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.9 (heading on p.9, The rank zero case)
- ok `what is section 6 about` → p.13 (heading on p.13, Numerical data)
- ok `what is section 6.2 about` → p.16 (heading on p.16, Primes with λ > 1 in the rank one case)

### 2201.03733 — The perfectly matched layer (PML) for hyperbolic wave propagation problems: A review

math.NA, 52 pages, 0 two-column pages, class `article`, citations numeric (83). Role: random.
HTML declaration strings found in the PDF: 30/34 named, 114/114 equations.
Main resolves 85% (351/411); misses 33, extraction gaps 27, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.07s plus 1.13s extraction. A model pass would send about 52709 input tokens across 38 pages.
Main fails: resolution 85.4% is under 90%.
Hover+chat fails: resolution 85.4% is under 90%.
Number search `Theorem 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.32 'Theorem 10': not in the statement index
- p.34 'Theorems 10': not in the statement index
- p.33 'Theorem 11': not in the statement index
- p.34 'Theorems 11': not in the statement index
- p.33 'Theorem 12': not in the statement index
- p.33 'Theorem 13': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 5 about` → p.27 (heading on p.27, Numerical analysis of the discrete PML)
- ok `what is section 8 about` → p.44 (heading on p.44, Summary and conclusions)
- ok `what is section 4.3 about` → p.18 (heading on p.18, Stability)

### 2501.06373 — Analysis of a Shear beam model with suspenders in thermoelasticity of type III

math.NA, 25 pages, 0 two-column pages, class `amsart`, citations numeric (21). Role: random.
Shared counters: Lemma 2.1 then Theorem 2.2; Theorem 4.1 then Lemma 4.2.
HTML declaration strings found in the PDF: 9/9 named, 102/102 equations.
Main resolves 93% (165/178); misses 0, extraction gaps 13, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.90s extraction. A model pass would send about 27832 input tokens across 21 pages.
Main fails: .
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.9 (heading on p.9, Exponential stability)
- ok `what is section 6 about` → p.17 (heading on p.17, Simulations)
- ok `what is section 5.2 about` → p.12 (heading on p.12, Study of the discrete energy)

### 2301.13423 — Analysis for idempotent states on quantum permutation groups

math.OA, 41 pages, 0 two-column pages, class `amsart`, citations numeric (32). Role: random.
Shared counters: Theorem 1.2 then Lemma 1.3; Proposition 1.8 then Lemma 1.9; Proposition 2.18 then Theorem 2.19; Theorem 2.19 then Corollary 2.20; Corollary 2.20 then Proposition 2.21; Proposition 2.21 then Lemma 2.22.
HTML declaration strings found in the PDF: 50/64 named, 16/16 equations.
Main resolves 99% (164/166); misses 0, extraction gaps 2, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.05s plus 0.43s extraction. A model pass would send about 43303 input tokens across 33 pages.
Main fails: .
Number search `Lemma 1.3` served: True. Short query `Lemma 1` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.5 (heading on p.5, Compact quantum groups)
- ok `what is section 4 about` → p.22 (heading on p.22, Exotic quasi-subgroups of the quantum permutation group)
- ok `what is section 6 about` → p.34 (heading on p.34, Integer fixed points quantum permutations)
- ok `what is section 2.3 about` → p.12 (heading on p.12, Group-like projections)

### 2601.14873 — Order isomorphisms in $C^*$-algebras

math.OA, 29 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (58). Role: random.
Shared counters: Proposition 3.3 then Theorem 3.4; Theorem 3.6 then Corollary 3.7; Lemma 4.2 then Corollary 4.3; Corollary 4.3 then Lemma 4.4; Lemma 4.4 then Theorem 4.5; Lemma 6.3 then Proposition 6.4.
HTML declaration strings found in the PDF: 27/27 named, 12/12 equations.
Main resolves 98% (86/88); misses 2, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.34s extraction. A model pass would send about 24794 input tokens across 18 pages.
Main fails: .
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.22 '(5.2)': not in the statement index
- p.23 '(5.2)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.11 (heading on p.11, Order isomorphisms between effect algebras)
- ok `what is section 7 about` → p.26 (heading on p.26, Remarks and intriguing questions)
- ok `what is section 2.2 about` → p.6 (heading on p.6, Regular monotone completion of C ∗ -algebras)

### 2401.05617 — Estimating the time-evolving refractivity of a turbulent medium using optical beam measurements: a data assimilation approach

math.OC, 15 pages, 0 two-column pages, class `optica-article`, citations numeric (17). Role: random.
HTML declaration strings found in the PDF: 1/1 named, 34/34 equations.
Main resolves 91% (71/78); misses 3, extraction gaps 4, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.57s extraction. A model pass would send about 18352 input tokens across 13 pages.
Main fails: .
Number search `Theorem 5.1` served: False. Short query `Theorem 5` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.3 'Section 2' did not locate section 2
- p.6 'section 2' did not locate section 2
- p.13 'Section 2' did not locate section 2
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.4 (heading on p.4, Estimating the medium using data assimilation)
- ok `what is section 5 about` → p.13 (heading on p.13, Concluding discussion)
- ok `what is section 3.2 about` → p.5 (heading on p.5, Data assimilation strategy in general form)

### 2101.03716 — Fairness over time in dynamic resource allocation with an application in Healthcare

math.OC, 25 pages, 0 two-column pages, class `article`, citations author-year (21). Role: random.
HTML declaration strings found in the PDF: 20/28 named, 10/13 equations.
Main resolves 49% (48/98); misses 14, extraction gaps 36, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.48s extraction. A model pass would send about 21905 input tokens across 13 pages.
Main fails: resolution 49.0% is under 90%.
Hover+chat fails: resolution 49.0% is under 90%.
Number search `Theorem 9` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.18 '(12)': not in the statement index
- p.19 '(12)': not in the statement index
- p.24 '(12)': not in the statement index
- p.9 '(7)': not in the statement index
- p.11 '(7)': not in the statement index
- p.12 '(7)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.8 (heading on p.8, General Combinatorial 𝒳)
- ok `what is section 7 about` → p.22 (heading on p.22, Conclusion)
- ok `what is section 5.1 about` → p.11 (heading on p.11, Preliminary Problem Formulation)

### 2501.05947 — Symmetry Analysis of Semi-Linear Partial Differential Equations and Forward Backward Stochastic Differential Equations

math.PR, 20 pages, 0 two-column pages, class `article`, citations none (35). Role: random.
HTML declaration strings found in the PDF: 18/18 named, 121/121 equations.
Main resolves 99% (123/124); misses 0, extraction gaps 0, wrong links 1, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.21s extraction. A model pass would send about 21398 input tokens across 16 pages.
Main fails: 1 wrong link.
Hover+chat fails: 1 wrong link.
Number search `Theorem 2.5` served: True. Short query `Theorem 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Wrong:
- p.7 'Theorem (3.2)' opened equation 3.2
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.9 (heading on p.9, Symmetry of FBSDE versus symmetry of semi linear PDE)
- ok `what is section 6 about` → p.17 (heading on p.17, Conclusion)
- ok `what is section 2.3 about` → p.4 (heading on p.4, Symmetries of FBSDE)

### 2201.01899 — Invariant Galton-Watson trees: metric properties and attraction with respect to generalized dynamical pruning

math.PR, 30 pages, 0 two-column pages, class `not-found`, citations numeric+qualified (25). Role: random.
HTML declaration strings found in the PDF: 37/40 named, 51/51 equations.
Main resolves 88% (179/203); misses 18, extraction gaps 6, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.36s extraction. A model pass would send about 30363 input tokens across 23 pages.
Main fails: resolution 88.2% is under 90%.
Number search `Lemma 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: True. Printed name served: False (None).
Missed:
- p.4 'Def. 1': detector missed it
- p.22 'Def. 3': detector missed it
- p.5 'Lem. 2': detector missed it
- p.13 'Lem. 6': detector missed it
- p.13 'Thm. 1': detector missed it
- p.17 'Thm. 11': detector missed it
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 3 about` → p.10 (heading on p.10, Results)
- ok `what is section 5 about` → p.24 (heading on p.24, Discussion)
- ok `what is section 2.7 about` → p.9 (heading on p.9, Bernoulli leaf coloring)

### 2601.05136 — State integrals for the quantized $\operatorname{SL}_2(\mathbb{C})$ Chern-Simons invariant

math.QA, 19 pages, 7 two-column pages, class `sl2art`, citations qualified (50). Role: random.
HTML declaration strings found in the PDF: 1/1 named, 28/28 equations.
Main resolves 97% (34/35); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 9. Index built in 0.03s plus 0.11s extraction. A model pass would send about 21533 input tokens across 14 pages.
Main fails: 9 indexed statements are not in the HTML declarations.
Hover+chat fails: 1 wrong link; 10 citation spans emitted as local refs; 9 indexed statements are not in the HTML declarations.
Number search `Theorem 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 3 about` → p.9 (heading on p.9, State integrals for the quantized Chern-Simons invariant)
- ok `what is section 4 about` → p.12 (heading on p.12, Formal asymptotics)
- ok `what is section 3.1 about` → p.9 (heading on p.9, Quantum dilogarithms)

### 2301.02670 — Brane wrapping, AKSZ sigma models, and QP manifolds

math.QA, 41 pages, 0 two-column pages, class `article`, citations numeric (32). Role: random.
HTML declaration strings found in the PDF: 1/1 named, 162/162 equations.
Main resolves 90% (72/80); misses 8, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.05s plus 0.47s extraction. A model pass would send about 39644 input tokens across 29 pages.
Main fails: .
Number search `Theorem 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.35 '(B.10)': detector missed it
- p.35 '(B.11)': detector missed it
- p.36 '(B.18)': detector missed it
- p.37 '(B.24)': detector missed it
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 4 about` → p.15 (heading on p.15, Examples – dim Y = 0)
- ok `what is section 7 about` → p.31 (heading on p.31, Conclusions)
- ok `what is section 5.2 about` → p.24 (heading on p.24, M5 on S 1)

### 2101.04091 — A transitivity result for ad-nilpotent ideals in type A

math.RT, 11 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (34). Role: random.
Shared counters: Corollary 4.5 then Proposition 4.6; Proposition 4.6 then Lemma 4.7; Proposition 6.1 then Corollary 6.2.
HTML declaration strings found in the PDF: 21/24 named, 10/10 equations.
Main resolves 93% (64/69); misses 0, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.19s extraction. A model pass would send about 16523 input tokens across 9 pages.
Main fails: .
Number search `Lemma 3.2` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.3 (heading on p.3, Proof of Theorem 2.2)
- ok `what is section 6 about` → p.6 (heading on p.6, Combinatorics)
- ok `what is section 6.2 about` → p.7 (heading on p.7, Two coarser equivalence relations)

### 2401.09156 — Symmetric varieties for endoscopic groups

math.RT, 120 pages, 0 two-column pages, class `amsart`, citations qualified (164). Role: random.
Shared counters: Proposition 2.2 then Lemma 2.3; Proposition 3.8 then Lemma 3.9; Lemma 4.6 then Proposition 4.7; Proposition 4.7 then Lemma 4.8; Proposition 5.3 then Lemma 5.4; Theorem 6.4 then Lemma 6.5.
HTML declaration strings found in the PDF: 130/147 named, 62/62 equations.
Main resolves 92% (321/349); misses 8, extraction gaps 20, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.16s plus 1.60s extraction. A model pass would send about 129251 input tokens across 92 pages.
Main fails: 1 indexed statement is not in the HTML declarations.
Hover+chat fails: 68 citation spans emitted as local refs; 2 indexed statements are not in the HTML declarations.
Number search `Lemma 2.3` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.111 '(A.1)': detector missed it
- p.112 '(A.2)': detector missed it
- p.49 'Sections 2.4.1' did not locate section 2.4.1
- p.34 'Sections 4.2' did not locate section 4.2
- p.40 'Section 4.2' did not locate section 4.2
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 6 about` → p.50 (heading on p.50, Outer data for symmetric varieties)
- ok `what is section 10 about` → p.100 (heading on p.100, Examples and applications)
- ok `what is section 5.1 about` → p.43 (heading on p.43, Generalities on symmetric pairs and varieties)

### 2201.09321 — A Spectral Theorem for Zeon Matrices

math.RA, 29 pages, 0 two-column pages, class `article`, citations numeric (10). Role: random.
Shared counters: Proposition 4.3 then Corollary 4.4; Corollary 4.4 then Lemma 4.5; Lemma 4.6 then Corollary 4.7; Theorem 5.3 then Lemma 5.4; Theorem 5.7 then Corollary 5.8; Lemma 6.6 then Theorem 6.7.
HTML declaration strings found in the PDF: 44/44 named, 22/22 equations.
Main resolves 90% (18/20); misses 1, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.63s extraction. A model pass would send about 30169 input tokens across 24 pages.
Main fails: .
Number search `Lemma 2.10` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 'Section 3' did not locate section 3
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 5 about` → p.12 (heading on p.12, Eigenvalues, Eigenvectors, and the Characteristic Polynomial)
- ok `what is section 8 about` → p.27 (heading on p.27, Conclusion and Avenues for Further Research)
- ok `what is section 6.1 about` → p.17 (heading on p.17, The Inner Product on ℂ ​ ℨ m)

### 2501.19379 — A Basis Theorem for Rings with Commuting Operators in Characteristic Zero

math.RA, 21 pages, 0 two-column pages, class `amsart`, citations numeric (12). Role: random.
Shared counters: Lemma 2.8 then Corollary 2.9; Lemma 4.13 then Corollary 4.14; Theorem 4.18 then Corollary 4.19.
HTML declaration strings found in the PDF: 29/43 named, 4/4 equations.
Main resolves 96% (45/47); misses 0, extraction gaps 2, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.41s extraction. A model pass would send about 27430 input tokens across 18 pages.
Main fails: .
Number search `Lemma 2.6` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.8 (heading on p.8, Reduction results)
- ok `what is section 4 about` → p.14 (heading on p.14, 𝒟 ∗ -basis theorem)
- ok `what is section 4.1 about` → p.14 (heading on p.14, Perfect 𝒟 ∗ -ideals)

## Proposed tickets

1. **Match “1. Introduction” when asked what section 1 is about** — AskStructureLocator treats a dotted number such as 9.2 as a section title, and does not treat a top-level heading “N. Title” as section N. Main has no locator, so the question fails there too. Size: small–medium. The locator already exists on the chat branch; section titles need the undotted leading-number match that chapter titles already use. Evidence: On the combined profile, dotted section questions land correctly 47/49 times and undotted ones 173/175 times. 4/60 papers still miss at least one probed section.
2. **Suppress author–year qualified citations, not only numeric ones** — Hover drops [12, Theorem 3.2], and still emits [IK99, Lemma 1.15] and [CV23, Theorem 3.5] as local references. New abbreviation and plural matches inside those cites can add detections. Size: small. The qualifier pattern should accept an author key or a year, not only a number before the comma. Evidence: Citation-span emissions on the comparable papers go from 0 on main to 248 on hover. Hover is higher on 2610.21544, 2610.04096, 2610.21303, 2610.19333, 2610.19307, 2610.21864, 2601.08804, 2301.06347, 2401.03520, 2102.00901, 2601.05136, 2401.09156.
3. **Do not index enumerated proof items (1) (2) (3) as equations** — A left-margin line that contains a math arrow passes declarationMatches, so the source-fallback index stores equation keys the paper never displays. Size: medium. The declaration filter needs a tighter check than “label near the left margin and the line looks like mathematics.” Evidence: 55 indexed keys on main are absent from the HTML declarations, after setting aside papers whose HTML numbers do not match the PDF.
4. **Resolve a shortened number, and plurals on main** — “Lemma 2” now returns Lemma 2.1, and “Lemmas 4.6” is detected. Literal “Lemma 4” still requires a lemma numbered exactly 4. Size: small. Evidence: Exact printed queries are served on 56/58 comparable papers. A shortened first component retrieves the full number on 46/47 papers. Literal “Lemma 4” hits a lemma numbered 4 on 2 papers. Plural misses include: 2201.03733 p.34 'Theorems 10': not in the statement index.
5. **Store the printed statement name on the source-fallback index** — A parenthetical such as “(Zorn)” is now stored on the source-fallback entry. This corpus does not print that name inside the HTML theorem tag, so the measured route stays empty. Size: small. Parse a parenthetical title into the fallback entry; the term route already exists. Evidence: 0/1 papers expose a parenthetical name in the HTML tag and serve it from the index. This corpus mostly does not print names inside the theorem tag, so the route is empty rather than wrong.
