#!/usr/bin/python
#
# 
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
#  Author Doug Hughes
#  Last modified 2018-03-14
#
# Run simple sql queries while removing the need to find the auth key or
# format the query
# This query outputs the query results, whatever they are, in a CSV output
# format. It does not currently take care of quoting.

import psycopg2
import ConfigParser
import sys
import pwd
import grp
import argparse

def getpgauth():
  try:
    config = ConfigParser.ConfigParser()
    config.read("/opt/starfish/etc/99-local.ini")
    return(config.get('pg','pg_uri'))
  except:
    print "can't read config file to get connection uri. check permissions."
    sys.exit(1)

try:
  conn = psycopg2.connect(getpgauth())
except psycopg2.DatabaseError, e:
  print "unable to connect to the database: %s" % self.fmt_errmsg(e)
  sys.exit(1)

# Parse Arguments
parser = argparse.ArgumentParser()
parser.add_argument("--csv", action="store_true")
parser.add_argument("--delimeter")
parser.add_argument("--query")
parser.parse_args()

args = parser.parse_args()

delimeter = " "
if args.delimeter:
  delimeter = args.delimeter

cur = conn.cursor()

#q = sys.argv[1]
q = args.query
#print "executing query " + q
cur.execute(q)
rows = cur.fetchall()

for row in rows:
  if args.csv:
    print ",".join(str(el) for el in row)
  else:
    print delimeter.join(str(el) for el in row)
    

