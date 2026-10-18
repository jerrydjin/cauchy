# arXiv maths scorecard

**0 of 20 random papers work with no fixes on main.**
**0 of 20 pass if the open hover and chat branches are both applied.**

A paper works with no fixes when all of these hold:

- At least 8 theorem, lemma, definition, equation, or section references are recoverable.
- At least 90% of them resolve. A statement resolves when the detector names the right kind and number and the source-fallback index contains that key. A section reference resolves when “what is section N about” lands on the page that prints the heading.
- There is no wrong link: no citation span opens an indexed statement, no printed reference opens a different statement, and the index contains no statement the HTML does not declare.
- No bracket or author–year citation is emitted as a local reference.
- Every probed “what is section N about” question lands on the heading page.

Main does not include the section locator, so the last condition fails on main for every paper that has numbered sections. Dropping only that condition, 2 of 20 pass on main and 3 of 20 pass on the hover branch. The headline above keeps the section question.

Shared counters, such as a theorem followed by a lemma with the next number, appear on 16 of 20 papers. The index key is the kind plus the full number, so the pair resolves when both declarations are indexed.

Text comes from PyMuPDF’s content stream, the stand-in for `PDFPage.string`. Equation x-positions are glyph-box fractions, the stand-in for PDFKit selection bounds. No model is called; index time is the deterministic source fallback. Token estimates are input size only and were not billed.

An exact printed query such as “Lemma 2.1” is served from the existing index on 19/19 comparable papers (the key must already be indexed). A shortened query such as “Lemma 2” retrieves the full number on 0/17 of those papers. Literal “Lemma 4” hits a lemma numbered 4 on 0 papers: these papers print dotted numbers, and lookup does not expand the first component. Source-fallback entries store no printed name, so a name query is not served from this index.

## Random papers

| arXiv | cat | pages | class | main | hover | chat | both | index s | model toks |
|---|---|---:|---|---|---|---|---|---:|---:|
| 2610.21544 | AG | 12 | amsart | 97% (57/59) | 97% (57/59) | 97% (57/59) | 97% (57/59) | 0.2 | 13355 |
| 2610.11671 | AT | 27 | amsart | 91% (61/67) | 93% (62/67) | 91% (61/67) | 93% (62/67) | 0.3 | 26453 |
| 2610.20976 | AP | 42 | article | 88% (348/395) | 88% (349/395) | 88% (348/395) | 88% (349/395) | 0.7 | 50978 |
| 2610.21341 | CO | 29 | amsart | 78% (100/129) | 78% (100/129) | 81% (104/129) | 81% (104/129) | 0.6 | 36924 |
| 2610.04096 | CT | 23 | amsart | 70% (16/23) | 70% (16/23) | 74% (17/23) | 74% (17/23) | 0.4 | 31894 |
| 2610.21303 | DG | 54 | scrartcl | 89% (100/112) | 89% (100/112) | 89% (100/112) | 89% (100/112) | 0.6 | 56907 |
| 2610.21627 | DS | 20 | amsart | 72% (65/90) | 73% (66/90) | 72% (65/90) | 73% (66/90) | 0.3 | 21567 |
| 2610.18041 | FA | 25 | amsart | 95% (215/226) | 95% (215/226) | 95% (215/226) | 95% (215/226) | 0.5 | 31551 |
| 2610.20306 | GR | 14 | amsart | 75% (47/63) | 75% (47/63) | 75% (47/63) | 75% (47/63) | 0.3 | 17071 |
| 2610.19333 | GT | 36 | amsart | 52% (33/63) | 52% (33/63) | 52% (33/63) | 52% (33/63) | 0.6 | 39436 |
| 2610.14417 | LO | 19 | amsart | 95% (55/58) | 95% (55/58) | 95% (55/58) | 95% (55/58) | 0.5 | 27693 |
| 2610.16227 | CA | 16 | amsart | 90% (114/127) | 93% (118/127) | 90% (114/127) | 93% (118/127) | 0.2 | 16309 |
| 2610.19307 | NT | 27 | amsart | 85% (40/47) | 85% (40/47) | 91% (43/47) | 91% (43/47) | 0.4 | 20456 |
| 2610.18580 | NA | 29 | siamart251216 | 0% (0/79) | 0% (0/79) | 0% (0/79) | 0% (0/79) | 0.9 | 27773 |
| 2610.13792 | OA | 41 | amsart | 74% (84/113) | 76% (86/113) | 74% (84/113) | 76% (86/113) | 0.5 | 44349 |
| 2610.19840 | OC | 22 | article | 84% (103/122) | 84% (103/122) | 84% (103/122) | 84% (103/122) | 0.3 | 17474 |
| 2610.21864 | PR | 40 | article | 94% (181/192) | 96% (184/192) | 94% (181/192) | 96% (184/192) | 0.8 | 52248 |
| 2610.15448 | QA | 17 | article | 98% (79/81) | 98% (79/81) | 98% (79/81) | 98% (79/81) | 0.3 | 18592 |
| 2610.14991 | RT | 30 | amsart | 82% (106/130) | 81% (105/130) | 82% (106/130) | 81% (105/130) | 0.4 | 34278 |
| 2610.11661 | RA | 25 | amsart | 100% (44/44) | 100% (44/44) | 100% (44/44) | 100% (44/44) | 0.4 | 29710 |

## Edge cases kept outside the 20

The random sample’s longest paper is 54 pages and it has 0 two-column pages. The papers below are scored the same way and are not part of the headline.

- 2609.00233 (survey-60-pages, 82 pages, 0 two-column, `amsart`): main 84% (203/241), pass=False. The random sample has no paper of 60 or more pages. This 82-page survey is kept as that edge case and is not one of the 20.
- 2610.22308 (two-column, 24 pages, 24 two-column, `revtex4-2`): main 55% (104/190), pass=False. No random math.* paper has a two-column page. This revtex4-2 reprint PDF is two-column on every page. Its primary category is quant-ph, with math-ph secondary, because recent math.* submissions are single-column. It is not one of the 20.

## Per paper

### 2610.21544 — On the variety of sum of powers of certain complete intersection forms

math.AG, 12 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (29). Role: random.
Shared counters: Lemma 2.1 then Theorem 2.2; Theorem 3.22 then Proposition 3.23.
HTML declaration strings found in the PDF: 15/15 named, 14/14 equations.
Main resolves 97% (57/59); misses 1, extraction gaps 1, wrong links 0, citation emissions 6 (0 of them indexed), false declarations 1. Index built in 0.01s plus 0.22s extraction. A model pass would send about 13355 input tokens across 9 pages.
Main fails: 6 citation spans emitted as local refs; 1 indexed statement is not in the HTML declarations; section questions are not implemented.
Hover+chat fails: 6 citation spans emitted as local refs; 1 indexed statement is not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.1 'Section 2' did not locate section 2
Citation:
- p.3 lemma 1.15 in 'er the reader to [IK99, Lemma 1.15] for a proof. Lemma 2.1'
- p.4 definition 3.5 in 'utability from [CCC+18, Definition 3.5]. In Theorem 2.2, the r'
- p.4 proposition 3.6 in '3.2]. Applying [CCC+18, Proposition 3.6] we get I(X) : (h) = I('
- p.6 proposition 23 in 'in the proof of [BBT13, Proposition 23]. Consider the open sub'
- p.9 proposition 28 in 'in the proof of [BBT13, Proposition 28]. Let B′ := n Y i=0 i̸='
- p.10 example 6.1 in 'ion. Proof. In [BCMS26, Example 6.1] it is proved that 4 < '
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.3, Computation of VSP)
- miss `what is section 4 about` → p.None (heading on p.10, Final remarks)

### 2610.11671 — A complete classification of the rational realization of gap-two products of Eilenberg--MacLane spaces as classifying spaces

math.AT, 27 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (19). Role: random.
Shared counters: Lemma 4.2 then Proposition 4.3; Proposition 4.3 then Lemma 4.4; Lemma 4.4 then Proposition 4.5; Proposition 4.5 then Lemma 4.6; Lemma 4.10 then Proposition 4.11; Proposition 5.2 then Lemma 5.3.
HTML declaration strings found in the PDF: 23/23 named, 9/9 equations.
Main resolves 91% (61/67); misses 1, extraction gaps 5, wrong links 0, citation emissions 3 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.31s extraction. A model pass would send about 26453 input tokens across 20 pages.
Main fails: 3 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: a section question missed its heading page.
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.15 'Lemmas 4.6': detector missed it
Citation:
- p.6 proposition 3.3 in 'o constant part. By [3, Proposition 3.3], this leads to a contr'
- p.9 proposition 14.13 in 'ING SPACES 9 (2) By [7, Proposition 14.13], we can show the minim'
- p.9 proposition 14.13 in ' = 0. Similarly, by [7, Proposition 14.13], we can show the minim'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.5, Reduction to two cases)
- miss `what is section 5 about` → p.None (heading on p.20, The branch n ≤ 4 n\leq 4)
- ok `what is section 4.5 about` → p.17 (heading on p.17, Realization when n ≥ 5 n\geq 5)

### 2610.20976 — Chemotaxis models with signal-dependent sensitivity and a logistic-type source, III: Bifurcation and spike-like solutions

math.AP, 42 pages, 0 two-column pages, class `article`, citations numeric+qualified (27). Role: random.
HTML declaration strings found in the PDF: 14/14 named, 111/113 equations.
Main resolves 88% (348/395); misses 18, extraction gaps 29, wrong links 0, citation emissions 8 (0 of them indexed), false declarations 2. Index built in 0.04s plus 0.64s extraction. A model pass would send about 50978 input tokens across 37 pages.
Main fails: resolution 88.1% is under 90%; 8 citation spans emitted as local refs; 2 indexed statements are not in the HTML declarations; section questions are not implemented.
Hover+chat fails: resolution 88.4% is under 90%; 2 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 '(2.18)': not in the statement index
- p.22 '(2.18)': not in the statement index
- p.19 '(2.28)': not in the statement index
- p.20 '(2.28)': not in the statement index
- p.6 'Section 2' did not locate section 2
- p.12 'Section 2' did not locate section 2
Citation:
- p.4 definition 1.1 in 'refer the reader to [3, Definition 1.1] in Part I. The reader '
- p.7 theorem 5.1.1 in 'anifold theory (see [8, Theorem 5.1.1]), there are no non-con'
- p.30 theorem 4.4 in 'ness hypotheses of [26, Theorem 4.4] also hold. Hence, [26,'
- p.30 theorem 4.4 in ' also hold. Hence, [26, Theorem 4.4] yields that the connec'
- p.32 theorem 4.3 in 'ifurcation theorem [26, Theorem 4.3] applied to the station'
- p.33 theorem 3.1 in 'g the arguments of [30, Theorem 3.1] and [21, Theorem 3.1],'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.None, Introduction)
- miss `what is section 4 about` → p.None (heading on p.None, Extension of the local bifurcation branches and proof of The)
- miss `what is section 6 about` → p.12 (heading on p.None, Numerical analysis of the bifurcation and spike-like solutio)
- miss `what is section 4.1 about` → p.2 (heading on p.None, Proof of Theorem 1.3 (1))

### 2610.21341 — Matrix Completion Discriminants

math.CO, 29 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (29). Role: random.
Shared counters: Proposition 2.1 then Lemma 2.2; Lemma 2.2 then Proposition 2.3; Proposition 2.3 then Theorem 2.4; Corollary 3.2 then Proposition 3.3; Proposition 4.3 then Lemma 4.4; Lemma 4.5 then Proposition 4.6.
HTML declaration strings found in the PDF: 33/33 named, 16/16 equations.
Main resolves 78% (100/129); misses 13, extraction gaps 15, wrong links 1, citation emissions 11 (0 of them indexed), false declarations 0. Index built in 0.03s plus 0.52s extraction. A model pass would send about 36924 input tokens across 24 pages.
Main fails: resolution 77.5% is under 90%; 1 wrong link; 11 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: resolution 80.6% is under 90%; 1 wrong link; a section question missed its heading page.
Number search `Lemma 2.2` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.18 'Section 1' did not locate section 1
- p.3 'Section 2' did not locate section 2
- p.3 'Section 3' did not locate section 3
- p.7 'Section 3' did not locate section 3
- p.2 'Section 3.4' did not locate section 3.4
- p.3 'Sections 4' did not locate section 4
Wrong:
- p.4 'Section 2.1' sits inside a citation
Citation:
- p.5 corollary 4.4.4 in 'symmetric matrices [14, Corollary 4.4.4] and the linear indepen'
- p.7 corollary 4.11 in 'ascarin, and Telen [21, Corollary 4.11]. We discuss this conne'
- p.7 theorem 1.1 in 'cKee [17] (see also [9, Theorem 1.1]): every cycle-completa'
- p.9 proposition 4.7 in ' is a hypersurface [21, Proposition 4.7], so H would be one of '
- p.9 corollary 4.11 in 's formula combines [21, Corollary 4.11] with the resultant for'
- p.9 theorem 3.12 in ' resultant formula [21, Theorem 3.12] and homoge- nization ['
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- ok `what is section 4 about` → p.8 (heading on p.8, Clique-sum)
- miss `what is section 6 about` → p.None (heading on p.19, MC discriminants of K 4 K_{4} -minor-free graphs and cycle-c)
- miss `what is section 3.3 about` → p.None (heading on p.10, Coincidence beyond cycle-completable graphs)

### 2610.04096 — The Benson--Etingof--Ostrik conjecture for finite tensor categories

math.CT, 23 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (32). Role: random.
Shared counters: Lemma 3.4 then Proposition 3.5; Proposition 3.5 then Corollary 3.6; Lemma 3.16 then Theorem 3.17; Theorem 3.17 then Lemma 3.18; Theorem 4.1 then Lemma 4.2; Proposition 4.5 then Lemma 4.6.
HTML declaration strings found in the PDF: 37/37 named, 10/10 equations.
Main resolves 70% (16/23); misses 3, extraction gaps 3, wrong links 1, citation emissions 27 (3 of them indexed), false declarations 3. Index built in 0.02s plus 0.36s extraction. A model pass would send about 31894 input tokens across 21 pages.
Main fails: resolution 69.6% is under 90%; 1 wrong link; 27 citation spans emitted as local refs; 3 indexed statements are not in the HTML declarations; section questions are not implemented.
Hover+chat fails: resolution 73.9% is under 90%; 1 wrong link; 27 citation spans emitted as local refs; 3 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 2.1` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.19 '§2.1.1' did not locate section 2.1.1
- p.17 '§2.2.3' did not locate section 2.2.3
- p.21 '§4.2' did not locate section 4.2
Wrong:
- p.3 '§4.2' sits inside a citation
Citation:
- p.2 equation 1 in '([CF26, Conjecture 5.4.2(1)], [CF25]). For any r ≥1'
- p.3 lemma 3.2.2 in 'The following is [CF25, Lemma 3.2.2]. Lemma 2.1. The follow'
- p.5 lemma 1.9.8 in '0. Moreover, by [Ben17, Lemma 1.9.8] we have supp(M|G) = su'
- p.5 lemma 1.9.5 in 'M) ⊂Pr−1 f (see [Ben17, Lemma 1.9.5]), while the condition '
- p.17 lemma 3.1.6 in 'ws directly from [CF25, Lemma 3.1.6], which shows that Str−'
- p.17 theorem 8.2.1 in ' categories, by [CEO24, Theorem 8.2.1]. Lemma 4.2. Consider s'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.6, The refined Steinberg splitting conjecture)
- miss `what is section 4 about` → p.None (heading on p.17, The Benson–Etingof–Ostrik conjecture)
- ok `what is section 3.3 about` → p.16 (heading on p.16, Steinberg splitting for elementary abelian groups)

### 2610.21303 — Asymptotics of the Moduli Spaces of Parabolic $\mathrm{SL}(3,\mathbb C)$-Higgs Bundles

math.DG, 54 pages, 0 two-column pages, class `scrartcl`, citations qualified (68). Role: random.
Shared counters: Proposition 2.7 then Lemma 2.8; Lemma 2.8 then Proposition 2.9; Proposition 4.3 then Lemma 4.4; Proposition 4.6 then Theorem 4.7; Theorem 4.7 then Lemma 4.8; Lemma 4.8 then Proposition 4.9.
HTML declaration strings found in the PDF: 37/37 named, 80/80 equations.
Main resolves 89% (100/112); misses 10, extraction gaps 0, wrong links 2, citation emissions 38 (11 of them indexed), false declarations 0. Index built in 0.04s plus 0.51s extraction. A model pass would send about 56907 input tokens across 43 pages.
Main fails: resolution 89.3% is under 90%; 2 wrong links; 38 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: resolution 89.3% is under 90%; 2 wrong links; 42 citation spans emitted as local refs; a section question missed its heading page.
Number search `Lemma 2.8` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.6 'Section 2' did not locate section 2
- p.12 'Sections 2.4' did not locate section 2.4
- p.8 'Section 2.5' did not locate section 2.5
- p.6 'Section 3' did not locate section 3
- p.6 'Section 4' did not locate section 4
- p.40 'Section 4' did not locate section 4
Wrong:
- p.33 'Section 4' sits inside a citation
- p.12 'Section 5' sits inside a citation
Citation:
- p.2 proposition 2.14 in ' Hodge pairings [Fre20, Proposition 2.14 and Theorem 2.15]. The '
- p.2 theorem 2.15 in '0, Proposition 2.14 and Theorem 2.15]. The asymptotic pictur'
- p.5 proposition 2.1 in 'ahler regularity [HT20, Proposition 2.1], and interpo- lation. '
- p.5 lemma 3.2 in ' calculation in [Jia26, Lemma 3.2 and the proof of Propos'
- p.5 proposition 3.3 in 'ma 3.2 and the proof of Proposition 3.3]. The resolution of (Y '
- p.5 proposition 6.3 in ' described in [Huang26, Proposition 6.3 and Lemma 6.10], follow'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.2, Introduction)
- miss `what is section 4 about` → p.6 (heading on p.21, Approximate and exact solutions)
- miss `what is section 6 about` → p.None (heading on p.43, ALG asymptotics and compactification)
- miss `what is section 4.2 about` → p.2 (heading on p.24, The linearized equation)

### 2610.21627 — Degree Growth of Rational Maps with Laurent Property

math.DS, 20 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (18). Role: random.
HTML declaration strings found in the PDF: 24/24 named, 19/19 equations.
Main resolves 72% (65/90); misses 25, extraction gaps 0, wrong links 0, citation emissions 1 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.24s extraction. A model pass would send about 21567 input tokens across 16 pages.
Main fails: resolution 72.2% is under 90%; 1 citation span emitted as a local ref; section questions are not implemented.
Hover+chat fails: resolution 73.3% is under 90%; a section question missed its heading page.
Number search `Lemma 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.3 '(1)': not in the statement index
- p.6 '(1)': not in the statement index
- p.7 'equation (1)': not in the statement index
- p.10 'equation (1)': not in the statement index
- p.10 '(1)': not in the statement index
- p.13 'equation (1)': not in the statement index
Citation:
- p.3 proposition 11.4 in 'binson recurrences [10, Proposition 11.4] from the combinatorial'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.7, Computing Algebraic Entropy)
- miss `what is section 4 about` → p.None (heading on p.14, Growth Rate Sequences of Gale–Robinson)
- ok `what is section 3.3 about` → p.11 (heading on p.11, Proof of Theorem 2)

### 2610.18041 — Completely symmetric subspaces of noncommutative $L_p$-spaces

math.FA, 25 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (62). Role: random.
Shared counters: Theorem 1.1 then Corollary 1.2; Corollary 1.2 then Theorem 1.3.
HTML declaration strings found in the PDF: 10/10 named, 65/65 equations.
Main resolves 95% (215/226); misses 8, extraction gaps 2, wrong links 1, citation emissions 51 (3 of them indexed), false declarations 1. Index built in 0.03s plus 0.43s extraction. A model pass would send about 31551 input tokens across 23 pages.
Main fails: 1 wrong link; 51 citation spans emitted as local refs; 1 indexed statement is not in the HTML declarations; section questions are not implemented.
Hover+chat fails: 1 wrong link; a section question missed its heading page.
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 '(39)': not in the statement index
- p.19 '(39)': not in the statement index
- p.17 '(41)': not in the statement index
- p.24 '(64)': not in the statement index
- p.7 '(8)': not in the statement index
Wrong:
- p.12 '(1)' sits inside a citation
Citation:
- p.1 corollary 5 in 'ec and Pe lczy´nski [9, Corollary 5] proved that every norm'
- p.1 corollary 2 in 'ubspace X ⊂Lp(0, 1) [9, Corollary 2]: X ∼= ℓ2, or X contain'
- p.1 theorem 1.14 in 'quences in Lp(0, 1) [6, Theorem 1.14]; see also the quantita'
- p.2 corollary 6.8 in 'b < ∞. Junge and Xu [8, Corollary 6.8] proved the classificat'
- p.2 corollary 6.3 in 'inite, Junge and Xu [8, Corollary 6.3] proved that every semi'
- p.2 corollary 6.4 in 'tated separately in [8, Corollary 6.4]: every infinite-dimens'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 2 about` → p.None (heading on p.3, Preliminaries)
- miss `what is section 3 about` → p.None (heading on p.5, Proofs of the main results)
- ok `what is section 3.2 about` → p.8 (heading on p.8, Upper estimate by interpolation)

### 2610.20306 — The zero divisor and augmentation conjectures for medial quandle rings

math.GR, 14 pages, 0 two-column pages, class `amsart`, citations numeric (51). Role: random.
Shared counters: Proposition 3.3 then Lemma 3.4; Lemma 3.4 then Proposition 3.5; Proposition 5.1 then Lemma 5.2; Lemma 6.5 then Proposition 6.6; Proposition 6.6 then Theorem 6.7.
HTML declaration strings found in the PDF: 38/38 named, 2/2 equations.
Main resolves 75% (47/63); misses 5, extraction gaps 4, wrong links 7, citation emissions 2 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.28s extraction. A model pass would send about 17071 input tokens across 11 pages.
Main fails: resolution 74.6% is under 90%; 7 wrong links; 2 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: resolution 74.6% is under 90%; 7 wrong links; a section question missed its heading page.
Number search `Lemma 3.4` served: True. Short query `Lemma 3` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 'Section 2' did not locate section 2
- p.2 'Section 3' did not locate section 3
- p.2 'Section 4' did not locate section 4
- p.2 'Section 5' did not locate section 5
- p.2 'Section 6' did not locate section 6
Wrong:
- p.3 'Sec. 2' sits inside a citation
- p.2 'Sec. 3' sits inside a citation
- p.3 'Sec. 3' sits inside a citation
- p.6 'Sec. 3' sits inside a citation
- p.2 'Sec. 4' sits inside a citation
- p.2 'Sec. 6' sits inside a citation
Citation:
- p.5 equation 8 in 'om the calculation [17, (8)]. Indeed, since π is a '
- p.9 equation 9.4 in 'ransform of u (see [49, (9.4)]) is the function ˆu: ˆ'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 4 about` → p.None (heading on p.7, The zero divisor conjecture)
- miss `what is section 6 about` → p.None (heading on p.10, The augmentation conjecture)
- ok `what is section 3.2 about` → p.6 (heading on p.6, Retracts)

### 2610.19333 — Algebraic overtwistedness of contact $(+1)$-surgeries via augmented Floer theories

math.GT, 36 pages, 0 two-column pages, class `amsart`, citations qualified (84). Role: random.
Shared counters: Theorem 1.1 then Corollary 1.2; Proposition 3.3 then Corollary 3.4.
HTML declaration strings found in the PDF: 25/28 named, 10/15 equations.
Main resolves 52% (33/63); misses 11, extraction gaps 15, wrong links 4, citation emissions 31 (5 of them indexed), false declarations 10. Index built in 0.04s plus 0.52s extraction. A model pass would send about 39436 input tokens across 26 pages.
Main fails: resolution 52.4% is under 90%; 4 wrong links; 31 citation spans emitted as local refs; 10 indexed statements are not in the HTML declarations; section questions are not implemented.
Hover+chat fails: resolution 52.4% is under 90%; 4 wrong links; 33 citation spans emitted as local refs; 10 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 3.6` served: True. Short query `Lemma 3` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.3 '§2' did not locate section 2
- p.3 '§3' did not locate section 3
- p.6 '§3' did not locate section 3
- p.23 '§3.1' did not locate section 3.1
- p.23 '§3.2' did not locate section 3.2
- p.29 '§3.3' did not locate section 3.3
Wrong:
- p.8 '§3' sits inside a citation
- p.8 '§4' sits inside a citation
- p.30 'Theorem 1.1' sits inside a citation
Citation:
- p.2 corollary 7 in ']. According to [MNW13, Corollary 7] (which generalizes the'
- p.2 corollary 6 in ' dim = 3 case of [NW11, Corollary 6]), the vanishing of CH('
- p.3 theorem 1.3 in '–Sabloﬀ–Traynor [BST15, Theorem 1.3] constructed Lagrangian'
- p.3 proposition 3.2 in 'it follows from [EES05, Proposition 3.2] that for any Legendria'
- p.3 corollary 4.5 in 'Ganatra–Lazarev [EGL20, Corollary 4.5]. In particular, by [EG'
- p.3 theorem 4.7 in ' particular, by [EGL20, Theorem 4.7], when n = 2, the ﬁllin'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.8, Symplectic cohomology, wrapped Floer cohomology, and contact)
- miss `what is section 5 about` → p.None (heading on p.30, Proof of the main results)
- miss `what is section 3.3 about` → p.None (heading on p.14, Structures on symplectic cohomology and wrapped Floer cohomo)

### 2610.14417 — A Nullstellensatz for the field of complex Laurent series

math.LO, 19 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (34). Role: random.
Shared counters: Lemma 4.2 then Theorem 4.3; Lemma 5.2 then Theorem 5.3; Theorem 5.3 then Lemma 5.4; Lemma 5.4 then Proposition 5.5; Proposition 5.5 then Corollary 5.6; Proposition 6.3 then Lemma 6.4.
HTML declaration strings found in the PDF: 38/38 named, 1/1 equations.
Main resolves 95% (55/58); misses 3, extraction gaps 0, wrong links 0, citation emissions 12 (0 of them indexed), false declarations 4. Index built in 0.03s plus 0.47s extraction. A model pass would send about 27693 input tokens across 17 pages.
Main fails: 12 citation spans emitted as local refs; 4 indexed statements are not in the HTML declarations; section questions are not implemented.
Hover+chat fails: 4 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 3.2` served: True. Short query `Lemma 3` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.16 'Theorem 8.3': not in the statement index
- p.17 'Theorem 8.3': not in the statement index
- p.18 'Theorem 8.3': not in the statement index
Citation:
- p.4 proposition 2.8.2 in 'omponents; see e.g. [3, Proposition 2.8.2] where the result is st'
- p.7 proposition 2.8.2 in 'rary field; compare [3, Proposition 2.8.2]. Only (3) uses model c'
- p.8 theorem 9.1 in ' a ∈Lp [11, Chapter VI, Theorem 9.1], and a = cp would give'
- p.8 remark 3.2.17 in 's such an extension [7, Remark 3.2.17]. The quotient Γw′/Γw i'
- p.8 theorem 3.3.4 in 'damental inequality [7, Theorem 3.3.4], p · [kw′ : kw] = [Γw′'
- p.8 theorem 5.2.2 in 'y its henselization [7, Theorem 5.2.2], which is an algebraic'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 5 about` → p.None (heading on p.7, Formally T T -adic fields)
- miss `what is section 9 about` → p.None (heading on p.18, Open questions)
- ok `what is section 2.2 about` → p.4 (heading on p.4, Radicals and zero sets)

### 2610.16227 — Contractivity of Rudin's diagonal restriction operator for $H^p$ of the polydisc

math.CA, 16 pages, 0 two-column pages, class `amsart`, citations numeric (22). Role: random.
Shared counters: Theorem 1.1 then Lemma 1.2; Lemma 2.1 then Theorem 2.2; Theorem 2.2 then Lemma 2.3; Theorem 3.2 then Lemma 3.3.
HTML declaration strings found in the PDF: 15/15 named, 14/14 equations.
Main resolves 90% (114/127); misses 11, extraction gaps 1, wrong links 1, citation emissions 21 (1 of them indexed), false declarations 0. Index built in 0.01s plus 0.21s extraction. A model pass would send about 16309 input tokens across 12 pages.
Main fails: resolution 89.8% is under 90%; 1 wrong link; 21 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: 1 wrong link; a section question missed its heading page.
Number search `Lemma 1.2` served: True. Short query `Lemma 1` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.6 '(2.2)': not in the statement index
- p.8 '(3.1)': not in the statement index
- p.3 'Lemmas 1.2': detector missed it
- p.7 'Lemmas 1.2': detector missed it
- p.3 'Section 2' did not locate section 2
- p.3 'Section 3' did not locate section 3
Wrong:
- p.12 'Theorem 1.1' sits inside a citation
Citation:
- p.1 exercise 3.4.4 in 'ially due to Rudin [20, Exercise 3.4.4(e)], although in this c'
- p.2 lemma 21 in 'when 0 < p < 2 (see [2, Lemma 21]). Let us discuss the m'
- p.4 proposition 2.2 in 'chter and Sundberg [19, Proposition 2.2] (see also [10, Section'
- p.4 exercise 6 in 'ars in [11, Chapter VI, Exercise 6]. For the convenience o'
- p.5 exercise 3.4.4 in 'Theorem 2.2 (Rudin [20, Exercise 3.4.4(e)]). We have ∥Df∥A2(D)'
- p.11 theorem 1 in ' ≤p ≤4 and n ≤4 in [14, Theorem 1]. Note that for p ≥6.8,'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.7, Extension to the polydisc)
- miss `what is section 4 about` → p.None (heading on p.11, Applications)
- ok `what is section 4.2 about` → p.12 (heading on p.12, Khinchin’s inequality for Steinhaus variables)

### 2610.19307 — Zero-cycles and Brauer groups on certain Enriques surfaces

math.NT, 27 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (49). Role: random.
Shared counters: Proposition 2.10 then Lemma 2.11; Lemma 2.11 then Theorem 2.12; Theorem 3.2 then Proposition 3.3; Lemma 3.7 then Theorem 3.8; Theorem 4.6 then Lemma 4.7; Lemma 4.8 then Corollary 4.9.
HTML declaration strings found in the PDF: 31/31 named, 0/0 equations.
Main resolves 85% (40/47); misses 6, extraction gaps 0, wrong links 1, citation emissions 16 (4 of them indexed), false declarations 0. Index built in 0.03s plus 0.40s extraction. A model pass would send about 20456 input tokens across 14 pages.
Main fails: resolution 85.1% is under 90%; 1 wrong link; 16 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: 1 wrong link; 16 citation spans emitted as local refs; a section question missed its heading page.
Number search `Lemma 2.7` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 'Section 2.3' did not locate section 2.3
- p.7 'Section 2.3' did not locate section 2.3
- p.2 'Section 4.2' did not locate section 4.2
- p.3 'Section 5' did not locate section 5
- p.4 'section\n5' did not locate section 5
- p.4 'Section 5' did not locate section 5
Wrong:
- p.20 'Lemma 3.7' sits inside a citation
Citation:
- p.5 proposition 6.3 in 'roposition 2.1. [CTC79, Proposition 6.3] Let Y →Z be a biration'
- p.5 example 1.3 in ' surface over k [Huy16, Example 1.3 (iii)]. In particular, '
- p.5 proposition 1.3.3 in 'the argument of [CDL25, Proposition 1.3.3]. □ 5 '
- p.8 theorem 1 in 'is 8-torsion by [Gaz25, Theorem 1]. Also the birational m'
- p.10 proposition 3.1 in ']×E2[2], E1, E2 [Shi06, Proposition 3.1]. Let L = m1E1 + m2E2 +'
- p.11 equation 3.3 in 'change to k. By [Bea09, (3.3) in Section 3], Br(SC) ∼'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.8, Brauer Groups of K3 and Enriques Surfaces)
- miss `what is section 5 about` → p.None (heading on p.24, Example and Application to Weak Approximation)
- ok `what is section 2.4 about` → p.7 (heading on p.7, Upper Bounds on Chow Groups of Enriques Surfaces)

### 2610.18580 — A two-level preconditioner for discontinuous virtual element methods with irregular subdomains

math.NA, 29 pages, 0 two-column pages, class `siamart251216`, citations numeric+qualified (25). Role: random.
HTML declaration strings found in the PDF: 0/18 named, 1/33 equations. Named statement numbers in the HTML do not match the PDF, so this resolution rate is not a fair Cauchy score.
Main resolves 0% (0/79); misses 2, extraction gaps 77, wrong links 0, citation emissions 5 (2 of them indexed), false declarations 51. Index built in 0.03s plus 0.82s extraction. A model pass would send about 27773 input tokens across 21 pages.
Main fails: resolution 0.0% is under 90%; 5 citation spans emitted as local refs; 51 indexed statements are not in the HTML declarations; section questions are not implemented.
Hover+chat fails: resolution 0.0% is under 90%; 51 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 4` served: False. Short query `None` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.14 '(1)': not in the statement index
- p.21 '(1)': not in the statement index
Citation:
- p.8 theorem 6.2 in 'ces can be found in [6, Theorem 6.2]. For s > 3/2, deﬁne th'
- p.12 lemma 2.2 in ' generalization of [14, Lemma 2.2]: Lemma 5.1. Let α = [α'
- p.17 lemma 5.2 in 'mma 5.6. Lemma 5.8 ([7, Lemma 5.2]). Let v ∈Vh ∩H1 0(Ω) h'
- p.17 lemma 5.7 in ' and hi. Lemma 5.9 ([7, Lemma 5.7]). Let χ ∈Vh ∩H1 0(Ω) a'
- p.19 theorem 4.1 in 'ment as in [7, proof of Theorem 4.1]. By the deﬁnition of R'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 4 about` → p.None (heading on p.10, Two level overlapping Schwarz methods)
- miss `what is section 7 about` → p.None (heading on p.None, Conclusions and final remarks)
- miss `what is section 4.2 about` → p.None (heading on p.10, Continuous reduced coarse space)

### 2610.13792 — The generator problem for C*-algebras with comparison

math.OA, 41 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (68). Role: random.
Shared counters: Lemma 2.8 then Corollary 2.9; Theorem 2.11 then Proposition 2.12; Proposition 3.4 then Lemma 3.5; Lemma 3.5 then Theorem 3.6; Lemma 4.7 then Theorem 4.8; Theorem 4.8 then Lemma 4.9.
HTML declaration strings found in the PDF: 39/39 named, 146/146 equations.
Main resolves 74% (84/113); misses 8, extraction gaps 19, wrong links 2, citation emissions 36 (6 of them indexed), false declarations 0. Index built in 0.04s plus 0.48s extraction. A model pass would send about 44349 input tokens across 33 pages.
Main fails: resolution 74.3% is under 90%; 2 wrong links; 36 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: resolution 76.1% is under 90%; 2 wrong links; a section question missed its heading page.
Number search `Lemma 2.3` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 'Definitions 2.5': detector missed it
- p.4 'Definitions 2.5': detector missed it
- p.28 '(4.39)': not in the statement index
- p.9 '§3' did not locate section 3
- p.5 '§4' did not locate section 4
- p.7 '§4' did not locate section 4
Wrong:
- p.37 'Lemma 2.4' sits inside a citation
- p.10 'Theorem 3.6' sits inside a citation
Citation:
- p.3 theorem 3.8 in 'd Winter proved in [46, Theorem 3.8] that every uni- tal, s'
- p.3 theorem 3.5 in ' singly generated ([46, Theorem 3.5]). An unpublished resul'
- p.3 theorem 2.4 in 'gly generated (see [46, Theorem 2.4]), [44] shows that sepa'
- p.4 corollary 5.16 in 'single generation ([42, Corollary 5.16]). In order to apply th'
- p.6 proposition 11.1.15 in 'ion 4.7] (see also [43, Proposition 11.1.15]), αa is characterized '
- p.7 proposition 1.6 in '. For a proof, see [25, Proposition 1.6] and [1, Lemma 12.1.2].'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 3 about` → p.None (heading on p.10, Tracially AF algebras)
- miss `what is section 4 about` → p.None (heading on p.20, C ∗ C^{*} -algebras with a Cantor spectrum subalgebra)
- ok `what is section 3.1 about` → p.10 (heading on p.10, Properties of tracially AF algebras)

### 2610.19840 — GPU-Accelerated Preprocessing for Large-Scale Linear Programming

math.OC, 22 pages, 0 two-column pages, class `article`, citations numeric (36). Role: random.
HTML declaration strings found in the PDF: 9/9 named, 13/13 equations.
Main resolves 84% (103/122); misses 14, extraction gaps 5, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.24s extraction. A model pass would send about 17474 input tokens across 12 pages.
Main fails: resolution 84.4% is under 90%; section questions are not implemented.
Hover+chat fails: resolution 84.4% is under 90%; a section question missed its heading page.
Number search `Theorem 1` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.3 'Section 2' did not locate section 2
- p.3 'Section 3' did not locate section 3
- p.5 'Section 3.2' did not locate section 3.2
- p.5 'Section 3.3' did not locate section 3.3
- p.8 'Section 3.3.1' did not locate section 3.3.1
- p.8 'Section 3.3.2' did not locate section 3.3.2
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.None, Introduction)
- miss `what is section 3 about` → p.None (heading on p.3, GPU-Preprocessor)
- miss `what is section 5 about` → p.None (heading on p.None, Conclusion)
- miss `what is section 4.1 about` → p.10 (heading on p.None, Experimental Setup)

### 2610.21864 — Localisation of the monkey walk with an "impurity" at the origin

math.PR, 40 pages, 0 two-column pages, class `article`, citations qualified (26). Role: random.
Shared counters: Lemma 3.6 then Theorem 3.7; Theorem 3.7 then Lemma 3.8; Proposition 4.1 then Lemma 4.2; Lemma 4.4 then Theorem 4.5; Theorem 4.5 then Lemma 4.6; Lemma 4.11 then Proposition 4.12.
HTML declaration strings found in the PDF: 31/31 named, 62/62 equations.
Main resolves 94% (181/192); misses 7, extraction gaps 4, wrong links 0, citation emissions 1 (0 of them indexed), false declarations 4. Index built in 0.06s plus 0.75s extraction. A model pass would send about 52248 input tokens across 36 pages.
Main fails: 1 citation span emitted as a local ref; 4 indexed statements are not in the HTML declarations; section questions are not implemented.
Hover+chat fails: 1 citation span emitted as a local ref; 4 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 3.1` served: True. Short query `Lemma 3` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.22 'Lemmas 3.8': detector missed it
- p.27 'Lemmas 3.8': detector missed it
- p.35 'Lemmas 3.8': detector missed it
- p.3 'Section 2' did not locate section 2
- p.18 'Section 2' did not locate section 2
- p.33 'Section 2.1' did not locate section 2.1
Citation:
- p.10 theorem 3.5 in ' is a version of [CV23, Theorem 3.5] that is sufficient for'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.None, Introduction)
- miss `what is section 3 about` → p.None (heading on p.None, Our MVPP satisfies “most of” (A1-3))
- miss `what is section 4 about` → p.None (heading on p.None, Proof of Theorem 1.1)
- miss `what is section 3.1 about` → p.6 (heading on p.None, Assumption (A1))

### 2610.15448 — The First Modular Zhu Algebra of $L(\frac12,0)_F$ in Characteristic Seven

math.QA, 17 pages, 0 two-column pages, class `article`, citations numeric (12). Role: random.
Shared counters: Theorem 2.2 then Lemma 2.3; Theorem 3.1 then Lemma 3.2; Lemma 3.8 then Theorem 3.9; Theorem 3.9 then Lemma 3.10; Lemma 3.10 then Proposition 3.11; Proposition 3.12 then Theorem 3.13.
HTML declaration strings found in the PDF: 16/16 named, 4/4 equations.
Main resolves 98% (79/81); misses 2, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.33s extraction. A model pass would send about 18592 input tokens across 12 pages.
Main fails: section questions are not implemented.
Hover+chat fails: a section question missed its heading page.
Number search `Lemma 2.3` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.2 'Section 2' did not locate section 2
- p.2 'Section 3' did not locate section 3
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.None, Introduction)
- miss `what is section 2 about` → p.2 (heading on p.None, Preliminaries)
- miss `what is section 3 about` → p.None (heading on p.None, Proof of the main result)
- miss `what is section 3.1 about` → p.4 (heading on p.None, Low homogeneous subspaces and PBW straightening)

### 2610.14991 — Affine realization of tilted Richardson varieties

math.RT, 30 pages, 0 two-column pages, class `amsart`, citations numeric+qualified (53). Role: random.
Shared counters: Theorem 2.1 then Proposition 2.2; Lemma 3.2 then Theorem 3.3; Theorem 3.5 then Lemma 3.6; Lemma 3.6 then Proposition 3.7; Proposition 3.7 then Theorem 3.8; Theorem 5.3 then Proposition 5.4.
HTML declaration strings found in the PDF: 48/48 named, 22/22 equations.
Main resolves 82% (106/130); misses 10, extraction gaps 5, wrong links 9, citation emissions 27 (8 of them indexed), false declarations 4. Index built in 0.03s plus 0.35s extraction. A model pass would send about 34278 input tokens across 25 pages.
Main fails: resolution 81.5% is under 90%; 9 wrong links; 27 citation spans emitted as local refs; 4 indexed statements are not in the HTML declarations; section questions are not implemented.
Hover+chat fails: resolution 80.8% is under 90%; 9 wrong links; 4 indexed statements are not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 1.2` served: True. Short query `Lemma 1` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.4 'Section 1' did not locate section 1
- p.5 '§1.2' did not locate section 1.2
- p.4 'Section 2' did not locate section 2
- p.12 '§2.1' did not locate section 2.1
- p.2 'Section 3' did not locate section 3
- p.4 'Section 3' did not locate section 3
Wrong:
- p.27 'Lemma 3.6' sits inside a citation
- p.26 '§2' sits inside a citation
- p.12 'Section 4' sits inside a citation
- p.8 '§6' sits inside a citation
- p.27 'Theorem 2.1' sits inside a citation
- p.11 'Theorem 4.8' sits inside a citation
Citation:
- p.6 theorem 3.2 in '⩽x⩽y⩽v ˚ Bx,y (cf. [23, Theorem 3.2]). 1.3. Quantum Bruhat '
- p.7 lemma 1 in 'e due to Postnikov [22, Lemma 1] and Mili´cevi´c–Viehma'
- p.9 proposition 4.4 in '2.2) Lam–Shimozono [15, Proposition 4.4] proved a correspondenc'
- p.9 theorem 4.2 in 'wing deeper result [26, Theorem 4.2] (with a different conv'
- p.11 theorem 4.8 in '- tially proved in [15, Theorem 4.8] (with a complicated ch'
- p.11 theorem 4.8 in 'y anti-dominant in [15, Theorem 4.8] corresponds to the pre'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.5, Preliminaries)
- miss `what is section 4 about` → p.None (heading on p.17, Tilted R R -polynomials)
- miss `what is section 6 about` → p.None (heading on p.26, Fundamental classes and quantum cohomology)
- miss `what is section 2.2 about` → p.None (heading on p.10, Affine realizations of tilted Bruhat intervals)

### 2610.11661 — BiHom-Poisson conformal superalgebras arising from related algebraic structures

math.RA, 25 pages, 0 two-column pages, class `amsart`, citations numeric (10). Role: random.
Shared counters: Theorem 2.7 then Proposition 2.8; Proposition 2.17 then Theorem 2.18; Theorem 2.18 then Proposition 2.19; Proposition 2.19 then Theorem 2.20; Proposition 2.22 then Theorem 2.23; Theorem 2.28 then Proposition 2.29.
HTML declaration strings found in the PDF: 67/67 named, 61/61 equations.
Main resolves 100% (44/44); misses 0, extraction gaps 0, wrong links 0, citation emissions 0 (0 of them indexed), false declarations 0. Index built in 0.02s plus 0.42s extraction. A model pass would send about 29710 input tokens across 22 pages.
Main fails: section questions are not implemented.
Hover+chat fails: a section question missed its heading page.
Number search `Lemma 3.26` served: True. Short query `Lemma 3` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 2 about` → p.None (heading on p.2, Preliminaries and some results)
- miss `what is section 3 about` → p.None (heading on p.14, Construction theorems)
- miss `what is section 3.1 about` → p.None (heading on p.15, From BiHom-associative conformal superalgebras)

### 2609.00233 — A survey on mapping class groups of 3-manifolds

math.GT, 82 pages, 0 two-column pages, class `amsart`, citations qualified (213). Role: survey-60-pages.
The random sample has no paper of 60 or more pages. This 82-page survey is kept as that edge case and is not one of the 20.
Shared counters: Theorem 3.2 then Proposition 3.3; Proposition 3.4 then Lemma 3.5; Theorem 4.2 then Proposition 4.3; Proposition 4.3 then Lemma 4.4; Lemma 4.4 then Proposition 4.5; Proposition 4.5 then Theorem 4.6.
HTML declaration strings found in the PDF: 151/151 named, 11/11 equations.
Main resolves 84% (203/241); misses 26, extraction gaps 0, wrong links 12, citation emissions 34 (1 of them indexed), false declarations 1. Index built in 0.14s plus 1.14s extraction. A model pass would send about 99969 input tokens across 66 pages.
Main fails: resolution 84.2% is under 90%; 12 wrong links; 34 citation spans emitted as local refs; 1 indexed statement is not in the HTML declarations; section questions are not implemented.
Hover+chat fails: resolution 84.2% is under 90%; 12 wrong links; 63 citation spans emitted as local refs; 1 indexed statement is not in the HTML declarations; a section question missed its heading page.
Number search `Lemma 2.4` served: True. Short query `Lemma 2` serves the full number: False. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.63 '(10.11)': not in the statement index
- p.64 '(10.11)': not in the statement index
- p.7 'Section 2' did not locate section 2
- p.11 'Sections 2' did not locate section 2
- p.45 'Sections 2' did not locate section 2
- p.3 'Section 3' did not locate section 3
Wrong:
- p.34 'Section 2' sits inside a citation
- p.42 'Section 2' sits inside a citation
- p.63 'Section 2' sits inside a citation
- p.75 'Section 2' sits inside a citation
- p.69 'Section 3' sits inside a citation
- p.44 'Sec. 4' sits inside a citation
Citation:
- p.3 theorem 2.1.2 in ' an isomorphism [AFW15, Theorem 2.1.2]. '
- p.4 proposition 2.1 in ' in Hatcher–Wahl [HW10, Proposition 2.1], but relies on the wor'
- p.6 corollary 5.21 in '1(a)]; see also [BBS24, Corollary 5.21]. Combining this with P'
- p.22 theorem 2.5 in 'S1 × S1 see e.g. [FM12, Theorem 2.5]). Using this interpret'
- p.26 theorem 2.8 in 'r–Liokumovich in [KL23, Theorem 2.8]. 5. Mapping class grou'
- p.28 theorem 2.10 in 'l group G (e.g. [Sak90, Theorem 2.10]). Note that this is no'
Section questions (hover+chat):
- miss `what is section 1 about` → p.None (heading on p.1, Introduction)
- miss `what is section 7 about` → p.None (heading on p.36, Mapping class groups of hyperbolic 3-manifolds)
- miss `what is section 12 about` → p.None (heading on p.73, Further topics)
- miss `what is section 6.2 about` → p.None (heading on p.33, Statement of the main theorems on Haken 3-manifolds)

### 2610.22308 — Classical Capacity of Single-Mode Bosonic Gaussian Channels

quant-ph, 24 pages, 24 two-column pages, class `revtex4-2`, citations numeric+qualified (57). Role: two-column.
No random math.* paper has a two-column page. This revtex4-2 reprint PDF is two-column on every page. Its primary category is quant-ph, with math-ph secondary, because recent math.* submissions are single-column. It is not one of the 20.
HTML declaration strings found in the PDF: 18/18 named, 33/146 equations. Most HTML equation numbers are not printed in the PDF, so equation mentions inflate the miss count.
Main resolves 55% (104/190); misses 7, extraction gaps 72, wrong links 7, citation emissions 13 (9 of them indexed), false declarations 0. Index built in 0.04s plus 0.49s extraction. A model pass would send about 36801 input tokens across 18 pages.
Main fails: resolution 54.7% is under 90%; 7 wrong links; 13 citation spans emitted as local refs; section questions are not implemented.
Hover+chat fails: resolution 53.2% is under 90%; 7 wrong links; a section question missed its heading page.
Number search `Lemma 9` served: True. Short query `None` serves the full number: True. `Lemma 4` hits lemma 4: False. Printed name served: False (None).
Missed:
- p.5 '(20)': not in the statement index
- p.3 '(31)': not in the statement index
- p.3 '(43)': not in the statement index
- p.3 '(46)': not in the statement index
- p.2 'Section V' did not locate section V
Wrong:
- p.3 'Eq. (11)' sits inside a citation
- p.3 'Eq. (14)' sits inside a citation
- p.3 'Eq. (28)' sits inside a citation
- p.3 '(62)' sits inside a citation
- p.1 'Theorem 1' sits inside a citation
- p.9 'Theorem 1' sits inside a citation
Citation:
- p.1 theorem 1 in 'duced by Adesso in [22, Theorem 1]. Here we resolve the o'
- p.1 theorem 2 in 'ion 3 of that work [22, Theorem 2]. In particular, we sol'
- p.3 equation 14 in 'in [14, Sec. III, after Eq. (14)]. For the fixed average'
- p.3 equation 55 in 'lemental Material, Eqs. (55)–(62)]. A pure squeezed '
- p.3 equation 62 in 'tal Material, Eqs. (55)–(62)]. A pure squeezed vacuu'
- p.3 equation 11 in 'ian optimisa- tion [12, Eq. (11)], written here in terms'

## Proposed tickets

1. **Match “1. Introduction” when asked what section 1 is about** — AskStructureLocator treats a dotted number such as 9.2 as a section title, and does not treat a top-level heading “N. Title” as section N. Main has no locator, so the question fails there too. Size: small–medium. The locator already exists on the chat branch; section titles need the undotted leading-number match that chapter titles already use. Evidence: On the combined profile, dotted section questions land correctly 9/19 times and undotted ones 1/60 times. 20/20 papers still miss at least one probed section.
2. **Suppress author–year qualified citations, not only numeric ones** — Hover drops [12, Theorem 3.2], and still emits [IK99, Lemma 1.15] and [CV23, Theorem 3.5] as local references. New abbreviation and plural matches inside those cites can add detections. Size: small. The qualifier pattern should accept an author key or a year, not only a number before the comma. Evidence: Citation-span emissions on the comparable papers go from 291 on main to 125 on hover. Hover is higher on 2610.21303, 2610.19333; also 2609.00233 34→63 outside the 20.
3. **Do not index enumerated proof items (1) (2) (3) as equations** — A left-margin line that contains a math arrow passes declarationMatches, so the source-fallback index stores equation keys the paper never displays. Size: medium. The declaration filter needs a tighter check than “label near the left margin and the line looks like mathematics.” Evidence: 29 indexed keys on main are absent from the HTML declarations, after setting aside papers whose HTML numbers do not match the PDF.
4. **Resolve a shortened number, and plurals on main** — “Lemma 2” does not return Lemma 2.1, because lookup requires the full key. Main also misses plural surfaces such as “Lemmas 4.6” and “Definitions 2.5”; the hover branch detects some of those. Size: small. Evidence: Exact printed queries are served on 19/19 comparable papers. A shortened first component retrieves the full number on 0/17 papers. Literal “Lemma 4” hits a lemma numbered 4 on 0 papers. Plural misses include: 2610.11671 p.15 'Lemmas 4.6': detector missed it; 2610.16227 p.3 'Lemmas 1.2': detector missed it; 2610.13792 p.2 'Definitions 2.5': detector missed it; 2610.21864 p.22 'Lemmas 3.8': detector missed it.
5. **Store the printed statement name on the source-fallback index** — matchingTermsIn can search a name, and source-fallback entries leave name empty, so “the definition of compactness” cannot be served without the model. Size: small. Parse a parenthetical title into the fallback entry; the term route already exists. Evidence: 0/0 papers expose a parenthetical name in the HTML tag and serve it from the index. This corpus mostly does not print names inside the theorem tag, so the route is empty rather than wrong.
