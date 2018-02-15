#!/bin/bash

set -euo pipefail

########################################################
#
# SF tag report
#
########################################################

# Set variables
readonly VERSION="1.0 February 7, 2018"
PROG="${0##*/}"
readonly NOW=$(date +"%Y%m%d-%H%M%S")
readonly SFHOME="${SFHOME:-/opt/starfish}"
readonly LOGDIR="$SFHOME/log/${PROG%.*}"
readonly LOGFILE="${LOGDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.log"

# Only necessary for report scripts
readonly REPORTSDIR="reports"
readonly REPORTFILE="${REPORTSDIR}/$(basename ${BASH_SOURCE[0]} '.sh')-$NOW.html"

# Global variables
SFVOLUMES=()
EMAIL=""
EMAILFROM=root

# Variables for SQL query scripts
QUERY=""
SQLURI=""

logprint() {
  echo "$(date +%D-%T): $*" >> $LOGFILE
#  echo $*
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

SF Tag Report
$VERSION

$PROG [options] 

   -h, --help              - print this help and exit

Required:
   --email <recipients>		 - Email reports to <recipients> (comma separated)

Optional:
   --volume <SF volume name>  - Starfish volume name (if not specified, all volumes are included)
   --from <sender>	      - Email sender (default: root)

Examples:
$PROG --volume nfs1: --from sysadmin@company.com  --email a@company.com,b@company.com
Run $PROG for all SF volume nfs1:.  Email results to users a@company.com and b@company.com, coming from sysadmin@company.com

EOF
exit 1
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
    *)
      logprint "input parameter: $1 unknown. Exiting.."
      fatal "input parameter: $1 unknown. Exiting.."
      ;;
    esac
    shift
  done

# Check for required parameters
  if [[ $EMAIL == "" ]]; then
    echo "Required parameter missing. Exiting.."
    logprint "Required parameter missing. Exiting.."
    exit 1
  fi
  if [[ ${#SFVOLUMES[@]} -eq 0 ]]; then
    logprint " SF volumes: [All]" 
  else
    logprint " SF volume: ${SFVOLUMES[@]}"
  fi
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
    errorcode="Starfish volume $1 is not a Starfish configured volume. The following process can be followed to create a new Starfish volume for use with this script, if necessary:
1) mkdir /mnt/sf/$1
2) run 'mount -o noatime,vers=3 {isilon_host:/path_to_snapshot_data} /mnt/sf/$1'
3) sf volume add $1 /mnt/sf/$1
4) sf volume list (to verify volume added)
5) sf scan list (to verify SF can access and scan the volume)
6) sf scan pending (to verify the volume does not have a currently running scan)
7) umount /mnt/sf/$1 (unmount volume in preparation for running this script)"
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

# Used for query scripts
build_sql_query() {
  logprint "Building SQL query"
  local volumes_query=""
  if [[ ${#SFVOLUMES[@]} > 0 ]]; then
    volumes_query="WHERE (volume_name = '${SFVOLUMES[0]}')"
    for volume in "${SFVOLUMES[@]:1}"
      do
        volumes_query="$volumes_query OR (volume_name = '$volume')"
      done
  fi
QUERY="
SELECT tag,
sum(round(size/(1024*1024*1024.0),2)) filter (where atime_age = 'Previous Months: 0-1') as \"Previous Months: 0-1\",
sum(round(size/(1024*1024*1024.0),2)) filter (where atime_age = 'Previous Months: 1-3') as \"Previous Months: 1-3\",
sum(round(size/(1024*1024*1024.0),2)) filter (where atime_age = 'Previous Months: 3-6') as \"Previous Months: 3-6\",
sum(round(size/(1024*1024*1024.0),2)) filter (where atime_age = 'Previous Months: 6-12') as \"Previous Months: 6-12\",
sum(round(size/(1024*1024*1024.0),2)) filter (where atime_age = 'Previous Years: 1-2') as \"Previous Years: 1-2\",
sum(round(size/(1024*1024*1024.0),2)) filter (where atime_age = 'Previous Years: 2-3') as \"Previous Years: 2-3\",
sum(round(size/(1024*1024*1024.0),2)) filter (where atime_age = 'Previous Years: > 3') as \"Previous Years: > 3\",
sum(round(size/(1024*1024*1024.0),2)) as \"Totals (GB)\"
FROM sf_reports.tags_current $volumes_query
GROUP BY tag
ORDER BY sum(size) DESC
;
"
  logprint "SQL query set"
  logprint $QUERY
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
  `echo "$SQL_OUTPUT" | awk -v emfrom="$EMAILFROM" -v emto="$EMAIL" -F',' 'BEGIN \
    {
      print "From: " emfrom "\n<br>"
      print "To: " emto "\n<br>"
      print "Subject: Tag report for SF volumes" 
      print "<html><body><table border=1 cellspace=0 cellpadding=3>"
      print "<td>Tag</td><td>Previous Months: 0-1</td><td>Previous Months: 1-3</td><td>Previous Months: 3-6</td><td>Previous Months: 6-12</td><td>Previous Years: 1-2</td><td>Previous Years: 2-3</td><td>Previous Years: >3</td><td>Total (GB)</td>"
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
  if [[ ${#SFVOLUMES[@]} -eq 0 ]]; then
    SFVOLUMES+="[All]"
  fi
  local subject="Tag Report for SF volumes: ${SFVOLUMES[@]}"
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
echo "Step 6: Format results into HTML"
#exit 1
format_results
echo "Step 6 Complete"
echo "Step 7: Email results"
email_report
echo "Step 7 Complete"
echo "Script complete"

