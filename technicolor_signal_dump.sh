#!/bin/bash

# technicolor_signal_dump.sh
# HomeAssistant scraper script for Technicolor TC4400 cable modem
#
# Based on the Arris and Netgear scraper scripts by mmiller7:
# * https://github.com/mmiller7/Arris_modem_scrape
# * https://github.com/mmiller7/Netgear_modem_scrape
#
# The script reads the software and connection status pages from the
# web interface of a Technicolor TC4400 cable modem. It parses them into
# MQTT messages compatible with HomeAssistant's automatic discovery 
# of devices and sensors.
# 
# Copyright (c) 2023 "Philipp Reichmuth" <philipp.reichmuth@gmail.com>
#
# License: CC-BY-SA-NC 4.0
# https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode 
# The original scripts by mmiller7 were published without a license.

# Default admin password is bEn2o#US9s
modem_url="http://192.168.100.1"
modem_username="admin"
modem_password="bEn2o#US9s"

# Settings for MQTT mqtt_broker to publish stats
mqtt_broker="127.0.0.1"
mqtt_username="your_mqtt_username_here"
mqtt_password="your_mqtt_password_here"

# Settings for HomeAssistant MQTT autodiscovery
mqtt_topic_prefix="homeassistant/sensor"
mqtt_uid_prefix="cablemodem"

# MQTT logging topic
mqtt_logging_topic="homeassistant/sensor/technicolor_scraper"

# Helper for writing to stderr
function echoerr() { echo "$@" 1>&2 ; } 

# HomeAssistant does not expose the mosquitto_pub binary to containers.
# So if we use a container installation, we have to make the binary and libraries available.
#
# Comment these out for a "normal" host that knows where mosquitto_pub is on its own
#export LD_LIBRARY_PATH='/config/bin/mosquitto_deps/lib'
#mqtt_pub_exe="/config/bin/mosquitto_deps/mosquitto_pub"

# Uncomment this for a "normal" host that knows where mosquitto_pub is on its own
#mqtt_pub_exe="mosquitto_pub"

# For debugging
mqtt_pub_exe="echo mosquitto_pub"

# Test if we have a working mosquitto_pub
if ! command -v ${mqtt_pub_exe} &> /dev/null
then
	echoerr "Mosquitto MQTT client '$mqtt_pub_exe' not found"
	exit 10
fi

#####################################
# Prep functions to interface modem #
#####################################

# Set the authentication info
function setAuthHash() {
	# Base-64 encode the user password to log into the modem
	# Note: must not have any newlines
	auth_hash=`echo -n "${modem_username}:${modem_password}" | base64`
	#echo "The auth_hash is [${auth_hash}]"
}

# This function publishes login status helpful for debugging
function loginStatus () {
	#echo "Modem login: $1"
	# Publish MQTT to announce status
	message="{ \"login\": \"$1\" }"
	echo "${mqtt_logging_topic}/login: ${message}"
	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${mqtt_logging_topic}/login" -m "$message" || { echoerr "MQTT error posting logging message ${message} to topic ${mqtt_logging_topic}/login" ; exit 20 ; } 
}

# Technicolor modems use basic HTTP authentification, we don't need complex handling of login scripts and tokens.
# This function fetches the CM SW info page from the modem for parsing
function getSWInfo () {
	result=$(curl --connect-timeout 20 -s "${modem_url}/cmswinfo.html" -H 'Accept: */*' -H 'Content-Type: application/x-www-form-urlencoded; charset=utf-8' -H "Authorization: Basic ${auth_hash}" -H 'X-Requested-With: XMLHttpRequest' -H 'Cookie: HttpOnly: true, Secure: true') || { echoerr "curl error accessing software info page" ; exit 22 ; } 
}

# This function fetches the connection status page from the modem for parsing
function getConnStatus () {
	result=$(curl --connect-timeout 20 -s "${modem_url}/cmconnectionstatus.html" -H 'Accept: */*' -H 'Content-Type: application/x-www-form-urlencoded; charset=utf-8' -H "Authorization: Basic ${auth_hash}" -H 'X-Requested-With: XMLHttpRequest' -H 'Cookie: HttpOnly: true, Secure: true') || { echoerr "curl error accessing connection status page" ; exit 22 ; } 
}

###############
# Preparation #
###############

# Set up authentification
setAuthHash;

# No need to get a token for logging into the modem
# getToken;

###################################
# Step 1: Cable modem information #
###################################

# Get the info page from the modem
echo "Getting SW info"
getSWInfo;

# See if we were successful
# Yes, it really says "Getway" in the title
if [ "$(echo "$result" | grep -c '<title>Residential Getway Configuration: Status - Software</title>')" == "0" ]; then
	echoerr "Got bad response retrieving software information page from modem. Retrying"
	echoerr "Result string: \n${result}"
	loginStatus "failed_retrying"

#	# If we failed (got a login prompt) try once more for new token
#	eraseToken;
#	getToken;
	getSWInfo;
fi

# See if we were successful
if [ "$(echo "$result" | grep -c '<title>Residential Getway Configuration: Status - Software</title>')" == "0" ]; then
	# At this point, if we weren't successful, we give up
	echoerr "Got bad response retrieving software information page modem on the second attempt. Exiting"
	echoerr "Result string: \n${result}"
	loginStatus "failed"
	exit 21
else
	loginStatus "success"
fi

####################
# Parse the result #
####################

sw_information=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/kHz/000/g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g;s/<[/]\?[bui]>//g' | awk -F "<tableborder=\"1\"cellpadding=\"3\"cellspacing=\"0\">|</table>" '{print $2}')
sw_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/kHz/000/g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g;s/<[/]\?[bui]>//g' | awk -F "<tableborder=\"1\"cellpadding=\"3\"cellspacing=\"0\">|</table>" '{print $4}')

sw_information_rows=$(echo "$sw_information" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
sw_status_rows=$(echo "$sw_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')

cm_info=$(echo "$sw_information_rows\\n$sw_status_rows" | sed 's/<th[^>]*>[^<]*<\/th>//g;s/^<td[^>]*>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g' | grep -v "^$" | tr '\n' '\t')

# At this moment we have a tab-delimited string with the following information and its indexes when parsed with awk:
# StandardSpecificationCompliant  Docsis3.1 ($2)
# HardwareVersion TC4400Rev:3.6.0 ($4)
# SoftwareVersion 70.12.43-190628 ($6)
# CableModemMACAddress    (MAC Address) ($8)
# CableModemSerialNumber  (Serial number) ($10)
# CMcertificate   Installed ($12)
# SystemUpTime    1days00h:07m:22s ($14)
# NetworkAccess   Allowed ($16)
# CableModemIPv4Address   IPv4=(some address) ($18)
# CableModemIPv6Address   IPv6=(some address) ($20)
# BoardTemperature        -99.0degreesCelsius ($22)
# 
# Extract the info we want 
serial_number=$(echo $cm_info | awk '{print $10}')
hw_version=$(echo $cm_info | awk '{print $4}')
sw_version=$(echo $cm_info | awk '{print $6}')
mac_address=$(echo $cm_info | awk '{print $8}')
# Generate updime in seconds - I'm sure there is a better way
uptime=$(echo $cm_info | awk '{print $14}' | sed 's/days/d /;s/:/ /g;s/ 0/ /g;')
addr_ipv4=$(echo $cm_info | awk '{print $18}' | sed 's/IPv4=//;')
addr_ipv6=$(echo $cm_info | awk '{print $20}' | sed 's/IPv6=//;')

echo "Serial number: $serial_number"
echo "Hardware version: $hw_version"
echo "Software version: $sw_version"
echo "Modem MAC Address: $mac_address"
echo "Modem IPv4 Address: $addr_ipv4"
echo "Modem IPv6 Address: $addr_ipv6"
echo "Uptime: $uptime"


modem_id="$mqtt_uid_prefix$serial_number"
mqtt_topic="$mqtt_topic_prefix/$modem_id"

#############################
# Step 2: Connection status #
#############################
# Get the connection status page from the modem
echo "Getting connection status"
getConnStatus;

# See if we were successful
# Yes, it really says "Getway" in the title
if [ "$(echo "$result" | grep -c '<title>Residential Getway Configuration: Status - Connection</title>')" == "0" ]; then
	echoerr "Got bad response retrieving connection status from modem. Retrying"
	echoerr "Result string: \n${result}"
	loginStatus "failed_retrying"

#	# If we failed (got a login prompt) try once more for new token
#	eraseToken;
#	getToken;
	getConnStatus;
fi

# See if we were successful
if [ "$(echo "$result" | grep -c '<title>Residential Getway Configuration: Status - Connection</title>')" == "0" ]; then
	# At this point, if we weren't successful, we give up
	echoerr "Got bad response retrieving connection status from modem on the second attempt. Exiting"
	echoerr "Result string: \n${result}"
	loginStatus "failed"
	exit 21
else
	loginStatus "success"
fi

# Helper function to build configuration messages for sensors
function pubConfigMessage () {

	# Sample config message
	# config_message="{\"name\": \"Channel ${index} Frequency\", \"device_class\": \"frequency\", \"state_topic\": \"${state_topic}\", \"unit_of_measurement\": \"Hz\", \"value_template\": \"{{ value_json.frequency}}\",\"unique_id\": \"${modem_id}_d${index}_frequency\", \"device\": {\"identifiers\": [\"${serial_number}\",\"${modem_id}\"], \"name\": \"Cable modem TC4400\" }}"

	# Break out field information from the command line
	# Descriptive name for the whole sensor (e.g. "Down 22")
	config_name="$1"
	# MQTT topic where the sensor data will be published
	config_state_topic="$2"
	# Infix for the unique ID of the sub-sensors (e.g. "down22")
	config_infix="$3"
	# Suffix for identifying each sub-sensor in MQTT topics (e.g. "freq")
	config_suffix="$4"
	# Suffix for identifying each sub-sensor descriptively (optional, e.g. "Frequency")
	config_suffix_descriptive="$5"
	# State class, so that Home Assistant can generate proper statistics (optional: one of "measurement", "total", "total_increasing")
	config_state_class="$6"
	# Unit of measurement (optional, e.g. "Hz")
	config_unit="$7"
	# Device class for the sensor (optional, e.g. "frequency")
	config_device_class="$8"
	
	# Derive config topic from state topic
	config_topic="${config_state_topic}_${config_suffix}/config"
	
	# Build the config message payload
	#config_message="\"name\": \"Channel ${config_index}"
	config_message="\"name\": \"${config_name}"
	if [ "${config_suffix_descriptive}" != "" ]; then
		config_message="${config_message} ${config_suffix_descriptive}"	   
	fi
	config_message="${config_message}\", "
	
	config_message="${config_message} \"state_topic\": \"${config_state_topic}\", "
	# Unique ID
	config_message="${config_message} \"unique_id\": \"${modem_id}_${config_infix}_${config_suffix}\", "
	# Where to get the data from in the state message
	config_message="${config_message} \"value_template\": \"{{ value_json.${config_suffix} }}\", "		

	# Add device class if we have one
	if [ "${config_device_class}" != "" ]; then
		config_message="${config_message} \"device_class\": \"${config_device_class}\", "	   
	fi

	# Add state class if we have one
	if [ "${config_state_class}" != "" ]; then
		config_message="${config_message} \"state_class\": \"${config_state_class}\", "	   
	fi

	# Add unit of measurement if we have one
	if [ "${config_unit}" != "" ]; then
		config_message="${config_message} \"unit_of_measurement\": \"${config_unit}\", "	   
	fi

	# Add reference to our device
	config_message="${config_message} \"device\": "
	config_message="${config_message} {"
	config_message="${config_message} \"identifiers\": [\"${serial_number}\",\"${modem_id}\"], "
	config_message="${config_message} \"manufacturer\": \"Technicolor\", "
	config_message="${config_message} \"model\": \"TC4400\", "
	config_message="${config_message} \"name\": \"TC4400\", "
	config_message="${config_message} \"configuration_url\": \"${modem_url}\", "
	config_message="${config_message} \"hw_version\": \"${hw_version}\", "
	config_message="${config_message} \"sw_version\": \"${sw_version}\", "
	config_message="${config_message} \"connections\": [[\"mac\", \"${mac_address}\"]]"
	config_message="${config_message} }"

	config_message="{ ${config_message} }"
	# Publish (persistent with -r, so that the device doesn't disappear)
	$mqtt_pub_exe -r -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${config_topic}" -m "${config_message}" || { echoerr "MQTT error posting config message ${config_message} to topic ${config_topic}" ; exit 20 ; } 
}

####################
# Parse the result #
####################

startup_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/kHz/000/g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g;s/<[/]\?[bui]>//g' | awk -F "<tableborder=\"1\"cellpadding=\"4\"cellspacing=\"0\">|</table>" '{print $2}')
downstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/kHz/000/g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<tableborder='1'cellpadding='4'cellspacing='0'>|</table>" '{print $3}')
upstream_status=$(echo "$result" | tr '\n' ' ' | sed 's/\t//g;s/ //g;s/dBmV//g;s/dB//g;s/kHz/000/g;s/Hz//g;s/<[/]\?strong>//g;s/<![^>]*>//g' | awk -F "<tableborder='1'cellpadding='4'cellspacing='0'>|</table>" '{print $5}')

# Break out by line
startup_rows=$(echo "$startup_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
downstream_rows=$(echo "$downstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')
upstream_rows=$(echo "$upstream_status" | sed 's/^<tr>//g;s/<\/tr>$//g;s/<\/tr><tr[^>]*>/\n/g')

echo "Parsing startup status"

# Parse out the startup status HTML table into JSON and publish
to_parse=$(echo "$startup_rows" | sed 's/<th[^>]*>[^<]*<\/th>//g;s/^<td[^>]*>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g' | grep -v "^$" | tr '\n' '\t')
# At this moment we have a tab-delimited string with the following information and its indexes when parsed with awk:
# Procedure       Status  Comment 
# AcquireDownstreamChannel        570000000 ($5)      Locked ($6)  
# ConnectivityState       OK ($8)      Operational ($9)
# BootState       OK ($11)     Operational ($12)
# ConfigurationFile       OK ($14)      bac10402000300018c6a8d0c8d48 ($15)
# Security   Enabled  ($17) BPI+ ($18)
#
# In addition, we can use some of our earlier variables, e.g. $uptime, $addr_ipv4, $addr_ipv6.

state_topic="${mqtt_topic}_status"
pubConfigMessage "Modem" ${state_topic} "status" "channel" "Channel State"
pubConfigMessage "Modem" ${state_topic} "status" "frequency" "Downstream Channel" "measurement" "Hz" "frequency"
pubConfigMessage "Modem" ${state_topic} "status" "connectivity" "Connectivity State"
pubConfigMessage "Modem" ${state_topic} "status" "boot" "Boot State"
pubConfigMessage "Modem" ${state_topic} "status" "security" "Security State"
pubConfigMessage "Modem" ${state_topic} "status" "secservice" "Security Service"
pubConfigMessage "Modem" ${state_topic} "status" "configfile" "Configuration File Hash"
pubConfigMessage "Modem" ${state_topic} "status" "uptime" "Uptime" 
pubConfigMessage "Modem" ${state_topic} "status" "addr_ipv4" "IPv4 Address"
pubConfigMessage "Modem" ${state_topic} "status" "addr_ipv6" "IPv6 Address"

state_message=""
state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"channel\": \""$6"\", " }')"
state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"frequency\": "$5", " }')"
state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"connectivity\": \""$9"\", " }')"
state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"boot\": \""$12"\", " }')"
state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"security\": \""$17"\", " }')"
state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"secservice\": \""$18"\", " }')"
state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"configfile\": \""$15"\", " }')"
state_message="${state_message}\"uptime\": \"${uptime}\", "
state_message="${state_message}\"addr_ipv4\": \"${addr_ipv4}\", "
state_message="${state_message}\"addr_ipv6\": \"${addr_ipv6}\""
state_message="{ ${state_message} }" 
$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${state_topic}" -m "${state_message}" || { echoerr "MQTT error posting modem status ${state_message} to topic ${state_topic}" ; exit 20 ; }

# Parse out the downstream HTML table into JSON and publish
# One sensor per downstream channel
echo "Parsing downstream channels"
counter=0
echo "$downstream_rows" | tail -n +3 | while read -r line; do
	counter=$(($counter+1))
	#echo "${mqtt_topic}/downstream/$counter"
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')
	
	# At this moment we have the following tab-separated data structure:
	# awk '{print "\"Channel\": "$1","
	# 		print "\"ChannelID\": "$2","
	# 		print "\"LockStatus\": \""$3"\","
	# 		print "\"ChannelType\": \""$4"\","
	# 		print "\"BondingStatus\": \""$5"\","
	# 		print "\"CenterFrequency\": "$6","
	# 		print "\"ChannelWidth\": "$7","
	# 		print "\"SNRMERThreshold\": "$8","
	# 		print "\"ReceivedLevel\": "$9","
	# 		print "\"ModulationProfileID\": \""$10"\","
	# 		print "\"Unerrored\": "$11","
	# 		print "\"Corrected\": "$12","
	# 		print "\"Uncorrectable\": "$13}'

	# We want our channel sensor IDs to be independent of the arbitrary ordering on the status page
	# index=$counter
	index=$(echo $to_parse | awk '{print $2}')
	state_topic="${mqtt_topic}_downstream${index}"

	echo "Publishing downstream channel ${index}"
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "id" "ID"
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "type" "Type"
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "frequency" "Frequency" "measurement" "Hz" "frequency"  
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "width" "Width" "measurement" "Hz" "frequency"
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "power" "Power" "measurement" "dBmV"  
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "profile" "Modulation Profile"
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "lockstatus" "Lock Status"
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "bondingstatus" "Bonding Status"
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "snr" "SNR" "measurement" "dB" "signal_strength"  
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "noerr" "Error-free" "total_increasing" "B" "data_size"  
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "corr" "Corrected" "total_increasing" "B" "data_size"  
	pubConfigMessage "Down ${index}" ${state_topic} "downstream${index}" "uncorr" "Uncorrectable" "total_increasing" "B" "data_size"  
    
	state_message=""
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"id\": "$2", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"type\": \""$4"\", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"frequency\": "$6", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"width\": "$7", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"snr\": "$8", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"power\": "$9", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"profile\": \""$10"\", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"lockstatus\": \""$3"\", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"bondingstatus\": \""$5"\", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"noerr\": "$11", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"corr\": "$12", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"uncorr\": "$13 }')"
	state_message="{ ${state_message} }" 

	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${state_topic}" -m "${state_message}" || { echoerr "MQTT error posting downstream channel status ${state_message} to topic ${state_topic}" ; exit 20 ; }
done

# Parse out the upstream HTML table into JSON and publish
echo "Parsing upstream channels"
counter=0
echo "$upstream_rows" | tail -n +3 | while read -r line; do
	counter=$(($counter+1))
	to_parse=$(echo "$line" | sed 's/<th[^>]*>[^<]*<\/th><\/tr>//g;s/^<td>//g;s/<\/td>$//g;s/<\/td><td[^>]*>/\t/g')

	# At this moment we have the following tab-separated data structure:
	# awk '{print "\"Channel\": "$1","
	# 		print "\"ChannelID\": "$2","
	# 		print "\"LockStatus\": \""$3"\","
	# 		print "\"ChannelType\": \""$4"\","
	# 		print "\"BondingStatus\": \""$5"\","
	# 		print "\"CenterFrequency\": "$6","
	# 		print "\"ChannelWidth\": "$7","
	# 		print "\"TransmitLevel\": "$8","
	# 		print "\"ModulationProfileID\": \""$9"\""}'

	index=${counter}
	state_topic="${mqtt_topic}_upstream${index}"

	echo "Publishing upstream channel ${index}"
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "id" "ID"
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "type" "Type"
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "frequency" "Frequency" "measurement" "Hz" "frequency"  
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "width" "Width" "measurement" "Hz" "frequency"
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "power" "Power" "measurement" "dBmV"  
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "profile" "Modulation Profile"
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "lockstatus" "Lock Status"
	pubConfigMessage "Up ${index}" ${state_topic} "upstream${index}" "bondingstatus" "Bonding Status"
    
	state_message=""
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"id\": "$2", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"type\": \""$4"\", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"frequency\": "$6", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"width\": "$7", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"power\": "$8", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"profile\": \""$9"\", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"lockstatus\": \""$3"\", " }')"
	state_message="${state_message}$(echo "$to_parse" | awk '{ print "\"bondingstatus\": \""$5"\"" }')"
	state_message="{ ${state_message} }" 

	$mqtt_pub_exe -h "$mqtt_broker" -u "$mqtt_username" -P "$mqtt_password" -t "${state_topic}" -m "${state_message}" || { echoerr "MQTT error posting upstream channel status ${state_message} to topic ${state_topic}" ; exit 20 ; }
done

echo "Done."
