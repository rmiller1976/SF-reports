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

#********************************************************
#  Author Ryan Miller
#  Last modified 2018-04-26
#
#  Report generation framework for Starfish

#********************************************************
#  Version History
#  1.0


#********************************************************
#Import required modules

import psycopg2 # Postgres SQL DB adapter
import ConfigParser # Config file parser
import sys
import os
import time
import datetime
#import pwd # Unix password database access
#import grp # Unix group database access
import argparse # Parser for command line options
import smtplib
import email.message

#********************************************************
# Define fixed variables (Use sparingly!)

sfconfigfile="/opt/starfish/etc/99-local.ini"  
logroot="/opt/starfish/log/sfreports/"        # NEEDS TRAILING '/'
reports_dir="reports/"                        # NEEDS TRAILING '/'

#********************************************************
# Define defaults (these can be overridden in the sql config file)

report_options = {'delimiter':',', 'format':'html', 'from':'root', }

#********************************************************
# Define functions

def readconfigfile(__configfile,*argv):
    try:
        config = ConfigParser.ConfigParser()
        config.read(__configfile)
        return(config.get(*argv))
    except Exception, e:
        logentry(logfile,'FATAL: Can\'t read config file '+str(__configfile))
        logentry(logfile,e)
        sys.exit(1)

def logentry(__filein,__txtin):
    with open(__filein, "a") as f:
        __ts=time.time()
        __ds=datetime.datetime.fromtimestamp(__ts).strftime("%Y%m%d-%H%M%S")
        f.write(__ds+":  "+str(__txtin)+'\n')
        print (__txtin)

#************************************************************
# Start here                                                #
#************************************************************

# Parse command line arguments
# ----------------------------
parser = argparse.ArgumentParser(description='Run a report query for Starfish')
parser.add_argument('query', metavar='{filename}', nargs=1, help='File containing SQL query to run')
args=parser.parse_args()

# Create logfile and initialize with header information and cmdline arguments
# ---------------------------------------------------------------------------
ts=time.time()
st=datetime.datetime.fromtimestamp(ts).strftime("%Y%m%d-%H%M%S")
logfile=logroot+args.query[0].split(".",1)[0]+"-"+st+".log"
if not os.path.exists(logroot):
    try:
        os.makedirs(logroot)
    except Exception, e:
        print ("FATAL: Can't make log root directory - "+logroot)
        print (e)
        sys.exit(1)
if not os.path.exists(logfile):
    try:
        with open(logfile, "w") as l:
            logentry(logfile,"*"*40)
            logentry(logfile,"Script Initiated at "+st)
            logentry(logfile,"Command Line Parameters:")
            for arg in vars(args):
                logentry(logfile,"    "+str(arg)+": "+str(getattr(args,arg)))
    except Exception, e:
        print ("FATAL: Can't create log file - "+logfile)
        print (e)
        sys.exit(1)

# Initialize reports directory
# ----------------------------
current_directory=os.getcwd()
reports_directory=os.path.join(current_directory,reports_dir)
if not os.path.exists(reports_directory):
    try:
        os.makedirs(reports_directory)
    except Exception, e:
        logentry(logfile,'FATAL: Can\'t make reports directory - '+reports_directory)
        logentry(logfile,e)
        sys.exit(1)

# Connect to PostgreSQL database
# ------------------------------
try:
    conn = psycopg2.connect(readconfigfile(sfconfigfile,'pg','pg_uri'))
    logentry(logfile,'Connected to database')
except psycopg2.Error, e:
    logentry(logfile,'FATAL: Unable to connect to the database. The following error message was generated:')
    logentry(logfile,e)
    sys.exit(1)

# Read report options from config file
# ------------------------------------
try:
    config=ConfigParser.ConfigParser()
    config.read(args.query[0])
    logentry(logfile,'Report parameters read from sql config file:')
    for option in config.options('reportoptions'):
        report_options[option]=readconfigfile(args.query[0],'reportoptions',option)
        logentry(logfile,'  '+option+": "+report_options[option])
    logentry(logfile,'All report parameters:')
    for option in report_options:
        logentry(logfile,'  '+option+": "+report_options[option])
except Exception, e:
    logentry(logfile,'FATAL: Unable to read report parameters in '+args.query[0])
    sys.exit(1)
 
# Read SQL query from config file
# -------------------------------
try:
    query=readconfigfile(args.query[0],'sqlquery','query')
    logentry(logfile,'SQL Query read')
except Exception, e:
    logentry(logfile,'FATAL: Unable to read SQL query in '+args.query[0])
    logentry(logfile,e)
    sys.exit(1)

# Read SQL variables from config file
# -----------------------------------
try:
    config=ConfigParser.ConfigParser()
    config.read(args.query[0])
    qv=(config.options('queryvars'))
    logentry(logfile,'SQL variables read')
except Exception, e:
    logentry(logfile,'FATAL: Unable to read SQL variables in '+args.query[0])
    logentry(logfile,e)
    sys.exit(1)
    
# Replace variable placeholders in SQL query with those found in config file
# --------------------------------------------------------------------------
for qvar in qv:
    varvalue=config.get('queryvars',qvar)
    query=query.replace("{{"+qvar+"}}",varvalue)

# Execute SQL query and capture results
# -------------------------------------
column_names=[]
data_rows=[]
with conn.cursor() as cursor:
    logentry(logfile,'Executing SQL Query')
    try:
        cursor.execute(query)
        column_names = [desc[0] for desc in cursor.description]
        for row in cursor:
            data_rows.append(row)
    except Exception, e:
        logentry(logfile,'FATAL: Error during SQL query execution')
        logentry(logfile,e)
        sys.exit(1)

# Generate either csv or html report 
# ----------------------------------
report_file=reports_directory+args.query[0].split(".",1)[0]+"-"+st+"-report."+report_options['format']
try:
    with open(report_file, "w+") as rf:
        if report_options['format'] == "csv":
            rf.write((report_options['delimiter']).join(column_names)+"\n")
            for row in data_rows:
                rf.write(report_options['delimiter'].join(str(element) for element in row)+"\n")
        elif report_options['format'] == "html":
#            rf.write('From: '+report_options['from'])
#            rf.write('\nTo: '+report_options['to'])
#            rf.write('\nSubject: '+report_options['subject'])
#            rf.write('\nMIME-Version:1.0')
#            rf.write('\nContent-Type: text/html')
            rf.write('\n<img src="http://starfishstorage.com/wp-content/uploads/2016/01/StarFishLogo.png" alt="Starfish" id="logo" height="22" width="88.6">')
            rf.write('\n<p></p><b>'+report_options['subject']+'</b><p></p>')
            rf.write('\n<table border="1">')
            rf.write('\n  <tr>')
            for column in column_names:
                rf.write('\n    <th align="center">'+str(column)+'</th>')
            rf.write('\n  </tr>')
            for row in data_rows:
                rf.write('\n  <tr valign="top">')
                for element in row:
                    rf.write('\n    <td align="center">'+str(element)+'</td>')
                rf.write('\n  </tr>')
            rf.write('\n</table>')
        else:
            logentry(logfile,'FATAL: Invalid log format specified')
            sys.exit(1)
    logentry(logfile,'Report generated: '+report_file)
except Exception,e:
    logentry(logfile,'FATAL: Error during report generation')
    logentry(logfile,e)
    sys.exit(1)

# Email report




with open(report_file, "r") as rf:
    msg=email.message.Message()
    msg['Subject']=report_options['subject']
    msg['From']=report_options['from']
    msg['To']=report_options['to']
    msg.add_header('Content-Type', 'text/html')
    msg.set_payload(rf.read())
    from email.mime.text import MIMEText
    attachment=MIMEText(rf.read())
    attachment.add_header('Content-Disposition','attachment',filename=report_file)
    att.attach(attachment)
    s=smtplib.SMTP('localhost')
    s.sendmail(report_options['from'], report_options['to'], msg.as_string())
    s.quit()


