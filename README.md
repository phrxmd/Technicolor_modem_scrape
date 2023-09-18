# Technicolor Modem MQTT Scraper

This script is for monitoring signal quality on a Technicolor cable modem through MQTT. This script should allow you to scrape the modem status data and write it out to a MQTT broker. You can then use something like Home Assistant to take actions based on the data (graph it, issue automations to cycle a smartplug, etc).

You can run the script on any Unix/Linux computer that can see both the modem and the MQTT broker and has a working `mosquitto_pub`, or you can run it on the Home Assistant instance itself.

This is a modification of [mmiller7](https://github.com/mmiller7/)'s scrapers for [Arris](https://github.com/mmiller7/Arris_modem_scrape) and [Netgear](https://github.com/mmiller7/Netgear_modem_scrape) cable modems. The login process has been simplified because the Technicolor modem does not require a login token, but uses HTTP and basic authentification only. In addition, the script is somewhat easier to install because it uses MQTT Discovery for telling Home Assistant about all the data sources, so Home Assistant picks them up automatically and assigns them to a cable modem device. You don't need a separate YAML file where they are all defined manually and which you need to edit manually for the number of channels provided by your ISP. 

## Files 

- `technicolor_signal_dump.sh` - the script which logs into the modem and scrapes/parses the data publishing JSON to MQTT 

## Install Process in Home Assistant

Prerequisite: [MQTT configured and working on Home Assistant](https://www.home-assistant.io/integrations/mqtt/). I have tested this only with Home Assistant's own Mosquitto add-on.

1. Download the script off GitHub and place it in `/config`, e.g. as `/config/technicolor_signal_dump.sh` or in a subfolder as you see fit.

2. If you want to run this from within Home Assistant, you need to set up the Mosquitto binary for posting MQTT data. Unfortunately the Home Assistant container seems not to give access to binaries in `/usr/bin`. So we have to set up a copy under `/config` where our script can see it. This is a bit of a hack, the easiest way to do this is through the SSH terminal:
```
> mkdir /config/bin /config/bin/mosquitto_deps /config/bin/mosquitto_deps/libcares
> cp /usr/bin/mosquitto_pub /config/bin/mosquitto_deps
> cp /usr/lib/libcares.so.2 /usr/lib/libmosquitto.so.1 /config/bin/mosquitto_deps/lib
```
In the script there is a section in the beginning that uses the `$mqtt_pub_exe` variable to point to the executable for your MQTT publisher. If you are not running this from a Home Assistant automation and have access to your system's binaries, you can comment out the lines that are there and uncomment the section that points the script directly to the `mosquitto_pub` binary. 

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
At this point, if you wish, it should be possible to do an initial test. By opening a MQTT Explorer/Browser, and then in the SSH addon running `/config/technicolor_signal_dump.sh`, it should scrape the modem and publish new topics.  You can see the command line output. In addition, one of the published topics should be `homeassistant/sensor/technicolor_scraper/login` which will provide information about problems or success of the modem login process while scraping the data.

5. Now, you will need to configure Home Assistant to connect to the sensors. For this, edit `configuration.yaml` and add a shell command that points to wherever under `/config` you saved the script. If the script is directly under `/config`, it could look like this:
```
# Technicolor TC4400 cable modem scraper script
shell_command:
  technicolor_signal_dump: '/config/technicolor_signal_dump.sh'
```

7. Set up an automation to adjust when the signal-scrape is triggered. I prefer to do this not in a separate YAML file, but in the Automation set-up in Home Assistant; that way I have all automations in one place. Here is a very verbose automation that shows you all the things you could do:
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
- Start the script whenever HomeAssistant starts
- Start the script every hour at the 10th minute
- Start the script whenever Google's DNS server `8.8.8.8` becomes unreachable for more than five seconds, as tested through a [ping sensor](https://www.home-assistant.io/integrations/ping/)
- If the script succeeds, send a notification with its command line output to the first available notification provider
- If the script fails, send a notification with the error message to the first available notification provider.

8. Go to Home Assistant control panel, and validate your configuration.  If there are any errors, review those files before restarting Home Assistant.

9. Restart Home Assistant so it loads all the new changes.

10. You should have a new device appearing under the MQTT integration, and a bunch of new sensors under the new device. 

This has been tested on my Technicolor TC4400, firmware 70.12.43-190628.
