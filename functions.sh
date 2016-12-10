#!/bin/bash
. ./visualization.sh

function get_all_volumes()
{
    fdisk -l 2> /dev/null | grep -E 'Disk.*bytes' | sed 's,:,,g' | 
	awk '{ print $2 }'
}

function get_disk_capacity()
{
    fdisk -l $1 2> /dev/null | grep -E 'Disk.*bytes' |
	awk '{ print $3 }'
}

function get_all_raidsets()
{
    cat /proc/mdstat | grep md | awk '{ print "/dev/" $1 }'
}

function get_disks_in_raid()
{
    for rs in `get_all_raidsets`
    do
	mdadm --detail $rs | grep '/dev/sd' | awk '{print $NF}'
    done
}

function get_raid_capacity_detail()
{
    local raid_cap=`get_disk_capacity $1`
    local -i raw_cap=0
    local -i parity_cap=0
    local raid_level=`mdadm --detail $1 | grep "Raid Level" | awk '{print $NF}'`
    local raid_disks=`mdadm --detail $1 | grep '/dev/sd' | awk '{print $NF}'`
    if [ "$raid_level" = "raid0" ]
    then
	echo "$raid_cap 0"
    else
	for d in $raid_disks
	do
	    raw_cap="${raw_cap}+`get_disk_capacity $d`"
	done
	parity_cap=$raw_cap-$raid_cap
	echo "$raid_cap $parity_cap"
    fi
}

function get_lv_vg_pv_info()
{
    vgdisplay -v 2> /dev/null | grep -E "LV Name|PV Name|VG Name"
}

function get_disks_in_vgs()
{
    get_lv_vg_pv_info | grep "/dev/sd" | awk '{ print $NF }'
}

function get_lvs()
{
    get_lv_vg_pv_info | grep "LV Name" | awk '{ print $NF }' 
}

function get_lvs_with_size()
{
    lvs --noheading --nosuffix --unit m | awk '{ print $2 "/" $1 "-" $4 }'
}

function get_vgs()
{
    get_lv_vg_pv_info | grep "VG Name" | awk '{ print $NF }' | sort | uniq
}

function get_used_vgs()
{
    vgs --noheading --nosuffix --unit M | 
	awk '{
	    if ($3 != 0) {
		print $1
	    }
	}'
}

function get_unused_vgs()
{
    vgs --noheading --nosuffix --unit M | 
	awk '{
	    if ($3 == 0) {
		print $1
	    }
	}'
}

function get_available_vgs()
{
    vgs --noheading --nosuffix --unit m | 
	awk '{
	    if ($NF >= 50) {
		print $1
	    }
	}'
}

function get_available_vgs_with_size()
{
    vgs --noheading --nosuffix --unit m | 
	awk '{
	    if ($NF >= 50) {
		print $1 "-" $NF
	    }
	}'
}

function get_full_vgs()
{
    vgs --noheading --nosuffix --unit m | 
	awk '{
	    if ($NF <= 50) {
		print $1
	    }
	}'
}

function display_vgs_lvs_with_sizes()
{
    local vgs=`vgs --noheading --nosuffix --unit m |\
	awk '{print $1 "/free" ":" $NF}'`
    local lvs=`lvs --noheading --nosuffix --unit m |\
	awk '{print $2"/" $1 ":" $4}'`
    local all_lvs_sorted=`for ll in $lvs $vgs; do echo $ll; done | sort`
    echo $all_lvs_sorted | sed 's,:, ,g'
}

function display_iet_active_conf()
{
    cat /proc/net/iet/volume | 
	awk -F ":| |\t" '{
	    if ($1 == "tid") {
		tid=$2
	    } else if ($2 == "lun") {
		lun=$3
		vol=$NF
		print "T:" tid "-L:" lun "-V:" vol
	    }
	}'
}

function display_iet_exported_capacity()
{
    local vol=""
    local volcap=""
    for i_entry in `display_iet_active_conf`
    do
	vol=`echo $i_entry | awk -F ':|-' '{print $NF}'`
	volcap=`get_disk_capacity $vol`
	echo "`echo $i_entry | sed 's,/dev/,,g'` $volcap"
    done
}

function get_iscsi_unit_vols()
{
    display_iet_active_conf | awk -F ':|-' '{ print $NF }'
}

function get_iscsi_targets()
{
    cat /proc/net/iet/volume | awk -F ':| |\t' '{ if ($1 == "tid") print $2 }'
}

function get_iscsi_luns_for_target()
{
    display_iet_active_conf | 
	awk -F ':|-' -v targ=$1 '{ 
	if (targ == $2) {
	    print $4 
	}
    }'
}

function get_next_iscsi_lun_for_target()
{
    local -i l=0
    while [ -n "`display_iet_active_conf | grep T:$1-L:$l`" ]
    do
	l=$l+1
    done
    echo $l
}

function get_used_raidsets()
{
    get_lv_vg_pv_info | grep "md" | awk '{ print $NF }'
    get_iscsi_unit_vols | grep "md"
}

function get_used_disks()
{
    df -xtmpfs -HT | grep -v 'Mounted on' | awk '{ print $1 }' | 
	sed 's,[0-9],,g'
    get_all_raidsets
    get_disks_in_raid
    get_disks_in_vgs
    get_iscsi_unit_vols
}

function cleanup_cgi_args
{
    echo "$QUERY_STRING" | 
	awk -F "&|=" '{
	    print $NF
	    for (i = 1; i < NF; i++) {
		if ($i != "on") {
		    print $i
		}
	    }
	}'
}

function process_iscsi_delete_lun
{
    local tmpfile=`mktemp`
    local devstr=`echo $1 | sed 's,%2F,/,g' | sed 's,%3A,:,g'`
    local devarr=(`echo ${devstr} | awk -F ":|-" '{print $2 " " $4 " " $6}'`)
    local targ=`grep "tid:${devarr[0]}" /proc/net/iet/volume |\
	awk -F ':' '{print $NF}'`
    cat /etc/ietd.conf |
	awk -F ":| |\t|=|," \
	    -v targ="$targ" -v lun="${devarr[1]}" -v dev="${devarr[2]}" '
	    BEGIN { 
		target_found=0
		lun_found=0
	    }

	    /^[ |\t]*Target/ {
		if (targ == $NF) {
		    target_found = 1
		    lun_found = 0
		} else {
		    target_found = 0
		}
	    }
	    /^[ |\t]*Lun/ {
		if (target_found == 1) {
		    for (i = 1; i <=NF; i++) {
			if (($i == "Lun") && ($(i+1) == lun) && 
			    ($(i+3) == dev)) {
			    target_found = 0
			    next
			}
		    }
		}
	    }
	    {
		print $0
	    }' > $tmpfile
    cp /etc/ietd.conf /etc/ietd.conf.bak
    mv $tmpfile /etc/ietd.conf
    ietadm --op delete --tid=${devarr[0]} --lun=${devarr[1]}
    last_action_message="$last_action_message \
	Deleted-Target:${devarr[0]} Lun: ${devarr[1]}"
}

function process_iscsi_export_lun
{
    local tmpfile=`mktemp`
    local dev=`echo $3 | sed 's,%2F,/,g'`
    for l in `get_iscsi_luns_for_target $1`
    do
	if [ "$l" = "$2" ]
	then
	    last_action_message="${last_action_message}\
		    Error: Lun: $2 already present on Target: $1"
	    return
	fi
    done
    local targ=`grep "tid:$1" /proc/net/iet/volume | awk -F ':' '{print $NF}'`
    cat /etc/ietd.conf | 
	awk -F ":| |\t" -v targ=$targ -v lun=$2 -v dev=$dev '
	    BEGIN { 
		target_found=0
		lun_found=0
		output_line="\tLun " lun " Path=/dev/" dev ",Type=blockio"
	    }
	    
	    /^[ |\t]*Target/ {
		if (target_found == 1) {
		    print output_line
		    target_found = 0
		    lun_found = 0
		} else {
		    if (targ == $NF) {
			target_found = 1
			lun_found = 0
		    }
		}
		print $0
		next
	    }
	    /^[ |\t]*Lun/ {
		if (target_found == 1) {
		    lun_found = 1
		}
		print $0
		next
	    }
	    {
		if (target_found == 1 && lun_found == 1) {
		    print output_line
		    target_found = 0
		    lun_found = 0
		}
		print $0
	    }
	    END {
		if (target_found == 1) {
		    print output_line
		    target_found = 0
		}
	    }' > $tmpfile
    cp /etc/ietd.conf /etc/ietd.conf.bak
    mv $tmpfile /etc/ietd.conf
    ietadm --op new --tid=$1 --lun=$2 --params Path="/dev/${dev},Type=blockio"
    last_action_message="$last_action_message Created-Target: $1 Lun: $2"
}

function get_next_iscsi_tid_tname()
{
    cat /proc/net/iet/session | grep tid | awk -F "[: .]" '{ 
	if ($2 >= candidate_tid) {
	    $2 = $2 + 1
	    candidate_tid = $2
	    $NF = "targ" $2
	    split($0, candidate_tid_tname)
	}
    }
    END {
	for ( i = 1; i in candidate_tid_tname; i++ ) {
	    if ( i == 2 || i == 4 || i == 8)
		printf (":")
	    else if ( i == 3 ) 
		printf (" ")
	    else if (i > 1)
		printf (".")
	    printf ("%s", candidate_tid_tname[i])
	}
	printf("\n")
    }'
}

function process_iscsi_create_target()
{
    local tmpfile=`mktemp`
    local tid_tname=(`get_next_iscsi_tid_tname |\
	awk -F '[: ]' '{ print $2 " " $4 ":" $NF}'`)
    ietadm --op new --tid=${tid_tname[0]} --params Name=${tid_tname[1]}
    cp /etc/ietd.conf $tmpfile
    echo "Target ${tid_tname[1]}" >> $tmpfile
    cp /etc/ietd.conf /etc/ietd.conf.bak
    mv $tmpfile /etc/ietd.conf
    last_action_message="$last_action_message \
	    Created-Target:tid:${tid_tname[0]} ${tid_tname[1]}"
}

function get_unused_iscsi_targets()
{
    cat /proc/net/iet/volume | awk -F "[: |\t]" '{
	if ($1 == "tid") {
	    cur_tid = $2
	    tid_arr[$2] = "unused"
	} else if ($2 == "lun")
	    tid_arr[cur_tid] = "used"
	}
	END {
	    for (tid in tid_arr) {
		if (tid_arr[tid] == "unused") {
		    print tid
		}
	    }
	}'
}

function get_known_iscsi_initiators()
{
    cat /etc/initiators.allow |
	awk '{
	    for ( i = 1; i <= NF; i++ ) {
		if ($i != 0) {
		    if (substr($i, 1, 1) != "#") {
			print
		    }
		    next
		}
	    }
	}' | awk -v FS="[,| |\t]" '{
	    for ( i = 2; i <= NF; i++ ) {
		if ($i) {
		    print $i
		}
	    }
	}' | sort | uniq
}

function process_iscsi_delete_target()
{
    local tmpfile=`mktemp`
    local tmpfile1=`mktemp`
    local tname=`grep "tid:$1" /proc/net/iet/session |\
	awk -F "[: ]" '{ print $4 ":" $5}'`
    ietadm --op delete --tid=$1
    cp /etc/ietd.conf /etc/ietd.conf.bak
    grep -v $tname /etc/ietd.conf > $tmpfile
    mv $tmpfile /etc/ietd.conf
    grep -v $tname /etc/initiators.allow > $tmpfile1
    mv $tmpfile1 /etc/initiators.allow
    last_action_message="$last_action_message Deleted-Target:tid:$1 $tname"
}

function process_iscsi_grant_access()
{
    local tmpfile=`mktemp`
    local tname=`grep "tid:$1" /proc/net/iet/session |\
	awk -F "[: ]" '{ print $4 ":" $5}'`
    cat /etc/initiators.allow | awk -v tname=$tname -v iname=$2 '{
	if ($1 == tname) {
	    print $0 ", " iname
	    target_found = 1
	} else {
	    print $0
	}
    }
    END {
	if (target_found != 1) {
	    print tname " " iname
	}
    }' > $tmpfile
    cp /etc/initiators.allow /etc/initiators.allow.bak
    mv $tmpfile /etc/initiators.allow
    last_action_message="$last_action_message Initiator Portal: $2 \
	granted access for Tid:$1"
}

function process_iscsi_revoke_access()
{
    local tmpfile=`mktemp`
    local tname=`grep "tid:$1" /proc/net/iet/session |\
	awk -v FS="[: ]" '{ print $4 ":" $5}'`
    cat /etc/initiators.allow | 
	awk -v FS="[,| |\t]" -v tname=$tname -v iname=$2 '{
	    if ($1 == tname) {
		tname_print_flag = 0
		for (i = 2; i <=NF; i++) {
		    if ($i && ($i != iname)) {
			printf("%s%s", 
			    (tname_print_flag == 0) ? tname " " : ", ", $i)
			tname_print_flag = 1
		    }
		}
		printf "\n"
	    } else {
		print $0
	    }
	}' > $tmpfile
    cp /etc/initiators.allow /etc/initiators.allow.bak
    mv $tmpfile /etc/initiators.allow
    last_action_message="$last_action_message Initiator Portal: $2 \
	revoked access for Tid:$1"
}

function iscsi.sh
{
    local arg_arr=( `cleanup_cgi_args` )
    if [ "${arg_arr[0]}" = "ExportLun" ]
    then
	process_iscsi_export_lun ${arg_arr[2]} ${arg_arr[4]} ${arg_arr[6]}
    elif [ "${arg_arr[0]}" = "DeleteLun" ]
    then
	process_iscsi_delete_lun ${arg_arr[2]}
    elif [ "${arg_arr[0]}" = "CreateTarget" ]
    then
	process_iscsi_create_target
    elif [ "${arg_arr[0]}" = "DeleteTarget" ]
    then
	process_iscsi_delete_target ${arg_arr[2]}
    elif [ "${arg_arr[0]}" = "GrantAccess" ]
    then
	process_iscsi_grant_access ${arg_arr[2]} ${arg_arr[4]}
    elif [ "${arg_arr[0]}" = "RevokeAccess" ]
    then
	process_iscsi_revoke_access ${arg_arr[2]} ${arg_arr[4]}
    fi
}

function get_next_raid_file
{
    local -i iter=0
    while [ -b "/dev/md${iter}" ]
    do
	iter=${iter}+1
    done
    echo "/dev/md${iter}"
}

function process_raid_create
{
    local raid_disks=""
    local -i no_raid_disks=0
    local dskflag="T"
    local raid_level="1000"
    local raid_dev=`get_next_raid_file`
    shift 1
    for arg in $*
    do
	if [ "$arg" = "level" ]
	then
	    dskflag="F"
	elif [ $dskflag = "T" ]
	then
	    raid_disks="/dev/${arg} ${raid_disks}"
	    no_raid_disks=${no_raid_disks}+1
	elif [ "$arg" != "raid.sh" ]
	then
	    raid_level=$arg
	fi
    done
    yes | 
	mdadm --create ${raid_dev} --level=${raid_level} \
	    --raid-devices=${no_raid_disks} ${raid_disks}
    last_action_message="$last_action_message \
	Created: RAID: ${raid_dev} Level: ${raid_level}"
}

function process_raid_delete
{
    local dsks=`mdadm --detail /dev/$3 | grep '/dev/sd' | awk '{print $NF}'`
    mdadm --stop /dev/$3
    for d in $dsks
    do
	mdadm --zero-superblock $d
    done
    rm -f /dev/$3
    last_action_message="$last_action_message Deleted-RAID: /dev/$3"
}

function raid.sh
{
    local all_args="`cleanup_cgi_args`"
    local arg_arr=( $all_args )
    if [ "${arg_arr[0]}" = "CreateRAID" ]
    then
	process_raid_create $all_args
    elif [ "${arg_arr[0]}" = "DeleteRAID" ]
    then
	process_raid_delete $all_args
    fi
}

function get_next_vg_file
{
    local -i iter=0
    while [ -n "`vgs vg${iter} 2> /dev/null`" ]
    do
	iter=${iter}+1
    done
    echo "vg${iter}"
}

function process_create_vg()
{
    local pvs=""
    local vg_name=`get_next_vg_file`
    shift 1
    for arg in $*
    do
	if [ ${arg} = "lvm.sh" ]
	then
	    break
	else
	    dd if=/dev/zero of=/dev/${arg} bs=1k count=1
	    pvcreate -f /dev/${arg} > /dev/null
	    pvs="/dev/${arg} $pvs"
	fi
    done
    vgcreate $vg_name $pvs > /dev/null
    last_action_message="$last_action_message Created-VG: $vg_name"
}

function process_extend_vg()
{
    shift 2
    local arg_vg=$1
    local arg_pvs=""
    shift 1
    while [ "$1" != "lvm.sh" ]
    do
	dd if=/dev/zero of=/dev/$1 bs=1k count=1
	pvcreate -f /dev/$1 > /dev/null
	arg_pvs="${arg_pvs} /dev/$1"
	shift 1
    done
    vgextend $arg_vg $arg_pvs > /dev/null
    last_action_message="$last_action_message \
	Extended $arg_vg by adding $arg_pvs"
}

function process_delete_vg()
{
    vgremove $3 > /dev/null
    last_action_message="$last_action_message Deleted-VG: $3"
}

function process_create_lv()
{
    local lvcreate_out=""
    local argarr=(`echo $* | awk -F "-| " '{ print $3 " " $6}'`)
    lvcreate_out=`lvcreate -L ${argarr[1]}M ${argarr[0]} | \
	awk -F " |\"" '{print $6}'`
    last_action_message="$last_action_message \
	Created-LV: ${argarr[0]}/${lvcreate_out}"
}

function process_delete_lv()
{
    local args=(`echo $* | sed 's,%2F,/,g' | sed 's,%3A,:,g'`)
    lvremove -f ${args[2]} > /dev/null
    last_action_message="$last_action_message Deleted-LV: ${args[2]}"
}

function process_snapshot_lv()
{
    local args=(`echo $* | sed 's,%2F,/,g' | sed 's,%3A,:,g' | sed 's,-, ,g'`)
    local lvname="`echo ${args[2]} | awk -F '/' '{print $2}'`"
    lvcreate --size ${args[5]}M \
	--snapshot --name sn$lvname /dev/${args[2]} > /dev/null
    last_action_message="$last_action_message \
	Created-Snapshot: sn$lvname of /dev/${args[2]}"
}

function process_extend_lv()
{
    local args=(`echo $* | sed 's,%2F,/,g' | sed 's,%3A,:,g' | sed 's,-, ,g'`)
    local lvname="${args[2]}"
    lvextend -L +${args[5]}M /dev/$lvname > /dev/null
    last_action_message="Extended $lvname by ${args[5]}M"
}

function lvm.sh
{
    local all_args="`cleanup_cgi_args`"
    local arg_arr=( $all_args )
    if [ "${arg_arr[0]}" = "CreateVG" ]
    then
	process_create_vg $all_args
    elif [ "${arg_arr[0]}" = "ExtendVG" ]
    then
	process_extend_vg $all_args
    elif [ "${arg_arr[0]}" = "DeleteVG" ]
    then
	process_delete_vg $all_args
    elif [ "${arg_arr[0]}" = "CreateLV" ]
    then
	process_create_lv $all_args
    elif [ "${arg_arr[0]}" = "DeleteLV" ]
    then
	process_delete_lv $all_args
    elif [ "${arg_arr[0]}" = "ExtendLV" ]
    then
	process_extend_lv $all_args
    elif [ "${arg_arr[0]}" = "SnapshotLV" ]
    then
	process_snapshot_lv $all_args
    fi
}

function process_create_storage()
{
    local raid_disks=""
    local -i no_raid_disks=0
    local dskflag="T"
    local lvpercent_flag="F"
    local lvpercent=""
    local target_flag="F"
    local target=""
    local level_flag="F"
    local raid_level="1000"
    local raid_dev=`get_next_raid_file`
    local vg_name=`get_next_vg_file`
    shift 1
    for arg in $*
    do
	if [ "$arg" = "level" ]
	then
	    dskflag="F"
	    level_flag="T"
	elif [ $dskflag = "T" ]
	then
	    raid_disks="/dev/${arg} ${raid_disks}"
	    no_raid_disks=${no_raid_disks}+1
	elif [ "$level_flag" = "T" ]
	then
	    raid_level=$arg
	    level_flag="P"
        elif [ "${lvpercent_flag}" = "F" ] && [ "$arg" = "wizard.sh" ]
        then
            lvpercent_flag="T"
	elif [ "${lvpercent_flag}" = "T" ]
	then
	    lvpercent=$arg
	    lvpercent_flag="P"
	elif [ "${target_flag}" = "F" ] && [ "$arg" = "target" ]
	then
	    target_flag="T"
	elif [ "${target_flag}" = "T" ]
	then
	    target=$arg
	    target_flag="P"
	fi
    done
    yes | 
	mdadm --create ${raid_dev} --level=${raid_level} \
	    --raid-devices=${no_raid_disks} ${raid_disks}
    last_action_message="${last_action_message} \
	Created RAID: ${raid_dev} Level: ${raid_level}"
    dd if=/dev/zero of=/dev/${raid_dev} bs=1k count=1
    pvcreate -f ${raid_dev} > /dev/null
    vgcreate $vg_name ${raid_dev} > /dev/null
    local vgsize=`vgs $vg_name --noheading --units m --nosuffix |\
	awk '{print $NF}'`
    local lvsize=`echo "${vgsize}*${lvpercent}/100"|bc -q`
    lvcreate -L ${lvsize}M $vg_name > /dev/null
    last_action_message="${last_action_message} VG/LV: ${vg_name}/lvol0"
    local lun=`get_next_iscsi_lun_for_target $target`
    process_iscsi_export_lun $target $lun "${vg_name}/lvol0"
}

function wizard.sh
{
    local all_args="`cleanup_cgi_args`"
    local arg_arr=( $all_args )
    if [ "${arg_arr[0]}" = "CreateStorage" ]
    then
	process_create_storage $all_args
    fi
}

function enumerate_numbers
{
    local -i i
    i=0
    while [ "$i" -lt $1 ]
    do
	echo $i
	i=$i+1
    done
}

function eliminate_entities()
{
    for d1 in $1
    do
	entity_found="F"
	for d2 in $2
	do
	    if [ $d1 == $d2 ]
	    then
		entity_found="T"
                break
	    fi
	done
	if [ $entity_found == "F" ]
	then
	    echo $d1
	fi
    done
}

function print_devices
{
  for d in $*
  do
      echo $d | sed 's,/dev/,,g'
  done
}

function refresh_global_state()
{
    all_volumes=`get_all_volumes`
    used_disks=`get_used_disks`
    raid_sets=`get_all_raidsets`
    all_disks=`eliminate_entities "$all_volumes" "$raid_sets"`
    unused_disks=`eliminate_entities "$all_volumes" "$used_disks"`
    disks_in_use=`eliminate_entities "$all_disks" "$unused_disks"`
    all_lvs=`get_lvs`
    unused_lvs=`eliminate_entities "$all_lvs" "$used_disks"`
    used_lvs=`eliminate_entities "$all_lvs" "$unused_lvs"`
    all_vgs=`get_vgs`
    used_vgs=`get_used_vgs`
    unused_vgs=`get_unused_vgs`
    full_vgs=`get_full_vgs`
    available_vgs=`get_available_vgs`
    partially_used_vgs=`eliminate_entities "$used_vgs" "$full_vgs"`
    used_raidsets=`get_used_raidsets`
    unused_raid_sets=`eliminate_entities "$raid_sets" "$used_raidsets"`
    exportable_block_devices="$unused_disks $unused_raid_sets $unused_lvs"
    active_iscsi_units=`display_iet_active_conf`
}

function display_iscsi_export_form()
{
    echo "<tr>"
    echo "<td style=\"background:aqua;font-size:12\" \
	title=\"Select the Block Device to be exported on iSCSI \
	    along with the Target and LUN to present it on\" >" \
		"Export Block Device as LUN" "</td>"
    echo "<td colspan=2 style=\"background:aqua;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> Target: </td>"
    echo "<td>"
    echo "<select name=\"target\" style=\"font-size:12\">"
    for t in `get_iscsi_targets`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td> LUN: </td>"
    echo "<td>"
    echo "<select name=\"lun\" style=\"font-size:12\">"
    for t in `enumerate_numbers 16`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td> Device: </td>"
    echo "<td>"
    echo "<select name=\"device\" style=\"font-size:12\">"
    for d in `print_devices "$exportable_block_devices"`
    do
	echo "<option value=\"$d\">$d</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input name=\"iscsi.sh\" type=\"submit\" \
	style=\"font-size:12\" value=\"ExportLun\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</td>"
    echo "</tr>"
    echo "</table>"
}

function display_iscsi_delete_lun_form()
{
    echo "<tr>"
    echo "<td style=\"background:aqua;font-size:12\" \
	title=\"Select the Device which should not be presented any more. \
	    Note that the underlying device configuration is not deleted\">"\
		"Delete Exported iSCSI LUN" "</td>"
    echo "<td colspan=2 style=\"background:aqua;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> iSCSI Active Unit: </td>"
    echo "<td>"
    echo "<select name=\"ietconf\" style=\"font-size:12\">"
    for t in `display_iet_active_conf`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input name=\"iscsi.sh\" type=\"submit\" \
	style=\"font-size:12\" value=\"DeleteLun\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_iscsi_target_form()
{
    echo "<tr>"
    echo "<td style=\"background:aqua;font-size:12\" \
	title=\"Create/Delete iSCSI Target. \
	    Different targets can be used to export LUNs to different \
		initiators providing a way to implement selective LUN \
		    presentation or LUN Masking\">"\
			"Create/Delete iSCSI Target" "</td>"
    echo "<td style=\"background:aqua;font-size:12\">"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<input name=\"iscsi.sh\" type=\"submit\" \
	style=\"font-size:12\" value=\"CreateTarget\">"
    echo "</form>"
    echo "</td>"
    echo "<td style=\"background:aqua;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> iSCSI Target: </td>"
    echo "<td>"
    echo "<select name=\"targets\" style=\"font-size:12\">"
    for t in `get_unused_iscsi_targets`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input name=\"iscsi.sh\" type=\"submit\" \
	style=\"font-size:12\" value=\"DeleteTarget\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_iscsi_grant_access()
{
    echo "<tr>"
    echo "<td style=\"background:aqua;font-size:12\" \
	title=\"Select the target and provide the initiator portal that \
	    should be granted to access the target.\">"\
	    "Grant Access" "</td>"
    echo "<td colspan=2 style=\"background:aqua;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> iSCSI Target: </td>"
    echo "<td>"
    echo "<select name=\"targets\" style=\"font-size:12\">"
    for t in `get_iscsi_targets`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>IP Address of Initiator Portal:<input type=\"text\" \
	style=\"font-size:12\" size=\"15\" name=\"initip\"> </td>"
    echo "<td>"
    echo "<input name=\"iscsi.sh\" type=\"submit\" \
	style=\"font-size:12\" value=\"GrantAccess\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_iscsi_revoke_access()
{
    echo "<tr>"
    echo "<td style=\"background:aqua;font-size:12\" \
	title=\"Select the target and the initiator portal that \
	    should be revoked access the target.\">"\
	    "Revoke Access" "</td>"
    echo "<td colspan=2 style=\"background:aqua;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> iSCSI Target: </td>"
    echo "<td>"
    echo "<select name=\"targets\" style=\"font-size:12\">"
    for t in `get_iscsi_targets`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>Initiator Portal:</td>"
    echo "<td>"
    echo "<select name=\"initiator\" style=\"font-size:12\">"
    for t in `get_known_iscsi_initiators`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input name=\"iscsi.sh\" type=\"submit\" \
	style=\"font-size:12\" value=\"RevokeAccess\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_iscsi_forms_table()
{
    display_table_start
    display_iscsi_export_form
    display_iscsi_delete_lun_form
    display_iscsi_target_form
    display_iscsi_grant_access
    display_iscsi_revoke_access
    display_table_end
}

function display_raid_create_form
{
    echo "<tr>"
    echo "<td style=\"background:pink;font-size:12\" \
	title=\"Select the disks and the RAID level to create the RAID Set\">"\
	    "Create RAID Set" "</td>"
    echo "<td colspan=2 style=\"background:pink;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> Disks: </td>"
    echo "<td>"
    for d in `print_devices $unused_disks`
    do
	echo "<input style=\"font-size:12\" type=checkbox name=\"$d\">$d"
    done
    echo "</td>"
    echo "<td> RAID Level: </td>"
    echo "<td>"
    echo "<select name=\"level\" style=\"font-size:12\">"
    echo "<option value=\"0\">0</option>"
    echo "<option value=\"1\">1</option>"
    echo "<option value=\"4\">4</option>"
    echo "<option value=\"5\">5</option>"
    echo "<option value=\"6\">6</option>"
    echo "<option value=\"10\">10</option>"
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input style=\"font-size:12\" name=\"raid.sh\" \
	type=\"submit\" value=\"CreateRAID\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_raid_delete_form
{
    echo "<tr>"
    echo "<td style=\"background:pink;font-size:12\" \
	title=\"Select the RAID Set to be deleted\">" "Delete RAID Set" "</td>"
    echo "<td colspan=2 style=\"background:pink;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> RAID Set: </td>"
    echo "<td>"
    echo "<select name=\"raidset\" style=\"font-size:12\">"
    for d in `print_devices $unused_raid_sets`
    do
	echo "<option value=\"$d\">" $d "</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input style=\"font-size:12\" name=\"raid.sh\" \
	type=\"submit\" value=\"DeleteRAID\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_raid_forms_table()
{
    display_table_start
    display_raid_create_form
    display_raid_delete_form
    display_table_end
}

function display_vg_create_form()
{
    echo "<tr>"
    echo "<td style=\"background:greenyellow;font-size:12\" \
	title=\"Select the block devices to be aggregated as a Volume Group\">"\
	    "Create VG" "</td>"
    echo "<td colspan=2 style=\"background:greenyellow;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> Physical Volumes: </td>"
    echo "<td>"
    for d in `print_devices $unused_disks`
    do
	echo "<input style=\"font-size:12\" type=checkbox name=\"$d\">$d"
    done
    for d in `print_devices $unused_raid_sets`
    do
	echo "<input style=\"font-size:12\" type=checkbox name=\"$d\">$d"
    done
    echo "</td>"
    echo "<td>"
    echo "<input name=\"lvm.sh\" style=\"font-size:12\" \
	type=\"submit\" value=\"CreateVG\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "<tr>"
    echo "<td style=\"background:greenyellow;font-size:12\" \
	title=\"Select the block devices and the VG where they \
	    will be added for expansion\">" "Extend VG" "</td>"
    echo "<td colspan=2 style=\"background:greenyellow;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> VG: </td>"
    echo "<td>"
    echo "<select name=\"vg\" style=\"font-size:12\">"
    for d in $all_vgs
    do
	echo "<option value=\"$d\">" $d "</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td> Physical Volumes: </td>"
    echo "<td>"
    for d in `print_devices $unused_disks`
    do
	echo "<input style=\"font-size:12\" type=checkbox name=\"$d\">$d"
    done
    for d in `print_devices $unused_raid_sets`
    do
	echo "<input style=\"font-size:12\" type=checkbox name=\"$d\">$d"
    done
    echo "</td>"
    echo "<td>"
    echo "<input style=\"font-size:12\" name=\"lvm.sh\" \
	type=\"submit\" value=\"ExtendVG\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td style=\"background:greenyellow;font-size:12\" \
	title=\"Select the VG to be deleted. \
	    Note that the underlying devices are not deleted\">" \
		"Delete VG" "</td>"
    echo "<td colspan=2 style=\"background:greenyellow;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> VG: </td>"
    echo "<td>"
    echo "<select name=\"vg\" style=\"font-size:12\">"
    for d in $unused_vgs
    do
	echo "<option value=\"$d\">" $d "</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input style=\"font-size:12\" name=\"lvm.sh\" \
	type=\"submit\" value=\"DeleteVG\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_lv_create_form()
{
    echo "<tr>"
    echo "<td style=\"background:yellow;font-size:12\" \
	title=\"Select the VG and the size of the LV to be created\">" \
	    "Create LV" "</td>"
    echo "<td colspan=2 style=\"background:yellow;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> VG (free space in MB): </td>"
    echo "<td>"
    echo "<select name=\"vg\" style=\"font-size:12\">"
    for d in `get_available_vgs_with_size`
    do
	echo "<option value=\"$d\">" $d "</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>Enter LV Size in MB:<input type=\"text\" \
	style=\"font-size:12\" size=\"5\" name=\"lvsize\"> </td>"
    echo "<td>"
    echo "<input name=\"lvm.sh\" \
	style=\"font-size:12\" type=\"submit\" value=\"CreateLV\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td style=\"background:yellow;font-size:12\" \
	title=\"Select the LV to be extended and provide the extension size\">"\
	    "Extend LV" "</td>"
    echo "<td colspan=2 style=\"background:yellow;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> LV: (size in MB) </td>"
    echo "<td>"
    echo "<select name=\"lv\" style=\"font-size:12\">"
    for d in `get_lvs_with_size`
    do
	echo "<option value=\"$d\">" $d "</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>Enter Extension Size in MB:<input type=\"text\" \
	style=\"font-size:12\" size=\"5\" name=\"snsize\"> </td>"
    echo "<td>"
    echo "<input name=\"lvm.sh\" style=\"font-size:12\" \
	type=\"submit\" value=\"ExtendLV\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td style=\"background:yellow;font-size:12\" \
	title=\"Select the LV for which a Snapshot is to be created \
	    and the size of the space to be used to store \
		the Snapshot Delta\">" "Snapshot LV" "</td>"
    echo "<td colspan=2 style=\"background:yellow;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> LV: (size in MB) </td>"
    echo "<td>"
    echo "<select name=\"lv\" style=\"font-size:12\">"
    for d in `get_lvs_with_size`
    do
	echo "<option value=\"$d\">" $d "</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>Enter Snapshot Size in MB:<input type=\"text\" \
	style=\"font-size:12\" size=\"5\" name=\"snsize\"> </td>"
    echo "<td>"
    echo "<input name=\"lvm.sh\" style=\"font-size:12\" type=\"submit\" \
	value=\"SnapshotLV\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td style=\"background:yellow;font-size:12\" \
	title=\"Select the LV to be deleted\">" "Delete LV" "</td>"
    echo "<td colspan=2 style=\"background:yellow;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<td> LV: </td>"
    echo "<td>"
    echo "<select name=\"lv\" style=\"font-size:12\">"
    for d in $unused_lvs
    do
	echo "<option value=\"$d\">" $d "</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "<td>"
    echo "<input name=\"lvm.sh\" style=\"font-size:12\" type=\"submit\" \
	value=\"DeleteLV\">"
    echo "</td>"
    echo "</form>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
}

function display_vg_forms_table()
{
    display_table_start
    display_vg_create_form
    display_table_end
}

function display_lvm_forms_table()
{
    display_table_start
    display_lv_create_form
    display_table_end
}

function display_wizard_forms_table()
{
    display_table_start
    echo "<form action=\"/cgi-bin/main.cgi\" method=\"POST\">"
    echo "<tr>"
    echo "<td style=\"background:pink;font-size:12\" \
	onclick=\"show_raid_forms_table();\" \
	    title=\"Select the disks and the RAID level \
		to create the RAID Set\">" "Create RAID Set" "</td>"
    echo "<td colspan=2 style=\"background:pink;font-size:12\">"
    echo "<table border=0 style=\"font-size:12\">"
    echo "<tr>"
    echo "<td> Disks: </td>"
    echo "<td>"
    for d in `print_devices $unused_disks`
    do
	echo "<input style=\"font-size:12\" type=checkbox name=\"$d\">$d"
    done
    echo "</td>"
    echo "<td> RAID Level: </td>"
    echo "<td>"
    echo "<select name=\"level\" style=\"font-size:12\">"
    echo "<option value=\"0\">0</option>"
    echo "<option value=\"1\">1</option>"
    echo "<option value=\"4\">4</option>"
    echo "<option value=\"5\">5</option>"
    echo "<option value=\"6\">6</option>"
    echo "<option value=\"10\">10</option>"
    echo "</select>"
    echo "</td>"
    echo "</tr>"
    echo "</table>"
    echo "</td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td style=\"background:yellow;font-size:12\" \
	onclick=\"show_lvm_forms_table();\" \
	    title=\"Select the percentage of space from the VG on \
		just created RAID Set that should be used for the LV \
		    which will be exported as a Logical Unit\">\
			Allocate LV from the VG</td>"
    echo "<td colspan=2 style=\"background:yellow;font-size:12\">"
    echo "<input style=\"font-size:12\" name=\"wizard.sh\" \
	type=\"radio\" value=\"25\">"
    echo "25%"
    echo "<input name=\"wizard.sh\" style=\"font-size:12\" \
	type=\"radio\" value=\"50\" checked>"
    echo "50%"
    echo "<input name=\"wizard.sh\" style=\"font-size:12\" \
	type=\"radio\" value=\"75\">"
    echo "75%"
    echo "<input name=\"wizard.sh\" style=\"font-size:12\" \
	type=\"radio\" value=\"100\">"
    echo "100%"
    echo "</td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td style=\"background:aqua;font-size:12\" \
	onclick=\"show_iscsi_forms_table();\" \
	    title=\"Select the iSCSI Target on which the LV \
		should be exported as a LUN\">Export on iSCSI</td>"
    echo "<td colspan=2 style=\"background:aqua;font-size:12\">"
    echo "Target: "
    echo "<select name=\"target\" style=\"font-size:12\">"
    for t in `get_iscsi_targets`
    do
	echo "<option value=\"$t\">$t</option>"
    done
    echo "</select>"
    echo "</td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td style=\"background:sandybrown;font-size:12\" \
	title=\"Review the selections and click the CreateStorage button \
	    to create and export storage\">Create and Export Storage</td>"
    echo "<td colspan=2 style=\"background:sandybrown;font-size:12\">"
    echo "<input name=\"wizard.sh\" style=\"font-size:12\" type=\"submit\" \
	value=\"CreateStorage\">"
    echo "</td>"
    echo "</tr>"
    echo "</form>"
    display_table_end
}

function jscript_forms_table()
{
    echo "<script type=\"text/javascript\">"
    echo "function show_raid_forms_table(){"
    echo "document.getElementById('wizard_forms_table').style.display=\"none\";"
    echo "document.getElementById('vg_forms_table').style.display=\"none\";"
    echo "document.getElementById('lvm_forms_table').style.display=\"none\";"
    echo "document.getElementById('iscsi_forms_table').style.display=\"none\";"
    echo "document.getElementById('raid_forms_table').style.display=\"inline\";"
    echo "}"
    echo "function show_wizard_forms_table(){"
    echo "document.getElementById('raid_forms_table').style.display=\"none\";"
    echo "document.getElementById('vg_forms_table').style.display=\"none\";"
    echo "document.getElementById('lvm_forms_table').style.display=\"none\";"
    echo "document.getElementById('iscsi_forms_table').style.display=\"none\";"
    echo "document.getElementById('wizard_forms_table').style.display=\
	\"inline\";"
    echo "}"
    echo "function show_iscsi_forms_table(){"
    echo "document.getElementById('raid_forms_table').style.display=\"none\";"
    echo "document.getElementById('vg_forms_table').style.display=\"none\";"
    echo "document.getElementById('lvm_forms_table').style.display=\"none\";"
    echo "document.getElementById('wizard_forms_table').style.display=\"none\";"
    echo "document.getElementById('iscsi_forms_table').style.display=\
	\"inline\";"
    echo "}"
    echo "function show_lvm_forms_table(){"
    echo "document.getElementById('raid_forms_table').style.display=\"none\";"
    echo "document.getElementById('iscsi_forms_table').style.display=\"none\";"
    echo "document.getElementById('wizard_forms_table').style.display=\"none\";"
    echo "document.getElementById('vg_forms_table').style.display=\"none\";"
    echo "document.getElementById('lvm_forms_table').style.display=\"inline\";"
    echo "}"
    echo "function show_vg_forms_table(){"
    echo "document.getElementById('raid_forms_table').style.display=\"none\";"
    echo "document.getElementById('iscsi_forms_table').style.display=\"none\";"
    echo "document.getElementById('wizard_forms_table').style.display=\"none\";"
    echo "document.getElementById('lvm_forms_table').style.display=\"none\";"
    echo "document.getElementById('vg_forms_table').style.display=\"inline\";"
    echo "}"
    echo "</script>"
}

function display_table_start()
{
    echo "<table border=1 width=\"750\" style=\"font-size:12\">"
}

function display_table_end()
{
    echo "</table>"
}

function display_main_header()
{
    echo "<h1 colspan=3 style=\"align:center;font-size:12\">\
	Linux Storage Orchestrator</h1>"
}

function display_cgi_header()
{
    echo "Content-Type: text/html"
    echo ""
    echo "<head>"
    echo "<title>Linux Storage Orchestrator</title>"
    echo "</head>"
}

function display_last_action_message()
{
    if [ -n "$last_action_message" ]
    then
	echo "<script type=\"text/javascript\">"
	echo "var xxonload;"
	echo "xxonload = window.onload;"
	echo "if (typeof window.onload != 'function') {"
	echo "window.onload = function() {"
	echo "alert('$last_action_message');"
	echo "};"
	echo "} else {"
	echo "window.onload = function() {"
	echo "xxonload();"
	echo "alert('$last_action_message');"
	echo "};"
	echo "}"
	echo "</script>"
	##echo "<p> $last_action_message </p>"
	##echo "<body onload=\"javascript: alert('$last_action_message')\">"
	last_action_message=""
    fi
}

function display_storage_stack()
{
    /usr/lib/cgi-bin/storage
}

function load_visualization_charts()
{
    local argstr=""
    local -i used_capacity=0
    local -i unused_capacity=0
    local -i total_capacity=0
    local -i used_count=0
    local -i unused_count=0
    local used_dsk_str=""
    local unused_dsk_str=""
    local raidsets=`cat /proc/mdstat | grep md | awk '{print $1}'`
    local rcaparr
    local raidstr=""
    local -i raid_count=0
    local vglvstr=""
    local -i vg_count=0
    local -i max_lv_count=0
    local -i cur_lv_count=0
    local last_vg=""
    local cur_vg=""
    local expvolstr=""
    local -i expvol_count=0
    local dsk=""

    for d in $disks_in_use
    do
	dsk=`print_devices $d`
	used_dsk_str="${used_dsk_str} $dsk `get_disk_capacity $d`"
	used_count=${used_count}+1
    done
    for d in $unused_disks
    do
	dsk=`print_devices $d`
	unused_dsk_str="${unused_dsk_str} $dsk `get_disk_capacity $d`"
	unused_count=${unused_count}+1
    done
    for r in $raidsets
    do
	rcaparr=( `get_raid_capacity_detail /dev/$r` )
	raidstr="$raidstr $r-user ${rcaparr[0]} $r-parity ${rcaparr[1]}"
	raid_count=$raid_count+1
    done
    vglv_str=`display_vgs_lvs_with_sizes`
    for vl in $vglv_str
    do
	cur_vg=`echo $vl | grep "vg" | awk -F '/' '{print $1}'`
	if [ -n "$cur_vg" ]
	then
	    if [ "$cur_vg" != "$last_vg" ]
	    then
		last_vg=$cur_vg
		vg_count=$vg_count+1
		cur_lv_count=0
	    else
		cur_lv_count=$cur_lv_count+1
		if [ "$cur_lv_count" -gt "$max_lv_count" ]
		then
		    max_lv_count=$cur_lv_count
		fi
	    fi
	fi
    done
    expvolstr=`display_iet_exported_capacity`
    for ev in $expvolstr
    do
	expvol_count=${expvol_count}+1
    done
    expvol_count=${expvol_count}/2 ## Don't count the capacity

    argstr="Used ${used_count} ${used_dsk_str} Unused ${unused_count} \
	${unused_dsk_str} Raidsets ${raid_count} $raidstr VGS ${vg_count}\
	    ${max_lv_count} ${vglv_str} EXPVOL ${expvol_count} ${expvolstr}"
    load_capacity_visualization $argstr
}

function display_raw_capacity_chart()
{
    local capacity_string="0"
    local used_capacity="0"
    local unused_capacity="0"
    for d in $disks_in_use
    do
	capacity_string="${capacity_string}+`get_disk_capacity $d`"
    done
    used_capacity="`echo $capacity_string | bc -q`"
    capacity_string="0"
    for d in $unused_disks
    do
	capacity_string="${capacity_string}+`get_disk_capacity $d`"
    done
    unused_capacity="`echo $capacity_string | bc -q`"
    display_table_start
    echo "<tr>"
    echo "<td align=center><b>Total Raw Capacity</b><br>"
    echo "<b>Used:</b> ${used_capacity} MB <b>Unused:</b> \
	${unused_capacity} MB<br>"
    echo "<div id=\"total_raw_capacity_chart_div\"></div>"
    echo "</td>"
    echo "</tr>"
    display_table_end
}

function display_used_raw_capacity_chart()
{
    display_table_start
    echo "<tr>"
    echo "<td align=center><b>Used Raw Capacity in MB</b><br>"
    echo "<div id=\"used_raw_capacity_chart_div\"></div>"
    echo "</td>"
    echo "</tr>"
    display_table_end
}

function display_unused_raw_capacity_chart()
{
    display_table_start
    echo "<tr>"
    echo "<td align=center><b>Unused Raw Capacity in MB</b><br>"
    echo "<div id=\"unused_raw_capacity_chart_div\"></div>"
    echo "</td>"
    echo "</tr>"
    display_table_end
}

function display_raid_capacity_chart()
{
    display_table_start
    echo "<tr>"
    echo "<td align=center><b>RAID Capacity in MB</b><br>"
    echo "<div id=\"raidset_capacity_chart_div\"></div>"
    echo "</td>"
    display_table_end
}

function display_vglv_capacity_chart()
{
    display_table_start
    echo "<tr>"
    echo "<td align=center><b>Volume Group Capacity in MB</b><br>"
    echo "<div id=\"vglv_capacity_chart_div\"></div>"
    echo "</td>"
    echo "</tr>"
    display_table_end
}

function display_iscsi_capacity_chart()
{
    display_table_start
    echo "<tr>"
    echo "<td align=center><b>Exported Volume Capacity in MB</b><br>"
    echo "<div id=\"expvol_capacity_chart_div\"></div>"
    echo "</td>"
    echo "</tr>"
    display_table_end
}

function dump_iscsi_info()
{
    echo "<textarea rows=\"7\" cols=\"91\" style=\"background:aqua\">"
    echo "iSCSI Sessions"
    cat /proc/net/iet/session
    echo "iSCSI Volumes"
    cat /proc/net/iet/volume
    echo "</textarea>"
}

function dump_iscsi_access_info()
{
    echo "<textarea rows=\"7\" cols=\"91\" style=\"background:aqua\">"
    cat /etc/initiators.allow |
	awk '{
	    for ( i = 1; i <= NF; i++ ) {
		if ($i != 0) {
		    if (substr($i, 1, 1) != "#") {
			print
		    }
		    next
		}
	    }
	}'
    echo "</textarea>"
}

function dump_lv_info()
{
    echo "<textarea rows=\"7\" cols=\"91\" style=\"background:yellow\">"
    lvdisplay 2> /dev/null
    echo "</textarea>"
}

function dump_vg_info()
{
    echo "<textarea rows=\"7\" cols=\"91\" style=\"background:greenyellow\">"
    vgdisplay 2> /dev/null
    echo "</textarea>"
}

function dump_raid_info()
{
    echo "<textarea rows=\"7\" cols=\"91\" style=\"background:pink\">"
    for rs in `get_all_raidsets`
    do
	mdadm -D $rs 2> /dev/null
    done
    echo "</textarea>"
}

function dump_disk_info()
{
    echo "<textarea rows=\"7\" cols=\"91\" style=\"background:sandybrown\">"
    fdisk -l 2> /dev/null
    echo "</textarea>"
}

function load_tabs_script()
{
    cat << __ENDOFTABBERSCRIPT__
    <script type="text/javascript" src="/jscripts/tabber.js"></script>
    <link rel="stylesheet" href="/css/storageui.css" TYPE="text/css" MEDIA="screen">
    <script type="text/javascript">
    document.write('<style type="text/css">.tabber{display:none;}<\/style>');
    </script>
__ENDOFTABBERSCRIPT__
}

function display_storage_state_tabs()
{
    echo "<div class=\"tabber\">"
	echo "<div class=\"tabbertab\" title=\"Storage Stack\">\
	    `display_storage_stack`</div>"
	echo "<div class=\"tabbertab\" title=\"iSCSI Details\">\
	    `dump_iscsi_info`</div>"
	echo "<div class=\"tabbertab\" title=\"iSCSI Access Details\">\
	    `dump_iscsi_access_info`</div>"
	echo "<div class=\"tabbertab\" title=\"LV Details\">\
	    `dump_lv_info`</div>"
	echo "<div class=\"tabbertab\" title=\"VG Details\">\
	    `dump_vg_info`</div>"
	echo "<div class=\"tabbertab\" title=\"RAID Details\">\
	    `dump_raid_info`</div>"
	echo "<div class=\"tabbertab\" title=\"Disk Details\">\
	    `dump_disk_info`</div>"
    echo "</div>"
}

function display_forms_tabs()
{
    echo "<div class=\"tabber\">"
	echo "<div class=\"tabbertab\" title=\"Storage Wizard\">\
	    `display_wizard_forms_table`</div>"
	echo "<div class=\"tabbertab\" title=\"iSCSI Actions\">\
	    `display_iscsi_forms_table`</div>"
	echo "<div class=\"tabbertab\" title=\"LV Actions\">\
	    `display_lvm_forms_table`</div>"
	echo "<div class=\"tabbertab\" title=\"VG Actions\">\
	    `display_vg_forms_table`</div>"
	echo "<div class=\"tabbertab\" title=\"RAID Actions\">\
	    `display_raid_forms_table`</div>"
    echo "</div>"
}

function display_charts_tabs()
{
    load_visualization_charts
    echo "<div class=\"tabber\">"
	echo "<div class=\"tabbertab\" title=\"Raw Capacity\">\
	    `display_raw_capacity_chart`</div>"
	echo "<div class=\"tabbertab\" title=\"Used Raw Capacity\">\
	    `display_used_raw_capacity_chart`</div>"
	echo "<div class=\"tabbertab\" title=\"Unused Raw Capacity\">\
	    `display_unused_raw_capacity_chart`</div>"
	echo "<div class=\"tabbertab\" title=\"RAID Capacity\">\
	    `display_raid_capacity_chart`</div>"
	echo "<div class=\"tabbertab\" title=\"VG-LV Capacity\">\
	    `display_vglv_capacity_chart`</div>"
	echo "<div class=\"tabbertab\" title=\"iSCSI Capacity\">\
	    `display_iscsi_capacity_chart`</div>"
    echo "</div>"
}
