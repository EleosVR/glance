#!/bin/bash

## COLORS ##
NC="\033[0m" # no color
RED="\033[0;31m"
GREEN="\033[0;32m"
PURPLE="\033[0;35m"

## FILES ##
discord_file="$(dirname "$0")/discord.sh"
settings_file="$(dirname "$0")/settings.conf"
data_file="$(dirname "$0")/data.json"

if [ ! -f "$discord_file" ]; then
	printf "${RED}Error: discord.sh does not exist${NC}\n" >&2
	exit 1
fi
if [ ! -f "$settings_file" ]; then
	printf "${RED}Error: settings.conf does not exist${NC}\n" >&2
	printf "${GREEN}Downloading settings.conf from GitHub...${NC}\n" >&2
	
	if ! curl -o "$settings_file" -L https://raw.githubusercontent.com/EleosVR/glance/main/settings.conf; then
		printf "${RED}Failed to download settings.conf from GitHub${NC}\n" >&2
		exit 1
	fi
fi

source "$settings_file"

if [ -z "$DASHBOARD_URL" ]; then
	printf "${RED}Please set ${PURPLE}DASHBOARD_URL${RED} in the ${PURPLE}settings.conf${RED} file\n" >&2
fi
if [ -z "$DISCORD_WEBHOOK" ]; then
	printf "${RED}Please set ${PURPLE}DISCORD_WEBHOOK${RED} in the ${PURPLE}settings.conf${RED} file\n" >&2
fi
if [ -z "$DASHBOARD_URL" ] || [ -z "$DISCORD_WEBHOOK" ]; then
	exit 1
fi

## FUNCTIONS ##
api_call() {
	response=$(curl -s -L --fail "$1")

	if [ $? -ne 0 ]; then
		printf "${RED}Failed to reach api at line ${LINENO}: ${PURPLE}$1${NC}\n" >&2
		exit 1
	fi
	if ! jq '.' <<<"$response" >/dev/null 2>&1; then
		printf "${RED}Error: Response is not valid JSON, line ${LINENO}${NC}\n" >&2
		exit 1
	fi
	
	echo "$response"
}
convert_timestamp() {
	if [[ $1 =~ ^[0-9]+$ ]]; then
		time_difference=$1
	else
		# convert timestamp to seconds since Unix epoch
		timestamp_seconds=$(date -d "$1" +%s)
		
		# calculate current time in seconds since Unix epoch
		current_time_seconds=$(date +%s)
		
		# calculate the difference in seconds
		time_difference=$(("$current_time_seconds" - "$timestamp_seconds"))
	fi
	
	include_ago="${2:-true}"
	
	if [ "$time_difference" -eq 0 ]; then
		echo "$time_difference seconds"
	else
		years=$(("$time_difference" / 31536000))
		time_difference=$(("$time_difference" % 31536000))

		months=$(("$time_difference" / 2592000))
		time_difference=$(("$time_difference" % 2592000))

		days=$(("$time_difference" / 86400))
		time_difference=$(("$time_difference" % 86400))

		hours=$(("$time_difference" / 3600))
		time_difference=$(("$time_difference" % 3600))

		minutes=$(("$time_difference" / 60))

		if [ "$years" -gt 0 ]; then
			echo -n "$years year"
			[ "$years" -eq 1 ] || echo -n "s"
			echo -n ", "
		fi
		if [ "$months" -gt 0 ]; then
			echo -n "$months month"
			[ "$months" -eq 1 ] || echo -n "s"
			echo -n ", "
		fi
		if [ "$days" -gt 0 ]; then
			echo -n "$days day"
			[ "$days" -eq 1 ] || echo -n "s"
			echo -n ", "
		fi
		if [ "$hours" -gt 0 ]; then
			echo -n "$hours hour"
			[ "$hours" -eq 1 ] || echo -n "s"
			echo -n ", "
		fi
		if [ "$minutes" -gt 0 ]; then
			echo -n "$minutes minute"
			[ "$minutes" -eq 1 ] || echo -n "s"
		fi
		if [ "$time_difference" -lt 60 ]; then
            echo -n "$time_difference second"
            [ "$time_difference" -eq 1 ] || echo -n "s"
        fi
		
		[ "$include_ago" = true ] && echo " ago"
	fi
}
convert_bytes() {
	if [ $1 -lt 1000 ]; then
        # Bytes
        value=$1
        unit="B"
    elif [ $1 -lt 1000000 ]; then
        # KB
        value=$(awk "BEGIN {printf \"%.2f\", $1 / 1000}")
        unit="KB"
    elif [ $1 -lt 1000000000 ]; then
        # MB
        value=$(awk "BEGIN {printf \"%.2f\", $1 / 1000000}")
        unit="MB"
    elif [ $1 -lt 1000000000000 ]; then
        # GB
        value=$(awk "BEGIN {printf \"%.2f\", $1 / 1000000000}")
        unit="GB"
    else
        # TB
        value=$(awk "BEGIN {printf \"%.2f\", $1 / 1000000000000}")
        unit="TB"
    fi
	
	value=$(echo "$value" | sed 's/\.00//')
	
	echo "$value$unit"
}
convert_cents() {
	local value=$(awk "BEGIN {printf \"$%.2f\", $1 / 100}")
	
	echo $value
}
get_percentage() {
    local value=$(awk "BEGIN {printf \"%.2f\", ($1 / $2) * 100}")
	
	value=$(echo "$value" | sed 's/\.00//')
    
	echo "$value%"
}
get_estimated_time() {
    local current_space_used=$1
    local total_space_available=$2
    local data_added_since_start_month=$3
	local reset_time=$4

    # calculate time elapsed since the start of the month
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - reset_time))

    # calculate rate of data addition per second since the start of the month
    local data_addition_rate=$(bc <<< "scale=10; $data_added_since_start_month / $elapsed_time")

    # calculate estimated time until drive is full
    local estimated_time=$(bc <<< "scale=0; ($total_space_available - $current_space_used) / $data_addition_rate")

    echo "$estimated_time"
}

## API ##
request_1=$(api_call "$DASHBOARD_URL/api/sno/")
request_2=$(api_call "$DASHBOARD_URL/api/sno/estimated-payout/")
request_3=$(api_call "$DASHBOARD_URL/api/sno/satellites/")

## VARIABLES ##
nodeID=$(jq -r '.nodeID' <<< "$request_1")
used=$(jq -r '.diskSpace.used' <<< "$request_1")
available=$(jq -r '.diskSpace.available' <<< "$request_1")
trash=$(jq -r '.diskSpace.trash' <<< "$request_1")
overused=$(jq -r '.diskSpace.overused' <<< "$request_1")
node_ping=$(jq -r '.lastPinged' <<< "$request_1")
node_started=$(jq -r '.startedAt' <<< "$request_1")
quic_status=$(jq -r '.quicStatus' <<< "$request_1")
quic_ping=$(jq -r '.lastQuicPingedAt' <<< "$request_1")

current_payout=$(jq -r '.currentMonth.payout' <<< "$request_2")
current_held=$(jq -r '.currentMonth.held' <<< "$request_2")
expected_payout=$(jq -r '.currentMonthExpectations' <<< "$request_2")

bandwidth=$(jq -r '.bandwidthSummary' <<< "$request_3")
egress=$(jq -r '.egressSummary' <<< "$request_3")
ingress=$(jq -r '.ingressSummary' <<< "$request_3")
node_joined=$(jq -r '.earliestJoinedAt' <<< "$request_3")
satellite_audits=$(jq -r '.audits' <<< "$request_3")

## JSON ##
# check if the data file does not exist
if [ ! -f "$data_file" ]; then
	echo "{\"bandwidthSummary\": $bandwidth, \"previousUsedSpace\": $used, \"previousTrash\": $trash, \"resetTimestamp\": $(date +%s)}" > "$data_file"
fi

# check if a new month has NOT started (bandwidthSummary was NOT reset)
if [ "$bandwidth" -gt "$(jq '.bandwidthSummary' "$data_file")" ]; then
	jq -c --argjson newBandwidthSummary "$bandwidth" '.bandwidthSummary = $newBandwidthSummary' "$data_file" > tmpfile && mv tmpfile "$data_file"
fi

# check if a new month HAS started (bandwidthSummary WAS reset)
if [ "$bandwidth" -lt "$(jq '.bandwidthSummary' "$data_file")" ]; then
	jq -c --argjson newBandwidthSummary "$bandwidth" --argjson newUsed "$used" --argjson newTrash "$trash" --argjson newResetTimestamp "$(date +%s)" \
	'.bandwidthSummary = $newBandwidthSummary |
	.previousUsedSpace = $newUsed |
	.previousTrash = $newTrash |
	.resetTimestamp = $newResetTimestamp' \
    "$data_file" > tmpfile && mv tmpfile "$data_file"
fi

reset_timestamp="$(jq '.resetTimestamp' "$data_file")"
previous_used="$(jq '.previousUsedSpace' "$data_file")"
previous_trash="$(jq '.previousTrash' "$data_file")"

initial_used_space=$(("$previous_used" + "$previous_trash"))
current_total_used_space=$(("$used" + "$trash"))
data_difference=$(("$current_total_used_space" - "$initial_used_space"))

## SETTINGS ##
push_description=""
push_footer=""

if [ "$SHOW_NODE_ID" = false ]; then
	nodeID=""
fi
if [ "$TRIM_NODE_ID" = true ]; then
	nodeID="${nodeID:0:5}$(echo "${nodeID:5}" | sed 's/././g')"
fi

if [ "$SHOW_DASHBOARD_LINK" = true ]; then
	title_string="Open Dashboard"
fi
if [ "$SHOW_NODE_PING" = true ]; then
	push_description+="Node Pinged: $(convert_timestamp "$node_ping")"
	
	# spacing condition
	if [ "$SHOW_QUIC_PING" = true ]; then
		push_description+="\n"
	fi
fi
if [ "$SHOW_QUIC_PING" = true ]; then
	push_description+="Quic Pinged: $(convert_timestamp "$quic_ping"), $quic_status"
fi

# spacing condition
if ([ "$SHOW_NODE_PING" = true ] || [ "$SHOW_QUIC_PING" = true ]) && \
	([ "$SHOW_DISK_SPACE" = true ] || [ "$SHOW_DISK_PERCENTAGE" = true ] || [ "$SHOW_TRASH" = true ] || [ "$SHOW_TRASH_PERCENTAGE" = true ] || \
	[ "$SHOW_OVERUSED" = true ] || [ "$SHOW_OVERUSED_PERCENTAGE" = true ]); then
	
	push_description+="\n\n"
fi

if [ "$SHOW_DISK_SPACE" = true ] || [ "$SHOW_DISK_PERCENTAGE" = true ]; then
	push_description+="Total Disk Space: "
	
	if [ "$SHOW_DISK_SPACE" = true ]; then
		push_description+="$(convert_bytes "$used")/$(convert_bytes "$available")"
	fi
	if [ "$SHOW_DISK_SPACE" = true ] && [ "$SHOW_DISK_PERCENTAGE" = true ]; then
		push_description+=" ("
	fi
	if [ "$SHOW_DISK_PERCENTAGE" = true ]; then
		push_description+="$(get_percentage "$used" "$available")"
	fi
	if [ "$SHOW_DISK_SPACE" = true ] && [ "$SHOW_DISK_PERCENTAGE" = true ]; then
		push_description+=")"
	fi
	
	# spacing condition
	if [ "$SHOW_TRASH" = true ] || [ "$SHOW_TRASH_PERCENTAGE" = true ] || [ "$SHOW_OVERUSED" = true ] || [ "$SHOW_OVERUSED_PERCENTAGE" = true ]; then
		push_description+="\n"
	fi
fi

if [ "$SHOW_TRASH" = true ] || [ "$SHOW_TRASH_PERCENTAGE" = true ]; then
	push_description+="Trash: "
	
	if [ "$SHOW_TRASH" = true ]; then
		push_description+="$(convert_bytes "$trash")"
	fi
	if [ "$SHOW_TRASH" = true ] && [ "$SHOW_TRASH_PERCENTAGE" = true ]; then
		push_description+=" ("
	fi
	if [ "$SHOW_TRASH_PERCENTAGE" = true ]; then
		push_description+="$(get_percentage "$trash" "$available")"
	fi
	if [ "$SHOW_TRASH" = true ] && [ "$SHOW_TRASH_PERCENTAGE" = true ]; then
		push_description+=")"
	fi
	
	# spacing condition
	if [ "$SHOW_OVERUSED" = true ] || [ "$SHOW_OVERUSED_PERCENTAGE" = true ]; then
		push_description+="\n"
	fi
fi

if [ "$SHOW_OVERUSED" = true ] || [ "$SHOW_OVERUSED_PERCENTAGE" = true ]; then
	push_description+="Overused: "
	
	if [ "$SHOW_OVERUSED" = true ]; then
		push_description+="$(convert_bytes "$overused")"
	fi
	if [ "$SHOW_OVERUSED" = true ] && [ "$SHOW_OVERUSED_PERCENTAGE" = true ]; then
		push_description+=" ("
	fi
	if [ "$SHOW_OVERUSED_PERCENTAGE" = true ]; then
		push_description+="$(get_percentage "$overused" "$available")"
	fi
	if [ "$SHOW_OVERUSED" = true ] && [ "$SHOW_OVERUSED_PERCENTAGE" = true ]; then
		push_description+=")"
	fi
fi

# spacing condition
if ([ "$SHOW_NODE_PING" = true ] || [ "$SHOW_QUIC_PING" = true ] || [ "$SHOW_DISK_SPACE" = true ] || [ "$SHOW_DISK_PERCENTAGE" = true ] || \
	[ "$SHOW_TRASH" = true ] || [ "$SHOW_TRASH_PERCENTAGE" = true ] || [ "$SHOW_OVERUSED" = true ] || [ "$SHOW_OVERUSED_PERCENTAGE" = true ]) && \
	([ "$SHOW_EGRESS" = true ] || [ "$SHOW_INGRESS" = true ]); then
	
	push_description+="\n\n"
fi

if [ "$SHOW_EGRESS" = true ]; then
	push_description+="Egress: $(convert_bytes "$egress")"
	
	# spacing condition
	if [ "$SHOW_INGRESS" = true ]; then
		push_description+="\n"
	fi
fi
if [ "$SHOW_INGRESS" = true ]; then
	push_description+="Ingress: $(convert_bytes "$ingress")"
fi

# spacing condition
if ([ "$SHOW_NODE_PING" = true ] || [ "$SHOW_QUIC_PING" = true ] || [ "$SHOW_DISK_SPACE" = true ] || [ "$SHOW_DISK_PERCENTAGE" = true ] || \
	[ "$SHOW_TRASH" = true ] || [ "$SHOW_TRASH_PERCENTAGE" = true ] || [ "$SHOW_OVERUSED" = true ] || [ "$SHOW_OVERUSED_PERCENTAGE" = true ] || \
	[ "$SHOW_EGRESS" = true ] || [ "$SHOW_INGRESS" = true ]) && \
	([ "$SHOW_PAYOUT" = true ] || [ "$SHOW_PAYOUT_HELD" = true ]); then
	
	push_description+="\n\n"
fi

if [ "$SHOW_PAYOUT" = true ] || [ "$SHOW_PAYOUT_HELD" = true ]; then
	push_description+="Estimated Payout: "
	
	if [ "$SHOW_PAYOUT" = true ]; then
		push_description+="$(convert_cents "$current_payout")/$(convert_cents "$expected_payout")"
	fi
	if [ "$SHOW_PAYOUT" = true ] && [ "$SHOW_PAYOUT_HELD" = true ]; then
		push_description+=" ("
	fi
	if [ "$SHOW_PAYOUT_HELD" = true ]; then
		push_description+="-$(convert_cents "$current_held") held"
	fi
	if [ "$SHOW_PAYOUT" = true ] && [ "$SHOW_PAYOUT_HELD" = true ]; then
		push_description+=")"
	fi
fi

# spacing condition
if ([ "$SHOW_NODE_PING" = true ] || [ "$SHOW_QUIC_PING" = true ] || [ "$SHOW_DISK_SPACE" = true ] || [ "$SHOW_DISK_PERCENTAGE" = true ] || \
	[ "$SHOW_TRASH" = true ] || [ "$SHOW_TRASH_PERCENTAGE" = true ] || [ "$SHOW_OVERUSED" = true ] || [ "$SHOW_OVERUSED_PERCENTAGE" = true ] || \
	[ "$SHOW_EGRESS" = true ] || [ "$SHOW_INGRESS" = true ] || [ "$SHOW_PAYOUT" = true ] || [ "$SHOW_PAYOUT_HELD" = true ]) && \
	[ "$SHOW_SAT_SCORES" = true ]; then
	
	push_description+="\n\n"
fi

if [ "$SHOW_SAT_SCORES" = true ]; then
	for row in $(echo "${satellite_audits}" | jq -c '.[]'); do
		satellite_name=$(echo "${row}" | jq -r '.satelliteName' | cut -d'.' -f1)
		suspension_score=$(echo "${row}" | jq -r '.suspensionScore * 100' | awk '{if ($0 == int($0)) printf "%.0f", $0; else printf "%.2f", $0}')
		audit_score=$(echo "${row}" | jq -r '.auditScore * 100' | awk '{if ($0 == int($0)) printf "%.0f", $0; else printf "%.2f", $0}')
		online_score=$(echo "${row}" | jq -r '.onlineScore * 100' | awk '{if ($0 == int($0)) printf "%.0f", $0; else printf "%.2f", $0}')

		if [ "$SHORT_SAT_SCORES" = true ]; then
			push_description+="$satellite_name - S: $suspension_score%, A: $audit_score%, O: $online_score%\n"
		else
			push_description+="$satellite_name - Suspension: $suspension_score%, Audit: $audit_score%, Online: $online_score%\n"
		fi
	done
fi

if [ "$SHOW_NODE_UPTIME" = true ]; then
	push_footer+="- Uptime: $(convert_timestamp "$node_started" false)"
	
	# spacing condition
	if [ "$SHOW_NODE_AGE" = true ] || [ "$SHOW_FILL_TIME" = true ]; then
		push_footer+="\n"
	fi
fi
if [ "$SHOW_NODE_AGE" = true ]; then
	push_footer+="- Node Age: $(convert_timestamp "$node_joined" false)"
	
	# spacing condition
	if [ "$SHOW_FILL_TIME" = true ]; then
		push_footer+="\n"
	fi
fi

if [ "$SHOW_FILL_TIME" = true ]; then
	if [ "$(($used - $previous_used))" -ne 0 ]; then
		push_footer+="- Estimated Time Until Full: $(convert_timestamp "$(get_estimated_time "$used" "$available" "$data_difference" "$reset_timestamp")" false)"
	else
		push_footer+="- Estimated Time Until Full: ∞"
	fi
fi

## DISCORD ##
if [ "$quic_status" = "OK" ]; then
	push_color=0x519e62
else
	push_color=0xda2f2f
fi

"$discord_file" --webhook-url="$DISCORD_WEBHOOK" --color "$push_color" --author "$nodeID" --title "$title_string" --url "$DASHBOARD_URL" --description "$push_description" --footer "$push_footer"
