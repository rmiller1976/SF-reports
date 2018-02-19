#!/bin/bash

set -euo pipefail

########################################################
#
# SF tool to create User Size Change Rate Report
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
readonly VERSION="1.01 February 19, 2018"
PROG="${0##*/}"
readonly SFHOME="${SFHOME:-/opt/starfish}"
readonly LOGDIR="$SFHOME/log/${PROG%.*}"
readonly REPORTSDIR="reports"
readonly NOW=$(date +"%Y%m%d-%H%M%S")
readonly REPORTFILE="${REPORTSDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.html"
readonly LOGFILE="${LOGDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.log"

# Global variables
SFVOLUMES=()
EMAIL=""
EMAILFROM=root
QUERY=""
SQLURI=""
SQL_OUTPUT=""
MINSIZE=""
MINCHANGE=""
DAYSAGO=3
LIMIT=20

logprint() {
  echo "$(date +%D-%T): $*" >> $LOGFILE
}

email_alert() {
  (echo -e "$1") | mailx -s "$PROG Failed!" -a $LOGFILE -r $EMAILFROM $EMAIL
}

email_notify() {
  (echo -e "$1") | mailx -s "$PROG Completed Successfully" -r $EMAILFROM $EMAIL
}

fatal() {
  local msg="$1"
  echo "${msg}" >&2
  exit 1
}

check_parameters_value() {
  local param="$1"
  [ $# -gt 1 ] || fatal "Missing value for parameter ${param}"
}

usage () {
  local msg="${1:-""}"
  if [ ! -z "${msg}" ]; then
    echo "${msg}" >&2
  fi
  cat <<EOF

User Size Change Rate Report
$VERSION

$PROG [options] --min-size <minimum size> --min-change <minimum change> --days <days>

   -h, --help              - print this help and exit

Required:
   --min-size <minimum size>     - Minimum delta size (GB)
   --min-change <minimum change> - Minimum percent change
   --days <days>		 - Days to look back (default = 3)
   --email <recipients>		 - Email reports to <recipients> (comma separated)

Optional:
   --volume <SF volume name>  - Starfish volume name (if not specified, all volumes are included)
   --from <sender>	      - Email sender (default: root)
   --limit <#>		      - Limit to # results (default: 20)

Examples:
$PROG --min-size 1 --min-change 1 --days 5 --email a@company.com,b@company.com
Run $PROG for all SF volumes, looking for at least 1 GB delta size, 1% data change, and looking back 5 days.  Email results to users a@company.com and b@company.com

EOF
exit 1
}

check_path_exists () {
  if [[ ! -d "$1" ]]; then
    logprint "Directory $1 does not exist, exiting.."
    echo "Directory $1 does not exist. Please create this path and re-run"
    exit 1
  else
    logprint "Directory $1 found"
  fi
}

parse_input_parameters() {
  local errorcode
  local volume
  logprint "Parsing input parameters"
  while [[ $# -gt 0 ]]; do
    case $1 in
    "--volume")
      check_parameters_value "$@"
      shift
      volume=$1
      [[ $volume == *: ]] && volume=${volume::-1}
      SFVOLUMES+=("$volume")
      ;;
    "--email")
      check_parameters_value "$@"
      shift
      EMAIL=$1
      ;;
    "--from")
      check_parameters_value "$@"
      shift
      EMAILFROM=$1
      ;;
    "--min-size")
      check_parameters_value "$@"
      shift
      MINSIZE=$1
      ;;
    "--min-change")
      check_parameters_value "$@"
      shift
      MINCHANGE=$1
      ;;
    "--days")
      check_parameters_value "$@"
      shift
      DAYSAGO=$1
      ;;      
    "--limit")
      check_parameters_value "$@"
      shift
      LIMIT=$1
      ;;
    *)
      logprint "input parameter: $1 unknown. Exiting.."
      fatal "input parameter: $1 unknown. Exiting.."
      ;;
    esac
    shift
  done
  if [[ $MINSIZE == "" ]] || [[ $MINCHANGE == "" ]] || [[ $EMAIL == "" ]]; then
    echo "Required parameter missing. Exiting.."
    logprint "Required parameter missing. Exiting.."
    exit 1
  fi
  if [[ ${#SFVOLUMES[@]} -eq 0 ]]; then
    logprint " SF volumes: [All]" 
  else
    logprint " SF volume: ${SFVOLUMES[@]}"
  fi
  logprint " Minimum size: $MINSIZE"
  logprint " Minimum change: $MINCHANGE"
  logprint " Days back: $DAYSAGO"
  logprint " Limit: $LIMIT"
  logprint " email from: $EMAILFROM"
  logprint " email recipients: $EMAIL"
}

verify_sf_volume() {
  local sf_vol_list_output
  local errorcode
  logprint "Checking if $1 exists in Starfish"
  set +e
  sf_vol_list_output=$(sf volume list | grep $1)
  set -e
  if [[ -z "$sf_vol_list_output" ]]; then
    errorcode="Starfish volume $1 is not a Starfish configured volume."
    logprint "$errorcode"
    echo -e "$errorcode"
    email_alert "$errorcode"
    exit 1
  fi
  logprint "$1 found in Starfish"
}

check_mailx_exists() {
  logprint "Checking for mailx"
  if [[ $(type -P mailx) == "" ]]; then
    logprint "Mailx not found, exiting.."
    echo "mailx is required for this script. Please install mailx with yum or apt-get and re-run" 2>&1
   exit 1
  else
    logprint "Mailx found"
  fi
}

check_postgres_login() {
  local urifound
  urifound="false"
  while read LINE; do
    if [[ ${LINE:0:6} = "pg_uri" ]]; then
      set +e
      SQLURI=`echo $LINE | cut -c 8-`
      set -e
      logprint "pg_uri found"    
      urifound="true"
    fi
  done < $SFHOME/etc/99-local.ini
  if [[ "$urifound" == "false" ]]; then
    fatal "pg_uri not found in $SFHOME/etc/99-local.ini! Script exiting.."
  fi
}

build_sql_query() {
  logprint "Building SQL query"
  local volumes_query="(volume_name is not null)"
  if [[ ${#SFVOLUMES[@]} > 0 ]]; then
    volumes_query="(volume_name = '${SFVOLUMES[0]}')"
    for volume in "${SFVOLUMES[@]:1}"
      do
        volumes_query="$volumes_query OR (volume_name = '$volume')"
      done
  fi
  QUERY="
WITH runtime_range AS (
    SELECT MIN(run_time) AS start,
           MAX(run_time) AS end
    FROM sf_reports.last_time_generic_history
    WHERE run_time >= (now() - interval '$DAYSAGO days') 
), user_size_for_chosen_days AS (
    SELECT volume_name,
           user_name,
           run_time,
           SUM(SIZE) AS size
    FROM sf_reports.last_time_generic_history 
    INNER JOIN runtime_range ON run_time = runtime_range.start OR run_time = runtime_range.end
    WHERE $volumes_query
    GROUP BY volume_name,
             user_name,
             run_time
), user_size_delta AS (
    SELECT volume_name,
           user_name,
           (lag(run_time) OVER (PARTITION BY user_name, volume_name ORDER BY run_time))::date AS start_date,
           run_time::date AS end_date,
           size,
           size - lag(size) OVER (PARTITION BY user_name, volume_name ORDER BY run_time) AS size_delta
    FROM user_size_for_chosen_days
), user_percentage_delta AS (
    SELECT user_name,
           volume_name,
           start_date,
           end_date,
           CASE WHEN (size - size_delta) = 0 THEN
                CASE WHEN size_delta = 0 THEN 0
                ELSE 'Infinity'::float
                END
           ELSE
                (size_delta * 100) / (size - size_delta)
           END AS percentage_delta,
           (size - size_delta) AS previous_size,
           size AS current_size,
           size_delta
   FROM user_size_delta
)
SELECT 
       user_name AS \"User Name\",
       volume_name AS \"Volume\",
       start_date AS \"Start Date\",
       end_date AS \"End Date\",
       ROUND(percentage_delta) AS \"Percent Delta\",
       ROUND(previous_size / (1024*1024*1024.0), 1) AS \"Previous size GB\",
       ROUND(current_size / (1024*1024*1024.0), 1) AS \"Current size GB\",
       ROUND(size_delta / (1024*1024*1024.0), 1) AS \"Delta size GB\"
FROM user_percentage_delta
WHERE ABS(percentage_delta) >= $MINCHANGE
  AND ABS(size_delta) >= $MINSIZE::DECIMAL*(1024*1024*1024.0)
ORDER BY size_delta DESC
LIMIT $LIMIT"
  logprint "SQL query set"
  logprint $QUERY
}

execute_sql_query() {
  local errorcode
  logprint "executing SQL query"
  set +e
  SQL_OUTPUT=`psql $SQLURI -F, -A -H -c "$QUERY" > $REPORTFILE 2>&1`
  errorcode=$?
  set -e
  if [[ $errorcode -eq 0 ]]; then
    logprint "SQL query executed successfully"
  else
    logprint "SQL query failed with errorcode: $errorcode. Exiting.."
    echo -e "SQL query failed with errorcode: $errorcode. Exiting.."
    email_alert "SQL query failed with errorcode: $errorcode"
    exit 1
  fi
}

email_report() {
  if [[ ${#SFVOLUMES[@]} -eq 0 ]]; then
    SFVOLUMES+="[All]"
  fi
  local subject="Starfish User Size Change Rate Report (Minsize=$MINSIZE, Minchange=$MINCHANGE, Days=$DAYSAGO, Limit=$LIMIT)"
  logprint "Emailing results to $EMAIL"
  (echo -e "
From: $EMAILFROM
To: $EMAIL
Subject: $subject") | mailx -s "$subject" -a $REPORTFILE -r $EMAILFROM $EMAIL
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

# Check for reports directory, and create if it doesn't exist
[[ ! -e $REPORTSDIR ]] && mkdir $REPORTSDIR

# start script
echo "Step 1: Parse input parameters"
parse_input_parameters $@
echo "Step 1 Complete"
  if [[ ${#SFVOLUMES[@]} > 0 ]]; then
    echo "Step 1b: Verify volumes exist in SF"
    for volume in "${SFVOLUMES[@]}"
      do
        verify_sf_volume $volume
      done
    echo "Step 1b Complete"
  fi
echo "Step 2 Complete"
echo "Step 3: Verify prereq's (postgres login and mailx)"
check_postgres_login
echo "Step 3 - postgres login verified"
check_mailx_exists
echo "Step 3 - mailx verified"
echo "Step 3 Complete"
echo "Step 4: Build SQL query"
build_sql_query
echo "Step 4 Complete"
echo "Step 5: Execute SQL query"
execute_sql_query
echo "Step 5 Complete"
echo "Step 6: Email results"
email_report
echo "Step 6 Complete"
echo "Script complete"


