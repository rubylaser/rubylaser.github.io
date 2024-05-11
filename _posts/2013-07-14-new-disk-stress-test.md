---
title: 'New Disk Stress Test'
date: '2013-07-14T22:35:04-04:00'
layout: post
permalink: /new-disk-stress-test/
image: /wp-content/uploads/2013/10/dsc_0057.jpg
categories: [disk, linux, raid, ubuntu]
---

I bought a few new disks and wanted a better way to weed out marginal disks before I deployed them.

I don’t use UnRAID at home, but I liked the idea of their [preclear script](https://lime-technology.com/forum/index.php?topic=2817.0). I have modified it to remove a number of unnecessary options, but it works at this point, so I thought I would post it. How does it work?

The script:  
\* gets a SMART report  
\* pre-reads the entire disk  
\* writes zeros to the entire disk  
\* sets the special signature recognized by unRAID  
\* verifies the signature  
\* post-reads the entire disk  
\* optionally repeats the process for additional cycles (if you specified the “-c NN” option, where NN = a number from 1 to 20, default is to run 1 cycle)  
\* gets a final SMART report  
\* compares the SMART reports alerting you of differences.

It also has the option to run a (4) pass destructive write pass with badblocks. If a disk can make it through this, I can confidently use it in my fileserver. I’m still working on getting the options to work correctly, but it does run with the basic options at this point. By default, this option is on. This option can add 30 hours to the runtime on a large disk. If you want to turn it off, change the use\_badblocks=1 at the beginning to say use\_badblocks=0.

> [!WARNING]  
> WARNING: This will completely overwrite your disk!!!

You use it like this.

```bash
disk_tester.sh /dev/sdh
```

Here is the script.

```bash
#! /bin/bash
d=`basename $1`

get_start_smart() {
 # just in case, enable SMART monitoring
 d=`basename $1`
 smartctl -s on $1 >/dev/null 2>&1
 echo "Disk: $1" >/tmp/smart_start_$d
 #smartctl -d ata -a $1 2>&1 | egrep -v "Power_On_Minutes|Temperature_Celsius" >>/tmp/smart_start_$d
 smartctl $device_type -a $1 2>&1 >>/tmp/smart_start_$d
 cp /tmp/smart_start_$d /var/log/
}

get_finish_smart() {
 d=`basename $1`
 echo "Disk: $1" >/tmp/smart_finish_$d
 #smartctl -d ata -a $1 2>&1 | egrep -v "Power_On_Minutes|Temperature_Celsius" >>/tmp/smart_finish_$d
 smartctl $device_type -a $1 2>&1 >>/tmp/smart_finish_$d
 cp /tmp/smart_finish_$d /var/log/
}

get_mid_smart() {
 d=`basename $1`
 echo "Disk: $1" >/tmp/smart_mid_${2}_$d
 #smartctl -d ata -a $1 2>&1 | egrep -v "Power_On_Minutes|Temperature_Celsius" >>/tmp/smart_mid_${2}_$d
 smartctl $device_type -a $1 2>&1 >>/tmp/smart_mid_${2}_$d
 cp /tmp/smart_mid_${2}_$d /var/log/
}

analyze_for_errors() {
 err=""
 if [ "$2" = "" ]
 then
 sm_err=`analyze_smart $1`
 else
 post_err=`analyze_smart $1 $2`
 sm_err="$post_err"
 fi

 echo -e "$sm_err"
}

get_attr() {
 attribute_name=$1

 case $2 in
 old*) file=$3 ;;
 new*) file=$4 ;;
 esac

 case $2 in
 *val) col=3 ;;
 *thresh) col=5 ;;
 *status) col=8;;
 *raw) col=9;;
 esac
 sed "s/\([0-9]\) /\1-/" <$file | grep $attribute_name | sed 1q | awk '{print $'$col'}' | sed "s/^0\(.\)/\1/" | sed "s/^0\(.\)/\1/"
}

analyze_smart() {
 err=""
 attribute_changed=""
 chg_attr=""

 if [ "$#" = 2 ]
 then
 # look for changes in attributes.
 #First, get a list of the attributes, then for each list changes in an easy to read format.
 attributes=`cat $1 | sed -n "/ATTRIBUTE_NAME/,/^$/p" | grep -v "ATTRIBUTE_NAME" | grep -v "^$" | awk '{ print $1 "-" $2}'`
 chg_attr=`printf "%25s %-7s %-7s %16s %-11s %9s" "ATTRIBUTE" "NEW_VAL" "OLD_VAL" "FAILURE_THRESHOLD" "STATUS" "RAW_VALUE"`"\n"
 for i in $attributes
 do
 oldv=`get_attr $i old_val $1 $2`
 newv=`get_attr $i new_val $1 $2`
 let near=$newv-25 2>/dev/null
 newr=`get_attr $i new_raw $1 $2`
 oldr=`get_attr $i old_raw $1 $2`
 fthresh=`get_attr $i new_thresh $1 $2`
 stat=`get_attr $i new_status $1 $2`
 #echo "$i oldv=$oldv newv=$newv near=$near newr=$newr oldr=$oldr fthresh=$fthresh stat=$stat"
 case "$i" in
 Current_Pending_Sector|Reallocated_Sector_Ct|Reallocated_Event_Count)
 if [ "$oldr" != "$newr" ]
 then
 l=`printf "%25s = %3s %3s %3s %-11s %s" $i $newv $oldv $fthresh $stat $newr`
 chg_attr="{chg_attr}${l}\n"
 attribute_changed="yes"
 continue;
 fi
 ;;
 esac
 [ "$oldv" = "253" ] && [ "$newv" = "200" -o "$newv" = "100" -o "$newv" = "253" ] && continue
 [ "$near" -le "$fthresh" -a "$stat" = "-" ] && stat="near_thresh"
 [ "$stat" = "-" -o "$stat" = "" ] && stat="ok"
 [ "$stat" = "ok" ] && [ "$oldv" = "$newv" ] && continue # not failing, and unchanged
 [ "$stat" = "ok" ] && [ "$oldv" = "100" -a "$newv" = "200" ] && continue # initialized to start value
 attribute_name="${i#*-}"
 l=`printf "%25s = %3s %3s %3s %-11s %s" $attribute_name $newv $oldv $fthresh $stat $newr`
 chg_attr="{chg_attr}${l}\n"
 attribute_changed="yes"
 done
 fi

 if [ "$attribute_changed" = "yes" ]
 then
 err="${err}** Changed attributes in files: $1 $2\n$chg_attr"
 fi

 if [ "$#" = 1 ]
 then
 smart_file=$1
 else
 smart_file=$2
 fi
 # next, check for individual attributes that have failed.
 failed_attributes=`grep 'FAILING_NOW' $smart_file| grep -v "No SMART attributes"`
 if [ "$failed_attributes" != "" ]
 then
 err="${err}\n*** Failing SMART Attributes in $smart_file *** \n"
 err="${err}ID# ATTRIBUTE_NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE\n"
 err="$err$failed_attributes\n\n"
 else
 err="$err No SMART attributes are FAILING_NOW\n\n"
 fi


 if [ "$#" = 1 ]
 then
 # next, look for sectors pending re-allocation
 pending_sectors=`get_attr "Current_Pending_Sector" old_raw $1`
 if [ "$pending_sectors" != "" ]
 then
 err="$err $pending_sectors sectors are pending re-allocation.\n"
 fi

 # look for re-allocated sectors
 reallocated_sectors=`get_attr "Reallocated_Sector_Ct" old_raw $1`
 if [ "$reallocated_sectors" != "" ]
 then
 err="$err $reallocated_sectors sectors had been re-allocated.\n"
 fi
 else
 # next, look for sectors pending re-allocation
 o_pending_sectors=`get_attr "Current_Pending_Sector" old_raw $1`
 if [ "$o_pending_sectors" != "" ]
 then
 if [ "$o_pending_sectors" = "1" ]
 then
 err="$err $o_pending_sectors sector was pending re-allocation before the start of the preclear.\n"
 else
 err="$err $o_pending_sectors sectors were pending re-allocation before the start of the preclear.\n"
 fi
 fi
 if [ -f /tmp/smart_mid_pending_reallocate_$d ]
 then
 err="$err`cat /tmp/smart_mid_pending_reallocate_$d`\n"
 fi
 n_pending_sectors=`get_attr "Current_Pending_Sector" new_raw $1 $2`
 if [ "$n_pending_sectors" != "" ]
 then
 if [ "$n_pending_sectors" = "1" ]
 then
 err="$err $n_pending_sectors sector is pending re-allocation at the end of the preclear,\n"
 else
 err="$err $n_pending_sectors sectors are pending re-allocation at the end of the preclear,\n"
 fi
 fi
 if [ "$o_pending_sectors" != "$n_pending_sectors" ]
 then
 let chg=$n_pending_sectors-$o_pending_sectors
 err="$err a change of $chg in the number of sectors pending re-allocation.\n"
 else
 err="$err the number of sectors pending re-allocation did not change.\n"
 fi

 # look for re-allocated sectors
 o_reallocated_sectors=`get_attr "Reallocated_Sector_Ct" old_raw $1 $2`
 if [ "$o_reallocated_sectors" != "" ]
 then
 if [ "$o_reallocated_sectors" = "1" ]
 then
 err="$err $o_reallocated_sectors sector had been re-allocated before the start of the preclear.\n"
 else
 err="$err $o_reallocated_sectors sectors had been re-allocated before the start of the preclear.\n"
 fi
 fi
 n_reallocated_sectors=`get_attr "Reallocated_Sector_Ct" new_raw $1 $2`
 if [ "$n_reallocated_sectors" != "" ]
 then
 if [ "$n_reallocated_sectors" = "1" ]
 then
 err="$err $n_reallocated_sectors sector is re-allocated at the end of the preclear,\n"
 else
 err="$err $n_reallocated_sectors sectors are re-allocated at the end of the preclear,\n"
 fi
 fi
 if [ "$o_reallocated_sectors" != "$n_reallocated_sectors" ]
 then
 let r_chg=$n_reallocated_sectors-$o_reallocated_sectors
 err="$err a change of $r_chg in the number of sectors re-allocated.\n"
 else
 err="$err the number of sectors re-allocated did not change.\n"
 fi
 fi

 # last, check overall health
 overall_state=`grep 'SMART overall-health self-assessment test result:' $smart_file | cut -d":" -f2`
 if [ "$overall_state" != " PASSED" ]
 then
 err="$err SMART overall-health status = ${overall_state}\n"
 fi

 echo -e "$err\n"
}

get_start_smart $1 >/dev/null 2>&1
badblocks -wsv $1
get_mid_smart $theDisk >/dev/null 2>&1
badblocks -wsv $1
get_finish_smart $1 >/dev/null 2>&1

errs=`analyze_for_errors /tmp/smart_start_$d /tmp/smart_finish_$d`

echo "$errs "


report_out+="$errs \n"
report_out+="============================================================================\n"
report_out+="============================================================================\n"
report_out+="==\n"
report_out+="== S.M.A.R.T Initial Report for $theDisk \n"
report_out+="==\n"
report_out+="`cat /tmp/smart_start_$d` \n"
report_out+="==\n"
report_out+="============================================================================\n"
report_out+="\n"
report_out+="\n"
report_out+="\n"
report_out+="============================================================================\n"
report_out+="==\n"
report_out+="== S.M.A.R.T Final Report for $theDisk \n"
report_out+="==\n"
report_out+="`cat /tmp/smart_finish_$d` \n"
report_out+="==\n"
report_out+="============================================================================\n"
echo -e "$report_out " > /root/disk_test_results.txt
```