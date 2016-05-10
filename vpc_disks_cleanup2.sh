#!/bin/bash

aws_access_key=$1
aws_secret_key=$2
account_id=$3
vpc_cidr=$4

export AWS_ACCESS_KEY_ID=${aws_access_key}
export AWS_SECRET_ACCESS_KEY=${aws_secret_key}

function aws_disk_delete {

  # Collect volume that are not in use
  vpc_volumes=`aws ec2 describe-volumes | jq -r '.Volumes[] | .VolumeId + "," + .State'`

  # Delete unused Volumes
  for volume in `echo ${vpc_volumes}`
  do
    id=`echo ${volume} | cut -d ',' -f1`
    state=`echo ${volume} | cut -d ',' -f2`

    if [ "$state" == "available" ]
    then
      echo "AWS Deleting unused volume: ${id}"
      aws ec2 delete-volume --volume-id ${id}
    fi
  done

  echo ""
}


function aws_snapshot_delete {

  # Collect disk snapshots
  vpc_disks_snapshots=`aws ec2 describe-snapshots --owner-ids ${account_id} | jq -r '.Snapshots[] | .VolumeId + "," + .StartTime + "," + .SnapshotId + "," + .State' | sort -r`

  previous_disk_id=""
  snapshots_count=0
  # Selecting what will be deleted
  for snapshot in `echo ${vpc_disks_snapshots}`
  do
     disk_id=`echo ${snapshot} | cut -d ',' -f1`
     snapshot_time=`echo ${snapshot} | cut -d ',' -f2`
     snapshot_id=`echo ${snapshot} | cut -d ',' -f3`

     if [ "$previous_disk_id" != "${disk_id}" ]
     then
       echo ""
       echo "AWS Disk: ${disk_id}"
       echo "------------------------------------------------------------"
       echo "No deletion of: ${snapshot_id} ${snapshot_time}"
       snapshots_count=1
       previous_disk_id=${disk_id}
     else
       if [ ${snapshots_count} -ge 5 ]
       then
         echo "Deletion of: ${snapshot_id} ${snapshot_time}"
         aws ec2 delete-snapshot --snapshot-id ${snapshot_id}
       else
         echo "No deletion of: ${snapshot_id} ${snapshot_time}"
         snapshots_count=$((snapshots_count+1))
       fi
     fi
  done
}

##############################################

function bosh_disk_cleanup {
  bosh_target_list=`cat ~/.bosh_config | yaml2json | jq -r '.auth | to_entries | map({target: .key, password: .value.password, username: .value.username}) | group_by(.key) | .[][] | .target + "," + .username + "," + .password' | grep "${vpc_cidr}"`

  for bosh in `echo ${bosh_target_list}`
  do
    target=`echo ${bosh} | cut -d "," -f1`
    username=`echo ${bosh} | cut -d "," -f2`
    password=`echo ${bosh} | cut -d "," -f3`

    # Target bosh
    bosh target ${target}

    # Get list of deployments
    bosh_deployments=`curl -s -k -u ${username}:${password} ${target}/deployments | jq -r '.[] | .name'`

    # Looping on deployments
    for deployment in `echo ${bosh_deployments}`
    do
      #rm -f /tmp/${deployment}-cleanup.yml && bosh download manifest ${deployment} /tmp/${deployment}-cleanup.yml && bosh deployment /tmp/${deployment}-cleanup.yml
      snapshots=`curl -s -k -u ${username}:${password} ${target}/deployments/${deployment}/snapshots | jq -r '.[] | .job + "_" + (.index | tostring) + "," + .created_at + "," + .snapshot_cid' | sort -r | sed -e 's/ /_/g'`

      previous_component=""
      snapshots_count=0
      # Selecting what will be deleted
      for snapshot in `echo ${snapshots}`
      do
         component=`echo ${snapshot} | cut -d ',' -f1`
         snapshot_time=`echo ${snapshot} | cut -d ',' -f2`
         snapshot_id=`echo ${snapshot} | cut -d ',' -f3`

         if [ "$previous_component" != "${component}" ]
         then
           echo ""
           echo "BOSH Spnapshots: ${component}"
           echo "--------------------------------------------------------------------------------"
           echo "No deletion of: ${snapshot_id} ${snapshot_time}"
           snapshots_count=1
           previous_component=${component}
         else
           if [ ${snapshots_count} -ge 5 ]
           then
             queued_tasks_count=`curl -s -k -u ${username}:${password} ${target}/tasks\?state\=queued | jq '.[] | .id' | wc -l`
             while [ "${queued_tasks_count}" -ge "50" ]
             do
               echo "Sleeping since queue is too big on bosh: ${queued_tasks_count}"
               sleep 30
               queued_tasks_count=`curl -s -k -u ${username}:${password} ${target}/tasks\?state\=queued | jq '.[] | .id' | wc -l`
             done

             echo "Deletion of: ${snapshot_id} ${snapshot_time}"
             #echo "bosh -n delete snapshot ${snapshot_id}"
             curl -s -k -XDELETE -u ${username}:${password} ${target}/deployments/${deployment}/snapshots/${snapshot_id}
             #bosh -n delete snapshot ${snapshot_id}
           else
             echo "No deletion of: ${snapshot_id} ${snapshot_time}"
             snapshots_count=$((snapshots_count+1))
           fi
         fi
      done
    done

    # Delete orphaned disks
    orphean_disks=`bosh disks --orphaned | grep -oh "vol-\w*"`
    echo ""
    echo "BOSH Disks"
    echo "--------------------------------------------------------------------------------"
    for disk in `echo ${orphean_disks}`
    do
      echo "BOSH Deleting disk: ${disk}"
      bosh delete disk ${disk}
    done
  done
}

bosh_disk_cleanup
aws_snapshot_delete
aws_disk_delete
