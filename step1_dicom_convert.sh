#!/bin/bash
#SBATCH --job-name=dicom_convert
#SBATCH --output=dicom_convert_%j.log
#SBATCH --time=01:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --partition=preempt

# ============================================================
# Step 1: DICOM → NIfTI Conversion + Discovery
# Converts all scan folders and prints a summary of what was found
# ============================================================

DATA_ROOT="/gpfs/fs2/scratch/rkabir5/StarterCodes_Data/new_data/afaiyaz-20260313_190724/TEST03092026"
SESSION_DIR="${DATA_ROOT}/26_03_09-10_33_23-DST-1_3_12_2_1107_5_2_43_167029"
OUTPUT_DIR="${DATA_ROOT}/nifti"

echo "========================================"
echo "DICOM Conversion + Discovery"
echo "========================================"
echo "Session dir: ${SESSION_DIR}"
echo "Output dir:  ${OUTPUT_DIR}"
echo "Date: $(date)"
echo ""

# Activate conda environment (has dcm2niix installed)
source /home/rkabir5/miniconda3/etc/profile.d/conda.sh
conda activate /scratch/rkabir5/mri_env

# Install dcm2niix into mri_env if not already present
if ! command -v dcm2niix &>/dev/null; then
    echo "dcm2niix not found — installing via conda-forge (one-time setup)..."
    conda install -y -c conda-forge dcm2niix
fi

which dcm2niix || { echo "ERROR: dcm2niix still not found after install. Exiting."; exit 1; }
echo "dcm2niix version: $(dcm2niix --version 2>&1 | head -1)"
echo ""

mkdir -p "${OUTPUT_DIR}"

# ---- Convert each numbered folder -------------------------
echo "Converting all scan folders..."
echo ""

for scan_folder in $(ls -d "${SESSION_DIR}"/*/  | sort -V); do
    scan_num=$(basename "${scan_folder}")
    out_subdir="${OUTPUT_DIR}/scan_${scan_num}"
    mkdir -p "${out_subdir}"

    # Skip if no DICOM subfolder
    if [ ! -d "${scan_folder}/DICOM" ] && [ ! -d "${scan_folder}/secondary" ]; then
        echo "  Scan ${scan_num}: no DICOM/secondary subfolder — skipping"
        continue
    fi

    # Use whichever subfolder exists
    if [ -d "${scan_folder}/DICOM" ]; then
        dicom_dir="${scan_folder}/DICOM"
    else
        dicom_dir="${scan_folder}/secondary"
    fi

    # Run dcm2niix
    dcm2niix -z y -f "scan${scan_num}_%d" -o "${out_subdir}" "${dicom_dir}" > /tmp/dcm2niix_out.txt 2>&1
    exit_code=$?

    # Print one-line summary
    series_desc=$(grep -oP "Convert \d+ DICOM as \K[^\(]+" /tmp/dcm2niix_out.txt 2>/dev/null | head -1 | sed 's/ *$//')
    n_files=$(grep -oP "Found \K\d+" /tmp/dcm2niix_out.txt 2>/dev/null | head -1)

    if [ ${exit_code} -eq 0 ]; then
        nifti_files=$(ls "${out_subdir}"/*.nii.gz 2>/dev/null | wc -l)
        bval_files=$(ls "${out_subdir}"/*.bval 2>/dev/null | wc -l)
        echo "  Scan ${scan_num:->3}: ${series_desc:-(see log)} | NIfTI=${nifti_files} bval/bvec=${bval_files}"
    else
        echo "  Scan ${scan_num:->3}: CONVERSION FAILED (exit ${exit_code})"
        cat /tmp/dcm2niix_out.txt
    fi
done

echo ""
echo "========================================"
echo "DISCOVERY SUMMARY"
echo "========================================"
echo ""
echo "Looking for key sequences..."
echo ""

# ---- Identify DWI scans by checking bval files ------------
echo "Scans with bval/bvec (DWI data):"
echo "  Folder | Series name                          | #volumes | b-values"
echo "  -------|--------------------------------------|----------|----------"

for scan_dir in $(ls -d "${OUTPUT_DIR}"/scan_*/  | sort -V); do
    bval_file=$(ls "${scan_dir}"/*.bval 2>/dev/null | head -1)
    nii_file=$(ls "${scan_dir}"/*.nii.gz 2>/dev/null | head -1)
    if [ -n "${bval_file}" ] && [ -n "${nii_file}" ]; then
        scan_num=$(basename "${scan_dir}" | sed 's/scan_//')
        nvols=$(fslval "${nii_file}" dim4 2>/dev/null || echo "?")
        bvals_unique=$(sort -n "${bval_file}" | uniq | tr '\n' ' ')
        series_name=$(basename "${nii_file}" | sed 's/\.nii\.gz//' | sed "s/scan${scan_num}_//")
        printf "  %-6s | %-36s | %-8s | %s\n" \
            "${scan_num}" "${series_name:0:36}" "${nvols}" "${bvals_unique}"
    fi
done

echo ""
echo "All NIfTI files saved to: ${OUTPUT_DIR}"
echo ""
echo "========================================"
echo "NEXT STEPS"
echo "========================================"
echo ""
echo "From the table above, identify:"
echo "  1. PA b0 scan (P>A phase encoding, only b=0 volumes)"
echo "  2. b1000 DWI scans (one per direction count)"
echo "  3. b2000 DWI scans (one per direction count)"
echo ""
echo "Then run: sbatch preprocess_lab_dwi.sh"
echo ""
echo "Done: $(date)"
