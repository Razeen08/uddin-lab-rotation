#!/bin/bash
#SBATCH --job-name=noddi_lab_sub
#SBATCH --time=12:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=8
#SBATCH --partition=preempt
#SBATCH --output=noddi_lab_sub_%j.log
#SBATCH --error=noddi_lab_sub_%j.log

# ============================================================
# NODDI Fitting on Lab Subsampled Protocols - SLURM Batch Script
# Purpose: Fit NODDI for 14 single-shell protocols (5 × b1000, 5 × b2000, 4 × b3000)
# Partition: preempt (lower priority, cheaper)
# Expected runtime: ~3-4 hours for all 14 protocols
# ============================================================

echo "========================================"
echo "NODDI Lab Subsampling Study Started"
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

# Limit threading to avoid OpenBLAS segfault from nested parallelism.
# AMICO uses all available CPUs for voxel-level parallelism; setting
# OPENBLAS_NUM_THREADS=1 prevents each AMICO thread from spawning additional
# BLAS threads which exceeds OpenBLAS's compiled NUM_THREADS limit.
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

echo "✓ Environment activated"
echo "  Thread limit: $OMP_NUM_THREADS"
echo ""

# Verify key packages
echo "Checking installed packages:"
python -c "import numpy; print(f'  NumPy:   {numpy.__version__}')"
python -c "import scipy; print(f'  SciPy:   {scipy.__version__}')"
python -c "import nibabel; print(f'  NiBabel: {nibabel.__version__}')"
python -c "import amico; print(f'  AMICO:   {amico.__version__}')"
echo ""

# Define paths
NOTEBOOK="noddi_lab_subsampled.ipynb"
PYTHON_SCRIPT="noddi_lab_subsampled_${SLURM_JOB_ID}.py"

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
echo "Starting NODDI Fitting for All Protocols"
echo "========================================"
echo ""

python -u "$PYTHON_SCRIPT"

SCRIPT_EXIT_CODE=$?

echo ""
echo "========================================"
if [ $SCRIPT_EXIT_CODE -eq 0 ]; then
    echo "✓ NODDI FITTING COMPLETED SUCCESSFULLY"
else
    echo "✗ NODDI Fitting Failed with exit code: $SCRIPT_EXIT_CODE"
fi
echo "========================================"
echo "End Time:      $(date)"
echo "Job ID:        $SLURM_JOB_ID"
echo "Log File:      noddi_lab_sub_${SLURM_JOB_ID}.log"
echo "========================================"

exit $SCRIPT_EXIT_CODE
