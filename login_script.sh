#!/bin/bash
expect << 'DONE'
spawn ssh root@38.242.239.150
expect "password:"
send "kamil123\r"
expect "#"
send "cd ~/mojorust && echo '=== URUCHAMIANIE MOJORUST ===' && python3 run_automated_trading.py > trading_bot.log 2>&1 & echo 'Bot uruchomiony!' && ps aux | grep python3 | grep -v grep\r"
expect "#"
send "exit\r"
expect eof
DONE
