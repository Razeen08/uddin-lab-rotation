#!/bin/bash
#SBATCH --job-name=dtifit_lab_14
#SBATCH --output=dtifit_lab_14_%j.log
#SBATCH --error=dtifit_lab_14_%j.log
#SBATCH --time=02:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --partition=standard

# ============================================================
# DTIfit on all 14 lab protocols (TEST03092026)
#
# 14 protocols = contiguous blocks in eddy_unwarped_images.nii.gz
#   b1000: 20, 30, 45, 60, 90 dirs
#   b2000: 20, 30, 45, 60, 90 dirs
#   b3000: 20, 30, 45, 60 dirs  (no 90dir acquired)
#
# Protocol format: "shell  ndir  start_vol  n_vols"
#   n_vols = 4 b0 interleavings + ndir DW volumes
#
# Uses eddy_rotated_bvecs (motion-corrected gradient directions)
# ============================================================

echo "========================================"
echo "DTIfit: Lab Data — All 14 Protocols"
echo "Job ID: ${SLURM_JOB_ID} | Start: $(date)"
echo "========================================"

module purge
module load fsl
export FSLOUTPUTTYPE=NIFTI_GZ

source /home/rkabir5/miniconda3/etc/profile.d/conda.sh
conda activate /scratch/rkabir5/mri_env

PREPROC_DIR="/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026/preproc"
BASE_OUTPUT_DIR="/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026/dti_lab_results"
TEMP_DIR="${PREPROC_DIR}/tmp_dtifit_${SLURM_JOB_ID}"

mkdir -p "${BASE_OUTPUT_DIR}"
mkdir -p "${TEMP_DIR}"

# ---- Verify inputs ----
echo "Verifying inputs..."
for f in eddy_unwarped_images.nii.gz \
          eddy_unwarped_images.eddy_rotated_bvecs \
          bvals \
          hifi_nodif_brain_mask.nii.gz; do
    [ ! -f "${PREPROC_DIR}/${f}" ] && echo "ERROR: ${f} not found in ${PREPROC_DIR}. Run step4 first." && exit 1
done
echo "  All inputs found."

# ----  Protocol definitions: "shell  ndir  start_vol  n_vols" ----
# n_vols = 4 b0 + ndir DW (each scan has 4 interspersed b0s)
PROTOCOLS=(
    "1000  20    0  24"
    "1000  30   24  34"
    "1000  45   58  49"
    "1000  60  107  64"
    "1000  90  171  94"
    "2000  20  265  24"
    "2000  30  289  34"
    "2000  45  323  49"
    "2000  60  372  64"
    "2000  90  436  94"
    "3000  20  530  24"
    "3000  30  554  34"
    "3000  45  588  49"
    "3000  60  637  64"
)

TOTAL=${#PROTOCOLS[@]}
SUCCESS=0
FAILED=0

echo ""
echo "Total protocols to process: ${TOTAL}"
echo ""

# ---- Loop through all 14 protocols ----
for i in "${!PROTOCOLS[@]}"; do
    PROTO_NUM=$(( i + 1 ))
    read -r SHELL NDIR START NVOLS <<< "${PROTOCOLS[$i]}"
    PROTOCOL_NAME="b${SHELL}_${NDIR}dir"

    echo "----------------------------------------"
    echo "Protocol ${PROTO_NUM}/${TOTAL}: ${PROTOCOL_NAME}"
    echo "  start_vol=${START}  n_vols=${NVOLS}"
    echo "----------------------------------------"

    OUTPUT_DIR="${BASE_OUTPUT_DIR}/${PROTOCOL_NAME}"
    mkdir -p "${OUTPUT_DIR}"

    # ---- Extract contiguous volume block ----
    echo "  Extracting volumes ${START} to $(( START + NVOLS - 1 ))..."
    fslroi "${PREPROC_DIR}/eddy_unwarped_images" \
           "${TEMP_DIR}/dwi_${PROTOCOL_NAME}" \
           ${START} ${NVOLS}

    if [ $? -ne 0 ]; then
        echo "  ERROR: fslroi failed for ${PROTOCOL_NAME}"
        FAILED=$(( FAILED + 1 ))
        continue
    fi

    # ---- Extract bvals + rotated bvecs via Python ----
    echo "  Extracting bvals and rotated bvecs (indices ${START}:$(( START + NVOLS )})..."
    python3 - <<PYEOF
import numpy as np, sys

preproc = "${PREPROC_DIR}"
tmp     = "${TEMP_DIR}"
start   = ${START}
nvols   = ${NVOLS}
name    = "${PROTOCOL_NAME}"

bvals = np.loadtxt(f"{preproc}/bvals").flatten()
bvecs = np.loadtxt(f"{preproc}/eddy_unwarped_images.eddy_rotated_bvecs")
if bvecs.shape[0] != len(bvals):
    bvecs = bvecs.T   # handle (3 x N) layout → (N x 3)

idx = list(range(start, start + nvols))
sub_bvals = bvals[idx]
sub_bvecs = bvecs[idx, :]   # (nvols x 3)

np.savetxt(f"{tmp}/bvals_{name}", sub_bvals.reshape(1, -1), fmt='%g')
np.savetxt(f"{tmp}/bvecs_{name}", sub_bvecs.T, fmt='%.6f')  # save as (3 x N)

n_b0 = int((sub_bvals < 50).sum())
n_dw = int((sub_bvals >= 50).sum())
print(f"  b0={n_b0}  DW={n_dw}  total={len(sub_bvals)}")
print(f"  Unique b-values: {sorted(set(sub_bvals))}")
PYEOF

    if [ $? -ne 0 ]; then
        echo "  ERROR: Python bvals/bvecs extraction failed for ${PROTOCOL_NAME}"
        FAILED=$(( FAILED + 1 ))
        continue
    fi

    # ---- Run DTIfit ----
    echo "  Running dtifit..."
    start_t=$(date +%s)

    dtifit \
        --data="${TEMP_DIR}/dwi_${PROTOCOL_NAME}" \
        --mask="${PREPROC_DIR}/hifi_nodif_brain_mask" \
        --bvecs="${TEMP_DIR}/bvecs_${PROTOCOL_NAME}" \
        --bvals="${TEMP_DIR}/bvals_${PROTOCOL_NAME}" \
        --out="${OUTPUT_DIR}/dti"

    DTIFIT_EXIT=$?
    elapsed=$(( $(date +%s) - start_t ))

    if [ ${DTIFIT_EXIT} -eq 0 ]; then
        echo "  SUCCESS: DTIfit done in ${elapsed}s"
        SUCCESS=$(( SUCCESS + 1 ))

        # Save protocol metadata
        cat > "${OUTPUT_DIR}/protocol_info.txt" <<EOF
Protocol:     ${PROTOCOL_NAME}
Shell:        b=${SHELL}
Directions:   ${NDIR}
Start vol:    ${START}
Total vols:   ${NVOLS}
b0 vols:      $(( NVOLS - NDIR ))
bvecs:        eddy_rotated_bvecs (motion-corrected)
Job ID:       ${SLURM_JOB_ID}
Completed:    $(date)
EOF
    else
        echo "  ERROR: DTIfit failed for ${PROTOCOL_NAME} (exit ${DTIFIT_EXIT})"
        FAILED=$(( FAILED + 1 ))
    fi

    # Clean up temp volumes for this protocol (keep bvals/bvecs for inspection)
    rm -f "${TEMP_DIR}/dwi_${PROTOCOL_NAME}.nii.gz"

    echo ""
done

# ---- Clean up all temp files ----
rm -rf "${TEMP_DIR}"

# ---- Summary ----
echo "========================================"
echo "All protocols processed."
echo "  Total:      ${TOTAL}"
echo "  Successful: ${SUCCESS}"
echo "  Failed:     ${FAILED}"
echo ""
echo "Results saved in: ${BASE_OUTPUT_DIR}"
echo ""
echo "Output structure:"
ls -1 "${BASE_OUTPUT_DIR}"
echo ""
echo "Key output per protocol:"
echo "  dti_FA.nii.gz  — Fractional Anisotropy"
echo "  dti_MD.nii.gz  — Mean Diffusivity"
echo "  dti_V1.nii.gz  — Principal diffusion direction"
echo ""
echo "run14_dtifit_lab COMPLETE: $(date)"
echo "========================================"
