#!/bin/bash

set -euo pipefail

########################################################
#
# SF tool to report list of files
#
########################################################

#********************************************************
#
# Starfish Storage Corporation ("COMPANY") CONFIDENTIAL
# Unpublished Copyright (c) 2011-2018 Starfish Storage Corporation, All Rights Reserved.
#
# NOTICE:  All information contained herein is, and remains the property of COMPANY. The intellectual and
# technical concepts contained herein are proprietary to COMPANY and may be covered by U.S. and Foreign
# Patents, patents in process, and are protected by trade secret or copyright law. Dissemination of this
# information or reproduction of this material is strictly forbidden unless prior written permission is
# obtained from COMPANY.  Access to the source code contained herein is hereby forbidden to anyone except
# current COMPANY employees, managers or contractors who have executed Confidentiality and Non-disclosure
# agreements explicitly covering such access.
#
# ANY REPRODUCTION, COPYING, MODIFICATION, DISTRIBUTION, PUBLIC  PERFORMANCE, OR PUBLIC DISPLAY OF OR
# THROUGH USE  OF THIS  SOURCE CODE  WITHOUT  THE EXPRESS WRITTEN CONSENT OF COMPANY IS STRICTLY PROHIBITED,
# AND IN VIOLATION OF APPLICABLE LAWS AND INTERNATIONAL TREATIES.  THE RECEIPT OR POSSESSION OF  THIS SOURCE
# CODE AND/OR RELATED INFORMATION DOES NOT CONVEY OR IMPLY ANY RIGHTS TO REPRODUCE, DISCLOSE OR DISTRIBUTE
# ITS CONTENTS, OR TO MANUFACTURE, USE, OR SELL ANYTHING THAT IT  MAY DESCRIBE, IN WHOLE OR IN PART.  
#
# FOR U.S. GOVERNMENT CUSTOMERS REGARDING THIS DOCUMENTATION/SOFTWARE
#   These notices shall be marked on any reproduction of this data, in whole or in part.
#   NOTICE: Notwithstanding any other lease or license that may pertain to, or accompany the delivery of,
#   this computer software, the rights of the Government regarding its use, reproduction and disclosure are
#   as set forth in Section 52.227-19 of the FARS Computer Software-Restricted Rights clause.
#   RESTRICTED RIGHTS NOTICE: Use, duplication, or disclosure by the Government is subject to the
#   restrictions as set forth in subparagraph (c)(1)(ii) of the Rights in Technical Data and Computer
#   Software clause at DFARS 52.227-7013.
#
#********************************************************

# Set variables
readonly VERSION="1.01 December 4, 2017"
PROG="$0"
readonly SFHOME="${SFHOME:-/opt/starfish}"
readonly STARFISH_BIN_DIR="${SFHOME}/bin"

# Check to see if we are root, if so, set the SUDO_USER variable
if [ ! -v SUDO_USER ] ; then
   SUDO_USER=root
fi

USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
readonly LOGDIR="$SFHOME/log"
readonly NOW=$(date +"%Y%m%d-%H%M%S")
readonly LOGFILE="${LOGDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.log"
AGE="1"
TIME="atime_age"
TIMEDATE="atime_date"
HEADER_TIME="last accessed"
FORMAT="--csv -d,"
VERBOSE=false
VOLUME=""
readonly OUTPUTFILE="$USER_HOME/${SUDO_USER}-filelist.csv"

# logprint routine called to write to log file
logprint() {
   echo "$(date +%D-%T): $*" >> $LOGFILE
}

# fatal routine is called to end script due to an error
fatal() {
   local msg="$1"
   echo "${msg}" >&2
   exit 1
}

# check_parameters_value is called to verify that options have parameters assigned
check_parameters_value() {
   local param="$1"
   [ $# -gt 1 ] || fatal "Missing value for parameter ${param}"
}

# display usage
usage () {
   local msg="${1:-""}"

   if [ ! -z "${msg}" ]; then
      echo "${msg}" >&2
   fi

  cat <<EOF

File List Reporting Script
$VERSION

This script is invoked by a user to report on which files they own that are older than a specified time. The default output is a csv file in the users home directory.
Logs can be found in $SFHOME/log

Prerequisites:
- Sudo is required so that the script has appropriate rights to run the query
- Add the following to /etc/sudoers:
  ## Starfish run filelist script for all users
  ALL ALL=NOPASSWD: /opt/starfish/scripts/filelist.sh

$PROG [options]

   -h, --help         - print this help and exit
   --volume           - Starfish volume to report on (defaults to all Starfish volumes)
   --age X            - find files older than X months, where:
                        X=1, older than 1 month (default)
                        X=3, older than 3 months
                        X=6, older than 6 months
                        X=12, older than 12 months
                        X=24, older than 24 months 
                        X=36, older than 36 months
   --mtime            - use mtime instead of atime (Default = atime)
   --tsv              - Output in tab separated format (Default = comma separated)
   --verbose          - Include verbose output
   -o {filename}      - Specify an output filename. Default is $USER_HOME/${SUDO_USER}-filelist.csv 

Examples:
sudo $PROG --volume sfvol -o /tmp/myfiles.csv
This will report on all files owned by the current user older than 1 month that are located on volume sfvol. Output is /tmp/myfiles.csv as opposed to $USER_HOME/${SUDO_USER}-filelist.csv

sudo $PROG --volume sfvol --age 3
This will report on all files owned by the current user older than 3 months that are located on volume sfvol

sudo $PROG
This will report on all files owned by the current user older than 1 month that are located on any Starfish volume, and
EOF
exit 1
}

# if first parameter is -h or --help, call usage routine
if [ $# -gt 0 ]; then
  [[ "$1" == "-h" || "$1" == "--help" ]] && usage
fi

# Check if logdir and logfile exists, and create if it doesnt
[[ ! -e $LOGDIR ]] && mkdir $LOGDIR
[[ ! -e $LOGFILE ]] && touch $LOGFILE
logprint "---------------------------------------------------------------"
logprint "Script executing"
logprint "$VERSION"
echo "Script starting, in process"


# if first parameter is -h or --help, call usage routine
if [ $# -gt 0 ]; then
  [[ "$1" == "-h" || "$1" == "--help" ]] && usage
fi

logprint "Parsing input parameters"
while [[ $# -gt 0 ]]; do
   case $1 in
   "--age")
      check_parameters_value "$@"
      shift
      AGE=$1
      shift
      [[ "${AGE}" == "1" || "${AGE}" == "3" || "${AGE}" == "6" || "${AGE}" == "12" || "${AGE}" == "24" || "${AGE}" == "36" ]] || fatal "--age must be 1, 3, 6, 12, 24 or 36! (but is: ${AGE})"
      ;;
   "--mtime")
      shift
      TIME="mtime_age"
      TIMEDATE="mtime_date"
      HEADER_TIME="last modified"
      ;;
   "--volume")
      check_parameters_value "$@"
      shift
      VOLUME=$1
      [[ $VOLUME != *:* ]] && VOLUME="$VOLUME:"
      shift
      ;;
   "-o")
      check_parameters_value "$@"
      shift
      OUTPUTFILE=$1
      shift
      ;;
   "--tsv")
      FORMAT=""
      shift
      ;;
   "--verbose")
      shift
      VERBOSE=true
      ;;
   *)
      logprint "input parameter: $1 unknown. Exiting.."
      fatal "input parameter: $1 unknown. Exiting.." 
      ;;
   esac
done

# Report parameter values to logfile
if [ -z $VOLUME ]; then
   logprint " volume: [All]"
else
   logprint " volume: $VOLUME"
fi
logprint " age: $AGE"
logprint " time: ${TIME::-4}"
if [ -z "$FORMAT" ]; then
  logprint " format: tsv"
else
  logprint " format: csv"
fi
logprint " output file: $OUTPUTFILE"
logprint " verbose: $VERBOSE"

# Determine bigdate for sf query command
BIGDATE=`date -d "now - $AGE months" "+%Y%m%d"`

logprint " older than: $BIGDATE"
logprint "sudo user: $SUDO_USER"
echo "Running query for $SUDO_USER, output directed to $OUTPUTFILE. This may take a few minutes"

echo "volume,path,filename,$HEADER_TIME,Size(bytes),groupname,username" > $OUTPUTFILE
`sf query --no-headers $VOLUME --username $SUDO_USER --type f --${TIME::-4} 19700101-$BIGDATE $FORMAT --format "volume path fn $TIMEDATE size groupname username" >> $OUTPUTFILE`

[[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: SF Query command: sf query --no-headers $VOLUME --username $SUDO_USER --type f --${TIME::-4} 19700101-$BIGDATE $FORMAT --format \"volume path fn $TIMEDATE size groupname username\""

logprint "Script completed"
echo "Script completed"

