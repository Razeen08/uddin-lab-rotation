#!/bin/bash
#SBATCH --job-name=analyze_lab
#SBATCH --output=analyze_lab_%j.log
#SBATCH --error=analyze_lab_%j.log
#SBATCH --time=0:20:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=2
#SBATCH --partition=preempt

# ============================================================
# Lab Subsampling Analysis — Difference Maps
# Purpose: Compute voxel-wise FA, MD, NDI, ODI, FWF difference
#          maps between max-dir reference and subsampled protocols
# Input:   results/Lab/dtifit/ and results/Lab/noddi/
# Output:  results/Lab/analysis/diff_maps/
# Runtime: ~5 minutes expected
# ============================================================

echo "========================================"
echo "Lab Difference Map Analysis"
echo "Job ID: ${SLURM_JOB_ID} | Start: $(date)"
echo "========================================"

# Load FSL (required for fslmaths and fslstats)
module purge
module load fsl
export FSLOUTPUTTYPE=NIFTI_GZ

source ~/.bashrc
conda activate /scratch/rkabir5/mri_env

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to activate conda environment"
    exit 1
fi

# Re-add FSL to PATH after conda activation (conda overwrites PATH)
export PATH="${FSLDIR}/bin:${PATH}"
echo "FSL bin: ${FSLDIR}/bin"
which fslmaths

export OMP_NUM_THREADS=2
export MKL_NUM_THREADS=2
export OPENBLAS_NUM_THREADS=2

SCRIPT_DIR="/scratch/rkabir5/StarterCodes_Data"
NOTEBOOK="${SCRIPT_DIR}/analyze_lab.ipynb"
SCRIPT="${SCRIPT_DIR}/analyze_lab.py"

echo "Converting notebook to script..."
jupyter nbconvert --to python "${NOTEBOOK}" --output "${SCRIPT_DIR}/analyze_lab"

if [ $? -ne 0 ]; then
    echo "ERROR: nbconvert failed"
    exit 1
fi

echo "Running analysis..."
python -u "${SCRIPT}"

EXIT_CODE=$?

echo "========================================"
echo "Job finished: $(date)"
echo "Exit code: ${EXIT_CODE}"
echo "========================================"

exit ${EXIT_CODE}
