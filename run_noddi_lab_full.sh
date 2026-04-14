#!/bin/bash
#SBATCH --job-name=noddi_lab_full
#SBATCH --time=2:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=8
#SBATCH --partition=preempt
#SBATCH --output=noddi_lab_full_%j.log
#SBATCH --error=noddi_lab_full_%j.log

# ============================================================
# NODDI Fitting on Lab Data — SLURM Batch Script
# Protocol: b1000_90dir + b2000_90dir + b3000_60dir (252 vols)
# Expected runtime: ~30-45 minutes
# ============================================================

echo "========================================"
echo "NODDI Lab Full — Job Started"
echo "========================================"
echo "Job ID:        $SLURM_JOB_ID"
echo "Job Name:      $SLURM_JOB_NAME"
echo "Node:          $SLURM_NODELIST"
echo "Start Time:    $(date)"
echo "Working Dir:   $(pwd)"
echo "========================================"
echo ""

# Activate conda environment with AMICO
echo "Activating mri_env conda environment..."
source ~/.bashrc
conda activate /scratch/rkabir5/mri_env

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to activate conda environment"
    exit 1
fi

# Limit threading to match allocated CPUs
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8

echo "✓ Environment activated"
echo "  Thread limit: $OMP_NUM_THREADS"
echo ""

# Verify key packages
echo "Checking installed packages:"
python -c "import numpy; print(f'  NumPy:   {numpy.__version__}')"
python -c "import nibabel; print(f'  NiBabel: {nibabel.__version__}')"
python -c "import amico; print(f'  AMICO:   {amico.__version__}')"
echo ""

# Define paths
NOTEBOOK="noddi_lab_full.ipynb"
PYTHON_SCRIPT="noddi_lab_full_${SLURM_JOB_ID}.py"

# Check if notebook exists
if [ ! -f "$NOTEBOOK" ]; then
    echo "ERROR: Notebook file not found: $NOTEBOOK"
    echo "Current directory: $(pwd)"
    echo "Files present:"
    ls -lh *.ipynb 2>/dev/null || echo "  No .ipynb files found"
    exit 1
fi

echo "Converting notebook to Python script..."
jupyter nbconvert --to python "$NOTEBOOK" --output "$PYTHON_SCRIPT"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to convert notebook to Python script"
    exit 1
fi

echo "✓ Notebook converted to: $PYTHON_SCRIPT"
echo ""

echo "========================================"
echo "Starting NODDI Fitting"
echo "========================================"
echo ""

python -u "$PYTHON_SCRIPT"

EXIT_CODE=$?

echo ""
echo "========================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ NODDI Fitting Completed Successfully!"
else
    echo "✗ NODDI Fitting Failed with exit code: $EXIT_CODE"
fi
echo "========================================"
echo "End Time:      $(date)"
echo "Job ID:        $SLURM_JOB_ID"
echo "Log File:      noddi_lab_full_${SLURM_JOB_ID}.log"
echo "========================================"

# rm -f "$PYTHON_SCRIPT"

exit $EXIT_CODE
