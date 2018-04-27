# The [reportoptions] section lists options for the report. Valid entries are:
#  subject={subject of email message}
#  to={email recipient(s)}            # comma separateed list
#  from={email sender}   	      # default = root          
#  format={html OR CSV}               # default = html
#  disposition=inline OR attachment   # will be reverted to attachment for csv
#  delimiter={delimiter character for CSV output}

[reportoptions]
subject=Report: User size change rate
to=sfadmin@company.com
from=sf_server@company.com
format=csv
disposition=attachment
delimiter=,


# The [queryvars] section specifies the values of variables found in the sqlquery portion.

[queryvars]
number_of_days_to_look_back=90
minimum_delta_size_gb=0
minimum_percent_change=0


# The [sqlquery] section provides the report engine with the sql query to run.
# It is specified with 'query='.
# Note that every line should have at least one space of white space at the start, otherwise a parser error will be generated
# Also, variables specified in the [queryvars] section should be surrounded by dual curly braces {{ and }}

[sqlquery]
query=WITH runtime_range AS (
    SELECT MIN(run_time) AS start,
           MAX(run_time) AS end
    FROM sf_reports.last_time_generic_history
    WHERE run_time >= (now() - interval '{{number_of_days_to_look_back}} days')
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
       user_name,
       volume_name AS "Volume",
       start_date AS "Start Date",
       end_date AS "End Date",
           ROUND(percentage_delta)
           AS "Percent Delta",
       ROUND(previous_size / (1024 * 1024 * 1024.0), 1) AS "Previous size GB",
       ROUND(current_size / (1024 * 1024 * 1024.0), 1) AS "Current size GB",
       ROUND(size_delta / (1024 * 1024 * 1024.0), 1) AS "Delta size GB"
 FROM user_percentage_delta
 WHERE ABS(percentage_delta) >= {{minimum_percent_change}}
  AND ABS(size_delta) >= {{minimum_delta_size_gb}}::DECIMAL * (1024 * 1024 * 1024.0)
 ORDER BY size_delta DESC;
