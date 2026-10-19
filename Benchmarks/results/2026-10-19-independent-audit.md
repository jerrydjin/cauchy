# Independent audit of the arXiv scorecard corrections

Audit date: 2026-10-19. Scope: the harness corrections in PR #9 (`cursor/arxiv-scorecard-9533`) and every grading change in `Benchmarks/arxiv_scorecard` after the first scorecard commit `68f3bb4`. No application code was changed. Nothing was merged.

The claimed headline is **11 of 20** random papers passing on the main profile. This audit re-derives that count from the papers themselves.

## How the flips were found

`scorecard.json` was compared at each commit from `68f3bb4` through `2b76db8`. A paper “flipped” when `profiles.main.passes` changed. PDFs and LaTeXML HTML were downloaded from arXiv on 2026-10-19. Page counts match the scorecard (12 to 54 pages). Quotes below are from the PDF text layer. “PDF page N” is the printed page. The scorecard’s example label `p.N` is that same page. Section-question `truth_page` values in the JSON are 0-based.

Headline by commit, before any judgment:

| Commit | What the harness changed | Main passes |
|---|---|---:|
| `68f3bb4` | First scorecard. Main runs with the section locator off. | 0/20 |
| `f6daddd` | “N. Title” / “N.N. Title.” and the locator turned on for main. | 1/20 |
| `ac3b928` | Bracket and author–year citations dropped from main. | 2/20 |
| `d8d4948` | Same-line bare integers no longer indexed as equations. | 2/20 |
| `07c3702` | Plurals, shortened numbers, parenthetical names. | 2/20 |
| `9fb753f` | Wrong-link test, heading page, math/prose headings, unnumbered bookmarks. | 9/20 |
| `2b76db8` | Line break inside a citation bracket; plural HTML tag; bold remark. | 11/20 |

## Verdicts

### 1. Section headings “N. Title” and “N.N. Title.”, and main uses the locator

Commit `f6daddd`. This is the change that takes the headline off zero.

**Before.** Main was scored with `use_structure=False`. Every numbered section question failed with “section questions are not implemented”, even when the references were otherwise perfect. The title matcher accepted only a dotted leading number (`9.2 Groups`) and rejected a line that ended in a period, so an amsart heading such as `3.1. Title.` was not a title line. `1. Introduction` did not answer section 1.

**After.** Main is scored with the locator on. `1. Introduction` answers section 1, and a line matching `N.N. Title.` may end in a period.

**Flipped.** One paper, `2610.11661` (fail → pass). Resolution was already 44/44. The only failed gate was the section question.

PDF page 1 prints the heading, and the locator now returns that page:

> 1. Introduction
> A Poisson algebra is both an associative algebra and a Lie algebra…

PDF page 2: `2. Preliminaries and some results`, then `2.1. Generalities.` PDF page 14: `3. Construction theorems`. PDF page 15: `3.1. From BiHom-associative conformal superalgebras.` The HTML titles are the same four sections (Introduction, Preliminaries and some results, Construction theorems, From BiHom-associative conformal superalgebras). The scorecard’s predicted pages are PDF pages 1, 2, 14, and 15.

**Verdict: CORRECT.** The old gate failed this paper because the locator was switched off and because `1. Introduction` was not recognised as section 1. Those headings are the paper’s sections, on the pages the new locator returns.

### 2. A bracket or author–year citation is not a local reference

Commit `ac3b928`. PR #9 states the same rule for `[12]`, `[IK99, Lemma 1.15]`, `(Smith 2019)`, and `Smith et al. [2019]`, and says an interval such as `[0, 1]` stays an interval.

**Before.** On main, `Theorem 3.2` inside `[12, Theorem 3.2]` was a local reference. Any such emission failed the paper, including when the number was not in this paper’s index.

**After.** Main drops a local hit that sits inside a numeric bracket, an alphanumeric key such as `[IK99, Lemma 1.15]` or `[BO09b, Lemma 3.3]`, or an author–year citation. `[0, 1]` is left alone because the text after the comma has no letter and no parenthesis.

**Flipped.** One paper, `2610.11671` (fail → pass). Resolution stayed 61/67. The failed gate was three citation emissions:

- PDF page 6: “from our earlier work [3, Proposition 3.3]” and “By [3, Proposition 3.3], this leads to a contradiction.” This paper’s own statement on that page is `Lemma 3.1. A has codimension 1 in V^2.` It does not contain a Proposition 3.3.
- PDF page 9: “By [7, Proposition 14.13]”. The outline stops at section 5. Proposition 14.13 is reference [7].

The author–year surfaces `(Smith 2019)` and `Smith et al. [2019]` occur 0 times in the 20 PDFs, so that half of the rule does not move this corpus. The brackets that did move `2610.11671` are bibliography citations.

**Verdict: CORRECT.** Linking `[7, Proposition 14.13]` to a local proposition would be the defect. The old harness treated the citation itself as a local reference.

### 3. A bare integer with text beside it is not an equation

Commit `d8d4948`.

**Before.** A bare `(1)` or `(2)` was indexed as an equation unless it sat in the middle of the text block (`0.20 < x < 0.70`) with words after it. A label at the left of the block was still an equation.

**After.** A bare integer with text to its right is an enumerated item whenever its x-position is missing or below 0.78. A dotted label such as `(1.10)`, a right-margin label (`x ≥ 0.78`), and a number on its own line stay equations.

**Flipped.** No paper. The false-declaration list shrank on five papers that were already failing for another reason: `2610.20976`, `2610.04096`, `2610.19333`, `2610.14417`, `2610.14991`.

The dropped labels are proof items, not display equations.

- `2610.20976`, PDF page 8, x ≈ 0.13: “(1) Fix all the parameters except β.” and “(2) Fix all parameters except L.” PDF page 11: “(3) Assume a = b = 0, 1 ≤ m ≤ 2, and 0 < γ ≤ 1.”
- `2610.04096`, PDF page 3, x ≈ 0.15: “(1) The homomorphism ι_λ is injective. (2) The elements λ_i ∈ k are linearly independent over F_p.” PDF page 17: “(1) If p > 2, then there exists a tensor functor…” PDF page 22: “(3) Every incompressible finitely generated tensor category…”
- `2610.19333`, PDF page 4, x ≈ 0.11: “(1) λ = −y dx on B²(1). (2) λ = ½(x dy − y dx) outside B²(2).” PDF page 32: “(1) the natural map π₁(∂W) → π₁(W) is injective, (2) c₁(W) = 0, and (3) ∂W is ADC.”
- `2610.14417`, PDF page 2, x ≈ 0.16: “(3) 1/t ∉ O_K[γ(L)]; (4) 1/t ∉ Λ_L.” PDF page 10: “(1) The t-Kochen operator is the rational map γ(x) = …”
- `2610.14991`, PDF page 2, x ≈ 0.15: “(3) If u ≤ v, it is isomorphic to the ordinary Richardson variety.” PDF page 7: “(1) Vertices: Elements of W₀. (2) Edges: …”

`2610.14417` still fails, and the remaining false declaration is real relative to this rule. On PDF page 13 the item is line-broken, so `(2)` has an empty suffix and is kept:

> (2)
> φ(O_K[γ(K(X))]) ⊆ O_K and φ(Λ_{K(X)}) ⊆ K;

That is still an enumerated clause of a lemma, and the HTML has no equation `(2)`. The new rule does not let this paper pass. PR #9 says so.

**Verdict: CORRECT.** The old index was filing left-margin proof steps as equations. The rule did not clear the one line-broken item that still fails `2610.14417`.

### 4. A plural label such as “Lemmas 4.6” is that lemma

Commit `07c3702`, the plural half.

**Before.** Main recognised only a singular keyword. `Lemmas 4.6`, `Definitions 2.5`, and `Theorems 1.1` were detector misses.

**After.** Main accepts one number after a plural (`Lemmas 4.6`) and a plural list (`Lemmas 3.1, 3.2 and 3.4`).

**Flipped.** No paper. Resolution rose where a printed plural had been a miss, and those papers were already passing or still failed a harder gate:

- `2610.11671`, PDF page 15: “As we can see from Lemmas 4.6 and 4.7, the possible degrees…” PDF page 13 declares `Lemma 4.6. For 1 ≤ k ≤ N − 2, we have α_k = α_{N−1−k}.`
- `2610.16227`, PDF page 3: “via Lemmas 1.2 and 3.4” and “the equality cases in Theorems 1.1 and 3.2.” Theorem 1.1 is the paper’s main theorem, printed on PDF page 1.
- `2610.13792`, PDF page 2: “see Definitions 2.5 & 2.6”.
- `2610.21864`, PDF page 22: “we can verify from Lemmas 3.8 and 3.9 that…”

**Verdict: CORRECT.** Each of those plurals names a statement this paper actually declares. The old detector missed the printed word.

### 5. “Lemma 2” returns every lemma numbered 2.x

Commit `07c3702`, the shortened-number half. `_number_extends` treats `2` as matching `2` and `2.1`, and the unit test requires `Lemma 4` to return both lemma 4 and lemma 4.1.

**Before.** Lookup required the full key. `Lemma 3` did not return Lemma 3.1.

**After.** A shortened probe returns every indexed statement whose number equals the query or continues it with a dot.

**Flipped.** No paper. `statements_cited_in` is used by the reported `number_search` probe. It is not an input to `passes`.

The probe is still a looser reading than the paper. On `2610.11671` the shortened query is `Lemma 3`, and the statement it now “serves” is the one printed on PDF page 6 as `Lemma 3.1. A has codimension 1 in V^2.` There is no Lemma 3. The same function returns lemma 4.1 for `Lemma 4`, while the scorecard’s own literal counter says a lemma numbered 4.1 is not lemma 4.

**Verdict: LOOSER.** It equates a statement with a different number. It does not hide a failure inside the 11/20 rule, because that rule never consults it.

### 6. A parenthetical on the declaration is stored as the name

Commit `07c3702`, the name half.

**Before.** A source-fallback entry stored no printed name.

**After.** `Lemma 2.4 (Zorn)` stores `Zorn`. A following parenthesis that starts with a letter becomes the name.

**Flipped.** No paper. The pass predicate does not read the name. The HTML theorem tags in this corpus do not carry it, so the name-query probe stays unanswered. The printed names the parser would store include a real one and a citation:

- `2610.21544`, PDF page 3: `Lemma 2.1 (Apolarity Lemma).` That is the lemma’s name.
- The same page: `Theorem 2.2 (BCMS26, Theorem 3.4).` The parenthesis cites another paper. The parser would store that citation as the theorem’s name.

**Verdict: CORRECT.** The old entries dropped a real printed name such as “Apolarity Lemma”, and this change does not turn a failing paper into a pass. The citation-shaped parenthesis is a side capture, and it is outside the pass gate.

### 7. A printed mention inside a bracket is a wrong link only when the detector would open an indexed statement

Commit `9fb753f`. PR #9 names this correction and says it is what lets `2610.16227` and `2610.19307` pass.

**Before.** If the PDF span of an in-scope HTML mention sat inside a `[...]` span, the grader counted a wrong link. It did not ask whether the detector would open anything there. After correction 2, main already emitted 0 citation detections on these papers, and the wrong-link gate still failed them.

**After.** The span is a wrong link only when a detector match covers it and that match is in the statement index. A suppressed citation is neither resolved nor missed.

**Flipped.** Three papers, all fail → pass. A fourth paper lost the same class of wrong link and needed the heading fix as well (`2610.21303`, under correction 9).

- `2610.16227`, PDF page 12: “A strict version of this estimate was established in [5, Theorem 1.1] by different techniques.” Later on the same page the paper cites its own result in prose: “tried (and failed) to establish Theorem 1.1”. The bracketed theorem is reference [5]. This paper’s Theorem 1.1 is declared on PDF page 1. The detector does not open it from `[5, Theorem 1.1]`.
- `2610.19307`, PDF page 20: `Lemma 4.1. [GL26, Lemma 3.7] Let f : Y → Z be a proper map…` The bracket is GL26’s Lemma 3.7. This paper’s own Lemma 3.7 is on PDF page 12: `Lemma 3.7. ([SZ09] Lemma 3.6)`.
- `2610.20306`. The seven wrong links are other papers’ sections: PDF page 2 “[6, Sec. 3]”, “[16, Sec. 6]”, “[51, Sec. 4]”; PDF page 3 “[30, Sec. 2]” and “[6, Sec. 3]”; PDF page 6 “[27, Sec. 3]”. Removing those seven non-links from the denominator takes resolution from 51/63 to 51/56, which is already over 90%, and the section questions were already on the right pages. The paper passes from this rule alone.

**Verdict: CORRECT.** The old gate called a citation a wrong link after the detector had already refused to open it. The brackets above name another paper’s statement.

### 8. The heading page is the outline entry whose title matches the HTML heading

Commit `9fb753f`, the ground-truth half. PR #9: “A numbered sentence is not that page.”

**Before.** The correct page was the first body line that started with the section number and contained the first words of the HTML title. A numbered sentence qualified.

**After.** The PDF outline entry whose title matches the HTML heading wins. The body scan is only the fallback, and it now requires a title-shaped line.

**Flipped.** `2610.19840` (fail → pass), together with correction 10. The other heading flips in this commit are corrections 9 and 10; this rule is the one that moves the correct page.

On `2610.19840` the old correct page for section 3 was PDF page 3, the sentence:

> 3. Numerical experiments on three LP benchmark sets show that GPU-Preprocessor achieves

The HTML heading is `3 GPU-Preprocessor`. The outline bookmark `GPU-Preprocessor` is PDF page 5, and the text layer there is a margin number on its own line, then the title:

> 3
> GPU-Preprocessor
> 3.1
> Overview of GPU-Preprocessor

Section 1 is the outline title `Introduction` on PDF page 1, matching HTML `1 Introduction`. Section 5 is `Conclusion` on PDF page 15. Section 4.1 is `Experimental Setup` on PDF page 10, the first subsection under `Numerical Experiments`. Those are the pages the scorecard now uses.

**Verdict: CORRECT.** The old rule took a contribution-list sentence that happens to start with “3.” and to mention GPU-Preprocessor for the section heading. The heading is on PDF page 5.

### 9. A math fragment or a prose sentence is not a section heading

Commit `9fb753f`, the locator half. A heading line must be title-shaped, and the text after the number must start with a capital letter. `1 + z`, `4 =`, and `Section 4 constructs the metric.` do not qualify. `Section 4` as a keyword no longer makes a sentence into a heading by itself.

**Flipped.** Four papers move because the locator stops landing on these lines. `2610.15448` and `2610.20976` also need correction 10. `2610.21303` also lost two citation wrong links (correction 7); its section questions were already aimed at the right truth pages and were missing because of the locator.

- `2610.15448`. The old locator answered section 1 with PDF page 11, `1 + z^7 holds in characteristic 7. Hence`. It answered section 2 with PDF page 2, a line break of the fraction `1/2 = 1/16 = 4` (`2 =`). It answered section 3 with PDF page 13, `3. Moreover,`. The printed headings are `Introduction` on PDF page 1, `Preliminaries` on PDF page 2, and `Proof of the main result` plus `Low homogeneous subspaces and PBW straightening` on PDF page 4. The HTML numbers those as sections 1, 2, 3, and 3.1. The new locator returns those pages.
- `2610.20976`. The old locator answered section 1 with PDF page 11, `1 nor C−` (a line break of “neither C⁺₁ nor C⁻₁”). It answered section 4 with PDF page 13, `4 1_{k=0} u_0 v_0`, which is display (2.3). It answered section 6 with PDF page 12, the sentence “In Section 6, we establish the threshold consistency in Proposition 1.2…”. The outline headings are `Introduction` on PDF page 2, `Extension of the local bifurcation branches and proof of Theorem 1.3` on PDF page 27, `Proof of Theorem 1.3(1)` on PDF page 30, and `Numerical analysis of the bifurcation and spike-like solutions` on PDF page 36. Those match the HTML section numbers 1, 4, 4.1, and 6. Resolution moves from 88.4% to 90.9% because section mentions now land on these pages, which is what crosses the 90% gate.
- `2610.21303`, PDF page 6, in the organisation paragraph: “Section 4 constructs the approximate metric and solves the nonlinear equation.” The old locator used that sentence (PDF page 6) as section 4, and used the table-of-contents line `4.2` on PDF page 2 as section 4.2. The heading is PDF page 21, `4 Approximate and exact solutions`, and section 4.2 is PDF page 24, `4.2 The linearized equation`. The scorecard’s truth page was already page 21 before this commit. The two wrong links cleared in the same commit are external: PDF page 33 `[Moc26, Section 4]` and PDF page 12 `[BL92, Chapter II, Section 5]`.

**Verdict: CORRECT.** The old locator was answering section questions with equations, wrapped fractions, and sentences that mention a section. The new pages are the printed headings.

### 10. An unnumbered bookmark is still section 1 when no sibling prints a number

Commit `9fb753f`. Bookmarks that read `Introduction` rather than `1. Introduction` are numbered in sibling order. Numbering is invented only when none of the siblings already print a number. `Abstract`, `References`, and `Acknowledgments` are skipped.

**Before.** An outline title without a leading number did not answer `what is section 1 about`.

**After.** The first unnumbered section bookmark is section 1, the next is section 2, and the first child of section 4 is section 4.1.

**Flipped.** The same papers as corrections 8 and 9 whose PDF outlines omit the printed numbers: `2610.19840`, `2610.15448`, `2610.20976`. On each of them the sibling order matches the HTML numbering, and the pages are the ones quoted above. On `2610.19840` the later bookmarks `Proof of Theorem 3` and `Proof of Theorem 4` are Appendix A and Appendix B in the HTML. They are not among the probed questions, and the HTML has no section 6 for them to steal.

**Verdict: CORRECT.** On these three papers the outline title is the HTML section, and the number is only a margin glyph or is absent from the bookmark. Inventing that number in outline order lands on the heading.

### 11. A citation bracket may contain the text layer’s line break

Commit `2b76db8`. PR #9: `[17, Theorem 3.31(c)]` is not this paper’s Theorem 3.31, and this is what lets `2610.18041` pass.

**Before.** The bracket pattern was `\[([^\[\]\n]{1,180})\]`. A line break ended the match, so the theorem number on the next line was indexed as a local declaration.

**After.** Newlines inside the bracket are allowed, then collapsed, and the same key test is applied.

**Flipped.** `2610.18041` (fail → pass). The only failed gate was one false declaration, `p.10 theorem 3.31`. Resolution stayed 215/225.

PDF page 10:

> the weak-holomorphy criterion [17,
> Theorem 3.31(c)] shows that G is L₂-analytic on S°.

The same citation is unbroken on PDF page 9: `[17, Theorem 3.31(c)]`. This paper has no Theorem 3.31 of its own. The only line that starts `Theorem 3.` is that citation. Reference [17]’s Theorem 3.31(c) was being indexed as a local theorem because of the line break.

The same regex newly covers real citations that used to be scored as misses, and those papers stay failures: `2610.19333` PDF pages 6 and 7, `[Zho23, Proposition 3.2 and proof of Theorem 1.1]` and `[CE20, Theorem 1.1]`; `2610.14991` PDF page 7, `[19, (4.3)]`. Resolution there goes down, not up.

**Verdict: CORRECT.** The indexed “Theorem 3.31” is reference [17], split by the text layer. The old rule was wrong about this paper.

### 12. The HTML list includes a plural theorem tag and a bold run-in remark

Commit `2b76db8`. PR #9: `Examples 6.7` and `Remark 3.13.` This is what lets `2610.21544` pass, and `2610.14417` still fails on equation `(2)`.

**Before.** Declaration tags had to be singular (`example`, `remark`) and had to be an `ltx_tag_theorem`. A bold run-in was ignored.

**After.** `Examples` maps to `example`. A `span.ltx_font_bold` whose entire text is the label, such as `Remark 3.13.`, is a declaration. A bold sentence that merely starts with `Theorem 1.1` is not.

**Flipped.** `2610.21544` (fail → pass). Resolution stayed 58/59. The only failed gate was `p.5 remark 3.13`.

The remark is in the HTML, and it is not a theorem tag:

```html
<span class="ltx_text ltx_font_bold">Remark 3.13.</span>
```

PDF page 5: `Remark 3.13. In Theorem 3.11 above, the hypothesis that V(f_0, …, f_{k−1}) ⊂ P^n is a reduced subscheme is necessary.` The PDF index was right. The HTML parser had skipped the label.

`2610.14417` does not flip. The HTML really does contain a plural tag:

```html
<span class="ltx_tag ltx_tag_theorem">Examples 6.7</span>
```

PDF page 12: `Examples 6.7. (1) L = K(X): by Corollary 5.6, L is formally T-adic…` Clearing that one false declaration leaves `p.13 equation 2`, the line-broken enumerated item from correction 3. The paper stays a failure, as PR #9 says.

**Verdict: CORRECT.** `Remark 3.13.` and `Examples 6.7` are declarations in the HTML. The old parser did not read them, so a true index entry was scored as a false declaration.

## Recount, using only the corrections marked CORRECT

The shortened-number rule (correction 5) is the only **LOOSER** correction. It is not an input to `passes`, and it flipped no paper. Leaving it out does not remove a pass and does not add one.

Every correction that flipped a paper is **CORRECT**. Applying them, and not the shortened-number expansion, leaves the main-profile passes at the commits above. The 11 papers, and the correction that first made each one pass:

| arXiv | First passed because of | Verdict of that correction |
|---|---|---|
| 2610.11661 | 1. “N. Title” locator | CORRECT |
| 2610.11671 | 2. Citation brackets dropped | CORRECT |
| 2610.20976 | 9 and 10. Heading locator, unnumbered outline | CORRECT |
| 2610.21303 | 7 and 9. Citation is not a wrong link; prose is not a heading | CORRECT |
| 2610.20306 | 7. Citation is not a wrong link | CORRECT |
| 2610.18041 | 11. Line break inside `[17, Theorem 3.31(c)]` | CORRECT |
| 2610.16227 | 7. `[5, Theorem 1.1]` is not a wrong link | CORRECT |
| 2610.19307 | 7. `[GL26, Lemma 3.7]` is not a wrong link | CORRECT |
| 2610.19840 | 8 and 10. Outline title, not the numbered sentence | CORRECT |
| 2610.15448 | 9 and 10. Math fragment rejected; unnumbered outline | CORRECT |
| 2610.21544 | 12. Bold `Remark 3.13.` counted in the HTML | CORRECT |

**Recount: 11/20. Claimed: 11/20.**

The nine that remain failures are unchanged by dropping the looser rule: `2610.21341`, `2610.04096`, `2610.21627`, `2610.19333`, `2610.14417`, `2610.18580`, `2610.13792`, `2610.21864`, `2610.14991`. `2610.14417` is the check on corrections 3 and 12: it is one false declaration away from a pass, and that declaration is still counted.
