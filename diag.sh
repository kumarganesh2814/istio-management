#!/usr/bin/env bash
 
diagdata="/tmp/diagdata"
rm -rf ${diagdata}
mkdir -p ${diagdata}
 
envoylog_proc=""
tcpdump_proc=""
 
ctrl_cb()
{
    kill -9 ${envoylog_proc}
    kill -15 ${tcpdump_proc}
 
    wait ${envoylog_proc}
    wait ${tcpdump_proc}
    exit 0
}
 
execute_cmd()
{
    local cmd=$1
    local ofile=$2
 
    exec >> "${diagdata}/${ofile}" 2>&1
    echo "====================================================="
    date
    echo "====================================================="
    eval ${cmd}
}
 
 
trap ctrl_cb 2
 
nohup tcpdump -iany -w ${diagdata}/proxy.pcap &
tcpdump_proc=$!
 
envoy_pid=$(pgrep envoy)
nohup cat /proc/${envoy_pid}/fd/2 > ${diagdata}/proxy.log 2>&1 &
envoylog_proc=$!
 
execute_cmd "curl http://localhost:15000/config_dump" "envoy_config_dump"
 
while true
do
    execute_cmd "netstat -tulnap" "netstat"
 
    execute_cmd "lsof -itcp" "lsof"
 
    execute_cmd "dmesg --level=crit,err,warn" "dmesg"
 
    execute_cmd "curl http://localhost:15000/stats" "envoy_sats"
 
    sleep 0.5
done
