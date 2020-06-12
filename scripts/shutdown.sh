#!/bin/bash
sudo umount ${mount_dir}
gcloud compute instances detach-disk ${disk_owner} --disk ${disk_name} --zone ${disk_zone}