#!/bin/bash
#SBATCH --job-name=lab_topup
#SBATCH --output=lab_topup_%j.log
#SBATCH --time=01:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --partition=preempt

# ============================================================
# Step 3: TOPUP (susceptibility distortion estimation) + BET
# Runtime: ~10–15 minutes
# ============================================================

echo "========================================"
echo "Step 3: TOPUP + BET"
echo "Job ID: ${SLURM_JOB_ID} | Start: $(date)"
echo "========================================"

module purge
module load fsl
export FSLOUTPUTTYPE=NIFTI_GZ

OUTPUT_DIR="/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026/preproc"
cd "${OUTPUT_DIR}"

# Verify step 2 outputs exist
for f in AP_PA_b0.nii.gz acqparams.txt; do
    [ ! -f "${f}" ] && echo "ERROR: ${f} not found. Run step2 first." && exit 1
done

# ============================================================
# TOPUP: estimate susceptibility-induced field
# ============================================================
echo ""
echo "--- Running TOPUP ---"

# Select config file based on image dimensions.
# b02b0.cnf (alias for b02b0_2.cnf) requires ALL dims to be multiples of 2.
# b02b0_4.cnf requires ALL dims to be multiples of 4.
# b02b0_1.cnf works for any dimensions (odd or even) but is slower.
dim1=$(fslval AP_PA_b0 dim1)
dim2=$(fslval AP_PA_b0 dim2)
dim3=$(fslval AP_PA_b0 dim3)
echo "  Image dimensions: ${dim1} x ${dim2} x ${dim3}"
if [ $(( dim1 % 4 )) -eq 0 ] && [ $(( dim2 % 4 )) -eq 0 ] && [ $(( dim3 % 4 )) -eq 0 ]; then
    TOPUP_CONFIG="b02b0_4.cnf"
    echo "  All dims divisible by 4 → using ${TOPUP_CONFIG} (fastest)"
elif [ $(( dim1 % 2 )) -eq 0 ] && [ $(( dim2 % 2 )) -eq 0 ] && [ $(( dim3 % 2 )) -eq 0 ]; then
    TOPUP_CONFIG="b02b0.cnf"
    echo "  All dims divisible by 2 → using ${TOPUP_CONFIG}"
else
    TOPUP_CONFIG="b02b0_1.cnf"
    echo "  Odd dimension detected → using ${TOPUP_CONFIG} (required for odd dims)"
fi

start=$(date +%s)

topup \
    --imain=AP_PA_b0 \
    --datain=acqparams.txt \
    --config=${TOPUP_CONFIG} \
    --out=topup_AP_PA_b0 \
    --iout=topup_AP_PA_b0_iout \
    --fout=topup_AP_PA_b0_fout \
    --verbose

echo "TOPUP done in $(( $(date +%s) - start )) seconds"

# ============================================================
# BET: brain extraction from TOPUP-corrected b0
# ============================================================
echo ""
echo "--- Running BET ---"
fslmaths topup_AP_PA_b0_iout -Tmean hifi_nodif
bet hifi_nodif hifi_nodif_brain -m -f 0.2
echo "  Brain mask: hifi_nodif_brain_mask.nii.gz"
N_BRAIN=$(fslstats hifi_nodif_brain_mask -V | awk '{print $1}')
echo "  Brain voxels: ${N_BRAIN}"

echo ""
echo "========================================"
echo "Step 3 COMPLETE: $(date)"
echo "Next: sbatch step4_eddy.sh"
echo "========================================"
