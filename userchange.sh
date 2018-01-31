#!/bin/bash

set -euo pipefail

########################################################
#
# SF tool to create User Size Change Rate
#
########################################################

# Set variables
readonly VERSION="1.0 January 31, 2018"
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
MINSIZE=""
MINCHANGE=""
DAYSAGO=3

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

User Size Change Rate Report
$VERSION

$PROG [options] --min-size <minimum size> --min-change <minimum change> --days <days>

   -h, --help              - print this help and exit

Required:
   --min-size <minimum size>     - Minimum delta size (GB)
   --min-change <minimum change> - Minimum percent change
   --days <days>		 - Days to look back (default = 3)

Optional:
   --volume <SF volume name>  - Starfish volume name (if not specified, all volumes are included)
   --email <recipients>       - Email reports to <recipients> (comma separated)
   --from <sender>	      - Email sender (default: root)

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
    *)
      logprint "input parameter: $1 unknown. Exiting.."
      fatal "input parameter: $1 unknown. Exiting.."
      ;;
    esac
    shift
  done
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
       -- column below is printed in HTML to produce nice looking result in redash
       '<div class=\"' ||
           CASE
               WHEN (percentage_delta > 0) THEN 'bg-success'
               WHEN (percentage_delta < 0) THEN 'bg-danger'
               ELSE ''
           END
           || ' text-center\">' || ROUND(percentage_delta) || '%</div>'
           AS \"Percent Delta\",
       ROUND(previous_size / (1024*1024*1024.0), 1) AS \"Previous size GB\",
       ROUND(current_size / (1024*1024*1024.0), 1) AS \"Current size GB\",
       ROUND(size_delta / (1024*1024*1024.0), 1) AS \"Delta size GB\"
FROM user_percentage_delta
WHERE ABS(percentage_delta) >= $MINCHANGE
  AND ABS(size_delta) >= $MINSIZE::DECIMAL*(1024*1024*1024.0)
ORDER BY size_delta DESC
LIMIT 20"

#SELECT
#      volume_name as \"Volume\",
#      user_name as \"User Name\",
#      group_name as \"Group Name\",
#      SUM(ROUND((size)::DECIMAL/(1024*1024*1024), 2)) AS \"size (GB)\",
#      SUM(count)::BIGINT AS \"Number of Files\",
#      SUM(ROUND((cost)::DECIMAL,2)) AS \"Cost($)\"
#    FROM sf_reports.last_time_generic_current $volumes_query
#    GROUP BY user_name,volume_name,size,group_name
#    ORDER BY size DESC
#    LIMIT 20"



  logprint "SQL query set"
  logprint $QUERY
}

execute_sql_query() {
  logprint "executing SQL query"
  set +e
  SQL_OUTPUT=`psql $SQLURI -F, -t -A -c "$QUERY"`
  set -e
  logprint "SQL Query executed"
echo -e $SQL_OUTPUT
}

format_results() {
  logprint "Formatting results"
  DAY=`date '+%Y%m%d'`
  `echo "$SQL_OUTPUT" | awk -v emfrom="$EMAILFROM" -v emto="$EMAIL" -F',' 'BEGIN \
    {
      print "From: " emfrom "\n<br>"
      print "To: " emto "\n<br>"
#      print "MIME-Version: 1.0"
#      print "Content-Type: text/html"
      printf ("%s\n<br>", "Subject: User size listing with cost report", ENVIRON["DAY"])
      print "<html><body><table border=1 cellspace=0 cellpadding=3>"
      print "<td>Username</td><td>Volume</td><td>Start Date</td><td>End Date</td><td>Percent Delta</td><td>Previous Size GB</td><td>Current Size GB</td><td>Delta Size GB</td>"
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
  local subject="Report: User size listing with cost"
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


