#!/bin/bash

number_downstream=33
number_upstream=5

echo "    # Downstream"
for i in {1..33}; do 
echo "    - name: \"Cable Modem Downstream ${i} Power\""
echo "      expire_after: 200"
#echo "      unique_id: \"modemsignals_downstream_${i}_power\""
echo "      state_topic: \"homeassistant/sensor/modemsignals/downstream/${i}\""
echo "      json_attributes_topic: \"homeassistant/sensor/modemsignals/downstream/${i}\""
echo "      unit_of_measurement: 'dBmV'"
echo "      value_template: \"{{ value_json.ReceivedLevel }}\""
echo "    - name: \"Cable Modem Downstream ${i} SNR\""
echo "      expire_after: 200"
#echo "      unique_id: \"modemsignals_downstream_${i}_snr\""
echo "      state_topic: \"homeassistant/sensor/modemsignals/downstream/${i}\""
echo "      unit_of_measurement: 'dB'"
echo "      value_template: \"{{ value_json.SNRMERThreshold }}\""
echo "    - name: \"Cable Modem Downstream ${i} Error-Free\""
echo "      expire_after: 200"
#echo "      unique_id: \"modemsignals_downstream_${i}_errorfree\""
echo "      state_topic: \"homeassistant/sensor/modemsignals/downstream/${i}\""
echo "      unit_of_measurement: 'Codewords'"
echo "      value_template: \"{{ value_json.Unerrored }}\""
echo "    - name: \"Cable Modem Downstream ${i} Corrected\""
echo "      expire_after: 200"
#echo "      unique_id: \"modemsignals_downstream_${i}_corrected\""
echo "      state_topic: \"homeassistant/sensor/modemsignals/downstream/${i}\""
echo "      unit_of_measurement: 'Corrected Errors'"
echo "      value_template: \"{{ value_json.Corrected }}\""
echo "    - name: \"Cable Modem Downstream ${i} Uncorrectable\""
echo "      expire_after: 200"
#echo "      unique_id: \"modemsignals_downstream_${i}_uncorrectable\""
echo "      state_topic: \"homeassistant/sensor/modemsignals/downstream/${i}\""
echo "      unit_of_measurement: 'Uncorrectable Errors'"
echo "      value_template: \"{{ value_json.Uncorrectable }}\""
echo ""
done

echo "    # Upstream"
for i in {1..5}; do 
echo "    - name: \"Cable Modem Upstream ${i} Power\""
echo "      expire_after: 200"
#echo "      unique_id: \"modemsignals_upstream_${i}_power\""
echo "      state_topic: \"homeassistant/sensor/modemsignals/upstream/${i}\""
echo "      unit_of_measurement: 'dBmV'"
echo "      value_template: \"{{ value_json.TransmitLevel }}\""
echo "      json_attributes_topic: \"homeassistant/sensor/modemsignals/upstream/${i}\""
echo ""
done
