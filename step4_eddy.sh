#!/bin/bash
#SBATCH --job-name=lab_eddy
#SBATCH --output=lab_eddy_%j.log
#SBATCH --time=08:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=8
#SBATCH --partition=h100
#SBATCH --gres=gpu:H100:1

# ============================================================
# Step 4: EDDY — eddy current + motion correction (GPU)
# 701 volumes, H100 GPU
# Expected runtime: ~2–3 hours on H100
# ============================================================

echo "========================================"
echo "Step 4: EDDY (eddy_cuda)"
echo "Job ID: ${SLURM_JOB_ID} | Node: ${SLURMD_NODENAME}"
echo "Start: $(date)"
echo "========================================"

module purge
module load fsl
export FSLOUTPUTTYPE=NIFTI_GZ

# Print GPU info
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "nvidia-smi not available"

OUTPUT_DIR="/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026/preproc"
cd "${OUTPUT_DIR}"

# Verify step 2 + 3 outputs exist
for f in dwi_merged.nii.gz hifi_nodif_brain_mask.nii.gz index.txt acqparams.txt bvals bvecs topup_AP_PA_b0_fieldcoef.nii.gz; do
    [ ! -f "${f}" ] && echo "ERROR: ${f} not found. Run previous steps first." && exit 1
done

N_VOLS=$(fslval dwi_merged dim4)
echo "Input DWI: ${N_VOLS} volumes"
echo ""
echo "--- Running eddy_cuda ---"
start=$(date +%s)

eddy_cuda11.0 \
    --imain=dwi_merged \
    --mask=hifi_nodif_brain_mask \
    --index=index.txt \
    --acqp=acqparams.txt \
    --bvecs=bvecs \
    --bvals=bvals \
    --fwhm=0 \
    --topup=topup_AP_PA_b0 \
    --flm=quadratic \
    --out=eddy_unwarped_images \
    --data_is_shelled \
    --verbose

EDDY_EXIT=$?
echo "EDDY done in $(( $(date +%s) - start )) seconds (exit code: ${EDDY_EXIT})"

[ "${EDDY_EXIT}" -ne 0 ] && echo "ERROR: eddy_cuda failed." && exit 1

# Quick check on output
N_EDDY=$(fslval eddy_unwarped_images dim4)
echo "Eddy output volumes: ${N_EDDY}"

echo ""
echo "========================================"
echo "Step 4 COMPLETE: $(date)"
echo "Next: sbatch step5_dtifit.sh"
echo "========================================"
