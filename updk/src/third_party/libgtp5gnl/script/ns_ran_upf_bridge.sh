#!/bin/bash
source ./config
EXEC_NS2="sudo ip netns exec ${NS2}"

# Setup network namespace
sudo brctl addbr brupf
sudo ip netns add ${NS2}

sudo ip link add tap1 type veth peer name tap1_peer
sudo ip link add tap2 type veth peer name tap2_peer

sudo brctl addif brupf tap1_peer
sudo brctl addif brupf tap2_peer

sudo ip link set tap2 netns ${NS2}

# Setup RAN part
sudo ip addr add ${UE_IP} dev lo
sudo ip addr add ${RAN_IP}/24 dev tap1

# Setup UPF part
${EXEC_NS2} ip link set lo up
${EXEC_NS2} ip link set tap2 up
${EXEC_NS2} ip addr add ${DN_IP} dev lo
${EXEC_NS2} ip addr add ${AUPF_IP}/24 dev tap2

# Setup tap bridge
sudo ip link set brupf up
sudo ip link set tap1_peer up
sudo ip link set tap2_peer up
sudo ip r add ${NF_CIDR} dev brupf metric 0
# sudo ip route add ${NF_CIDR} dev tap1_peer metric 0

cd ${LIBGTP5GNL_TOOLS_PATH}

echo "############### RAN Part ###############"
sudo ./gtp5g-link add gtp5gtest --ran &
sleep 0.1
sudo ./gtp5g-tunnel add far gtp5gtest 1 --action 2
sudo ./gtp5g-tunnel add far gtp5gtest 2 --action 2 --hdr-creation 0 78 ${UPF_IP} 2152
sudo ./gtp5g-tunnel add pdr gtp5gtest 1 --pcd 1 --hdr-rm 0 --ue-ipv4 ${UE_IP} --f-teid 87 ${RAN_IP} --far-id 1
sudo ./gtp5g-tunnel add pdr gtp5gtest 2 --pcd 2 --ue-ipv4 ${UE_IP} --far-id 2 --gtpu-src-ip=${RAN_IP}
sudo ip r add ${DN_CIDR} dev gtp5gtest

echo "############### UPF Part ###############"
${EXEC_NS2} ./gtp5g-link add gtp5gtest &
sleep 0.1
${EXEC_NS2} ./gtp5g-tunnel add far gtp5gtest 1 --action 2
${EXEC_NS2} ./gtp5g-tunnel add far gtp5gtest 2 --action 2 --hdr-creation 0 87 ${RAN_IP} 2152
${EXEC_NS2} ./gtp5g-tunnel add pdr gtp5gtest 1 --pcd 1 --hdr-rm 0 --ue-ipv4 ${UE_IP} --f-teid 78 ${UPF_IP} --far-id 1
${EXEC_NS2} ./gtp5g-tunnel add pdr gtp5gtest 2 --pcd 2 --ue-ipv4 ${UE_IP} --far-id 2 --gtpu-src-ip=${UPF_IP}
${EXEC_NS2} ip r add ${UE_CIDR} dev gtp5gtest

echo "############### Test UP ###############"
ping -c5 -I ${UE_IP} ${DN_IP}

echo "############## Stopping ##############"
sleep 1
sudo killall -15 gtp5g-link
sleep 1

if [ ${DUMP_NS} ]
then
    ${EXEC_NS2} kill -SIGINT ${TCPDUMP_PID}
fi

sudo ip link del gtp5gtest
sudo ip link del tap1
sudo ip link del tap2_peer
sudo ip link set dev brupf down
sudo brctl delbr brupf
sudo ip netns del ${NS2}
sudo ip addr del ${UE_IP}/32 dev lo
