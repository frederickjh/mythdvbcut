#!/bin/bash

# Copyright (C) 2014 John Pilkington 
# Uses ideas from scripts posted by Tino Keitel and Kees Cook in the Mythtv lists.
# The suggestion to convert HD mpeg2 files to .mkv, and code to do it, came from Michael Stucky.

# **** I have not tried running this script on an .mkv file that it has created *****

# Usage: "$0" <recording>   ...or...
# ionice -c3 ./"$0" <recording> will reduce io priority and is recommended.
# <recording> is a file recorded by MythTV with a valid DB entry and seektable,
# e.g. 1234_20100405123400.ts or 1234_20100405123400.mpg
# in one of the RECDIRs defined below.
# The output file replaces the input file in the list of recordings, perhaps with a new suffix.
# The input file is renamed to <recording>.old

# This script is essentially a terminal-based replacement for the 'lossless' mpeg2 mythtranscode.
# It was developed from mythcutprojectx but will now cut some recording formats that defeat Project-X.
# All cuts are made at keyframes.  

# Project-X is used here to demux and apply a cutlist, and also to discard all but one video and one audio stream.
# If the audio is initially in .wav format it will be converted to .mp2; mp2 or ac3 will be unchanged.
# For non-mpeg2 video all streams are passed through unchanged, but with cuts applied at the video keyframes.  
  
# The script then clears the cutlist, updates some entries in the database, rebuilds the seek table and creates a new preview.

# If the script is edited to have MAKEMKV=false, the result should be acceptable as a recording within MythTV
# and perhaps as an input to MythArchive.  After MAKEMKV=true, IIUC, the file must be treated as a Video.

# The logfile includes the positions in the new file at which deletions have been made. 

# The script needs to be edited to define some local variables and folders.  
# It will not recognise Storage Groups.

# The Project-X java-based demuxer for mpeg2 video may be packaged for your distro, although perhaps not fully updated.
# A tarball of the most recent version of Project-X can be downloaded from the link near the bottom of this webpage:-

# http://project-x.cvs.sourceforge.net/viewvc/project-x/Project-X/

# I'm running it with java-1.7.0-openjdk under SL7; if you need to build it, install java*jdk-devel and run build.sh

# Some of the comments in this script have been left as reminders of things that might be useful.
 
####################

#. ~/.mythtv/mysql.txt # for DB access info
#PASSWD=`grep "^DBPassword" ~/.mythtv/mysql.txt | cut -d '=' -f 2-`
#PASSWD=mythtv

# mysql.txt is no longer referenced in 0.26+
# The values are now defined within ~/.mythtv/config.xml but it seems easier to
# get them into the script by editing.  They are:

# DBUserName, DBPassword, DBLocalHostName, DBName

# Define the variables used for DB access
#
DBUserName="mythtv"
DBPassword="mythtv" 
DBLocalHostName="localhost" 
DBName="mythconverg"

 
BN="$1"     # "Basename" of file as given in the command line but without special attributes.

MAKEMKV=false   # Do not convert to .mkv.  After running Project-X use mplex to create a DVD-profile file.
# Remultiplexing with mplex fails at higher bitrates as found in HD mpeg2, but mkv can cope.
# MAKEMKV=true     # after ProjectX create an .mkv file

# If TESTRUN is set to true, cutlists will be shown but the recording will be unchanged.

# TESTRUN=true    
TESTRUN=false   # the recording will be processed
if [ $TESTRUN != "false" ] ; then TESTRUN=true
fi

#CUTMODE="FRAMECOUNT"  # Not used here.
CUTMODE="BYTECOUNT"

USEPJX=true  # Can be set to false here if you wish; will be set to false if not mpeg2video (Main)
TIMEOUT=20   # Longest 'thinking time' in seconds allowed before adopting the automatically selected audio stream.

# Variables RECDIR1, TEMPDIR1, RECDIR2, TEMPDIR2, LOGDIR, PROJECTX, HOST1, HOST2, HOST3 need to be customised.
# The TEMPDIRs are used to hold the demuxed recording, so should have a few GiB available. 

# Use $HOSTNAME (as given by running 'hostname') to find out which machine is being used and assign working directories.
HOST1="PresV5000"  # laptop with single disk, FE/BE
HOST2="gateway12"  # twin-disk box, FE/BE
#HOST3="HP-kub"    #
HOST3="HP_Box"     # another single-disk FE/BE

if [ $HOSTNAME = ${HOST1} ] ; then

   RECDIR1=/home/john/Mythrecs
#   TEMPDIR1=/home/john/MythTmp
   TEMPDIR1=/mnt/VidsOnRoot/tmpPX     # Not a good location!

   RECDIR2=${RECDIR1}
   TEMPDIR2=${TEMPDIR1}

   LOGDIR=/home/john/Logs

   #PROJECTX=/path/to/ProjectX.jar (or to a link to it)
   PROJECTX=~/projectx_link

elif [ $HOSTNAME = ${HOST2} ] ; then

   # Section below for twin-disk setup using Project-X. 

   # RECDIR1 and TEMPDIR1 should if possible be on different drive spindles.  Likewise RECDIR2 and TEMPDIR2.
   # This will reduce the load on individual disks and disk-controllers in the IO-heavy processing. 

   RECDIR1=/mnt/f10store/myth/reca
   TEMPDIR1=/mnt/sam1/tempb

   RECDIR2=/mnt/sam1/recb
   TEMPDIR2=/mnt/f10store/myth/tempa

   LOGDIR=/home/John/Documents/PXcutlogs

   #PROJECTX=/path/to/ProjectX.jar (or to a link to it)
   PROJECTX=~/projectx_link
   
elif [ $HOSTNAME = ${HOST3} ] ; then

   RECDIR1=/home/john/SGs/RecsSG1
   TEMPDIR1=/home/john/MythTmp

#   RECDIR2=${RECDIR1}
   RECDIR2=/home/john/SGs/LivetvSG1
   TEMPDIR2=${TEMPDIR1}

   LOGDIR=/home/john/Logs

   #PROJECTX=/path/to/ProjectX.jar (or to a link to it)
   PROJECTX=~/projectx_link
else
   echo "Hostname $HOSTNAME not recognised."
   exit 1
fi 

if [ "$BN" = "-h" ] || [ "$BN" = "--help" ] ; then
echo "Usage: "$0" <recording>"
echo "<recording> is a file known to MythTV as a 'recording' with a valid DB entry and a seektable."
echo "e.g. 1234_20100405123400.ts or 1234_20100405123400.mpg "
echo "in one of the RECDIRs defined in the script."
echo "The input file will be renamed to <recording>.old and"
echo "MythTV will see the output file instead."
exit 0
fi

# exit if .old file exists

if  [ -f ${RECDIR1}/"$BN".old ] ; then 
    echo " ${RECDIR1}/"$BN".old exists: giving up." ; exit 1
fi

if  [ -f ${RECDIR2}/"$BN".old ] ; then 
    echo " ${RECDIR2}/"$BN".old exists: giving up." ; exit 1
fi
 
# Customize with paths to alternative recording and temp folders

cd ${RECDIR1}
RECDIR=${RECDIR1}
TEMP=${TEMPDIR1}
if  [ ! -f "$BN" ] ; then
  cd ${RECDIR2}
  RECDIR=${RECDIR2}
  TEMP=${TEMPDIR2} 
     if  [ ! -f "$BN" ] ; then 
       echo " "$BN" not found.  Giving up"
       cd ~
       exit 1
     fi
fi

# Is it an mpeg-2 recording?
echo
echo
#mythffmpeg -i "$BN" 2>&1 | grep -C 4 Video | tee "temp$$.txt"       # no longer adequate
#mythffmpeg -i "$BN" 2>&1 | grep -B 2 -A 4 Video | tee "temp$$.txt"  # no longer adequate
#mythffmpeg -i "$BN" 2>&1 | grep -B 2 -A 4 "mpeg2video (Main)" | tee "temp$$.txt" # a reminder

# mythffmpeg may fail to identify streams if recording started before, or continued after,
# the period of activity of a part-time channel. 
# ffmpeg usually works for me, but
# 'dd bs=1M skip=numblock1 count=numblock2 if=infile of=outfile' 
# gives a fallback.
# Specify mythffmpeg here because it should be generally available and usually works.

ffmpeg -i "$BN" 2>&1 | grep -B 2 -A 4 "mpeg2video (Main)" | tee "temp$$.txt"

mpeg=$(grep -c "mpeg2video (Main)" temp$$.txt) 
echo "mpeg2video (Main) stream count:  $mpeg"
if [ $mpeg != 1 ] ; then 
  echo "Not mpeg2video (Main), or no or multiple video streams"
  if [ $mpeg = 0 ] ; then
     USEPJX=false  # really ought to see if it's a radio channel.
  else
     exit 1
  fi
fi

if [ $# -lt 3  ]
then
   echo "Needs one or three arguments." 
   echo  
   cat temp$$.txt
   echo
   
#  Examples (BBC FOUR SD, March 2015) :

# $ mythffmpeg -version
# ffmpeg version 2.3.1 Copyright (c) 2000-2014 the FFmpeg developers
# built on Feb 19 2015 23:55:22 with gcc 4.8.2 (GCC) 20140120 (Red Hat 4.8.2-16)

#  Duration: 01:05:59.66, start: 29170.850711, bitrate: 3786 kb/s
#  Program 1 
#    Stream #0:0[0x191]: Video: mpeg2video (Main) ([2][0][0][0] / 0x0002), yuv420p(tv), 704x576 [SAR 16:11 DAR 16:9], max. 15000 kb/s, 25 fps, 25 tbr, 90k tbn, 50 tbc
#    Stream #0:1[0x192](eng): Audio: mp2 ([3][0][0][0] / 0x0003), 48000 Hz, stereo, s16p, 254 kb/s
#    Stream #0:2[0x196](eng): Audio: mp3 ([3][0][0][0] / 0x0003), 0 channels, s16p (visual impaired)
#    Stream #0:3[0x195](eng): Subtitle: dvb_subtitle ([6][0][0][0] / 0x0006)
#    Stream #0:4[0x1c2]: Unknown: none ([5][0][0][0] / 0x0005)

   # Thanks to Christopher Meredith for the basic parsing magic here. 
   VPID=`grep "mpeg2video (Main)"  temp$$.txt | head -n1 | cut -f 1,1 -d']' | sed 's+.*\[++g'`
   # It has to be tweaked for multiple audio streams.  This (with head -n1 ) selects the first listed by ffmpeg.
   # You may alternatively wish to select for language, format, etc.   May be channel, programme, user dependent.
   APID=`grep Audio  temp$$.txt | head -n1 | cut -f 1,1 -d']' | sed 's+.*\[++g'`

   echo -e "Choosing the first audio track listed by \" mythffmpeg -i \".  It may not be the one you want."
   echo -e "\nThe selected values would be "$VPID" and "$APID".  The track info for these is \n"

   grep "$VPID" temp$$.txt
   grep "$APID" temp$$.txt

   echo -e "\nTo accept these values press \"a\", or wait....\n"  
   echo  "If you want to select other values, or to quit and think about it, press another key within $TIMEOUT seconds."
   echo -e "If the format is not mpeg2video all streams will be passed unchanged.\n"
 
   read -t $TIMEOUT -n 1 RESP
   if  [ $? -gt 128 ] ; then    
       RESP="a"
   fi

   if [ "$RESP" != "a" ] ; then
       echo -e "Quitting: if you want to select the PIDs from the command line its expected form is   \n"
       echo " "$0" 1234_20070927190000.ts (or .mpg)  0xvvv 0xaaa " 
       echo -e "                    filename_in_DB           vPID  aPID \n" 
       cd ~
       exit 1
   fi

   echo -e "Going on: processing with suggested values $VPID  $APID \n"
   grep "$VPID" temp$$.txt
   grep "$APID" temp$$.txt
   echo
else
   VPID="$2"
   APID="$3"
fi
########################
# Now do the actual processing

# recordedid is now the prime search key in the DB.
recordedid=$(echo "select recordedid from recorded where basename=\"$BN\";" |
mysql -N -u${DBUserName} -p${DBPassword} -h${DBLocalHostName} $DBName )

# but some tables and utils still need chanid and starttime.
chanid=$(echo "select chanid from recorded where recordedid = '$recordedid' ;" |
mysql -N -u${DBUserName} -p${DBPassword} -h${DBLocalHostName} $DBName )

starttime=$(echo "select starttime from recorded where recordedid = '$recordedid' ;" |
mysql -N -u${DBUserName} -p${DBPassword} -h${DBLocalHostName} $DBName )

#exit
echo -e "\nLogfile listing:\n" > log$$
echo -e "Logfile is log$log$$ \n" | tee -a log$$

echo "chanid ${chanid}   starttime ${starttime}  recordedid ${recordedid} "  >> log$$
starttime=$(echo  ${starttime} | tr -d ': -')

echo "Reformatted starttime ${starttime} " >> log$$

command="mythutil --getcutlist --chanid  $chanid --starttime $starttime -q"
echo "Running: "${command}"" >> log$$
mythutilcutlist=$($(echo ${command}))
echo "${mythutilcutlist}" |tee -a  log$$

shortlist=$(echo ${mythutilcutlist} | sed 's/Cutlist://' )

echo -e "\nIf you want to reset this cutlist, after restoring the .old file 
and resetting the DB with mythsetsize, you could try: \n
mythutil --setcutlist ${shortlist} --chanid  $chanid --starttime $starttime \n
-but seektables from different tools may differ!!" | tee -a log$$

#exit 0

if [ "${mythutilcutlist}" = "Cutlist: " ] ; then
  echo "Cutlist was empty; inserting dummy EOF" >> log$$
  mythutilcutlist=" 9999999 "
fi

echo -e "\nCutframe list from editor: " >> log$$
echo "${mythutilcutlist}" | tr -d [:alpha:] | tr [:punct:] " " | tee  edlist$$ >> log$$

#cat edlist$$ | tee -a log$$
echo

#
#Reverse the sense of the cutlist 
#
echo -n > revedlist$$
for i in  $(cat edlist$$) ; 
do
   if  [ $i -eq 0 ] ;  then
      for j in  $(cat edlist$$) ; 
      do
         if  [ $j != 0 ] ; then echo -n "$j " >> revedlist$$
         fi
      done
   else
      echo -n " 0 " >> revedlist$$
      for j in  $(cat edlist$$) ; 
      do
          echo -n "$j " >> revedlist$$
      done
   fi
   break
done
echo >> revedlist$$
echo -e "\nPassframe (reversed cutframe) list from editor: " >> log$$
cat revedlist$$ | tee -a log$$
 
# For a byte-count cutlist, (PX CutMode=0)
# mark is the frame count in the seektable and is compared here with the frame count defined by the cutlist editor.
# mark type 9 is MARK_GOP_BYFRAME (see eg trac ticket #1088) with adjacent values typically separated by 12 or more,
# so that is presumably the cutpoint frame granularity in bytecount mode. 
# Subjectively the granularity seems smaller, but this may not apply to locally encoded recordings; 
# in dvb-t and similar systems the position of keyframes often appears to depend on pre-transmission edits of content. 
#
# Find the next keyframe (mark type 9) after a position slightly before the frame identified by the cutlist editor.
# The original version, which I have been using for years, effectively had lag=0.
# The 'recordedseek' table doesn't know about recordedid.

lag=4        #  In frames.  Best value might depend on recording source, MythTV version and seektable history.   
scope=2000   #  Sometimes h264 keyframes in the wild are much more widely spaced than expected.
             #  This might only have been true for 'rebuilt' seektables, but the large value should do no harm.
             
for frame in $(cat revedlist$$) 
do
    i=$((${frame} - ${lag})) 
    j=$((${i})) 
    k=$((${i} + ${scope}))
    echo  "select offset, mark from recordedseek
    where chanid=$chanid and starttime='$starttime' and type=9 
    and mark >= ${j} and mark < ${k}  order by offset limit 3 ;" |
    mysql -N -u${DBUserName} -p${DBPassword} -h${DBLocalHostName} ${DBName}          
done > tmp0$$

echo "Full results of DB read:"
cat tmp0$$
cat tmp0$$  | sed -n '1,${p;n;n;}' > tmp1$$  # select lines 1,4,7...
cat tmp0$$  | sed -n '2,${p;n;n;}' > tmp2$$  # 2,5,8...
cat tmp0$$  | sed -n '3,${p;n;n;}' > tmp3$$
rm tmp0$$
             
echo

# write the byte offset and frame number into one-line cutlists.

echo -e "\nActive keyframe passlist via DB.  First is a cut-in:" >> log$$
cut -f2 tmp1$$ | tr "\n" " "  | tee -a log$$ > keylist$$
echo >> keylist$$
echo >> log$$

echo -e "\n2nd keyframes, via DB.  For info only." >> log$$
cut -f2 tmp2$$ |  tr "\n" " "  >> log$$
echo >> log$$

echo -e "\n3rd keyframes, via DB.  For info only." >> log$$
cut -f2 tmp3$$ |  tr "\n" " "  >> log$$
echo >> log$$

echo -e "\nByte offsets of switchpoints in original file, via DB.  First is a cut-in:" >> log$$
cut -f1 tmp1$$ |  tr "\n" " "  >> log$$     
echo >> log$$

echo -e "\nByte offsets of 2nd keyframes, via DB.  Compare with PjX log." >> log$$
cut -f1 tmp2$$ |  tr "\n" " "  >> log$$ 
echo >> log$$

mv tmp1$$ tmp$$  # for use

rm  tmp2$$  tmp3$$ 

# Now apply a one-packet offset to the byte positions passed to Project-X.
# With this 188-byte adjustment in place, the byte-positions that PjX reports 
# having used are exactly equal to those held in the myth DB for 
# the keyframe that next follows the one selected:- i.e. it seems to report the 
# end-of-GOP position when that GOP has been processed. 

# Editing may be frame-accurate if edit-points are the first or last keyframes
# for which a wanted picture is displayed.

FILESIZE=$( du -bL "$BN" | cut -f 1 )

echo -e "\nCreating the cutlist for Project-X with 188 byte adjustment" >> log$$
cut -f1 tmp$$ > PXraw$$
for i in $( cat PXraw$$ ) ;
do 
 echo $(( $i + 188 ))
done > PXadj$$

rm tmp$$

echo "PXraw$$"
cat PXraw$$
echo "EOF"
echo "PXadj$$"
cat PXadj$$
echo "EOF"

# Add a limiting filesize value for use if EOF will be reached
J=$( cat PXraw$$ | wc -l )
echo "PXraw$$ has $J lines"
if [ $(( $J % 2 )) -eq 1 ] ; then
   echo "Adding EOF endmark"
   echo "$FILESIZE" >> PXraw$$
   echo "$FILESIZE" >> PXadj$$
fi

echo "###########  Start of recording " | tee -a log$$
hexdump -C -n 40 -s 0 ${1} | tee -a log$$

echo "###########  PXraw$$ ### " | tee -a log$$
for i in $( cat PXraw$$ ) ;
do 
  echo ${i} | tee -a log$$
  hexdump -C -n 40 -s  $i ${1} | tee -a log$$
done

echo "##########  PXadj$$ ###" | tee -a log$$
for i in $( cat PXadj$$ ) ;
do 
  echo ${i}  | tee -a log$$
  hexdump -C -n 40 -s  $i ${1}  | tee -a log$$
done


# Set up Project-X for bytecount mode
echo "CollectionPanel.CutMode=0" > projx$$
cat PXadj$$ >> projx$$

echo
echo >> log$$

cat projx$$ | tee -a log$$

# Don't apply the 188-byte offset when using pyscript
cat PXraw$$ | tr "\n" " " > bytelist$$
echo >> bytelist$$

# Prepare pyscript$$, the script that would run pycut.py
echo -e " #!/bin/bash\n mv  '$RECDIR/$BN' '$RECDIR/$BN.old' "  > pyscript$$
echo -en " ionice -c3 ~/pycut.py '$RECDIR/$BN.old' '$RECDIR/$BN' " >> pyscript$$
cat bytelist$$  >>  pyscript$$  

if ${USEPJX} ; then
   # Do apply the offset
   cat PXadj$$ | tr "\n" " " > bytelist$$
   echo >> bytelist$$
fi

rm PXraw$$ PXadj$$

# These calculations work only if no streams or frames have been dropped
# so should probably be 'if ! ${USEPJX} ; then'
if ! ${USEPJX} ; then
  echo -e "\nSwitchbyte positions in new file:" >> log$$
  J=0
  S=0                           # 0 or 1 for cut or pass lists
  for i in  $(cat bytelist$$) ;  
  do 
    if [ $S -eq 0 ] ; then
        J=$((J - i))           
        S=1
    else
        J=$((J + i))
        S=0
        echo -n "$J " >> log$$
     fi
  done 
  echo >> log$$

  echo -e "\nSwitchframe positions in new file:" >> log$$
  J=0
  S=0                           # 0 or 1 for cut or pass lists
  for i in  $(cat keylist$$) ;  
  do 
    if [ $S -eq 0 ] ; then
        J=$((J - i))           
        S=1
    else
        J=$((J + i))
        S=0
        echo -n "$J " >> log$$
     fi
  done 
  echo >> log$$
fi
echo
cat log$$

# create script to be run
echo -e "\nThis is pyscript$$, the script that will be run if TESTRUN is false 
and you are not trying to use PjX instead:\n"
cat pyscript$$
chmod +x pyscript$$
echo -e "\nTo run this use ./pyscript$$. \n"

if $TESTRUN ; then
   echo "Quitting because TESTRUN is ${TESTRUN}"
   rm -f cutlist$$
   rm -f temp$$   
   cd ~
   exit 0
fi
###########################

# Now do the actual cutting and concatenation

TEMPHEAD=$TEMP/tempcut${$}
OUTFILEHEAD=$( echo $BN  | tr -d [:alpha:] | tr -d [.] )

if ${USEPJX} ; then

   #################

   # For mpeg2 format only....
   # use ProjectX to de-multiplex selected streams with the created cutlist

   mv  "$BN" "$BN".old

   CMD="ionice -c3 java -jar "$PROJECTX" -name tempcut$$ -id ${VPID},${APID} \
   -out $TEMP -cut projx$$ "$BN".old"
   echo "running: "${CMD}""
   ${CMD}
   # 

   # if demuxed audio is in .wav format (maybe direct camera output) convert it to mp2
   if [ -f $TEMPHEAD.wav ] ; then
      twolame $TEMPHEAD.wav
   fi

   if [ -f $TEMPHEAD.mp2 ] ; then
       TEMPAUDIO=$TEMPHEAD.mp2
   else
       TEMPAUDIO=$TEMPHEAD.ac3
   fi

   if ! ${MAKEMKV} ; then

     # Now remux to MPEG2_PS.  
     # mplex -f 8, mplex -f 9 both use DVD profile. 
     # mplex -f 8 inserts blank DVD-nav sectors, -f 9 does not. 
     #
     # This seems to be a 'corner case' infrequent warning from mplex.  
     # I have never detected a problem during playback but it may make MythArchive fail. 
     # ++ WARN: [mplex] Stream e0: data will arrive too late sent(SCR)=7314 required(DTS)=7200
     # ++ WARN: [mplex] Video e0: buf= 101237 frame=000001 sector=00000050

     OUTFILE=$OUTFILEHEAD.mpg
     echo "Newfile name will be:  $OUTFILE "
     CMD="ionice -c3  mplex -o "$OUTFILE" -V -f 9 $TEMPHEAD.m2v $TEMPAUDIO" 
     echo "running: ${CMD}"
     ${CMD}
   else
     # Remux to .mkv
     # This does play as a recording via uPnP but won't seek or skip in Mythfrontend.

#     OUTFILE=$( echo $BN | sed 's/mpg/mkv/')
     OUTFILE=$OUTFILEHEAD.mkv
     echo "Newfile name will be:  $OUTFILE "
     CMD="ionice -c3 mythffmpeg -fflags +genpts -i $TEMPHEAD.m2v -i $TEMPAUDIO -vcodec copy -acodec copy $OUTFILE " 
     echo "running: ${CMD}"
     ${CMD}
   fi 
   
   # tell mythDB about new filename and set the 'transcoded' flag
   echo "update recorded set basename='${OUTFILE}', transcoded = 1 where recordedid = '$recordedid' ; " |
   mysql -N -u${DBUserName} -p${DBPassword} -h${DBLocalHostName} ${DBName}
       

   # Update the container type, needed for uPnP playback.  Empty will work too, if the transcoded flag is set.
   # This is a HACK pending 0.28 release, when mythutil should do it.  See Ticket #12388
   
   echo "update recordedfile set basename = '${OUTFILE}', container = 'MPEG2-PS' where recordedid = '$recordedid' ;" |
   mysql -N -u${DBUserName} -p${DBPassword} -h${DBLocalHostName} ${DBName}

   CMD="rm  $TEMPHEAD.m2v   $TEMPAUDIO "  # Large; usually best to remove these. 
   echo "running: "${CMD}""
   ${CMD}

   ################

else

   ################
   # Use pyscript, which isn't restricted to mpeg2; but PjX can repair some mpeg2 defects.
   echo "Running : " 
   cat pyscript$$
   echo
   echo
   ./pyscript$$
   echo
   ###############
   OUTFILE=$BN
fi

# Cutting completed.  Now clean up.
CMD="ionice -c3 mythutil  --clearcutlist  --chanid "$chanid" --starttime "$starttime" -q "
echo "running: "${CMD}""
${CMD}
echo -e "Cutlist has been cleared.\n" 

# Rebuild seek table; this now also resets filesize in DB 
# TODO? With MKV output, seektable is probably not useful and may cause problems. 
CMD="ionice -c3 mythcommflag -q --rebuild --file $OUTFILE "
echo "running: "${CMD}""
${CMD}
#echo -e "Seek table has been rebuilt.\n"

#echo  "The cutlist was applied in ** "$CUTMODE" ** mode."
echo -e "Output file is $OUTFILE. \n" 

# Get tech details of output file into the log.
echo -e "\nRunning:  mythffmpeg -i "$OUTFILE" 2>&1 | grep -C 4 Video" | tee -a log$$
echo
mythffmpeg -i "$OUTFILE" 2>&1 | grep -C 4 Video | tee -a log$$
echo

CMD="grep -A 2 Switch log$$ " # put non-ProjectX outfile switchpoints onto terminal
echo "running: "${CMD}""
${CMD}

# The PjX-listed switchpoints are usually 2 frames further apart than those calculated above.
# The editor often sees them about 1 GOP earlier.  Dropped frames and/or seektable problems?  
echo "outfile switchpoints listed by ProjectX"
grep 'cut-in' ${TEMPHEAD}_log.txt 
grep '.Video (m2v):' ${TEMPHEAD}_log.txt  \
   |  awk '{print "Overall :                       " $3, $4,"    " $5}'
cat log$$ >> ${TEMPHEAD}_log.txt

echo -e "\nWhile the .old file still exists you can examine it with\n
hexdump -C -n 40 -s {byteoffset} ${RECDIR}/$BN.old\n
32-bit hexdump may misinterpret start offsets > 2 GiB.\n "

grep "we have" ${TEMPHEAD}_log.txt  # show PX 'errorcount' nearer to end of screen output.
# Values up to a few tens are usually ok, but rare backward jumps in timestamps, 
# which may truncate PX output, give much larger numbers.
# 
echo

CMD="mv ${TEMPHEAD}_log.txt  ${LOGDIR}/${OUTFILE}.PXcut$$.txt"
echo "running: "${CMD}""
${CMD}

rm bytelist$$
rm edlist$$
rm keylist$$
rm revedlist$$
rm pyscript$$
rm projx$$
rm temp$$.txt
rm log$$
rm -f $BN.png   # old preview, which may not exist
cd ~

# mythpreviewgen isn't essential here so put it where failure won't cause other problems.
# Creates a blank frame from .mkv file.

CMD="ionice -c3 mythpreviewgen --chanid "$chanid" --starttime "$starttime" -q "
echo "running: "${CMD}""
${CMD}
echo -e "Preview created.\n"

exit 0
