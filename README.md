# uddin-lab-rotation

Code for a lab rotation project at the Uddin Lab, University of Rochester (April 2026).

## Project Overview

Evaluation of DWI gradient direction subsampling on DTI and NODDI microstructural metrics.  
The central question: **how few gradient directions are needed per b-value shell to reliably estimate FA, MD, NDI, ODI, and FWF?**

Two datasets are compared:
- **HCP** (subject 100408) — random subsampling from n=90 directions
- **Lab** (TEST03092026) — optimized angular coverage subsampling

---

## Repository Structure

```
├── preprocessing/
│   ├── step1_dicom_convert.sh       # DICOM → NIfTI (dcm2niix)
│   ├── step2_merge_prepare.sh       # Volume merge, bvals/bvecs, TOPUP prep
│   ├── step3_topup_bet.sh           # Susceptibility correction (FSL topup) + BET
│   ├── step4_eddy.sh                # Eddy current + motion correction (FSL eddy, GPU)
│   └── PreProcessDWI.sh             # Original unified preprocessing script
│
├── dtifit/
│   ├── run18_dtifit.sh              # HCP: FSL dtifit across 18 subsampled protocols
│   └── run14_dtifit_lab.sh          # Lab: FSL dtifit across 14 subsampled protocols
│
├── noddi/
│   ├── run_noddi_hcp.sh             # HCP: AMICO NODDI (subsampled)
│   ├── run_noddi_lab_subsampled.sh  # Lab: AMICO NODDI (subsampled)
│   ├── run_noddi_lab_full.sh        # Lab: AMICO NODDI (full acquisition)
│   ├── noddi_hcp_subsampled.ipynb   # NODDI fitting notebook — HCP
│   └── noddi_lab_subsampled.ipynb   # NODDI fitting notebook — Lab
│
├── analysis/
│   ├── analyze_hcp.ipynb            # HCP difference maps, MAE, subsampling SNR
│   ├── analyze_lab.ipynb            # Lab difference maps, MAE, subsampling SNR
│   ├── run_analyze_hcp.sh           # SLURM wrapper for HCP analysis
│   └── run_analyze_lab.sh           # SLURM wrapper for Lab analysis
│
├── visualization/
│   ├── plot_results.ipynb           # MAE/SNR summary figures (HCP vs Lab)
│   ├── view_maps.ipynb              # Orthoview PNG export for all NIfTI maps
│   └── visualize_bvecs_lab.ipynb    # 3D gradient direction plots (Lab)
│
└── subsampled_protocols/            # Protocol definition files (indices, bvals, bvecs)
    ├── indices_b{shell}_n{ndir}.txt # Volume indices selected per protocol
    ├── bvals_b{shell}_n{ndir}       # Corresponding bvals
    └── bvecs_b{shell}_n{ndir}       # Corresponding bvecs
```

---

## Datasets

| | HCP | Lab |
|---|---|---|
| Subject | 100408 | TEST03092026 |
| b-values | 1000, 2000, 3000 s/mm² | 1000, 2000, 3000 s/mm² |
| Max directions | 90/shell | 90 (b1000/b2000), 60 (b3000) |
| Protocols | 18 | 14 |
| Subsampling | Random | Optimized angular coverage |

---

## Pipeline Summary

1. **DICOM → NIfTI** — `dcm2niix`
2. **Merge + prepare** — `fslmerge`, Python (NumPy)
3. **Distortion correction** — FSL `topup`
4. **Brain extraction** — FSL `bet`
5. **Eddy + motion correction** — FSL `eddy_cuda` (H100 GPU)
6. **DTI fitting** — FSL `dtifit` → FA, MD
7. **NODDI fitting** — AMICO → NDI, ODI, FWF
8. **Analysis** — voxel-wise diff maps, MAE, subsampling SNR

---

## Requirements

- FSL 6.0.7+
- Python 3.10+: `numpy`, `nibabel`, `matplotlib`, `pandas`, `plotly`
- AMICO (for NODDI fitting)
- SLURM (for HCP cluster job submission)

---

## Author

Raiyun Kabir — University of Rochester, Uddin Lab, 2026
