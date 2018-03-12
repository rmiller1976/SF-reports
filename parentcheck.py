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

import psycopg2
import ConfigParser
import sys
import pwd
import grp

def getpgauth():
  config = ConfigParser.ConfigParser()
  config.read("/opt/starfish/etc/99-local.ini")
  return(config.get('pg','pg_uri'))

try:
  conn = psycopg2.connect(getpgauth())
except:
  print "I am unable to connect to the database"
  sys.exit(1)

cur = conn.cursor()

# get table name/type for relationship for query
def ctype(tname, volume):
  # Find all parent/child relationships at least 3 deep from the parent in %volume where the owner uid 
  # is different or the gid is different. Exclude any where the owner is root 

  q = "SELECT a.path, b.name, a.uid as P_UID, b.uid as C_UID, a.gid as P_GID, b.gid as C_GID from sf.dir_current a INNER JOIN sf.%s_current b on a.id = b.parent_id INNER JOIN sf_volumes.volume v on a.volume_id = v.id where v.name = '%s' and a.volume_id = b.volume_id and a.name != '' and (a.uid != b.uid OR a.gid != b.gid) and a.uid != 0 and b.uid != 0 LIMIT 30;" % (tname, volume)
  # print "executing " + q
  cur.execute(q)
  rows = cur.fetchall()

  print "parents and mismatched %s children:\n"%(tname)
  for row in rows:
    try:
      name1 = pwd.getpwuid(int(row[2]))[0]
    except:
      name1 = row[2]
    try:
      name2 = pwd.getpwuid(int(row[3]))[0]
    except:
      name2 = row[3]
    try:
      gid1 = grp.getgrgid(int(row[4]))[0]
    except:
      gid1 = row[4]
    try:
      gid2 = grp.getgrgid(int(row[5]))[0]
    except:
      gid2 = row[5]

    print "%s/%s\t%-8s %-8s %-8s %-8s"%(row[0], row[1], name1, name2, gid1, gid2)


# get dir/dir pairs
rows = ctype("dir", "nfs1")
# get dir/file pairs
rows = ctype("file", "nfs1")


