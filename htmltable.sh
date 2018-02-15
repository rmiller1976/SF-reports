#!/bin/bash

set -euo pipefail

########################################################
#
# SF tool to create an html formatted table from the command line
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
readonly VERSION="1.0 January 22, 2018"
PROG="${0##*/}"
readonly SFHOME="${SFHOME:-/opt/starfish}"
readonly LOGDIR="$SFHOME/log/${PROG%.*}"
readonly REPORTSDIR="reports"
readonly NOW=$(date +"%Y%m%d-%H%M%S")
readonly REPORTFILE="${REPORTSDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.html"
readonly LOGFILE="${LOGDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.log"

# Global variables
EMAIL=""
EMAILFROM=root
TIME="atime_age"
SFVOLUMENAME=""
QUERY=""
SQLURI=""
VERBOSE=false
EMAIL_TEXT=""

logprint() {
  echo "$(date +%D-%T): $*" >> $LOGFILE
#  echo $*
}

email_alert() {
  (echo -e "$1") | mailx -s "$PROG Failed!" -a $LOGFILE -r $EMAILFROM sf-status@starfishstorage.com,$EMAIL
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

Create Custom HTML Table
$VERSION

This script creates a custom table and formats the output in HTML.

$PROG <SF volume name> [options]

   -h, --help              - print this help and exit

Required Parameters:
  <SF volume name>	   - Starfish volume name

Optional:
   --mtime		   - Use mtime (default = atime)
   --email <recipients>    - Email reports to <recipients> (comma separated)
   --from <sender>	   - Email sender (default: root)

Examples:
$PROG nfs1 --mtime --email a@company.com,b@company.com
Run $PROG, using mtime instead of atime, and email results to users a@company.com and b@company.com

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
  logprint "Parsing input parameters"
  SFVOLUMENAME=$1
  logprint " volume: $SFVOLUMENAME"
  shift
  while [[ $# -gt 0 ]]; do
    case $1 in
    "--mtime")
      TIME="mtime_age"
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
    *)
      logprint "input parameter: $1 unknown. Exiting.."
      fatal "input parameter: $1 unknown. Exiting.."
      ;;
    esac
    shift
  done

  logprint " time: ${TIME::-4}"
  logprint " email recipients: $EMAIL"
}

check_sfvolume_exists() {
  local errorcode
  local sf_vol_list_output
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
      [[ "$VERBOSE" == "true" ]] && logprint "VERBOSE: pg_uri - $SQLURI"
      urifound="true"
    fi
  done < $SFHOME/etc/99-local.ini
  if [[ "$urifound" == "false" ]]; then
    fatal "pg_uri not found in $SFHOME/etc/99-local.ini! Script exiting.."
  fi
}

build_sql_query() {
  logprint "Building SQL query"
  QUERY="WITH query AS (
    SELECT
      volume_name as volume,
      user_name,
      group_name,
      uid,
      gid,
      atime_age,
      mtime_age,
      ROUND(size / (1024 * 1024 * 1024.0), 2) AS \"size (GB)\",
      count,
      cost
    FROM sf_reports.last_time_generic_current
      WHERE user_total_size >= 1024
      AND volume_name = '$SFVOLUMENAME'
      AND (ROUND(size / (1024 * 1024 * 1024.0), 2) > 0)
    ), is_empty AS (
      SELECT
        CASE
          WHEN EXISTS (SELECT * FROM query LIMIT 1) THEN 0
          ELSE 1
        END AS val
    ) SELECT * FROM query
    UNION ALL
    SELECT
      'No results. Decrease Min size per user (GB) and refresh the report' AS volume,
      NULL AS user_name,
      NULL AS group_name,
      NULL AS uid,
      NULL AS gid,
      NULL AS atime_age,
      NULL AS mtime_age,
      NULL AS \"size (GB)\",
      NULL AS count,
      NULL AS cost
    FROM is_empty WHERE is_empty.val = 1;"
  logprint "SQL query set"
}

execute_sql_query() {
  logprint "executing SQL query"
  set +e
  SQL_OUTPUT=`psql $SQLURI -F, -t -A -c "$QUERY"`
  set -e
  logprint "SQL Query executed"
}

format_results() {
  logprint "Formatting results"
  DAY=`date '+%Y%m%d'`
  `echo "$SQL_OUTPUT" | awk -v sfvolume="$SFVOLUMENAME" -v emfrom="$EMAILFROM" -v emto="$EMAIL" -F',' 'BEGIN \
    {
#      print "From: " emfrom
#      print "To: " emto
#      print "MIME-Version: 1.0"
#      print "Content-Type: text/html"
#      printf ("%s %s\n", "Subject: " sfvolume " Report", ENVIRON["DAY"])
      print "<html><body><table border=1 cellspace=0 cellpadding=3>"
      print "<td>Volume</td><td>User Name</td><td>Group Name</td><td>uid</td><td>gid</td><td>atime_age</td><td>mtime_age</td><td>size</td><td>count</td><td>cost</td>"
    } 
    {
      print "<tr>"
      print "<td>"$1"</td>";
      print "<td>"$2"</td>";
      print "<td>"$3"</td>";
      print "<td>"$4"</td>";
      print "<td>"$5"</td>";
      print "<td>"$6"</td>";
      print "<td>"$7"</td>";
      print "<td>"$8"</td>";
      print "<td>"$9"</td>";
      print "<td>"$10"</td>";
      print "</tr>"
    } 
    END \
    {
      print "</table></body></html>"
      print "<br />"
      print "<br />"
    }' > $REPORTFILE` 
  logprint "Results formatted"
}

email_report() {
  local subject="Starfish Report for $SFVOLUMENAME"
  logprint "Emailing results to $EMAIL"
  (echo -e "
From: $EMAILFROM
To: $EMAIL
Subject: $subject")| mailx -s "$subject" -a $REPORTFILE -r $EMAILFROM $EMAIL
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
echo "Step 2: Verify SF volume exists"
check_sfvolume_exists $SFVOLUMENAME
echo "Step 2 Complete"
echo "Step 3: Verify prereq's (postgres login and mailx)"
#echo "here"
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
echo "Step 6: Format results into HTML"
format_results
echo "Step 6 Complete"
echo "Step 7: Email results"
email_report
echo "Step 7 Complete"
echo "Script complete"


