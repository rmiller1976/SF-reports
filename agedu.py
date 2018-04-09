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
import os
import argparse
import locale



def getpgauth():
  config = ConfigParser.ConfigParser()
  config.read("/opt/starfish/etc/99-local.ini")
  return(config.get('pg','pg_uri'))

def ins_sort(k):
    for i in range(1,len(k)):    #start at beginning of list
        j = i                    #reducing i directly will break for loop, so reduce copy j 
        temp = k[j]              #temp will be used for comparison with previous items, and sent to the place it belongs
	#j>0 : no point going till k[0] since there is no seat available on its left, for temp
        while j > 0 and temp < k[j-1]: 
	    #Move the bigger item 1 step right to make room for temp
            k[j] = k[j-1] 
            #take k[j] all the way left to the place where it has a smaller/no value to its left.
            j=j-1 
        k[j] = temp
    return k

#--------------------------------------------------------------------------------------------

# connect to Postgres
try:
  conn = psycopg2.connect(getpgauth())
except psycopg2.DatabaseError, e:
  print "unable to connect to the database: %s" % self.fmt_errmsg(e)
  sys.exit(1)

locale.setlocale(locale.LC_ALL, 'C')

# Parse Arguments
parser = argparse.ArgumentParser()
parser.add_argument("--volume")
parser.add_argument("--path")
parser.parse_args()

args = parser.parse_args()

# Setup DB cursor
cur = conn.cursor()

# optional string appends to WHERE clause
wlist = []

# where clause
wappend = ""

# Check for volume
if args.volume:
  volume = args.volume
  wlist.append("v.name = '%s'" % (args.volume))
else:
  print "use of --volume is recommended"

if args.path:
  dirname = args.path
  wlist.append("d.path like '%s'" % (args.path))

if len(wlist) > 0:
  wappend = "WHERE " + " AND ".join(wlist)


# we probably don't need this. Leaving it in an if for later
qdirs = 0

if qdirs:
  qdirs = """SELECT d.size, extract(epoch from d.atime), m.path, d.path
  FROM sf_volumes.volume v 
       JOIN sf.dir_current d ON v.id = d.volume_id
       JOIN sf_volumes.mount m ON m.volume_id = v.id
  %s
  ORDER BY d.path""" % (wappend)

  cur.execute(qdirs)
  rows = cur.fetchall()

  # open temp file
  d1 = open("/tmp/d1", "w+")
  for row in rows:
    d1.write( "%d %d %s/%s\n" % (row))
  d1.close()
    

# now do file list
qfiles = """SELECT f.size, extract(epoch from f.atime), v.name, d.path, f.name
FROM sf.file_current f JOIN sf_volumes.volume v ON v.id = f.volume_id 
     JOIN sf.dir_current d ON f.parent_id = d.id
%s
ORDER BY v.name, d.path COLLATE "C", d.name COLLATE "C", f.name COLLATE "C" """ % (wappend)

# debugging
print qfiles
#os.exit(0)

cur.execute(qfiles)
rows = cur.fetchall()

# open temp file
d2 = open("/tmp/d2", "w+")
# print header
d2.write("agedu dump file. pathsep=2f\n")
# initialize path to do directory output when a new one is entered
savepath = ""
for row in rows:
  dpath = row[3]
  if dpath != savepath:
    # note, this gets the atime of the first element in the directory and set
    # the directory size to 1024. That's really ok to a reasonable approximation.
    d2.write("1024 %d %s:/%s\n" % (row)[1:-1])
    savepath = dpath
  if dpath == "":
    # absorb the / dir without doubling
    d2.write("%d %d %s:/%s%s\n" % (row))
  else:
    d2.write("%d %d %s:/%s/%s\n" % (row))

d2.close()
    

#d3 = open("/tmp/d3", "w")
# print header
#d3.write("agedu dump file. pathsep=2f\n")
#d3.close()
#
#os.system("LC_ALL='C' sort -k3,30 /tmp/d1 /tmp/d2 >> /tmp/d3")
