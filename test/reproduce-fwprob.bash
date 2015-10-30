#!/bin/bash

#
# Once upon a time there was a bug (NET-329), which resulted in a VM's firewall
# rules not getting cleaned up after the VM is destroyed. A brave programmer
# came along and heroically crushed the bug. This test verifies that the bug
# never becomes uncrushed.
#
# We have to test against Docker _and_ SmartOS containers. We spin up a docker
# container which runs a MongoDB job. This results in a bunch of firewall rules
# being created automatically. They should get cleaned up, after the machine is
# destroyed.
#
# Similarly, we create a SmartOS container, we manually add some firewall
# rules, and then destroy the container. Which should result in the firewall
# rules being deleted.
#


source ~/.bashrc


#
# This should provision a mongo container, run the below command in it, and
# then destroy the container.
#
echo "Testing on Docker"
echo "Start Time:"
date

docker --tls run -d --name="fw-docker-bug" -p 27017-27050:27017-27050 mongo
sleep 5
vmid=$(sdc-listmachines | json -a -e 'if (this.name == "fw-docker-bug"){}'  | json id)
echo VMID = $vmid
triton delete-instance --wait $vmid
# Workflow0 takes its sweet time removing firewall rules. Consequently, we have
# to wait for quite a while for it to do its job.
sleep 10
# We want to get rules that are specific to this VM.
num_rules=$(sdc-listfirewallrules | json -a id,rule | grep $vmid | wc -l)
if [[ $num_rules -gt 0 ]]; then
    echo "Docker zone's autogenerated FW rules are orphaned!"
    echo rules are
    sdc-listmachinefirewallrules $vmid
    exit 1
fi
echo "End Time:"
date


#
# Then, we reproduce the bug in a SmartOS container. base64-15.2.0 package
# sample_128
#
echo "Testing on SmartOS"
echo "Start Time:"
date

triton create-instance --name=fw-smartos-bug 5c7d0d24 76f85c8e
# If we don't sleep for a while, we can't delete this because CNAPI thinks that
# "vm_uuid is not set", even though we can actually extract the UUID
sleep 10 
vmid=$(sdc-listmachines | json -a -e 'if (this.name == "fw-smartos-bug"){}'  | json id)
sdc-createfirewallrule --enabled --rule "FROM any TO vm $vmid ALLOW tcp PORT 22" 2>&1 > /dev/null
echo VMID = $vmid
triton delete-instance --wait $vmid
# See workflow0 comment above.
sleep 10
# We want to get rules that are specific to this VM.
num_rules=$(sdc-listfirewallrules | json -a id,rule | grep $vmid | wc -l)
if [[ $num_rules -gt 0 ]]; then
    echo "SmartOS zone's FW rules are orphaned!"
    echo rules are
    sdc-listmachinefirewallrules $vmid
    exit 1
fi
echo "End Time:"
date
