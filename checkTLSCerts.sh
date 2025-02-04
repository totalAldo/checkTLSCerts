#!bin/bash

# This script checks the expiration date of the TLS certificates of the given servers in parallel.
# It uses a timeout for each check, and exits gracefully on timeout.

# List of your web servers (one per line)
servers=(
  "server1.domain.com"
  "server2.domain.com"
)

# Set timeout in seconds
TIMEOUT_DURATION=3

# Use 'timeout' or 'gtimeout' if available
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD=gtimeout
else
    echo "Error: neither 'timeout' nor 'gtimeout' is available. Please install coreutils."
    exit 1
fi

for server in "${servers[@]}"; do
    (
        # Determine host and port
        if [[ "$server" == *:* ]]; then
            host="${server%%:*}"
            port="${server##*:}"
        else
            host="$server"
            port=443
        fi

        # Retrieve the certificate (extract the PEM block) with timeout
        cert=$($TIMEOUT_CMD $TIMEOUT_DURATION bash -c "echo | openssl s_client -servername '$host' -connect '$host:$port' 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'")
        exitcode=$?

        if [ $exitcode -eq 124 ]; then
            echo "Timeout occurred while connecting to $server"
            exit 0
        elif [ -z "$cert" ]; then
            echo "No certificate found for $server"
            exit 0
        fi

        # Extract the expiration date from the certificate.
        # Example output: "notAfter=Jul 25 12:00:00 2025 GMT"
        end_date=$(echo "$cert" | openssl x509 -noout -enddate | cut -d= -f2)

        # Convert the expiration date to epoch seconds using FreeBSD date.
        # The format string "%b %d %T %Y %Z" matches strings like "Jul 25 12:00:00 2025 GMT"
        exp_epoch=$(date -j -f "%b %d %T %Y %Z" "$end_date" "+%s")

        # Get current time in epoch seconds
        now_epoch=$(date +%s)

        # Calculate remaining days (86400 seconds per day)
        days_left=$(((exp_epoch - now_epoch) / 86400))

        echo "$days_left days left [$end_date] for $server"
    ) &
done

# wait for all background processes to complete
wait

echo "All done"
