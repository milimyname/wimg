#!/usr/bin/env python3
"""Compare wimg embedding output against reference HuggingFace model.

Usage:
  python3 scripts/check-embeddings.py
  python3 scripts/check-embeddings.py "passage: My custom text" "query: my search"
"""
import sys
import numpy as np
from sentence_transformers import SentenceTransformer

model = SentenceTransformer("intfloat/multilingual-e5-small")

if len(sys.argv) > 1:
    texts = sys.argv[1:]
else:
    texts = [
        "passage: Netto Marken-Discount Netto Marken-Discount, Wuppertal",
        "passage: Manuel Alles",
        "passage: Klarna Bank AB Purchase at Zalando",
        "passage: BAECKEREI BORGGRAEFE G BAECKEREI BORGGRAEFE G, WUPPERTAL DE",
        "passage: WHAT A DOENER WHAT A DOENER, WUPPERTAL DE",
        "passage: Envivas Krankenversicherung AG ENVIVAS Krankenvers. AG",
        "passage: VIADUKT GMBH LOHN / GEHALT 12/25 MAKSUDOV KOMILJON",
        "query: essen",
        "query: arbeit",
        "query: lebensmittel",
        "query: versicherung",
        "query: gehalt",
        "query: kleidung",
    ]

embeddings = model.encode(texts, normalize_embeddings=True)

print("=== Embeddings (first 4 dims) ===")
for txt, emb in zip(texts, embeddings):
    print(f"  {txt[:60]:60s} [{emb[0]:.4f}, {emb[1]:.4f}, {emb[2]:.4f}, {emb[3]:.4f}]")

# Split into passages and queries
passages = [(t, e) for t, e in zip(texts, embeddings) if t.startswith("passage:")]
queries = [(t, e) for t, e in zip(texts, embeddings) if t.startswith("query:")]

if passages and queries:
    print("\n=== Cosine Similarities (query × passage) ===")
    for qt, qe in queries:
        print(f"\n  {qt}:")
        sims = [(pt, float(np.dot(qe, pe))) for pt, pe in passages]
        sims.sort(key=lambda x: -x[1])
        for pt, sim in sims:
            marker = " <<<" if sim == max(s for _, s in sims) else ""
            print(f"    {pt[:55]:55s} sim={sim:.4f}{marker}")
