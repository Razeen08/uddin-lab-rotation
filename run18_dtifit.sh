#!/bin/bash
#SBATCH --job-name=dtifit_subsampled
#SBATCH --time=6:00:00
#SBATCH --mem=32gb
#SBATCH --cpus-per-task=8
#SBATCH --partition=standard
#SBATCH --output=dtifit_subsampled_%j.log
#SBATCH --error=dtifit_subsampled_%j.log

# Load FSL module
module purge
module load fsl

# Set up FSL environment
export FSLOUTPUTTYPE=NIFTI_GZ

# Define paths
SUBJ="100408"
DATA_ROOT="/scratch/rkabir5/StarterCodes_Data"
DATA_DIR="${DATA_ROOT}/100408_3T_Diffusion_preproc/${SUBJ}/T1w/Diffusion"
PROTOCOL_DIR="${DATA_ROOT}/subsampled_protocols"
BASE_OUTPUT_DIR="${DATA_ROOT}/dti_results_subsampled"
TEMP_DIR="${DATA_ROOT}/temp_${SLURM_JOB_ID}"

# Create directories
mkdir -p ${BASE_OUTPUT_DIR}
mkdir -p ${TEMP_DIR}

echo "========================================"
echo "Running DTIfit on all subsampled protocols"
echo "========================================"
echo "Subject: ${SUBJ}"
echo "Data directory: ${DATA_DIR}"
echo "Protocol directory: ${PROTOCOL_DIR}"
echo "Base output directory: ${BASE_OUTPUT_DIR}"
echo "Job ID: ${SLURM_JOB_ID}"
echo "Start time: $(date)"
echo "========================================"
echo ""

# Define protocol parameters
SHELLS=(1000 2000 3000)
NDIRS=(20 30 45 60 75 90)

# Counter
TOTAL=0
SUCCESS=0
FAILED=0

# Loop through all protocols
for shell in "${SHELLS[@]}"; do
    for ndir in "${NDIRS[@]}"; do
        TOTAL=$((TOTAL + 1))
        
        PROTOCOL_NAME="b${shell}_n${ndir}"
        
        echo "----------------------------------------"
        echo "Processing protocol ${TOTAL}/18: ${PROTOCOL_NAME}"
        echo "----------------------------------------"
        
        # Define file paths
        INDICES="${PROTOCOL_DIR}/indices_${PROTOCOL_NAME}.txt"
        BVALS="${PROTOCOL_DIR}/bvals_${PROTOCOL_NAME}"
        BVECS="${PROTOCOL_DIR}/bvecs_${PROTOCOL_NAME}"
        
        # Check if files exist
        if [ ! -f "${INDICES}" ]; then
            echo "  ERROR: Indices file not found: ${INDICES}"
            FAILED=$((FAILED + 1))
            continue
        fi
        
        if [ ! -f "${BVALS}" ]; then
            echo "  ERROR: Bvals file not found: ${BVALS}"
            FAILED=$((FAILED + 1))
            continue
        fi
        
        if [ ! -f "${BVECS}" ]; then
            echo "  ERROR: Bvecs file not found: ${BVECS}"
            FAILED=$((FAILED + 1))
            continue
        fi
        
        # Create output directory for this protocol
        OUTPUT_DIR="${BASE_OUTPUT_DIR}/${PROTOCOL_NAME}"
        mkdir -p ${OUTPUT_DIR}
        
        # Extract volumes using fslselectvols
        EXTRACTED_DATA="${TEMP_DIR}/data_${PROTOCOL_NAME}.nii.gz"
        
        echo "  Extracting volumes from original data..."
        # Convert indices file to comma-separated list
        VOLS_LIST=$(cat ${INDICES} | tr '\n' ',' | sed 's/,$//')
        
        fslselectvols \
            -i ${DATA_DIR}/data.nii.gz \
            -o ${EXTRACTED_DATA} \
            --vols=${VOLS_LIST}
        
        if [ $? -ne 0 ]; then
            echo "  ERROR: Failed to extract volumes for ${PROTOCOL_NAME}"
            FAILED=$((FAILED + 1))
            continue
        fi
        
        echo "  Running dtifit..."
        dtifit \
            --data=${EXTRACTED_DATA} \
            --mask=${DATA_DIR}/nodif_brain_mask.nii.gz \
            --bvecs=${BVECS} \
            --bvals=${BVALS} \
            --out=${OUTPUT_DIR}/dti
        
        if [ $? -eq 0 ]; then
            echo "  SUCCESS: DTIfit completed for ${PROTOCOL_NAME}"
            SUCCESS=$((SUCCESS + 1))
            
            # Save protocol info
            echo "Protocol: ${PROTOCOL_NAME}" > ${OUTPUT_DIR}/protocol_info.txt
            echo "Shell: b=${shell}" >> ${OUTPUT_DIR}/protocol_info.txt
            echo "Directions: ${ndir}" >> ${OUTPUT_DIR}/protocol_info.txt
            echo "Total volumes: $((6 + ndir))" >> ${OUTPUT_DIR}/protocol_info.txt
            echo "Job ID: ${SLURM_JOB_ID}" >> ${OUTPUT_DIR}/protocol_info.txt
            echo "Completion time: $(date)" >> ${OUTPUT_DIR}/protocol_info.txt
        else
            echo "  ERROR: DTIfit failed for ${PROTOCOL_NAME}"
            FAILED=$((FAILED + 1))
        fi
        
        # Clean up extracted data to save space
        rm -f ${EXTRACTED_DATA}
        
        echo ""
    done
done

# Clean up temp directory
rm -rf ${TEMP_DIR}

echo "========================================"
echo "All protocols processed!"
echo "========================================"
echo "Total protocols: ${TOTAL}"
echo "Successful: ${SUCCESS}"
echo "Failed: ${FAILED}"
echo "End time: $(date)"
echo "========================================"
echo ""
echo "Results saved in: ${BASE_OUTPUT_DIR}"
echo ""
echo "Folder structure:"
ls -1 ${BASE_OUTPUT_DIR} | head -20
