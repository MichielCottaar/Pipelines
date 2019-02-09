#!/usr/bin/env bash
#
# Merges the individually processed diffusion datasets into a single diffusion image
# Called from DiffusionPreprocessing/DiffPreprocPipeline_Merge.sh
#

set -e
echo -e "\n START: merge_split"

StudyFolder=$1
Subject=$2
OutDWIName=$3
InDWINames="${@:4}"

# Register to mean b0 space
T1wFolder="${StudyFolder}/${Subject}/T1w" #Location of T1w images
FinalDirectory=${T1wFolder}/${OutDWIName}
for dwi_name in ${InDWINames} ; do
    in_dir=${T1wFolder}/${dwi_name}
    ${FSLDIR}/bin/select_dwi_vols ${in_dir}/data ${in_dir}/bvals ${in_dir}/b0 0 -m
done

mkdir -p ${FinalDirectory}
cmd="${FSLDIR}/bin/fsladd ${FinalDirectory}/ref_b0 -m"
for dwi_name in ${InDWINames} ; do
    cmd+=" ${T1wFolder}/${dwi_name}/b0"
done
${cmd}


for dwi_name in ${InDWINames} ; do
    in_dir=${T1wFolder}/${dwi_name}
    ${FSLDIR}/bin/flirt -in ${in_dir}/b0 -ref ${FinalDirectory}/ref_b0 -omat ${in_dir}/str2mean.mat -dof 6

    # apply new transform to un-transformed diffusion data
	UntransformedDir=${StudyFolder}/${Subject}/${dwi_name}
    ${FSLDIR}/bin/convert_xfm -omat ${UntransformedDir}/reg/diff2mean.mat -concat ${UntransformedDir}/reg/diff2str.mat ${in_dir}/str2mean.mat

    echo "Applying transfomation to mean space for ${dwi_name}"
    DiffRes=`${FSLDIR}/bin/fslval ${UntransformedDir}/data/data pixdim1`
    DiffRes=`printf "%0.2f" ${DiffRes}`
    mkdir -p ${in_dir}_mean

    GdFlag=0
    echo ${in_dir}/grad_dev
    if [ `imtest ${in_dir}/grad_dev` == "1" ] ; then
            echo "Gradient nonlinearity distortion correction coefficients found!"
            GdFlag=1
    fi

    ${HCPPIPEDIR_dMRI}/DiffusionToStructural_apply.sh \
            --t1folder="${T1wFolder}" \
            --workingdir="${UntransformedDir}/reg" \
            --datadiffdir="${UntransformedDir}/data" \
            --t1restore="${T1wFolder}/T1w_acpc_dc_restore" \
            --brainmask="${T1wFolder}/brainmask_fs" \
            --datadiffT1wdir="${in_dir}_mean" \
            --dof="${DegreesOfFreedom}" \
            --gdflag=${GdFlag} \
            --targetspace="mean" \
            --diffresol=${DiffRes}
done

T1wRestoreImage="${T1wFolder}/T1w_acpc_dc_restore"
FreeSurferBrainMask="${T1wFolder}/brainmask_fs"
DiffRes=`${FSLDIR}/bin/fslval ${OutDirectory}/data/data pixdim1`
DiffRes=`printf "%0.2f" ${DiffRes}`



#
# Merges the individual images
#
echo "merging data"
cmd="${FSLDIR}/bin/fslmerge -t ${FinalDirectory}/${DWIName}/data"
for dwi_name in ${InDWINames} ; do
    in_dir=${T1wFolder}/${dwi_name}_mean
    cmd+=" ${in_dir}/data"
done
${cmd}

mean_image()
{
    echo "computing mean of $1"
	local error_msgs=""
    cmd="${FSLDIR}/bin/fsladd ${FinalDirectory}/$1 -m"
    for dwi_name in ${InDWINames} ; do
        in_dir=${T1wFolder}/${dwi_name}_mean
        cmd+=" ${in_dir}/$1"
    done
    ${cmd}
}

mean_image nodif_brain_mask
# include voxels based on majority voting (erring on the side of inclusion)
${FSLDIR}/bin/fslmaths ${FinalDirectory}/nodif_brain_mask -thr 0.49 -bin ${FinalDirectory}/nodif_brain_mask

if [ -f ${indir}/grad_dev.nii* ]; then
    mean_image grad_dev
fi


#
# Merges the individual b-values and b-vectors
#
merge_text()
{
    echo "merging $1"
    cmd="paste"
    for dwi_name in ${InDWINames} ; do
        in_dir=${T1wFolder}/${dwi_name}_mean
        cmd+=" ${in_dir}/$1"
    done
    ${cmd} >${FinalDirectory}/$1
}

merge_text bvals
merge_text bvecs

echo -e "\n END: merge_split"

