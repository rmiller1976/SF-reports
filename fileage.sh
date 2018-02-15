#!/bin/bash

set -euo pipefail

########################################################
#
# SF tool to report on users with old data
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
readonly VERSION="1.02 December 4, 2017"
PROG="$0"
readonly SFHOME="${SFHOME:-/opt/starfish}"
readonly LOGDIR="logs"
readonly REPORTSDIR="reports"
readonly NOW=$(date +"%Y%m%d-%H%M%S")
readonly LOGFILE="${LOGDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.log"
AGE="1"
TIME="atime_age"
readonly ONETOTHREEMONTHS="Previous Months: 1-3"
readonly THREETOSIXMONTHS="Previous Months: 3-6"
readonly SIXTOTWELVEMONTHS="Previous Months: 6-12"
readonly ONETOTWOYEARS="Previous Years: 1-2"
readonly TWOTOTHREEYEARS="Previous Years: 2-3"
readonly THREEPLUS="Previous Years: > 3" 
TIMEFRAME=""
USERS=""
VOLUME=""
EMAILDOMAIN=""
FORMAT="text"
WHERESTATEMENT=""
EMAIL=true
VERBOSE=false
DRYRUN=false

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

File Age Reporting Script
$VERSION

This script emails all users that have files with mtime or atime older than a specified age on a starfish volume.  It can also be used to output data to files only. 

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
   --noemail          - Instead of emailing, output to files. Files will be named "<username>.txt"
   --emaildomain      - Appends email domain to username for mail delivery. Default is to email to username with no domain appended. 
   --verbose          - Create verbose log, which includes email content.

Examples:
$PROG --volume sfvol
This will email all users with files on Starfish volume sfvol older than 1 month.
The report will break file size and age into time ranges

$PROG --volume sfvol --emaildomain domain.com
This will append @domain.com for emails. So user ffoo with have email sent to ffoo@domain.com

$PROG --volume sfvol --age 3
Emails users with files of atime older than 3 months.

$PROG
Will email all users with files on all Starfish volumes older than 1 month.

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

# Check that mailx exists
logprint "Checking for mailx"
if [[ $(type -P mailx) == "" ]]; then
   logprint "Mailx not found, exiting.."
   echo "mailx is required for this script. Please install mailx with yum or apt-get and re-run" 2>&1
   exit 1
else
   logprint "Mailx found"
fi

# check for postgres login
URIFOUND="false"
while read LINE; do
  if [[ ${LINE:0:6} = "pg_uri" ]]; then
   SQLURI=`echo $LINE | cut -c 8-`
   logprint "pg_uri found"    
   [[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: pg_uri - $SQLURI"
   URIFOUND="true"
  fi
done < $SFHOME/etc/99-local.ini
[[ "$URIFOUND" == "false" ]] && fatal "pg_uri not found in $SFHOME/etc/99-local.ini! Script exiting.."
 
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
      ;;
   "--format")
      shift
      FORMAT=$1
      case $FORMAT in
      "html")
        ;;
      "csv")
        ;;
      "text")
        ;;
      *)
         break
         ;;
      esac
      shift
      ;;
   "--volume")
      check_parameters_value "$@"
      shift
      VOLUME=$1
      [[ $VOLUME == *: ]] && VOLUME=${VOLUME::-1}
      shift
      ;;
   "--noemail")
      shift
      EMAIL=false
      ;;
   "--emaildomain")
      shift
      EMAILDOMAIN=$1
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
   VOLUME="(volume_name = '$VOLUME') AND "
fi
logprint " age: $AGE"
logprint " time: ${TIME::-4}"
logprint " format: $FORMAT"
logprint " email: $EMAIL"
([[ -z $EMAILDOMAIN ]] && logprint " emaildomain: [None]") || logprint " emaildomain: $EMAILDOMAIN"
logprint " verbose: $VERBOSE"

# Define TIMEFRAME for SQL query based on user age selection
case $AGE in
   "1")
     TIMEFRAME="(($TIME = '$ONETOTHREEMONTHS') OR ($TIME = '$THREETOSIXMONTHS') OR ($TIME = '$SIXTOTWELVEMONTHS') OR ($TIME = '$ONETOTWOYEARS') OR ($TIME = '$TWOTOTHREEYEARS') OR ($TIME = '$THREEPLUS'))"
     ;;
   "3")
     TIMEFRAME="(($TIME = '$THREETOSIXMONTHS') OR ($TIME = '$SIXTOTWELVEMONTHS') OR ($TIME = '$ONETOTWOYEARS') OR ($TIME = '$TWOTOTHREEYEARS') OR ($TIME = '$THREEPLUS'))"
     ;;
   "6")
     TIMEFRAME="(($TIME = '$SIXTOTWELVEMONTHS') OR ($TIME = '$ONETOTWOYEARS') OR ($TIME = '$TWOTOTHREEYEARS') OR ($TIME = '$THREEPLUS'))"
     ;;
   "12")
     TIMEFRAME="(($TIME = '$ONETOTWOYEARS') OR ($TIME = '$TWOTOTHREEYEARS') OR ($TIME = '$THREEPLUS'))"
     ;;
   "24")
     TIMEFRAME="(($TIME = '$TWOTOTHREEYEARS') OR ($TIME = '$THREEPLUS'))"
     ;;
   "36")
     TIMEFRAME="(($TIME = '$THREEPLUS'))"
     ;;
esac

# Build SQL query to get users based on volume and age specifie
USER_QUERY="WITH QUERY AS (
  SELECT DISTINCT
    USER_NAME 
  FROM SF_REPORTS.LAST_TIME_GENERIC_CURRENT
  WHERE $VOLUME $TIMEFRAME), is_empty AS (
   SELECT
     CASE
       WHEN EXISTS (SELECT * FROM query LIMIT 1) THEN 0
       ELSE 1
     END AS val
) SELECT * from query;"

# Execute SQL query to get users
logprint "Querying for user list"
[[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: $USER_QUERY"
[[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: psql $SQLURI -t -A -c $USER_QUERY"
USERS=`psql $SQLURI -t -A -c "$USER_QUERY"`
ALLUSERS=($USERS)
[[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: User list: ${ALLUSERS[*]}"

# Make reports directory if it doesn't exist, and clear it out
[[ ! -e $REPORTSDIR ]] && mkdir $REPORTSDIR

# Create and run SQL queries for each user
for INDIVIDUAL_USER in "${ALLUSERS[@]}"; do
  EMAILUSERNAME=$INDIVIDUAL_USER
  echo "Executing query for user: $EMAILUSERNAME"
  INDIVIDUAL_USER="(USER_NAME = '$INDIVIDUAL_USER')"
  case $TIME in
    "atime_age")
      EMAILHEADER="Dear $EMAILUSERNAME,\nThe following is a report showing size and number of files that were last accessed prior to $AGE month(s) ago.\nThis report was generated on $(date "+%D").\n"
    ;;
    "mtime_age")
      EMAILHEADER="Dear $EMAILUSERNAME,\nThe following is a report showing size and number of files that were last modified prior to $AGE month(s) ago.\nThis report was generated on $(date "+%D").\n"
    ;;
  esac

  # Build SQL 'WHERE' statement
  SQL_QUERY="WITH QUERY AS (
   SELECT
      VOLUME_NAME,
      USER_NAME,
      GROUP_NAME,
      UID,
      GID,
      $TIME,
      ROUND(SUM(SIZE) / (1024 * 1024 * 1024.0),2) AS \"SIZE(GB)\",
      SUM(COUNT) AS \"COUNT\"
    FROM SF_REPORTS.LAST_TIME_GENERIC_CURRENT 
   WHERE $VOLUME $TIMEFRAME AND $INDIVIDUAL_USER
   GROUP BY VOLUME_NAME,USER_NAME,GROUP_NAME,UID,GID,$TIME
   ORDER BY user_name,$TIME
  ), is_empty AS (
     SELECT
       CASE
         WHEN EXISTS (SELECT * FROM query LIMIT 1) THEN 0
         ELSE 1
       END AS val
  ) SELECT * FROM query
  UNION ALL
  SELECT
     'No results.' AS volume,
     NULL as user_name,
     NULL as group_name,
     NULL as uid,
     NULL as gid,
     NULL as $TIME,
     NULL as \"size (GB)\",
     NULL as count
  FROM is_empty WHERE is_empty.val = 1;"

  [[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: Primary SQL Query Built for $EMAILUSERNAME"
  [[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: $SQL_QUERY"
  logprint " Running query for $EMAILUSERNAME"
  if [ $FORMAT == "text" ]; then
     [[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: psql $SQLURI -A -t -c $SQL_QUERY" 
     QUERYOUTPUT=`psql $SQLURI -A -t -c "$SQL_QUERY"`
     [[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: Query output in $QUERYOUTPUT"
  fi

# Feed query output to awk and process
  USERDATA=`echo "$QUERYOUTPUT" | awk -F '|' '\
  BEGIN {
    FS="|"
  }
  {
    volbysize[$1,$6] = $7
    volbycnt[$1,$6] = $8
    totalsizebyvol[$1] += $7
    totalcntbyvol[$1] += $8
    categories[$6]++
    volumes[$1]++
  }
  END {
    for (volume in volumes) 
      {
        sortorder[1] = ""
        sortorder[2] = ""
        sortorder[3] = ""
        sortorder[4] = ""
        sortorder[5] = ""
        sortorder[6] = ""
        print "Volume: ", volume,"   "
        for (category in categories) 
          {
            myindex = volume SUBSEP category
            if (volbycnt[myindex] > 0)
               {
                 if (category == "Previous Months: 1-3")
                   sortorder[1] = "1 to 3 Months: "volbysize[myindex]"(GB), "volbycnt[myindex]" items"
                 if (category == "Previous Months: 3-6")
                   sortorder[2] = "3 to 6 months: "volbysize[myindex]"(GB), "volbycnt[myindex]" items"
                 if (category == "Previous Months: 6-12")
                   sortorder[3] = "6 to 12 months: "volbysize[myindex]"(GB), "volbycnt[myindex]" items"
                 if (category == "Previous Years: 1-2")
                   sortorder[4] = "12 to 24 months: "volbysize[myindex]"(GB), "volbycnt[myindex]" items"
                 if (category == "Previous Years: 2-3")
                   sortorder[5] = "24 to 36 months: "volbysize[myindex]"(GB), "volbycnt[myindex]" items"
                 if (category == "Previous Years: > 3")
                   sortorder[6] = "36+ months: "volbysize[myindex]"(GB), "volbycnt[myindex]" items"
               }
          }
        if (length(sortorder[1]) > 0)
          print sortorder[1]
        if (length(sortorder[2]) > 0)
          print sortorder[2]
        if (length(sortorder[3]) > 0)
          print sortorder[3]
        if (length(sortorder[4]) > 0)
          print sortorder[4]
        if (length(sortorder[5]) > 0)
          print sortorder[5]
        if (length(sortorder[6]) > 0)
          print sortorder[6]
        print ""
      } 
  }
  '`
  [[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: User data is: $USERDATA"

# Email processed data or write to reports file
  [[ $EMAILDOMAIN ]] && EMAILUSERNAME="${EMAILUSERNAME}@${EMAILDOMAIN}"
  case $EMAIL in
     "true")
# for debugging only
#        EMAILUSERNAME="rmiller@starfishstorage.com"
        logprint " Emailing results for $EMAILUSERNAME"
        (echo -e "$EMAILHEADER\n$USERDATA" ) | mailx -s "Starfish File Age Report for $EMAILUSERNAME" -r root $EMAILUSERNAME 
        ;;
     "false")
        logprint "Sending results to output file(s)"
        OUTPUT_FILENAME="$REPORTSDIR/${EMAILUSERNAME}.txt"
        echo -e "$EMAILHEADER\n$USERDATA" > $OUTPUT_FILENAME
        ;;
  esac
done
logprint "Script completed"
echo "Script completed"

