#!/bin/bash
#SBATCH --job-name=lab_merge
#SBATCH --output=lab_merge_%j.log
#SBATCH --time=00:30:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --partition=preempt

# ============================================================
# Step 2: Merge NIfTI volumes + prepare bvals/bvecs/index/acqparams
# Shells: b1000 (20,30,45,60,90 dirs)
#         b2000 (20,30,45,60,90 dirs)
#         b3000 (20,30,45,60 dirs — no 90dir scan)
# ============================================================

echo "========================================"
echo "Step 2: Merge + Prepare"
echo "Job ID: ${SLURM_JOB_ID} | Start: $(date)"
echo "========================================"

module purge
module load fsl
export FSLOUTPUTTYPE=NIFTI_GZ

source /home/rkabir5/miniconda3/etc/profile.d/conda.sh
conda activate /scratch/rkabir5/mri_env

NIFTI_ROOT="/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026/nifti"
OUTPUT_DIR="/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026/preproc"
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

# ---- Input NIfTI files (raw DWI scans only — skip inline ADC/FA/ColFA/TRACEW) ----
B1000_NIIS=(
    "${NIFTI_ROOT}/scan_8/scan8_p2_s3_dti_1.5mmiso_A_P_b1000_20dir.nii.gz"
    "${NIFTI_ROOT}/scan_11/scan11_p2_s3_dti_1.5mmiso_A_P_b1000_30dir.nii.gz"
    "${NIFTI_ROOT}/scan_19/scan19_p2_s3_dti_1.5mmiso_A_P_b1000_45dir.nii.gz"
    "${NIFTI_ROOT}/scan_22/scan22_p2_s3_dti_1.5mmiso_A_P_b1000_60dir.nii.gz"
    "${NIFTI_ROOT}/scan_25/scan25_p2_s3_dti_1.5mmiso_A_P_b1000_90dir.nii.gz"
)
B2000_NIIS=(
    "${NIFTI_ROOT}/scan_9/scan9_p2_s3_dti_1.5mmiso_A_P_b2000_20dir.nii.gz"
    "${NIFTI_ROOT}/scan_12/scan12_p2_s3_dti_1.5mmiso_A_P_b2000_30dir.nii.gz"
    "${NIFTI_ROOT}/scan_20/scan20_p2_s3_dti_1.5mmiso_A_P_b2000_45dir.nii.gz"
    "${NIFTI_ROOT}/scan_23/scan23_p2_s3_dti_1.5mmiso_A_P_b2000_60dir.nii.gz"
    "${NIFTI_ROOT}/scan_26/scan26_p2_s3_dti_1.5mmiso_A_P_b2000_90dir.nii.gz"
)
B3000_NIIS=(
    "${NIFTI_ROOT}/scan_10/scan10_p2_s3_dti_1.5mmiso_A_P_b3000_20dir.nii.gz"
    "${NIFTI_ROOT}/scan_17/scan17_p2_s3_dti_1.5mmiso_A_P_b3000_30dir.nii.gz"
    "${NIFTI_ROOT}/scan_21/scan21_p2_s3_dti_1.5mmiso_A_P_b3000_45dir.nii.gz"
    "${NIFTI_ROOT}/scan_24/scan24_p2_s3_dti_1.5mmiso_A_P_b3000_60dir.nii.gz"
)
B1000_BVALS=( "${B1000_NIIS[@]//.nii.gz/.bval}" )
B1000_BVECS=( "${B1000_NIIS[@]//.nii.gz/.bvec}" )
B2000_BVALS=( "${B2000_NIIS[@]//.nii.gz/.bval}" )
B2000_BVECS=( "${B2000_NIIS[@]//.nii.gz/.bvec}" )
B3000_BVALS=( "${B3000_NIIS[@]//.nii.gz/.bval}" )
B3000_BVECS=( "${B3000_NIIS[@]//.nii.gz/.bvec}" )
PA_B0="${NIFTI_ROOT}/scan_7/scan7_p2_s3_dti_1.5mmiso_P_A_b0.nii.gz"

# ---- Verify all inputs ----
echo "Verifying input files..."
MISSING=0
for f in "${PA_B0}" \
         "${B1000_NIIS[@]}" "${B1000_BVALS[@]}" "${B1000_BVECS[@]}" \
         "${B2000_NIIS[@]}" "${B2000_BVALS[@]}" "${B2000_BVECS[@]}" \
         "${B3000_NIIS[@]}" "${B3000_BVALS[@]}" "${B3000_BVECS[@]}"; do
    [ ! -f "${f}" ] && echo "  MISSING: $(basename ${f})" && MISSING=$((MISSING+1))
done
[ "${MISSING}" -gt 0 ] && echo "ERROR: ${MISSING} missing file(s). Exiting." && exit 1
echo "  All input files present."

# ============================================================
# Merge NIfTI volumes: b1000, b2000, b3000 → combined DWI
# ============================================================
echo ""
echo "--- Merging NIfTI volumes ---"
fslmerge -t dwi_merged \
    "${B1000_NIIS[@]}" "${B2000_NIIS[@]}" "${B3000_NIIS[@]}"
N_VOLS=$(fslval dwi_merged dim4)
echo "  Total merged volumes: ${N_VOLS}  (b1000:265 + b2000:265 + b3000:171)"

# Fallback: count from bvals file in case fslval is unavailable
if [ -z "${N_VOLS}" ]; then
    echo "  Warning: fslval unavailable, counting from bvals file..."
    N_VOLS=$(python3 -c "import numpy as np; print(len(np.loadtxt('/tmp/all_bval_files.txt').split() and np.loadtxt('${OUTPUT_DIR}/bvals').flatten()))" 2>/dev/null || echo 701)
    echo "  N_VOLS (from bvals): ${N_VOLS}"
fi

# ============================================================
# Merge bvals/bvecs with Python (handles 3050→3000 rounding)
# ============================================================
echo ""
echo "--- Merging bvals/bvecs ---"

# Write file lists for Python
echo "${B1000_BVALS[*]} ${B2000_BVALS[*]} ${B3000_BVALS[*]}" > /tmp/all_bval_files.txt
echo "${B1000_BVECS[*]} ${B2000_BVECS[*]} ${B3000_BVECS[*]}" > /tmp/all_bvec_files.txt

python3 - <<'PYEOF'
import numpy as np, os

bval_files = open("/tmp/all_bval_files.txt").read().split()
bvec_files = open("/tmp/all_bvec_files.txt").read().split()
output_dir = "/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026/preproc"

def round_to_shell(b):
    """Round to nearest standard shell (handles scanner 3050 → 3000)."""
    if b < 50:   return 0
    elif b < 1500: return 1000
    elif b < 2500: return 2000
    else:          return 3000

all_bvals, all_bvecs = [], []
for bval_f, bvec_f in zip(bval_files, bvec_files):
    bvals = np.loadtxt(bval_f).flatten()
    bvecs = np.loadtxt(bvec_f)
    if bvecs.ndim == 1: bvecs = bvecs.reshape(3, -1)
    if bvecs.shape[0] != 3: bvecs = bvecs.T
    bvals_rounded = np.array([round_to_shell(b) for b in bvals])
    all_bvals.append(bvals_rounded)
    all_bvecs.append(bvecs)

merged_bvals = np.concatenate(all_bvals)
merged_bvecs = np.hstack(all_bvecs)

print(f"  Total volumes: {len(merged_bvals)}")
print(f"  Unique b-values: {sorted(set(merged_bvals))}")
print(f"  b0 count:   {int((merged_bvals == 0).sum())}")
print(f"  b1000 count:{int((merged_bvals == 1000).sum())}")
print(f"  b2000 count:{int((merged_bvals == 2000).sum())}")
print(f"  b3000 count:{int((merged_bvals == 3000).sum())}")

np.savetxt(os.path.join(output_dir, "bvals"), merged_bvals.reshape(1,-1), fmt='%g')
np.savetxt(os.path.join(output_dir, "bvecs"), merged_bvecs, fmt='%.6f')
print("  bvals and bvecs saved.")
PYEOF

# ============================================================
# Prepare TOPUP inputs: 4 AP b0s + 3 PA b0s = 7 volumes
# Lab standard (matching PreProcessDWI.sh):
#   - 2 AP b0s from b1000 scan (scan_8, vols 0-1)
#   - 2 AP b0s from b2000 scan (scan_9, vols 265-266, i.e. first 2 of that shell)
#   - 3 PA b0s from scan_7 (all 3 dedicated PA b0 volumes)
# Spreading AP b0s across shells captures any slow field drift between scans.
# ============================================================
echo ""
echo "--- Preparing TOPUP inputs ---"
# 2 b0s from b1000 (scan_8 = vols 0-1 of dwi_merged)
fslroi dwi_merged ap_b0_b1000 0 2
# 2 b0s from b2000 (scan_9 starts at vol 265 of dwi_merged)
fslroi dwi_merged ap_b0_b2000 265 2
# Merge: 2 AP-b1000 + 2 AP-b2000 + 3 PA = 7 volumes
fslmerge -t AP_PA_b0 ap_b0_b1000 ap_b0_b2000 "${PA_B0}"
echo "  AP_PA_b0 ready: $(fslval AP_PA_b0 dim4) volumes  (2 AP-b1000 + 2 AP-b2000 + 3 PA = 7)"

# acqparams: one row per volume in AP_PA_b0 (7 rows total)
# EPI factor=172, echo spacing=0.66ms → TotalReadoutTime=0.11352s
# 4 AP rows (phase-encode in -y: 0 -1 0) + 3 PA rows (phase-encode in +y: 0 1 0)
printf "0 -1 0 0.11352\n0 -1 0 0.11352\n0 -1 0 0.11352\n0 -1 0 0.11352\n0 1 0 0.11352\n0 1 0 0.11352\n0 1 0 0.11352\n" > acqparams.txt
echo "  acqparams.txt written (7 lines: 4 AP + 3 PA)"

# index: all volumes = 1 (AP)
# Use Python to safely read N_VOLS from saved bvals if shell variable is empty
python3 - <<IDXEOF
import numpy as np
bvals = np.loadtxt("${OUTPUT_DIR}/bvals").flatten()
n = len(bvals)
with open("${OUTPUT_DIR}/index.txt", "w") as f:
    f.write(" ".join(["1"]*n) + "\n")
print(f"  index.txt written ({n} entries)")
IDXEOF

echo ""
echo "========================================"
echo "Step 2 COMPLETE: $(date)"
echo "Output: ${OUTPUT_DIR}"
echo "Next:   sbatch step3_topup_bet.sh"
echo "========================================"
