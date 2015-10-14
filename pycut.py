#! /usr/bin/env python
# -*- coding: utf-8 -*-

# Cut out and concatenate sections of a file
# access as pycut.py from mythDVBcut.sh

import sys, os
#print sys.argv


######################
## For tests
##
## echo "0123456789A123456789B123456789C123456789D123456789E123456789F123456789" > ~/test.txt 
## 
## fn1 = './test.txt'
## fn2 = './temp.txt'
## chunks = [ 3, 12, 35, 47, 53, 68  ]
## buflen = 5

## Doesn't recognise '~/test.txt' but this, or full path, seems ok
## python pycut.py './test.txt' './temp.txt' 3 12 35 47 53 68  

# Zambesi HD

#./printcutlist /home/john/Mythrecs/1054_20120328222600.mpg
# Generates byte-mode cutlist for use with Project-X  - and here
#CollectionPanel.CutMode=0

#fn1 = '/mnt/f10store/myth/reca/1054_20120323002600old.mpg'
#fn2 = '/mnt/sam1/recb/1054_20120323002600.mpg'
#chunks = [ 390284804, 4556742872 ]
#buflen = 1024*1024
#
########################

fn1 = sys.argv[1]  # input file
fn2 = sys.argv[2]  # output file
chunks = map( int, sys.argv [ 3 : ] )  # start and end bytes of chunks in infile
buflen = 1024*1024
#bignum = 10000000000                   # for use as EOF if needed
# less likely to be surprised if we use the actual filesize here

print "infile        ", fn1
print "outfile       ", fn2
print "switchpoints  ", chunks

#######################

# sanity checks

chunklen = len(chunks)
if chunklen != 2 * ( chunklen / 2 ) :
#    chunks.append(bignum)
    chunks.append( 1 + os.path.getsize(fn1))
    chunklen = len(chunks)

# adjust chunk-endpoints in the hope of keeping chain linkage in the data intact
n = 1
while n < chunklen :
  chunks[n] += -1
  n += 2
  
n=0
while n < chunklen - 2 :
   if chunks[n] > chunks[n+1] :
      print "Quitting: switchpoints out of order"
      sys.exit(98)
   n += 1

print "Adjusted switchpoints  ", chunks

n = 0
m = 0
offset = [ 0 ]
while n < chunklen - 1 :
   m += 1 + chunks[ n+1 ] - chunks[ n ]
   offset.append( m )
   n += 2

print
print "Byte offsets of cutpoints in output file: ",  offset
print "DB table is recordedseek, mark (framecount) is type 9."
##################################
# Don't touch stuff below here 
## byte numbering starts at 0 and output includes both chunk-endpoints
i=0
j=0
imax = 40     # buffers per star
jmax = 25     # stars per line 
print         # for progress display

chnklim = len(chunks) - 1 
nchnk = 0
chstart=chunks[nchnk]
chend=chunks[nchnk + 1]
bufstart = 0

f1 = open(fn1, 'rb')
f2 = open(fn2, 'wb')

while True :
  data = f1.read(buflen)
  lendat = len(data)
  if lendat == 0 :
       break
  bufend = bufstart + lendat 
  while chstart < bufend :
       if chend <  bufend :
           f2.write(data[chstart - bufstart : chend - bufstart + 1 ])
           nchnk += 2
           if nchnk > chnklim :             # job done
               chstart = bufend + buflen*2  # kill further looping
               break
           
           chstart = chunks[nchnk]
           chend   = chunks[nchnk + 1]
       else :
           f2.write(data[chstart - bufstart :  ])
           chstart = bufend 
 
  bufstart += lendat
  i += 1           # progress display          
  if i > imax :
     sys.stdout.write("*")
     sys.stdout.flush()
     i = 0
     j += 1
     if j > jmax :
        print
        j = 0
 
f1.close()
f2.close()
print
