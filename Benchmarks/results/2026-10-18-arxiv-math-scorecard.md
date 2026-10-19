# arXiv maths scorecard

**12 of 20 random papers work with no fixes on main.**
**9 of 20 pass if the open hover and chat branches are both applied.**

A paper works with no fixes when all of these hold:

- At least 8 theorem, lemma, definition, equation, or section references are recoverable.
- At least 90% of them resolve. A statement resolves when the detector names the right kind and number and the source-fallback index contains that key. A section reference resolves when “what is section N about” lands on the page that prints the heading.
- There is no wrong link: no citation span opens an indexed statement, no printed reference opens a different statement, and the index contains no statement the HTML does not declare.
- No bracket or author–year citation is emitted as a local reference.
- Every probed “what is section N about” question lands on the heading page.

Main locates a section written as “N. Title” or “N.N. Title.” Main also drops a local reference inside [12], [IK99, Lemma 1.15], (Smith 2019), or Smith et al. [2019]; an interval such as [0, 1] is not a citation. A bare integer with text to its right, such as “(1) f ∈ W”, is an enumerated item and is not indexed as an equation. A number alone on its line is an equation when the next line is a formula, as in “(1)” followed by “xn+m xn = P(...)”. “Lemmas 4.6” is lemma 4.6, and “Lemma 2” retrieves a lemma numbered 2.1. A parenthetical printed on the declaration, such as “(Zorn)”, is stored as the statement name. Dropping only the section-question condition, 12 of 20 pass on main and 6 of 20 pass on the hover branch. The headline above keeps the section question.

A bracket that the detector does not open is not a wrong link. The heading page for a section question is the PDF outline entry whose title matches the HTML heading, or else a title-shaped line. A numbered sentence is not that heading. An outline bookmark that reads “Introduction” rather than “1. Introduction” is still section 1 when it is the first section bookmark. A citation bracket may be split by a line break, as in “[17, Theorem 3.31(c)]”. The HTML declaration list includes a plural tag such as “Examples 6.7” and a bold run-in such as “Remark 3.13.”

Shared counters, such as a theorem followed by a lemma with the next number, appear on 16 of 20 papers. The index key is the kind plus the full number, so the pair resolves when both declarations are indexed.

Text comes from PyMuPDF’s content stream, the stand-in for `PDFPage.string`. Equation x-positions are glyph-box fractions, the stand-in for PDFKit selection bounds. No model is called; index time is the deterministic source fallback. Token estimates are input size only and were not billed.

An exact printed query such as “Lemma 2.1” is served from the existing index on 19/19 comparable papers (the key must already be indexed). A shortened query such as “Lemma 2” retrieves the full number on 17/17 of those papers. Literal “Lemma 4” hits a lemma numbered exactly 4 on 0 papers: these papers print dotted numbers, so 4.1 is not lemma 4. A parenthetical name is stored when the PDF prints one; this corpus does not put that name in the HTML theorem tag.

## What the failing papers hit first

8 of 20 random papers fail on main. The first check is the earliest gate in the pass rule: enough references, then 90% resolution, wrong links, citation emissions, false declarations, and section questions. A later gate can still fail the same paper; the blocking count is every paper that fails that check.

| First failing check | Papers | Blocking count |
|---|---:|---:|
| resolution under 90% | 5 | 5 |
| indexed statement absent from the HTML | 3 | 6 |
| section question missed the heading page | 0 | 3 |

Papers by the first check they fail:

- **resolution under 90%** (5): 2610.21341, 2610.04096, 2610.19333, 2610.18580, 2610.13792
- **indexed statement absent from the HTML** (3): 2610.14417, 2610.21864, 2610.14991

## Author–year citations in the PDF text

Across the 20 random papers, the text layer contains 0 parenthetical citations of the form (Smith 2019) and 0 of the form Smith et al. [2019]. It contains 585 alphanumeric keys such as [IK99], 111 of them qualified with a theorem, lemma, or equation, on 6 papers: 2610.21544, 2610.04096, 2610.21303, 2610.19333, 2610.19307, 2610.21864. Main emits 0 of those spans as local references; the hover profile, which still only suppresses numeric brackets, emits 125. A count of 0 on main is the suppression firing. The HTML citation-style label does not say author–year, because the HTML cite element often omits the key the PDF prints.

## Random papers

| arXiv | cat | pages | class | main | hover | chat | both | index s | model toks |
|---|---|---:|---|---|---|---|---|---:|---:|
| 2610.21544 | AG | 12 | amsart | pass | 97% (57/59) | pass | 98% (58/59) | 0.2 | 13355 |
| 2610.11671 | AT | 27 | amsart | pass | 93% (62/67) | pass | pass | 0.3 | 26453 |
| 2610.20976 | AP | 42 | article | pass | 88% (349/395) | pass | pass | 0.7 | 50978 |
| 2610.21341 | CO | 29 | amsart | 87% (111/128) | 78% (100/128) | 87% (111/128) | 87% (111/128) | 0.6 | 36924 |
| 2610.04096 | CT | 23 | amsart | 77% (17/22) | 73% (16/22) | 77% (17/22) | 77% (17/22) | 0.4 | 30252 |
| 2610.21303 | DG | 54 | scrartcl | pass | 91% (100/110) | pass | 100% (110/110) | 0.6 | 56907 |
| 2610.21627 | DS | 20 | amsart | pass | 100% (90/90) | pass | pass | 0.3 | 21567 |
| 2610.18041 | FA | 25 | amsart | pass | 96% (217/225) | pass | pass | 0.5 | 31551 |
| 2610.20306 | GR | 14 | amsart | pass | 84% (47/56) | pass | pass | 0.3 | 17071 |
| 2610.19333 | GT | 36 | amsart | 63% (37/59) | 54% (33/61) | 63% (37/59) | 66% (40/61) | 0.6 | 35071 |
| 2610.14417 | LO | 19 | amsart | 95% (55/58) | 95% (55/58) | 95% (55/58) | 95% (55/58) | 0.5 | 24257 |
| 2610.16227 | CA | 16 | amsart | pass | 97% (122/126) | pass | pass | 0.3 | 16309 |
| 2610.19307 | NT | 27 | amsart | pass | 85% (40/47) | pass | 98% (46/47) | 0.5 | 20456 |
| 2610.18580 | NA | 29 | siamart251216 | 0% (0/79) | 0% (0/79) | 0% (0/79) | 0% (0/79) | 1.0 | 27773 |
| 2610.13792 | OA | 41 | amsart | 83% (92/111) | 79% (88/111) | 83% (92/111) | 83% (92/111) | 0.6 | 44349 |
| 2610.19840 | OC | 22 | article | pass | 84% (103/122) | pass | pass | 0.3 | 17474 |
| 2610.21864 | PR | 40 | article | 98% (188/192) | 96% (184/192) | 98% (188/192) | 98% (188/192) | 1.0 | 52248 |
| 2610.15448 | QA | 17 | article | pass | 98% (79/81) | pass | pass | 0.4 | 18592 |
| 2610.14991 | RT | 30 | amsart | 92% (111/121) | 87% (105/121) | 92% (111/121) | 92% (111/121) | 0.4 | 34278 |
| 2610.11661 | RA | 25 | amsart | pass | 100% (44/44) | pass | pass | 0.5 | 29710 |

## Edge cases kept outside the 20

The random sample’s longest paper is 54 pages and it has 0 two-column pages. The papers below are scored the same way and are not part of the headline.

- 2609.00233 (survey-60-pages, 82 pages, 0 two-column, `amsart`): main 97% (223/229), pass=False. The random sample has no paper of 60 or more pages. This 82-page survey is kept as that edge case and is not one of the 20.
- 2610.22308 (two-column, 24 pages, 24 two-column, `revtex4-2`): main 55% (101/183), pass=False. No random math.* paper has a two-column page. This revtex4-2 reprint PDF is two-column on every page. Its primary category is quant-ph, with math-ph secondary, because recent math.* submissions are single-column. It is not one of the 20.

## Per paper

### 2610.21544 — On the variety of sum of powers of certain complete intersection forms

math.AG, 12 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (29). Role: random.
Shared counters: Lemma 2.1 then Theorem 2.2; Theorem 3.22 then Proposition 3.23.
HTML declaration strings found in the PDF: 16/16 named, 14/14 equations.
Main resolves 98% (58/59); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.22s extraction. A model pass would send about 13355 input tokens across 9 pages.
Main fails: .
Hover+chat fails: 6 citation spans emitted as local refs.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.3 (heading on p.3, Computation of VSP)
- ok `what is section 4 about` → p.10 (heading on p.10, Final remarks)

### 2610.11671 — A complete classification of the rational realization of gap-two products of Eilenberg--MacLane spaces as classifying spaces

math.AT, 27 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (19). Role: random.
Shared counters: Lemma 4.2 then Proposition 4.3; Proposition 4.3 then Lemma 4.4; Lemma 4.4 then Proposition 4.5; Proposition 4.5 then Lemma 4.6; Lemma 4.10 then Proposition 4.11; Proposition 5.2 then Lemma 5.3.
HTML declaration strings found in the PDF: 23/23 named, 9/9 equations.
Main resolves 93% (62/67); misses 0, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.31s extraction. A model pass would send about 26453 input tokens across 20 pages.
Main fails: .
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.5 (heading on p.5, Reduction to two cases)
- ok `what is section 5 about` → p.20 (heading on p.20, The branch n ≤ 4 n\leq 4)
- ok `what is section 4.5 about` → p.17 (heading on p.17, Realization when n ≥ 5 n\geq 5)

### 2610.20976 — Chemotaxis models with signal-dependent sensitivity and a logistic-type source, III: Bifurcation and spike-like solutions

math.AP, 42 pages, 0 two-column pages, class `article`, citations numeric+qualified (27). Role: random.
HTML declaration strings found in the PDF: 14/14 named, 111/113 equations.
Main resolves 91% (359/395); misses 7, extraction gaps 29, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.06s plus 0.63s extraction. A model pass would send about 50978 input tokens across 37 pages.
Main fails: .
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 '(2.18)': not in the statement index
- p.22 '(2.18)': not in the statement index
- p.19 '(2.28)': not in the statement index
- p.20 '(2.28)': not in the statement index
- p.8 'Section 3' did not locate section 3
- p.12 'Section 3' did not locate section 3
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 4 about` → p.27 (heading on p.27, Extension of the local bifurcation branches and proof of The)
- ok `what is section 6 about` → p.36 (heading on p.36, Numerical analysis of the bifurcation and spike-like solutio)
- ok `what is section 4.1 about` → p.30 (heading on p.30, Proof of Theorem 1.3 (1))

### 2610.21341 — Matrix Completion Discriminants

math.CO, 29 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (29). Role: random.
Shared counters: Proposition 2.1 then Lemma 2.2; Lemma 2.2 then Proposition 2.3; Proposition 2.3 then Theorem 2.4; Corollary 3.2 then Proposition 3.3; Proposition 4.3 then Lemma 4.4; Lemma 4.5 then Proposition 4.6.
HTML declaration strings found in the PDF: 33/33 named, 16/16 equations.
Main resolves 87% (111/128); misses 2, extraction gaps 15, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.05s plus 0.53s extraction. A model pass would send about 36924 input tokens across 24 pages.
Main fails: resolution 86.7% is under 90%; a section question missed its heading page.
Hover+chat fails: resolution 86.7% is under 90%; a section question missed its heading page.
Number search `Lemma 2.2` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 'Section 3.4' did not locate section 3.4
- p.8 'Section 6' did not locate section 6
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.11 (heading on p.11, Clique-sum)
- miss `what is section 6 about` → p.None (heading on p.None, MC discriminants of K 4 K_{4} -minor-free graphs and cycle-c)
- miss `what is section 3.3 about` → p.None (heading on p.None, Coincidence beyond cycle-completable graphs)

### 2610.04096 — The Benson--Etingof--Ostrik conjecture for finite tensor categories

math.CT, 23 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (32). Role: random.
Shared counters: Lemma 3.4 then Proposition 3.5; Proposition 3.5 then Corollary 3.6; Lemma 3.16 then Theorem 3.17; Theorem 3.17 then Lemma 3.18; Theorem 4.1 then Lemma 4.2; Proposition 4.5 then Lemma 4.6.
HTML declaration strings found in the PDF: 37/37 named, 10/10 equations.
Main resolves 77% (17/22); misses 2, extraction gaps 3, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.04s plus 0.36s extraction. A model pass would send about 30252 input tokens across 20 pages.
Main fails: resolution 77.3% is under 90%; 1 indexed statement is not in the HTML declarations.
Hover+chat fails: resolution 77.3% is under 90%; 27 citation spans emitted as local refs; 1 indexed statement is not in the HTML declarations.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.19 '§2.1.1' did not locate section 2.1.1
- p.17 '§2.2.3' did not locate section 2.2.3
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.6 (heading on p.6, The refined Steinberg splitting conjecture)
- ok `what is section 4 about` → p.17 (heading on p.17, The Benson–Etingof–Ostrik conjecture)
- ok `what is section 3.3 about` → p.16 (heading on p.16, Steinberg splitting for elementary abelian groups)

### 2610.21303 — Asymptotics of the Moduli Spaces of Parabolic $\mathrm{SL}(3,\mathbb C)$-Higgs Bundles

math.DG, 54 pages, 0 two-column pages, class `scrartcl`, citations qualified (68). Role: random.
Shared counters: Proposition 2.7 then Lemma 2.8; Lemma 2.8 then Proposition 2.9; Proposition 4.3 then Lemma 4.4; Proposition 4.6 then Theorem 4.7; Theorem 4.7 then Lemma 4.8; Lemma 4.8 then Proposition 4.9.
HTML declaration strings found in the PDF: 37/37 named, 80/80 equations.
Main resolves 100% (110/110); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.06s plus 0.51s extraction. A model pass would send about 56907 input tokens across 43 pages.
Main fails: .
Hover+chat fails: 42 citation spans emitted as local refs.
Number search `Lemma 2.8` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.2 (heading on p.2, Introduction)
- ok `what is section 4 about` → p.21 (heading on p.21, Approximate and exact solutions)
- ok `what is section 6 about` → p.43 (heading on p.43, ALG asymptotics and compactification)
- ok `what is section 4.2 about` → p.24 (heading on p.24, The linearized equation)

### 2610.21627 — Degree Growth of Rational Maps with Laurent Property

math.DS, 20 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (18). Role: random.
HTML declaration strings found in the PDF: 24/24 named, 19/19 equations.
Main resolves 100% (90/90); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.24s extraction. A model pass would send about 21567 input tokens across 16 pages.
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
Main resolves 96% (217/225); misses 6, extraction gaps 2, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.46s extraction. A model pass would send about 31551 input tokens across 23 pages.
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
Main resolves 63% (37/59); misses 7, extraction gaps 15, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 7. Index built in 0.06s plus 0.56s extraction. A model pass would send about 35071 input tokens across 23 pages.
Main fails: resolution 62.7% is under 90%; 7 indexed statements are not in the HTML declarations; a section question missed its heading page.
Hover+chat fails: resolution 65.6% is under 90%; 2 wrong links; 33 citation spans emitted as local refs; 7 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 3.6` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.23 '§3.1' did not locate section 3.1
- p.23 '§3.2' did not locate section 3.2
- p.29 '§3.3' did not locate section 3.3
- p.8 '§3.4' did not locate section 3.4
- p.6 'Theorem 1.1': detector missed it
- p.7 'Theorem 1.1': detector missed it
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.8 (heading on p.8, Symplectic cohomology, wrapped Floer cohomology, and contact)
- ok `what is section 5 about` → p.30 (heading on p.30, Proof of the main results)
- miss `what is section 3.3 about` → p.None (heading on p.None, Structures on symplectic cohomology and wrapped Floer cohomo)

### 2610.14417 — A Nullstellensatz for the field of complex Laurent series

math.LO, 19 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (34). Role: random.
Shared counters: Lemma 4.2 then Theorem 4.3; Lemma 5.2 then Theorem 5.3; Theorem 5.3 then Lemma 5.4; Lemma 5.4 then Proposition 5.5; Proposition 5.5 then Corollary 5.6; Proposition 6.3 then Lemma 6.4.
HTML declaration strings found in the PDF: 38/39 named, 1/1 equations.
Main resolves 95% (55/58); misses 3, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.04s plus 0.50s extraction. A model pass would send about 24257 input tokens across 15 pages.
Main fails: 1 indexed statement is not in the HTML declarations.
Hover+chat fails: 1 indexed statement is not in the HTML declarations.
Number search `Lemma 3.2` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 'Theorem 8.3': not in the statement index
- p.17 'Theorem 8.3': not in the statement index
- p.18 'Theorem 8.3': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 5 about` → p.7 (heading on p.7, Formally T T -adic fields)
- ok `what is section 9 about` → p.18 (heading on p.18, Open questions)
- ok `what is section 2.2 about` → p.4 (heading on p.4, Radicals and zero sets)

### 2610.16227 — Contractivity of Rudin's diagonal restriction operator for $H^p$ of the polydisc

math.CA, 16 pages, 0 two-column pages, class `amsart`, citations numeric (22). Role: random.
Shared counters: Theorem 1.1 then Lemma 1.2; Lemma 2.1 then Theorem 2.2; Theorem 2.2 then Lemma 2.3; Theorem 3.2 then Lemma 3.3.
HTML declaration strings found in the PDF: 15/15 named, 14/14 equations.
Main resolves 99% (125/126); misses 0, extraction gaps 1, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.24s extraction. A model pass would send about 16309 input tokens across 12 pages.
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
Main resolves 100% (46/46); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.43s extraction. A model pass would send about 20456 input tokens across 14 pages.
Main fails: .
Hover+chat fails: 1 wrong link; 16 citation spans emitted as local refs.
Number search `Lemma 2.7` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.8 (heading on p.8, Brauer Groups of K3 and Enriques Surfaces)
- ok `what is section 5 about` → p.24 (heading on p.24, Example and Application to Weak Approximation)
- ok `what is section 2.4 about` → p.7 (heading on p.7, Upper Bounds on Chow Groups of Enriques Surfaces)

### 2610.18580 — A two-level preconditioner for discontinuous virtual element methods with irregular subdomains

math.NA, 29 pages, 0 two-column pages, class `siamart251216`, citations numeric+qualified (25). Role: random.
HTML declaration strings found in the PDF: 0/18 named, 1/33 equations. Named statement numbers in the HTML do not match the PDF, so this resolution rate is not a fair Cauchy score.
Main resolves 0% (0/79); misses 2, extraction gaps 77, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 51. Index built in 0.04s plus 0.92s extraction. A model pass would send about 27773 input tokens across 21 pages.
Main fails: resolution 0.0% is under 90%; 51 indexed statements are not in the HTML declarations.
Hover+chat fails: resolution 0.0% is under 90%; 51 indexed statements are not in the HTML declarations.
Number search `Lemma 4` served: False. Short query `None` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.14 '(1)': not in the statement index
- p.21 '(1)': not in the statement index
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 4 about` → p.10 (heading on p.10, Two level overlapping Schwarz methods)
- ok `what is section 7 about` → p.25 (heading on p.25, Conclusions and final remarks)
- ok `what is section 4.2 about` → p.10 (heading on p.10, Continuous reduced coarse space)

### 2610.13792 — The generator problem for C*-algebras with comparison

math.OA, 41 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (68). Role: random.
Shared counters: Lemma 2.8 then Corollary 2.9; Theorem 2.11 then Proposition 2.12; Proposition 3.4 then Lemma 3.5; Lemma 3.5 then Theorem 3.6; Lemma 4.7 then Theorem 4.8; Theorem 4.8 then Lemma 4.9.
HTML declaration strings found in the PDF: 39/39 named, 146/146 equations.
Main resolves 83% (92/111); misses 0, extraction gaps 19, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.06s plus 0.57s extraction. A model pass would send about 44349 input tokens across 33 pages.
Main fails: resolution 82.9% is under 90%.
Hover+chat fails: resolution 82.9% is under 90%.
Number search `Lemma 2.3` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 3 about` → p.10 (heading on p.10, Tracially AF algebras)
- ok `what is section 4 about` → p.20 (heading on p.20, C ∗ C^{*} -algebras with a Cantor spectrum subalgebra)
- ok `what is section 3.1 about` → p.10 (heading on p.10, Properties of tracially AF algebras)

### 2610.19840 — GPU-Accelerated Preprocessing for Large-Scale Linear Programming

math.OC, 22 pages, 0 two-column pages, class `article`, citations numeric (36). Role: random.
HTML declaration strings found in the PDF: 9/9 named, 13/13 equations.
Main resolves 96% (117/122); misses 0, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.28s extraction. A model pass would send about 17474 input tokens across 12 pages.
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
Main resolves 98% (188/192); misses 0, extraction gaps 4, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 4. Index built in 0.08s plus 0.88s extraction. A model pass would send about 52248 input tokens across 36 pages.
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
Main resolves 100% (81/81); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.36s extraction. A model pass would send about 18592 input tokens across 12 pages.
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
Main resolves 92% (111/121); misses 5, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 1. Index built in 0.04s plus 0.39s extraction. A model pass would send about 34278 input tokens across 25 pages.
Main fails: 1 indexed statement is not in the HTML declarations; a section question missed its heading page.
Hover+chat fails: 1 indexed statement is not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 1.2` served: True. Short query `Lemma 1` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.7 '(4.3)': detector missed it
- p.5 '§1.2' did not locate section 1.2
- p.12 '§2.1' did not locate section 2.1
- p.14 '§3.1' did not locate section 3.1
- p.24 '§3.1' did not locate section 3.1
Section questions (hover+chat):
- ok `what is section 1 about` → p.5 (heading on p.5, Preliminaries)
- ok `what is section 4 about` → p.17 (heading on p.17, Tilted R R -polynomials)
- ok `what is section 6 about` → p.26 (heading on p.26, Fundamental classes and quantum cohomology)
- miss `what is section 2.2 about` → p.None (heading on p.9, Affine realizations of tilted Bruhat intervals)

### 2610.11661 — BiHom-Poisson conformal superalgebras arising from related algebraic structures

math.RA, 25 pages, 0 two-column pages, class `amsart`, citations numeric (10). Role: random.
Shared counters: Theorem 2.7 then Proposition 2.8; Proposition 2.17 then Theorem 2.18; Theorem 2.18 then Proposition 2.19; Proposition 2.19 then Theorem 2.20; Proposition 2.22 then Theorem 2.23; Theorem 2.28 then Proposition 2.29.
HTML declaration strings found in the PDF: 67/67 named, 61/61 equations.
Main resolves 100% (44/44); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.04s plus 0.46s extraction. A model pass would send about 29710 input tokens across 22 pages.
Main fails: .
Number search `Lemma 3.26` served: True. Short query `Lemma 3` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 2 about` → p.2 (heading on p.2, Preliminaries and some results)
- ok `what is section 3 about` → p.14 (heading on p.14, Construction theorems)
- ok `what is section 3.1 about` → p.15 (heading on p.15, From BiHom-associative conformal superalgebras)

### 2609.00233 — A survey on mapping class groups of 3-manifolds

math.GT, 82 pages, 0 two-column pages, class `amsart`, citations qualified (213). Role: survey-60-pages.
The random sample has no paper of 60 or more pages. This 82-page survey is kept as that edge case and is not one of the 20.
Shared counters: Theorem 3.2 then Proposition 3.3; Proposition 3.4 then Lemma 3.5; Theorem 4.2 then Proposition 4.3; Proposition 4.3 then Lemma 4.4; Lemma 4.4 then Proposition 4.5; Proposition 4.5 then Theorem 4.6.
HTML declaration strings found in the PDF: 151/151 named, 11/11 equations.
Main resolves 97% (223/229); misses 6, extraction gaps 0, wrong links 0, citation emissions 2 (0 of them indexed), false declarations 0. Index built in 0.13s plus 1.20s extraction. A model pass would send about 99969 input tokens across 66 pages.
Main fails: 2 citation spans emitted as local refs; a section question missed its heading page.
Hover+chat fails: 4 wrong links; 63 citation spans emitted as local refs; a section question missed its heading page.
Number search `Lemma 2.4` served: True. Short query `Lemma 2` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.63 '(10.11)': not in the statement index
- p.64 '(10.11)': not in the statement index
- p.3 'Section 3' did not locate section 3
- p.5 'Section 3' did not locate section 3
- p.7 'Section 3' did not locate section 3
Citation:
- p.37 theorem 1 in 'wn by Jørgensen [Jør77, Theorem 1] that there exist compa'
- p.39 theorem 2.28 in 'r as well (see [L¨uc10, Theorem 2.28]). In particular, if tw'
Section questions (hover+chat):
- ok `what is section 1 about` → p.1 (heading on p.1, Introduction)
- ok `what is section 7 about` → p.36 (heading on p.36, Mapping class groups of hyperbolic 3-manifolds)
- ok `what is section 12 about` → p.73 (heading on p.73, Further topics)
- miss `what is section 6.2 about` → p.None (heading on p.None, Statement of the main theorems on Haken 3-manifolds)

### 2610.22308 — Classical Capacity of Single-Mode Bosonic Gaussian Channels

quant-ph, 24 pages, 24 two-column pages, class `revtex4-2`, citations numeric+qualified (57). Role: two-column.
No random math.* paper has a two-column page. This revtex4-2 reprint PDF is two-column on every page. Its primary category is quant-ph, with math-ph secondary, because recent math.* submissions are single-column. It is not one of the 20.
HTML declaration strings found in the PDF: 18/18 named, 33/146 equations. Most HTML equation numbers are not printed in the PDF, so equation mentions inflate the miss count.
Main resolves 55% (101/183); misses 10, extraction gaps 72, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.06s plus 0.58s extraction. A model pass would send about 36801 input tokens across 18 pages.
Main fails: resolution 55.2% is under 90%; a section question missed its heading page.
Hover+chat fails: resolution 55.2% is under 90%; a section question missed its heading page.
Number search `Lemma 9` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.3 'Eq. (12)': detector missed it
- p.5 '(20)': not in the statement index
- p.3 '(31)': detector missed it
- p.3 '(43)': detector missed it
- p.3 '(46)': detector missed it
- p.2 'Section V' did not locate section V

## Proposed tickets

1. **Match “1. Introduction” when asked what section 1 is about** — AskStructureLocator treats a dotted number such as 9.2 as a section title, and does not treat a top-level heading “N. Title” as section N. Main has no locator, so the question fails there too. Size: small–medium. The locator already exists on the chat branch; section titles need the undotted leading-number match that chapter titles already use. Evidence: On the combined profile, dotted section questions land correctly 16/19 times and undotted ones 59/60 times. 3/20 papers still miss at least one probed section.
2. **Suppress author–year qualified citations, not only numeric ones** — Hover drops [12, Theorem 3.2], and still emits [IK99, Lemma 1.15] and [CV23, Theorem 3.5] as local references. New abbreviation and plural matches inside those cites can add detections. Size: small. The qualifier pattern should accept an author key or a year, not only a number before the comma. Evidence: Citation-span emissions on the comparable papers go from 0 on main to 125 on hover. Hover is higher on 2610.21544, 2610.04096, 2610.21303, 2610.19333, 2610.19307, 2610.21864; also 2609.00233 2→63 outside the 20.
3. **Do not index enumerated proof items (1) (2) (3) as equations** — A left-margin line that contains a math arrow passes declarationMatches, so the source-fallback index stores equation keys the paper never displays. Size: medium. The declaration filter needs a tighter check than “label near the left margin and the line looks like mathematics.” Evidence: 14 indexed keys on main are absent from the HTML declarations, after setting aside papers whose HTML numbers do not match the PDF.
4. **Resolve a shortened number, and plurals on main** — “Lemma 2” now returns Lemma 2.1, and “Lemmas 4.6” is detected. Literal “Lemma 4” still requires a lemma numbered exactly 4. Size: small. Evidence: Exact printed queries are served on 19/19 comparable papers. A shortened first component retrieves the full number on 17/17 papers. Literal “Lemma 4” hits a lemma numbered 4 on 0 papers. Plural misses include: none recorded.
5. **Store the printed statement name on the source-fallback index** — A parenthetical such as “(Zorn)” is now stored on the source-fallback entry. This corpus does not print that name inside the HTML theorem tag, so the measured route stays empty. Size: small. Parse a parenthetical title into the fallback entry; the term route already exists. Evidence: 0/0 papers expose a parenthetical name in the HTML tag and serve it from the index. This corpus mostly does not print names inside the theorem tag, so the route is empty rather than wrong.
