#!/bin/bash

set -e
echo -e "\n START: DiffusionToStructural_apply"


########################################## SUPPORT FUNCTIONS ########################################## 

# function for parsing options
getopt1() {
    sopt="$1"
    shift 1
    for fn in $@ ; do
	if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
	    echo $fn | sed "s/^${sopt}=//"
	    return 0
	fi
    done
}

defaultopt() {
    echo $1
}

################################################## OPTION PARSING #####################################################
# Input Variables

WorkingDirectory=`getopt1 "--workingdir" $@`       # "$1" #Path to registration working dir, e.g. ${StudyFolder}/${Subject}/Diffusion/reg
DataDirectory=`getopt1 "--datadiffdir" $@`         # "$2" #Path to diffusion space diffusion data, e.g. ${StudyFolder}/${Subject}/Diffusion/data
T1wRestoreImage=`getopt1 "--t1restore" $@`         # "$3" #T1w_acpc_dc_restore image
InputBrainMask=`getopt1 "--brainmask" $@`          # "$4" #Freesurfer Brain Mask, e.g. brainmask_fs
GdcorrectionFlag=`getopt1 "--gdflag" $@`           # "$5" #Flag for gradient nonlinearity correction (0/1 for Off/On)
DiffRes=`getopt1 "--diffresol" $@`                 # "$6" #Diffusion resolution in mm (assume isotropic)
TargetSpace=`getopt1 "--targetspace" $@`              # "$7" #Which space the transformation is targeting (str or mean)
dof=`getopt1 "--dof" $@`                           # Degrees of freedom for registration to T1w (defaults to 6)

# Output Variables
T1wOutputDirectory=`getopt1 "--datadiffT1wdir" $@` # "$8" #Path to T1w space diffusion data (for producing output)

# Set default option values
dof=`defaultopt $dof 6`

if [ ! -f ${WorkingDirectory}/diff2${TargetSpace}.mat ] ; then
    echo ${WorkingDirectory}/diff2${TargetSpace}.mat
    echo "Transform to target space ${TargetSpace} does not exist"
    exit 1
fi

echo $T1wOutputDirectory

# Paths for scripts etc (uses variables defined in SetUpHCPPipeline.sh)
GlobalScripts=${HCPPIPEDIR_Global}

regimg="nodif"

#Generate 1.25mm structural space for resampling the diffusion data into
${FSLDIR}/bin/flirt -interp spline -in "$T1wRestoreImage" -ref "$T1wRestoreImage" -applyisoxfm ${DiffRes} -out "$WorkingDirectory"/T1w_acpc_dc_restore_${DiffRes}
${FSLDIR}/bin/applywarp --rel --interp=spline -i "$T1wRestoreImage" -r "$WorkingDirectory"/T1w_acpc_dc_restore_${DiffRes} -o "$WorkingDirectory"/T1w_acpc_dc_restore_${DiffRes}
immv "$WorkingDirectory"/T1w_acpc_dc_restore_${DiffRes} "$T1wRestoreImage"_${DiffRes}

#Generate 1.25mm mask in structural space
${FSLDIR}/bin/flirt -interp nearestneighbour -in "$InputBrainMask" -ref "$InputBrainMask" -applyisoxfm ${DiffRes} -out "$T1wOutputDirectory"/nodif_brain_mask
${FSLDIR}/bin/fslmaths "$T1wOutputDirectory"/nodif_brain_mask -kernel 3D -dilM "$T1wOutputDirectory"/nodif_brain_mask

DilationsNum=6 #Dilated mask for masking the final data and grad_dev
${FSLDIR}/bin/imcp "$T1wOutputDirectory"/nodif_brain_mask "$T1wOutputDirectory"/nodif_brain_mask_temp
for (( j=0; j<${DilationsNum}; j++ ))
do
    ${FSLDIR}/bin/fslmaths "$T1wOutputDirectory"/nodif_brain_mask_temp -kernel 3D -dilM "$T1wOutputDirectory"/nodif_brain_mask_temp
done

#Rotate bvecs from diffusion to structural space
${GlobalScripts}/Rotate_bvecs.sh "$DataDirectory"/bvecs "$WorkingDirectory"/diff2${TargetSpace}.mat "$T1wOutputDirectory"/bvecs
cp "$DataDirectory"/bvals "$T1wOutputDirectory"/bvals

#Register diffusion data to T1w space. Account for gradient nonlinearities if requested
if [ ${GdcorrectionFlag} -eq 1 ]; then
    echo "Correcting Diffusion data for gradient nonlinearities and registering to structural space"
    ${FSLDIR}/bin/convertwarp --rel --relout --warp1="$DataDirectory"/warped/fullWarp --postmat="$WorkingDirectory"/diff2${TargetSpace}.mat --ref="$T1wRestoreImage"_${DiffRes} --out="$WorkingDirectory"/grad_unwarp_diff2${TargetSpace}
    ${FSLDIR}/bin/applywarp --rel -i "$DataDirectory"/warped/data_warped -r "$T1wRestoreImage"_${DiffRes} -w "$WorkingDirectory"/grad_unwarp_diff2${TargetSpace} --interp=spline -o "$T1wOutputDirectory"/data

    #Now register the grad_dev tensor 
    ${FSLDIR}/bin/vecreg -i "$DataDirectory"/grad_dev -o "$T1wOutputDirectory"/grad_dev -r "$T1wRestoreImage"_${DiffRes} -t "$WorkingDirectory"/diff2${TargetSpace}.mat --interp=spline
    ${FSLDIR}/bin/fslmaths "$T1wOutputDirectory"/grad_dev -mas "$T1wOutputDirectory"/nodif_brain_mask_temp "$T1wOutputDirectory"/grad_dev  #Mask-out values outside the brain 
else
    #Register diffusion data to T1w space without considering gradient nonlinearities
    ${FSLDIR}/bin/flirt -in "$DataDirectory"/data -ref "$T1wRestoreImage"_${DiffRes} -applyxfm -init "$WorkingDirectory"/diff2${TargetSpace}.mat -interp spline -out "$T1wOutputDirectory"/data
fi

${FSLDIR}/bin/fslmaths "$T1wOutputDirectory"/data -mas "$T1wOutputDirectory"/nodif_brain_mask_temp "$T1wOutputDirectory"/data  #Mask-out data outside the brain 
${FSLDIR}/bin/fslmaths "$T1wOutputDirectory"/data -thr 0 "$T1wOutputDirectory"/data      #Remove negative intensity values (caused by spline interpolation) from final data
${FSLDIR}/bin/imrm "$T1wOutputDirectory"/nodif_brain_mask_temp

${FSLDIR}/bin/fslmaths "$T1wOutputDirectory"/data -Tmean "$T1wOutputDirectory"/temp
${FSLDIR}/bin/immv "$T1wOutputDirectory"/nodif_brain_mask.nii.gz "$T1wOutputDirectory"/nodif_brain_mask_old.nii.gz
${FSLDIR}/bin/fslmaths "$T1wOutputDirectory"/nodif_brain_mask_old.nii.gz -mas "$T1wOutputDirectory"/temp "$T1wOutputDirectory"/nodif_brain_mask
${FSLDIR}/bin/imrm "$T1wOutputDirectory"/temp

echo " END: DiffusionToStructural_apply"
