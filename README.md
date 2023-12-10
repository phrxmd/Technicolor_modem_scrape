# Technicolor Modem MQTT Scraper

This script is for monitoring signal quality on a Technicolor cable modem through MQTT. It allow you to scrape the modem status data and write it out to a MQTT broker. You can then use something like Home Assistant to take actions based on the data: graph it, issue automations to cycle a smartplug, etc.

You can run the script on any Unix/Linux computer that (a) can see both the modem and the MQTT broker and (b) has a working `mosquitto_pub`, or you can run it on a Home Assistant instance itself.

## Files 

- `technicolor_signal_dump.sh` - the script which logs into the modem and scrapes/parses the data publishing JSON to MQTT 
- `technicolor_modem_scrape.yaml` - YAML configuration examples for Home Assistant

## What the script does

The script does the following:

- Log into the modem's status pages using a username/password combination specified by the user
- Scrape the modem's status pages for connection information
- Publish the modem as a device, with manufacturer, hardware and software versions, serial number
- Publish the modem state as a sensor ("Modem"), with channel and connectivity state, connected frequency, IPv4 and IPv6 addresses and modem uptime
- For each downstream channel X, publish a sensor ("Down X") with the connection information for that channel (ID, frequency, width, SNR, received power level, modulation profile, lock and bonding status, error correction)
- For each upstream channel Y, publish a sensor ("Up Y") with the connection information for that channel (ID, type, frequency, width, transmission power level, modulation profile, lock and bonding status)
- Publish a sensor for the active connected channel ("Active"). If a connected channel is found, publish its state as "Active", as well as channel ID, frequency, SNR and power. If no connected channel is found, publish its state as "Inactive".

## MQTT Discovery and sensor entities 

The script publishes sensor information via MQTT Discovery. Home Assistant will pick this up automatically and generate appropriate sensor entities. Other [third-party tools that support MQTT Discovery](https://www.home-assistant.io/integrations/mqtt#support-by-third-party-tools) should pick it up as well. 

If your system does not support MQTT Discovery, you may need to set up appropriate sensor entities by hand, using the MQTT topics published by the script. By default, the MQTT topics are set up as follows, where `XXXX` is the serial number of your modem. 

- `homeassistant/sensor/technicolor_scraper/login` - if the script was able to log into the modem, set to `success`, otherwise `failed` after two failed attempts.  
- `homeassistant/sensor/cablemodemXXXX_status` - general status information for the modem 
- `homeassistant/sensor/cablemodemXXXX_active` - connection quality for the active channel
- `homeassistant/sensor/cablemodemXXXX_downstreamN` - link quality information for downstream channel `N`
- `homeassistant/sensor/cablemodemXXXX_upstreamN` - link quality information for downstream channel `N`

If you are not running Home Assistant, the prefixes `homeassistant/sensor` and `cablemodem` are configurable in the script.

### Multiple modems

If you have multiple Technicolor modems, the script should support scraping and publishing multiple modems separately. You need to set up a separate copy of the script for each modem. If you want to keep track of login attempts on each modem separately, you can set `mqtt_logging_topic` separately for each modem. This is untested.

## Installation process for Home Assistant

Here's how to get the script working in Home Assistant. If you're using something else than Home Assistant, you need to figure out how to get it working yourself (install the file, make sure it can use Mosquitto to publish things to MQTT, and set it up to run at regular intervals).

The prerequisite on Home Assistant is to have [MQTT configured and working](https://www.home-assistant.io/integrations/mqtt/). I have tested this only with Home Assistant's own Mosquitto add-on.

1. Download the script off GitHub and place it in `/config`, e.g. as `/config/technicolor_signal_dump.sh` or in a subfolder as you see fit.

2. The script needs to be able to see Mosquitto binaries for posting MQTT data. Unfortunately the Home Assistant container seems not to give access to binaries in `/usr/bin`, so if you want to run this from within a Home Assistant container or supervised installation, you need to make the Mosquitto binary accessible. The easiest way to do this is to set up a copy under `/config` where our script can see it. This is a bit of a hack. Issue the following through the SSH terminal:
```
> mkdir /config/bin /config/bin/mosquitto_deps /config/bin/mosquitto_deps/lib
> cp /usr/bin/mosquitto_pub /config/bin/mosquitto_deps
> cp /usr/lib/libcares.so.2 /usr/lib/libmosquitto.so.1 /config/bin/mosquitto_deps/lib
```
In the script there is a section in the beginning that uses the `$mqtt_pub_exe` variable to point to the executable for your MQTT publisher. If you are not running this from a Home Assistant automation (e.g. if you can run it on another server running on your network) and have access to your system's binaries, you can comment out the lines that are there and uncomment the section that points the script to the `mosquitto_pub` binary directly. 

3. Edit the `technicolor_signal_dump.sh` file and modify the lines at the top: 
- The `modem_url' should be your modem's IP address, which is normally 192.168.100.1, accessed via plain HTTP (the TC4400 at least doesn't even support HTTPS).
- If you changed the password for the modem's admin account from the default `bEn2o#US9s`, you need to modify it in the script.
- If you are running your MQTT broker somewhere else than on the Home Assistant instance, point it to the right address.
- The `mqtt_username` and `mqtt_password` should point to a valid username and password on the MQTT broker. If you use Home Assistant's built-in Mosquitto addon, you set these when installing the add-on.
```
modem_url="http://192.168.100.1"
modem_username="admin"
modem_password="bEn2o#US9s"

# Settings for MQTT mqtt_broker to publish stats
mqtt_broker="127.0.0.1"
mqtt_username="your_mqtt_username_here"
mqtt_password="your_mqtt_password_here"
```

Optional:
At this point, if you wish, it should be possible to do an initial test. By opening a MQTT Explorer/Browser, and then going to the SSH addon in Home Assistant and running `/config/technicolor_signal_dump.sh`, it should scrape the modem and publish new topics.  You can see the command line output. In addition, one of the published topics should be `homeassistant/sensor/technicolor_scraper/login` which will provide information about problems or success of the modem login process while scraping the data.

<<<<<<< HEAD
5. Now, you will need to configure Home Assistant to connect to the sensors. For this, edit `configuration.yaml` and add a shell command that points to wherever under `/config` you saved the script. If the script is directly under `/config`, it could look like this:
=======
5. Now, you will need to configure Home Assistant to connect to the sensors. For this, edit `configuration.yaml` and add a shell command that points to wherever under `/config` you saved the script. Take a look at `technicolor_modem_signal.yaml` for an example of what it could look like. If you installed the script is directly under `/config`, the minimally required entry in `configuration.yaml` would look like this:
>>>>>>> c495321 (More details in README.md)
```
# Technicolor TC4400 cable modem scraper script
shell_command:
  technicolor_signal_dump: '/config/technicolor_signal_dump.sh'
```

<<<<<<< HEAD
7. Set up an automation to adjust when the signal-scrape is triggered. I prefer to do this not in a separate YAML file, but in the Automation set-up in Home Assistant; that way I have all automations in one place. Here is a very verbose automation that shows you all the things you could do:
=======
7. Set up an automation to adjust when the signal-scrape is triggered. I prefer to do this not in YAML, but in the Automation set-up in Home Assistant; that way I have all automations in one place. If you prefer to do this in YAML, take a look at `technicolor_modem_signal.yaml` for an example of what it could look like. Here is a very verbose automation example that shows you all the things you could do:
>>>>>>> c495321 (More details in README.md)
```
alias: Technicolor Cable Modem Signals
description: Scrape the web interface of the TC4400 cable modem
trigger:
  - platform: homeassistant
    event: start
  - platform: time_pattern
    minutes: "10"
  - platform: state
    entity_id:
      - binary_sensor.ping_google_dns
    to: "off"
    for:
      hours: 0
      minutes: 0
      seconds: 5
condition: []
action:
  - service: shell_command.technicolor_signal_dump
    response_variable: technicolor_response
    data: {}
  - if:
      - condition: template
        value_template: "{{ technicolor_response['returncode'] == 0 }}"
    then:
      - service: notify.notify
        data:
          title: Technicolor modem successfully scraped
          message: "{{ technicolor_response['stdout'] }}"
    else:
      - service: notify.notify
        data:
          title: Error scraping Technicolor modem
          message: "{{ technicolor_response['stderr'] }}"
mode: single
```

This automation does the following:
- Start the script whenever HomeAssistant starts;
- Start the script every hour at the 10th minute;
- Start the script whenever Google's DNS server `8.8.8.8` becomes unreachable for more than five seconds, as tested through a [ping sensor](https://www.home-assistant.io/integrations/ping/);
- If the script succeeds, send a notification with its command line output to the first available notification provider;
- If the script fails, send a notification with the error message to the first available notification provider.

8. Go to Home Assistant control panel, and validate your configuration.  If there are any errors, review those files before restarting Home Assistant.

9. Restart Home Assistant so it loads all the new changes.

10. You should have a new device appearing under the MQTT integration, and a bunch of new sensors under the new device. 

This has been tested on my Technicolor TC4400, firmware 70.12.43-190628.
