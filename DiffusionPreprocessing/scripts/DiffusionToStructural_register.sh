#!/bin/bash

set -e
echo -e "\n START: DiffusionToStructural_register"


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

FreeSurferSubjectFolder=`getopt1 "--t1folder" $@`  # "$1" #${StudyFolder}/${Subject}/T1w
FreeSurferSubjectID=`getopt1 "--subject" $@`       # "$2" #Subject ID
WorkingDirectory=`getopt1 "--workingdir" $@`       # "$3" #Path to registration working dir, e.g. ${StudyFolder}/${Subject}/Diffusion/reg
DataDirectory=`getopt1 "--datadiffdir" $@`         # "$4" #Path to diffusion space diffusion data, e.g. ${StudyFolder}/${Subject}/Diffusion/data
T1wImage=`getopt1 "--t1" $@`                       # "$5" #T1w_acpc_dc image
T1wRestoreImage=`getopt1 "--t1restore" $@`         # "$6" #T1w_acpc_dc_restore image
T1wBrainImage=`getopt1 "--t1restorebrain" $@`      # "$7" #T1w_acpc_dc_restore_brain image
BiasField=`getopt1 "--biasfield" $@`               # "$8" #Bias_Field_acpc_dc
InputBrainMask=`getopt1 "--brainmask" $@`          # "$9" #Freesurfer Brain Mask, e.g. brainmask_fs
GdcorrectionFlag=`getopt1 "--gdflag" $@`           # "$10"#Flag for gradient nonlinearity correction (0/1 for Off/On) 
DiffRes=`getopt1 "--diffresol" $@`                 # "$11"#Diffusion resolution in mm (assume isotropic)
dof=`getopt1 "--dof" $@`                           # Degrees of freedom for registration to T1w (defaults to 6)

# Output Variables
RegOutput=`getopt1 "--regoutput" $@`               # "$13" #Temporary file for sanity checks
QAImage=`getopt1 "--QAimage" $@`                   # "$14" #Temporary file for sanity checks 

# Set default option values
dof=`defaultopt $dof 6`

# Paths for scripts etc (uses variables defined in SetUpHCPPipeline.sh)
GlobalScripts=${HCPPIPEDIR_Global}

T1wBrainImageFile=`basename $T1wBrainImage`
regimg="nodif"

${FSLDIR}/bin/imcp "$T1wBrainImage" "$WorkingDirectory"/"$T1wBrainImageFile"

#b0 FLIRT BBR and bbregister to T1w
${GlobalScripts}/epi_reg_dof --dof=${dof} --epi="$DataDirectory"/"$regimg" --t1="$T1wImage" --t1brain="$WorkingDirectory"/"$T1wBrainImageFile" --out="$WorkingDirectory"/"$regimg"2T1w_initII

${FSLDIR}/bin/applywarp --rel --interp=spline -i "$DataDirectory"/"$regimg" -r "$T1wImage" --premat="$WorkingDirectory"/"$regimg"2T1w_initII_init.mat -o "$WorkingDirectory"/"$regimg"2T1w_init.nii.gz
${FSLDIR}/bin/applywarp --rel --interp=spline -i "$DataDirectory"/"$regimg" -r "$T1wImage" --premat="$WorkingDirectory"/"$regimg"2T1w_initII.mat -o "$WorkingDirectory"/"$regimg"2T1w_initII.nii.gz
${FSLDIR}/bin/fslmaths "$WorkingDirectory"/"$regimg"2T1w_initII.nii.gz -div "$BiasField" "$WorkingDirectory"/"$regimg"2T1w_restore_initII.nii.gz

SUBJECTS_DIR="$FreeSurferSubjectFolder"
export SUBJECTS_DIR
${FREESURFER_HOME}/bin/bbregister --s "$FreeSurferSubjectID" --mov "$WorkingDirectory"/"$regimg"2T1w_restore_initII.nii.gz --surf white.deformed --init-reg "$FreeSurferSubjectFolder"/"$FreeSurferSubjectID"/mri/transforms/eye.dat --bold --reg "$WorkingDirectory"/EPItoT1w.dat --o "$WorkingDirectory"/"$regimg"2T1w.nii.gz
${FREESURFER_HOME}/bin/tkregister2 --noedit --reg "$WorkingDirectory"/EPItoT1w.dat --mov "$WorkingDirectory"/"$regimg"2T1w_restore_initII.nii.gz --targ "$T1wImage".nii.gz --fslregout "$WorkingDirectory"/diff2str_fs.mat

${FSLDIR}/bin/convert_xfm -omat "$WorkingDirectory"/diff2str.mat -concat "$WorkingDirectory"/diff2str_fs.mat "$WorkingDirectory"/"$regimg"2T1w_initII.mat
${FSLDIR}/bin/convert_xfm -omat "$WorkingDirectory"/str2diff.mat -inverse "$WorkingDirectory"/diff2str.mat

${FSLDIR}/bin/applywarp --rel --interp=spline -i "$DataDirectory"/"$regimg" -r "$T1wImage".nii.gz --premat="$WorkingDirectory"/diff2str.mat -o "$WorkingDirectory"/"$regimg"2T1w
${FSLDIR}/bin/fslmaths "$WorkingDirectory"/"$regimg"2T1w -div "$BiasField" "$WorkingDirectory"/"$regimg"2T1w_restore

#Are the next two scripts needed?
${FSLDIR}/bin/imcp "$WorkingDirectory"/"$regimg"2T1w_restore "$RegOutput"
${FSLDIR}/bin/fslmaths "$T1wRestoreImage".nii.gz -mul "$WorkingDirectory"/"$regimg"2T1w_restore.nii.gz -sqrt "$QAImage"_"$regimg".nii.gz


echo " END: DiffusionToStructural_register"
