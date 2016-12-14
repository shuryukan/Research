#!/bin/bash

PATH=$PATH:..:.
thisdir=$(dirname $(realpath $0))

features=$1
#the MFCC corresponds to sphinx 12 MFCC + Energy
# sphinx=the mfcc was computed by the java sphinx 4 tools
# 1: static coefficients are present in the file
# 1: energy coefficient is present in the file
# 0: delta coefficients are not present in the file
# 0: delta energy coefficient is not present in the file
# 0: delta delta coefficients are not present in the file
# 0: delta delta energy coefficient is not present in the file
# 13: total size of a feature vector in the mfcc file
# 0:0:0: no feature normalization
fDesc="audio16kHz2sphinx,1:1:0:0:0:0,13,0:0:0"

#this variable is use in CLR/NCLR clustering and gender detection
#the MFCC corresponds to sphinx 12 MFCC + E
# sphinx=the mfcc is computed by sphinx tools
# 1: static coefficients are present in the file
# 3: energy coefficient is present in the file but will not be used
# 2: delta coefficients are not present in the file and will be computed on the fly
# 0: delta energy coefficient is not present in the file
# 0: delta delta coefficients are not present in the file
# 0: delta delta energy coefficient is not present in the file
# 13: size of a feature vector in the mfcc file
# 1:1:300:4: the MFCC are wrapped (feature warping using a sliding windows of 300 features),
# next the features are centered and reduced: mean and variance are computed by segment
fDescCLR="audio16kHz2sphinx,1:3:2:0:0:0,13,1:1:300:4"

show=`basename $1 .sph`
show=`basename $show .wav`

echo $show

#need JVM 1.6
java=java

datadir=${show}

ubm=models/ubm.gmm
pmsgmm=models/sms.gmms
sgmm=models/s.gmms
ggmm=models/gender.gmms

# LOCALCLASSPATH=lium_spkdiarization-8.4.1.jar

echo "#####################################################"
echo "#   $show"
echo "#####################################################"


mkdir ./$datadir >& /dev/null

$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MSegInit --help --fInputMask=$features --fInputDesc=$fDesc --sInputMask=$uem --sOutputMask=./$datadir/%s.i.seg  $show

#Speech/Music/Silence segmentation
iseg=./$datadir/$show.i.seg
pmsseg=./$datadir/$show.pms.seg
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MDecode --help --fInputDesc=audio2sphinx,1:3:2:0:0:0,13,0:0:0 --fInputMask=$features --sInputMask=$iseg --sOutputMask=$pmsseg --dPenality=10,10,50 --tInputMask=$pmsgmm $show

#GLR based segmentation, make small segments
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MSeg --kind=FULL --sMethod=GLR --help --fInputMask=$features --fInputDesc=$fDesc --sInputMask=./$datadir/%s.i.seg --sOutputMask=./$datadir/%s.s.seg  $show

# linear clustering
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MClust --help --fInputMask=$features --fInputDesc=$fDesc --sInputMask=./$datadir/%s.s.seg --sOutputMask=./$datadir/%s.l.seg --cMethod=l --cThr=2 $show

h=3
# hierarchical clustering
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MClust --help --fInputMask=$features --fInputDesc=$fDesc --sInputMask=./$datadir/%s.l.seg --sOutputMask=./$datadir/%s.h.$h.seg --cMethod=h --cThr=$h $show

# initialize GMM
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MTrainInit --help --nbComp=8 --kind=DIAG --fInputMask=$features --fInputDesc=$fDesc --sInputMask=./$datadir/%s.h.$h.seg --tOutputMask=./$datadir/%s.init.gmms $show

# EM computation
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MTrainEM --help --nbComp=8 --kind=DIAG --fInputMask=$features --fInputDesc=$fDesc --sInputMask=./$datadir/%s.h.$h.seg --tOutputMask=./$datadir/%s.gmms --tInputMask=./$datadir/%s.init.gmms  $show

#Viterbi decoding
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MDecode --help --fInputMask=${features} --fInputDesc=$fDesc --sInputMask=./$datadir/%s.h.$h.seg --sOutputMask=./$datadir/%s.d.$h.seg --dPenality=250 --tInputMask=$datadir/%s.gmms $show

#Adjust segment boundaries
adjseg=./$datadir/$show.adj.$h.seg
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.tools.SAdjSeg --help --fInputMask=$features --fInputDesc=audio16kHz2sphinx,1:1:0:0:0:0,13,0:0:0 --sInputMask=./$datadir/%s.d.$h.seg --sOutputMask=$adjseg $show

#filter spk segmentation according pms segmentation
fltseg=./$datadir/$show.flt.$h.seg
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.tools.SFilter --help --fInputDesc=audio2sphinx,1:3:2:0:0:0,13,0:0:0 --fInputMask=$features --fltSegMinLenSpeech=150 --fltSegMinLenSil=25 --sFilterClusterName=j --fltSegPadding=25 --sFilterMask=$pmsseg --sInputMask=$adjseg --sOutputMask=$fltseg $show

#Split segment longer than 20s
splseg=./$datadir/$show.spl.$h.seg
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.tools.SSplitSeg --help  --sFilterMask=$pmsseg --sFilterClusterName=iS,iT,j --sInputMask=$fltseg --sOutputMask=$splseg --fInputMask=$features --fInputDesc=audio16kHz2sphinx,1:3:2:0:0:0,13,0:0:0 --tInputMask=$sgmm $show

#-------------------------------------------------------------------------------
#Set gender and bandwith
gseg=./$datadir/$show.g.$h.seg
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MScore --help --sGender --sByCluster --fInputDesc=$fDescCLR --fInputMask=$features --sInputMask=$splseg --sOutputMask=$gseg --tInputMask=$ggmm $show

#CLR clustering
# Features contain static and delta and are centered and reduced (--fdesc)
c=1.7
spkseg=./$datadir/$show.c.$h.seg
$java -Xmx1024m -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.programs.MClust --help --fInputMask=$features --fInputDesc=$fDescCLR --sInputMask=$gseg --sOutputMask=./$datadir/%s.c.$h.seg --cMethod=ce --cThr=$c --tInputMask=$ubm --emCtrl=1,5,0.01 --sTop=5,$ubm --tOutputMask=./$show/$show.c.gmm $show

#XML print out
#convert from .seg format to .xml
#$java -cp lium_spkdiarization-8.4.1.jar fr.lium.spkDiarization.tools.PrintSeg --sInputMask=./$datadir/%s.c.$h.seg --sOutputMask=%s.xml --sOutputFormat=seg.xml $show

#RTTM print out
#conversion from .seg format to .rttm using guidelines acquired in Albayzin Speaker Diarization 2016 Evaluation
awk '!/^;;/ {print "SPEAKER " $1 " " $2 " " (($3-($3%100))/ 100)  " " (($4-($4%100))/ 100) " <NA> <NA> " $8 " <NA> <NA>"}' $show/$show.c.3.seg > $show/$show.rttm

#converesion from .csv to .rttm
awk '!/^;;/ {print "SPEAKER R" $4 "S" $1 "W" $2 "D" $3 " 1 " ( ($6 * 3600) + ( $7 * 60 ) + $8 ) " " ( ($12 * 3600) + ( $13 * 60 ) + $14 ) " <NA> <NA> " $5 " <NA> <NA>"}' $show.csv > $show.ref.rttm

C:/Strawberry/perl/bin/perl.exe ./perl/md-eval-v21.pl -r $show.ref.rttm -s $show/$show.rttm > $show.perl.log

#Audacity print out
#Labels for Audacity import
#awk '!/^;;/ {printf("%0.2f\t%0.2f\t%s\n",($3 / 100.), (($3+$4)/ 100.), $8)}' $show/$show.c.3.seg > $show/$show.1.txt

#Audacity reconversion to RTTM -- NEEDS REVISION
#awk '!/^;;/ {print "SPEAKER show_SECTION_A 1 " $1 " " $2-$1 " <NA> <NA> " $3 " <NA> <NA>"}' $show/$show.txt > $show/$show.rttm

#perl for DER calculations
# md-eval-v21.pl [-h] -r <ref_file> -s <src_file>

# perl C:/cygwin/home/Sean/lium_spkdiarization-8.4.1/perl/md-eval-v21.pl -r C:/cygwin/home/Sean/lium_spkdiarization-8.4.1/show_ALL_SECTIONS/show_ALL_SECTIONS.rttm -s C:/cygwin/home/Sean/lium_spkdiarization-8.4.1/show_ALL_SECTIONS/show_ALL_SECTIONS.1.rttm > show_ALL_SECTIONS.DER.txt

#awk '!/^;;/ {print "$1 " " $2 " " $3 " " $4 " " $5 " " $6 " " $7 " " $8 " " $9; $10 = $7 + $9; }' 'Newstalk Breakfast 01.07.csv' > 'Newstalk Breakfast 01.07.fixed.csv'

#awk 'BEGIN{a=0}
#!/^;;/ {print "SPEAKER 20140701 1 " a ".00 " (($15*3600) + ($16*60) + $17) ".00 <NA> <NA> " $8 " <NA> <NA>"; a = a + (($15*3600) + ($16*60) + $17);}' 'Newstalk Breakfast 01.07.csv' > 'Newstalk Breakfast 01.07.rttm'

#awk '!/^;;/ {print "SPEAKER " $1 "." $2 "." $3 "." $4 ":" $5 ":" $6 " 1 " (($9*3600) + ($10*60) + $11) " " (($15*3600) + ($16*60) + $17) " <NA> <NA> " $8 " <NA> <NA>"}' 'Newstalk Breakfast 01.07.fixed.csv' > 'Newstalk Breakfast 01.07.rttm'

#RTTM print out from new csv with only Gender info
#same as above but with full decimal accuracy
awk '!/^;;/ {print "SPEAKER " $1 " " $2 " " ($3./ 100)  " " ($4./100) " <NA> <NA> " $5 " <NA> <NA>"}' R2S11W1D2.c.3.seg > R2S11W1D2.sexonly.rttm

#same as above but with printf function instead
awk '!/^;;/ {printf("SPEAKER R%dS%dW%dD%d 1 %.2f %.2f <NA> <NA> %d <NA> <NA>\n", $4, $1, $2, $3,( ($6 * 3600) + ( $7 * 60 ) + $8 ), ( ($12 * 3600) + ( $13 * 60 ) + $14 ), $5)  }' R2S11W1D2.sexonly.csv > R2S11W1D2.sexonly.ref.rttm

C:/Strawberry/perl/bin/perl.exe ./perl/md-eval-v21.pl -r RESULTS/R2S11W1D2/R2S11W1D2.sexonly.ref.rttm -s RESULTS/R2S11W1D2/R2S11W1D2.sexonly.rttm > R2S11W1D2.sexonly.perl.log

#Audacity example
awk '!/^;;/ {printf("%0.2f\t%0.2f\t%s\n",($3 / 100.), (($3+$4)/ 100.), $8)}' $show/$show.c.3.seg > $show/$show.1.txt

#NEW Segment to Audacity conversion
awk '!/^;;/ {printf("%0.2f\t%0.2f\t%s%s\n", ($3 / 100.), (($3 + $4)/ 100.) , $5, $8)}' $show/$show.c.3.seg > $show/$show.aud.txt

#CSV to Audacity conversion DOESN'T WORK?
awk '!/^;;/ {printf("%0.2f\t%0.2f\t%c%s\n", ( ($5 * 3600.) + ( $6 * 60. ) + $7 ), ( ($8 * 3600.) + ( $9 * 60. ) + $10 ), $15, $14)}' $show/$show.csv > $show/$show.audref.txt

#CSV to Audacity conversion WORKS?
awk '!/^;;/ {printf("%0.2f\t%0.2f\t%s\n", ( ($6 * 3600.) + ( $7 * 60. ) + $8 ), ( ($12 * 3600.) + ( $13 * 60. ) + $14 ), $5)  }' $show/$show.sexonly.csv > $show/$show.sexonly.audref.txt
