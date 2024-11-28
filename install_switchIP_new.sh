#!/bin/bash

workingdir=$1

if [ -z $workingdir ]; then
    workingdir="/opt/switchIP"
fi

if [ ! -d $workingdir ]; then
    mkdir -p $workingdir
    touch $workingdir/ip.txt
    touch $workingdir/netplan.txt
else
    echo "$workingdir is exist"
    exit 1
fi

cat > $workingdir/switchIP.sh <<'EOF'
#!/bin/bash
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--ip) check_list="$2"; shift ;;
        -n|--netplan) switch_list="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done
switch() {
    switch_list=$1
    while IFS= read -r line
    do
        if ! [ -f $line ]; then
            echo "$line not found"
            exit 2
        fi
    done < "$switch_list"
    lineFile=`cat $switch_list|wc -l`
    lineUsed=`cat $switch_list|grep -v -n bak$| awk -F: '{print $1}'`
    lineNew=1
    if [[ $lineUsed -lt $lineFile ]];
    then
        lineNew=$((lineUsed+1))
    else
        lineNew=1
    fi
    cat $switch_list | awk -F".bak" "{if (NR==$lineNew) { print \$1} else {print \$1\".bak\"}} " > ${switch_list}.tmp
    mv `sed -n "${lineUsed}p" $switch_list` `sed -n "${lineUsed}p" ${switch_list}.tmp`
    mv `sed -n "${lineNew}p" $switch_list` `sed -n "${lineNew}p" ${switch_list}.tmp`
    cat  ${switch_list}.tmp > $switch_list
    rm -rf ${switch_list}.tmp
    netplan apply
}
check() {
    ip_list=$1
    switch_list=$2
    down=0
    line_index=0
    if [ ! -s $ip_list ]; then
        echo "Need to verify IPs checklist"
        exit 3
    fi
    if [ ! -s $switch_list ]; then
        echo "Need to verify netplan config"
        exit 4
    fi
    while IFS= read -r line
    do
        ping -c5 $line > /dev/null
        if [ $? -eq 0 ]; then
            echo "$line up"
            down=0
        else
            echo "$line is unreachable"
            down=$((down+1))
        fi
        line_index=$((line_index+1))
    done < "$ip_list"
    if [[ $down -eq $line_index ]]; then
        switch $switch_list
    fi
    sleep 10
}
while true
do
    check $check_list $switch_list
done
EOF

cat > /lib/systemd/system/switchIP.service <<EOF
[Unit]
Description=switchIP service
After=network.target

[Service]
ExecStart=/bin/bash $workingdir/switchIP.sh --ip $workingdir/ip.txt --netplan $workingdir/netplan.txt
ExecStop=/bin/kill -- \$MAINPID
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
