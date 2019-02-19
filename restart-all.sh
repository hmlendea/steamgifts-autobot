function restart_unit {
    echo "Restarting $1..."
    sudo systemctl restart sgab@$1
}

for ENABLED_ACCOUNT in $(ls /etc/systemd/system/multi-user.target.wants | grep sgab | sed 's/^sgab@//g' | sed 's/.service$//g'); do
    restart_unit $ENABLED_ACCOUNT
done
