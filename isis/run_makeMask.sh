#!/bin/bash
# loop over a set of exposure numbers launching the mask making tasks in DBIMAGES for each
CMD="$(basename "${BASH_SOURCE[0]}")"
SRCDIR="$(dirname "${BASH_SOURCE[0]}")"
. ${SRCDIR}/utils.sh
. ${SRCDIR}/sk_utils.sh

export NOPTS=2
TYPE="interp"
export USAGE="${CMD} exposure_list ccd

For each exposure number in the list find the ${TYPE}_${PREFIX} image for the given CCD in dbimages and run makeMask on that image
"
. "${SRCDIR}/argparse.sh"

exposure_list="$(realpath $1)" && shift
ccd=$1 && shift

JOBID=()
DELLIST=()
logmsg INFO "Making mask using ${PREFIX} image"
while IFS="" read -r expnum || [[ -n ${expnum} ]]
do
    name=$(launch_name "makemask" ${PREFIX} ${expnum} ${VERSION} ${ccd})
    image_name="$(get_image_filename "" ${PREFIX} "${expnum}" ${VERSION} "${ccd}")"
    logmsg DEBUG "expnum: ${expnum} ccd: ${ccd}"
    directory="$(get_dbimages_directory "${expnum}" "${ccd}")"
    cd "$directory" || logmsg ERROR "Cannot change to directory ${directory}"
    logmsg INFO "launching mask on ${image_name} in ${directory}"
    THISID="$(sk_launch uvickbos/pycharm:0.1 "${name}" \
       /arc/home/jkavelaars/classy-pipeline/venv/bin/python "${SRCDIR}/makeMask.py" "${image_name}" \
      		 --maskbits BAD --maskbits SAT \
		 --maskbits SENSOR_EDGE --maskbits NO_DATA)"
    (echo ${THISID} | grep -q ${name}) || JOBID+=(${THISID})
    DELLIST+=("mask_${image_name}")
    echo ${THISID}
done < "${exposure_list}"

sk_wait "${JOBID[@]}" || exit $?

JOBID=()
logmsg INFO "swarpING ${PREFIX} mask to mask_${TYPE}"
while IFS="" read -r expnum || [[ -n ${expnum} ]]
do
    directory="$(get_dbimages_directory "${expnum}" "${ccd}")"
    cd "$directory" || logmsg ERROR "Cannot change to directory ${directory}"
    image_name="$(get_image_filename "" ${PREFIX} "${expnum}" ${VERSION} "${ccd}")"
    input_mask="mask_${image_name}"
    mask_name="$(get_image_filename "mask_${TYPE}" ${PREFIX} "${expnum}" ${VERSION} "${ccd}")"
    image_name="$(get_image_filename "${TYPE}" "${PREFIX}" "${expnum}" "${VERSION}" "${ccd}")"
    [ -f "${mask_name%%.fits}.head" ] || ln -s "${image_name%%.fits}.head" "${mask_name%%.fits}.head"
    name=$(launch_name "mask-swarp" ${PREFIX} ${expnum} ${VERSION} ${ccd})
    THISID="$(sk_launch uvickbos/swarp:0.1 "${name}" /usr/local/bin/swarp \
		 -c ${DBIMAGES}/configs/swarp.config \
		 -RESAMPLING_TYPE NEAREST \
		 -WEIGHT_TYPE NONE \
		 -FSCALASTRO_TYPE NONE \
		 -OVERSAMPLING 1 \
		 -IMAGEOUT_NAME ${mask_name} \
		 ${input_mask})"
    DELLIST+=("${mask_name}")
    logmsg DEBUG "launch of ${name} response ${THISID}"
    ( echo "${THISID}" | grep -q ${name} ) || JOBID+=("${THISID}")
    echo "${THISID}"
done < "${exposure_list}"

sk_wait "${JOBID[@]}" || exit $?

JOBID=()
logmsg INFO "Augmenting mask_${TYPE} to mask padding store to mask_mask_${TYPE}"
while IFS="" read -r expnum || [[ -n ${expnum} ]]
do
    directory="$(get_dbimages_directory "${expnum}" "${ccd}")"
    cd "$directory" || logmsg ERROR "Cannot change to directory ${directory}"
    mask_name="$(get_image_filename "mask_${TYPE}" ${PREFIX} "${expnum}" ${VERSION} "${ccd}")"
    image_name="$(get_image_filename "${TYPE}" "${PREFIX}" "${expnum}" "${VERSION}" "${ccd}")"
    name=$(launch_name "makemask-interp" ${PREFIX} ${expnum} ${VERSION} ${ccd})
    THISID="$(sk_launch uvickbos/pycharm:0.1 "${name}" \
		 /arc/home/jkavelaars/classy-pipeline/venv/bin/python "${SRCDIR}/makeMask.py" "${image_name}" \
		 --maskbits NO_DATA --maskfile ${mask_name})"
    ( echo ${THISID} | grep -q ${name} ) || JOBID+=("${THISID}")
    echo "${THISID}"

done < "${exposure_list}"

sk_wait "${JOBID[@]}" || exit $? 

echo "${DELLIST[@]}"
