#!/usr/bin/python
#
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
#  Author Ryan Miller
#  Last modified 2018-04-10
#
#  Report generation framework for Starfish




#********************************************************
#Import required modules

import psycopg2 # Postgres SQL DB adapter
import ConfigParser # Config file parser
import sys
import os
import time
import datetime
import pwd # Unix password database access
import grp # Unix group database access
import argparse # Parser for command line options

#********************************************************
# Define fixed variables (Use sparingly!)

logroot="/opt/starfish/log/sfreports/" # NEEDS TRAILING '/'
reports_dir="reports/"                 # NEEDS TRAILING '/'

#********************************************************
# Define functions

def getpgauth():
    try:
        config = ConfigParser.ConfigParser()
        config.read("/opt/starfish/etc/99-local.ini")
        return(config.get('pg','pg_uri'))
    except:
        print('FATAL: Can\'t read config file to get connection uri')
        sys.exit(1)

def logentry(__a__,__b__):
    with open(__a__, "a") as f:
        f.write(str(__b__)+'\n')

#************************************************************
# Start here

parser = argparse.ArgumentParser(description='Run a report query for Starfish')
parser.add_argument('email', type=str, metavar='{recipient(s)}', nargs=1, help='Email report to {recipient(s)} (comma separated)')
parser.add_argument('query', metavar='{filename}', nargs=1, help='File containing SQL query to run')
parser.add_argument('--csv', action='store_true', help='Output in CSV format (default is HTML)')
parser.add_argument('--delimiter', type=str, default=',', metavar='"x"', help='Set delimiter as x for CSV output (\'x\' can be any character. Default delimiter = ,)')
parser.add_argument('--from', type=str, metavar='{address}', nargs=1, help='Email address report should be sent from')
args=parser.parse_args()

ts=time.time()
st=datetime.datetime.fromtimestamp(ts).strftime("%Y%m%d-%H%M%S")
logfile=logroot+args.query[0].split(".",1)[0]+"-"+st+".log"
if not os.path.exists(logroot):
    try:
        os.makedirs(logroot)
    except:
        print ("FATAL: Can't make log root directory - "+logroot)
        sys.exit(1)
if not os.path.exists(logfile):
    try:
        with open(logfile, "w") as l:
            pass
    except:
        print ("FATAL: Can't create log file - "+logfile)
        sys.exit(1)

logentry(logfile,"*"*60)
logentry(logfile,"Script Initiated at "+st)
logentry(logfile,"Command Line Parameters:")
for arg in vars(args):
    logentry(logfile,"    "+str(arg)+": "+str(getattr(args,arg)))

try:
    logentry(logfile,'Connecting to the PostgreSQL database..')
    conn = psycopg2.connect(getpgauth())
    logentry(logfile,'Connected to database')
except psycopg2.Error, e:
    logentry(logfile,'FATAL: Unable to connect to the database. The following error message was generated:')
    logentry(logfile,e)
    sys.exit(1)

with open(args.query[0], "r") as queryfile:
    query=queryfile.read()
    logentry(logfile,'SQL Query read')

column_names=[]
data_rows=[]
with conn.cursor() as cursor:
    logentry(logfile,'Executing SQL Query')
    cursor.execute(query)
    column_names = [desc[0] for desc in cursor.description]
    for row in cursor:
        data_rows.append(row)

current_directory=os.getcwd()
reports_directory=os.path.join(current_directory,reports_dir)
if not os.path.exists(reports_directory):
    try:
        os.makedirs(reports_directory)
    except:
        print ("FATAL: Cant make reports directory - "+reports_directory)
        sys.exit(1)

if args.csv:
    report_file=reports_directory+args.query[0].split(".",1)[0]+"-"+st+"-report.csv"
    with open(report_file, "w") as rf:
        rf.write(args.delimiter.join(column_names)+"\n")
        for row in data_rows:
            rf.write(args.delimiter.join(str(element) for element in row)+"\n")
else:
    report_file=reports_directory+args.query[0].split(".",1)[0]+"-"+st+"-report.html"
    

  






