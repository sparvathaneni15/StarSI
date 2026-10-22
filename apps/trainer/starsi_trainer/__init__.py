"""starsi-trainer: the data factory.

Pipeline (README.md → Training path):

  generate  →  judge  →  pairs  →  train
     │            │         │         │
  dialogues    scores   DPO pairs   adapter
  from serving  novelty +  preferred /  (QLoRA on ≤14B here;
  nodes         plausib.   rejected     27B runs on the Studio
                                        or a rented card)

Each stage is a CLI reading/writing data/<stage>/ so it can be re-run
independently and inspected between steps.
"""
