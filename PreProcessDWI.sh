#!/bin/bash
#SBATCH --time=5-00:00:00 --mem=24gb --partition=gpu --gres=gpu:1
# Time 10hours should be more than enough
# Created by Kyle Murray
# Edited by Abrar Faiyaz
# Preprocess DTI data on Bluehive
# This script works for AP_b1000, AP_b2000, and two PA voumes
#

# ./2preprocDTI.sh RN046 18m 
# sbatch 2.preprocDTI.sh NC118 bsl
module unload fsl
module load fsl/6.0.0/b1

subj=${1} # NC901
sess=${2} #"bsl"
#out=${3}



# Set up TOPUP
NIFTI_nerocovid="/scratch/gschifit_lab/NeuroCovid/NIFTI_NC/" # First step is to make the data properly NIFTI formatted
di=${NIFTI_nerocovid}/sub-${subj}/ses-${sess}/dwi/
#di=DTI/data/${subj}
dp=$di/preproc/
#=$di/DTI/

# Store the outputs here.
mkdir $dp
cd ${dp}


mkdir $dp

# Combine all APs into one dwidata file
#fslmerge -t ${dp}/dwidata ${di}/dti_AP1000.nii ${di}/dti_AP2000.nii
fslmerge -t "${dp}/dwidata" "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-1000_dwi.nii.gz" "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-2000_dwi.nii.gz"

# Combine bvals and bvecs
read -d '' -r -a bval1 < "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-1000_dwi.bval"
read -d '' -r -a bval2 < "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-2000_dwi.bval"
echo ${bval1[@]} ${bval2[@]} > ${dp}/bvals

read -d '' -r -a bvec1 < "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-1000_dwi.bvec"
read -d '' -r -a bvec2 < "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-2000_dwi.bvec"
echo ${bvec1[@]:0:${#bval1[@]}} ${bvec2[@]:0:${#bval1[@]}} > ${dp}/bvecs
echo ${bvec1[@]:${#bval1[@]}:${#bval1[@]}} ${bvec2[@]:${#bval1[@]}:${#bval1[@]}} >> ${dp}/bvecs
echo ${bvec1[@]:$(( ${#bval1[@]} + ${#bval1[@]} )):${#bval1[@]}} ${bvec2[@]:$(( ${#bval1[@]} + ${#bval1[@]} )):${#bval1[@]}} >> ${dp}/bvecs

# Create index.txt file for later use
indx=""
for ((i=1; i<=$(( ${#bval1[@]} + ${#bval2[@]} )); i+=1));
do
		    indx="$indx 1"
done


	echo $indx > ${dp}/index.txt

	# Create all_my_b0_images.nii
	fslroi "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-1000_dwi.nii.gz" ${dp}/nodif_1000 0 2 # Take first 2 AP from 1000
	fslroi "${di}/sub-${subj}_ses-${sess}_enc-ap_shl-2000_dwi.nii.gz" ${dp}/nodif_2000 0 2 # Take second 2 AP from 2000
	fslmerge -t ${dp}/AP_b0 ${dp}/nodif_1000 ${dp}/nodif_2000 # Merge the 4 and name it AP_b0
	fslmerge -t ${dp}/AP_PA_b0 ${dp}/AP_b0 "${di}/sub-${subj}_ses-${sess}_enc-pa_shl-0_dwi.nii.gz" #Merge the AP and PA and name it AP_PA_b0


	# Create acqparams file
	#CSVD EPI factor/ Echo Train Length/ shot factor = 172
	#CSVD Echo Spacing = 0.66 ms
	echo "0 -1 0 0.11352" > ${dp}/acqparams.txt
	echo "0 -1 0 0.11352" >> ${dp}/acqparams.txt
	echo "0 -1 0 0.11352" >> ${dp}/acqparams.txt
	echo "0 -1 0 0.11352" >> ${dp}/acqparams.txt
	echo "0 1 0 0.11352" >> ${dp}/acqparams.txt
	echo "0 1 0 0.11352" >> ${dp}/acqparams.txt
	echo "0 1 0 0.11352" >> ${dp}/acqparams.txt
	cd ${dp}
#topup --imain=AP_PA_b0  --datain=acqparams.txt --config=b02b0.cnf --out=topup_AP_PA_b0 --iout=topup_AP_PA_b0_iout --fout=topup_AP_PA_b0_fout
	# Run TOPUP
echo "Running TopUp"

start=`date +%s`

	topup \
		--imain=AP_PA_b0 \
		--datain=acqparams.txt \
		--config=b02b0.cnf \
		--out=topup_AP_PA_b0 \
		--iout=topup_AP_PA_b0_iout \
		--fout=topup_AP_PA_b0_fout

end=`date +%s`
echo Execution time topup was `expr $end - $start` seconds.

	# Prepare EDDY
	# Generate brain mask using the corrected b0 volumes
	fslmaths topup_AP_PA_b0_iout -Tmean hifi_nodif
	# Brain extract the averaged b0
	bet hifi_nodif hifi_nodif_brain -m -f 0.2

	# Run EDDY
#eddy_cuda --imain=dwidata --mask=hifi_nodif_brain_mask --index=index.txt --acqp=acqparams.txt --bvecs=bvecs --bvals=bvals --fwhm=0 --topup=topup_AP_PA_b0 --flm=quadratic --out=eddy_unwarped_images --data_is_shelled

echo "Running EddyCuda"
start=`date +%s`
	eddy_cuda \
		--imain=dwidata \
		--mask=hifi_nodif_brain_mask \
		--index=index.txt \
    	--acqp=acqparams.txt \
	    --bvecs=bvecs \
	    --bvals=bvals \
	    --fwhm=0 \
	    --topup=topup_AP_PA_b0 \
	    --flm=quadratic \
	    --out=eddy_unwarped_images \
	    --data_is_shelled

end=`date +%s`
echo Execution time eddy  was `expr $end - $start` seconds.

	# Run dtifit
echo "Running dtifit"
	dtifit \
		--data=eddy_unwarped_images \
	    --mask=hifi_nodif_brain_mask \
	    --bvecs=bvecs \
	    --bvals=bvals \
	    --out=dti

