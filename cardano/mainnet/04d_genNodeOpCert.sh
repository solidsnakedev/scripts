#!/bin/bash

# Script is brought to you by ATADA_Stakepool, Telegram @atada_stakepool

#load variables from common.sh
#       socket          Path to the node.socket (also exports socket to CARDANO_NODE_SOCKET_PATH)
#       genesisfile     Path to the genesis.json
#       magicparam      TestnetMagic parameter
#       cardanocli      Path to the cardano-cli executable
#       cardanonode     Path to the cardano-node executable
. "$(dirname "$0")"/00_common.sh

if [[ $# -eq 1 && ! $1 == "" ]]; then nodeName=$1; else echo "ERROR - Usage: $0 <name>"; exit 2; fi

#check that *.node.skey/hwsfile is present
if ! [[ -f "${nodeName}.node.skey" || -f "${nodeName}.node.hwsfile" ]]; then echo -e "\e[0mERROR - Cannot find '${nodeName}.node.skey/hwsfile', please generate Node Keys with ${nodeName}.node.counter first with script 04a ...\e[0m"; exit 2; fi

#check if there is a node.counter file, if not, ask about generating a new one
if [ ! -f "${nodeName}.node.counter" ]; then
					#echo -e "\e[0mERROR - Please generate Node Keys with ${nodeName}.node.counter first with script 04a ...\e[0m"; exit 2;
					if ask "\e[33mCannot find '${nodeName}.node.counter', do you wanna create a new one?" N; then

							poolNodeCounter=1; #set to zero for now, can be improved

							if [ ! -f "${nodeName}.node.vkey" ]; then echo -e "\n\e[35mERROR - Cannot find '${nodeName}.node.vkey', please generate Node Keys first with script 04a ...\e[0m\n"; exit 2; fi
							${cardanocli} node new-counter --cold-verification-key-file ${nodeName}.node.vkey --counter-value ${poolNodeCounter} --operational-certificate-issue-counter-file ${nodeName}.node.counter
							checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
							#NodeCounter file was written, now add the description in the file to reflect the next node counter number
							newCounterJSON=$(jq ".description = \"Next certificate issue number: $((${poolNodeCounter}+0))\"" < "${nodeName}.node.counter")
							checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
							echo "${newCounterJSON}" > "${nodeName}.node.counter"
							checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
							file_lock "${nodeName}.node.counter"
							#file_unlock "${nodeName}.kes.counter"
							#nextKESnumber=$(printf "%03d" ${poolNodeCounter})
							#echo "${nextKESnumber}" > "${nodeName}.kes.counter"
							#file_lock "${nodeName}.kes.counter"

							echo -e "\n\e[0mAn new ${nodeName}.node.counter File was created with index ${poolNodeCounter}. You can now rerun this script 04d again to generate the opcert.\n\n\e[33mBE AWARE - we don't know how many opcerts you created before for this node on the chain.\nYou have to generate a higher number than you used the last time before you lost your opcert file. To do this\nyou have to run 04c & 04d multiple times until you feel good about the opcert index number.\n\n\e[0m"; exit 1;

					else

					echo -e "\n\e[35mERROR - Cannot create new OperationalCertificate (opcert) without a '${nodeName}.node.counter' file!\n\e[0m"; exit 2;

					fi
fi

#Check that there is a kes.counter file present
if [ ! -f "${nodeName}.kes.counter" ]; then echo -e "\e[0mERROR - Please generate new KES Keys with ${nodeName}.kes.counter first with script 04c ...\e[0m"; exit 2; fi

#grab the next issue number from the counter file
nextKESnumber=$(cat ${nodeName}.node.counter | jq -r .description | awk 'match($0,/Next certificate issue number: [0-9]+/) {print substr($0, RSTART+31,RLENGTH-31)}')
nextKESnumber=$(printf "%03d" ${nextKESnumber})  #to get a nice 3 digit output

#grab the latest generated KES number
latestKESnumber=$(cat ${nodeName}.kes.counter)

if [[ ! "${nextKESnumber}" == "${latestKESnumber}" ]]; then echo -e "\e[0mERROR - Please generate new KES Keys first ...\e[0m"; exit 2; fi

echo -e "\e[0mIssue a new Node operational certificate using KES-vKey \e[32m${nodeName}.kes-${latestKESnumber}.vkey\e[0m and Cold-sKey \e[32m${nodeName}.node.skey\e[0m:"
echo

#Static
slotLength=$(cat ${genesisfile} | jq -r .slotLength)                    #In Secs
epochLength=$(cat ${genesisfile} | jq -r .epochLength)                  #In Secs
slotsPerKESPeriod=$(cat ${genesisfile} | jq -r .slotsPerKESPeriod)      #Number
startTimeByron=$(cat ${genesisfile_byron} | jq -r .startTime)           #In Secs(abs)
startTimeGenesis=$(cat ${genesisfile} | jq -r .systemStart)             #In Text
startTimeSec=$(date --date=${startTimeGenesis} +%s)                     #In Secs(abs)
transTimeEnd=$(( ${startTimeSec}+(${byronToShelleyEpochs}*${epochLength}) ))                 #In Secs(abs) End of the TransitionPhase = Start of KES Period 0
byronSlots=$(( (${startTimeSec}-${startTimeByron}) / 20 ))              #NumSlots between ByronChainStart and ShelleyGenesisStart(TransitionStart)
transSlots=$(( (${byronToShelleyEpochs}*${epochLength}) / 20 ))                         #NumSlots in the TransitionPhase

#Dynamic
currentTimeSec=$(date -u +%s)                                           #In Secs(abs)

#Calculate current slot
if [[ "${currentTimeSec}" -lt "${transTimeEnd}" ]];
        then #In Transistion Phase between ShelleyGenesisStart and TransitionEnd
        currentSlot=$(( ${byronSlots} + (${currentTimeSec}-${startTimeSec}) / 20 ))
        else #After Transition Phase
        currentSlot=$(( ${byronSlots} + ${transSlots} + ((${currentTimeSec}-${transTimeEnd}) / ${slotLength}) ))
fi

#Calculating KES period
currentKESperiod=$(( (${currentSlot}-${byronSlots}) / (${slotsPerKESPeriod}*${slotLength}) ))
if [[ "${currentKESperiod}" -lt 0 ]]; then currentKESperiod=0; fi


#Calculating Expire KES Period and Date/Time
maxKESEvolutions=$(cat ${genesisfile} | jq -r .maxKESEvolutions)
expiresKESperiod=$(( ${currentKESperiod} + ${maxKESEvolutions} ))
#expireTimeSec=$(( ${transTimeEnd} + (${slotLength}*${expiresKESperiod}*${slotsPerKESPeriod}) ))
expireTimeSec=$(( ${currentTimeSec} + (${slotLength}*${maxKESEvolutions}*${slotsPerKESPeriod}) ))
expireDate=$(date --date=@${expireTimeSec})

file_unlock ${nodeName}.kes-expire.json
echo -e "{\n\t\"latestKESfileindex\": \"${latestKESnumber}\",\n\t\"currentKESperiod\": \"${currentKESperiod}\",\n\t\"expireKESperiod\": \"${expiresKESperiod}\",\n\t\"expireKESdate\": \"${expireDate}\"\n}" > ${nodeName}.kes-expire.json
file_lock ${nodeName}.kes-expire.json

echo -e "\e[0mCurrent KES period:\e[32m ${currentKESperiod}\e[90m"
echo


#Generate the opcert form a classic cli node skey or from a hwsfile (hw-wallet)
if [ -f "${nodeName}.node.skey" ]; then #key is a normal one
                echo -ne "\e[0mGenerating a new opcert from a cli signing key '\e[33m${nodeName}.node.skey\e[0m' ... "
		file_unlock ${nodeName}.node-${latestKESnumber}.opcert
		file_unlock ${nodeName}.node.counter
		${cardanocli} node issue-op-cert --hot-kes-verification-key-file ${nodeName}.kes-${latestKESnumber}.vkey --cold-signing-key-file ${nodeName}.node.skey --operational-certificate-issue-counter ${nodeName}.node.counter --kes-period ${currentKESperiod} --out-file ${nodeName}.node-${latestKESnumber}.opcert
		checkError "$?"; if [ $? -ne 0 ]; then file_lock ${nodeName}.node-${latestKESnumber}.opcert; file_lock ${nodeName}.node.counter; exit $?; fi
		file_lock ${nodeName}.node-${latestKESnumber}.opcert
		file_lock ${nodeName}.node.counter

elif [ -f "${nodeName}.node.hwsfile" ]; then #key is a hardware wallet
                if ! ask "\e[0mGenerating the new opcert from a local Hardware-Wallet keyfile '\e[33m${nodeName}.node.hwsfile\e[0m', continue?" Y; then echo; echo -e "\e[35mABORT - Opcert Generation aborted...\e[0m"; echo; exit 2; fi

                start_HwWallet "Ledger"; checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
		file_unlock ${nodeName}.node-${latestKESnumber}.opcert
		file_unlock ${nodeName}.node.counter
                tmp=$(${cardanohwcli} node issue-op-cert --kes-verification-key-file ${nodeName}.kes-${latestKESnumber}.vkey --kes-period ${currentKESperiod} --operational-certificate-issue-counter ${nodeName}.node.counter --hw-signing-file ${nodeName}.node.hwsfile --out-file ${nodeName}.node-${latestKESnumber}.opcert 2> /dev/stdout)
                if [[ "${tmp^^}" =~ (ERROR|DISCONNECT) ]]; then echo -e "\e[35m${tmp}\e[0m\n"; file_lock ${nodeName}.node-${latestKESnumber}.opcert; file_lock ${nodeName}.node.counter; exit 1; else echo -e "\e[32mDONE\e[0m"; fi
		file_lock ${nodeName}.node-${latestKESnumber}.opcert
		file_lock ${nodeName}.node.counter
                checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
else
     		echo -e "\e[35mError - Node Cold Signing Key for \"${nodeName}\" not found. No ${nodeName}.node.skey/hwsfile found !\e[0m\n"; exit 1;
fi




echo -e "\e[0mNode operational certificate:\e[32m ${nodeName}.node-${latestKESnumber}.opcert \e[90m"
cat ${nodeName}.node-${latestKESnumber}.opcert
echo

echo
echo -e "\e[0mUpdated Operational Certificate Issue Counter:\e[32m ${nodeName}.node.counter \e[90m"
cat ${nodeName}.node.counter
echo

echo
echo -e "\e[0mUpdated Expire date json:\e[32m ${nodeName}.kes-expire.json \e[90m"
cat ${nodeName}.kes-expire.json
echo


echo -e "\e[0mNew \e[32m${nodeName}.kes-${latestKESnumber}.skey\e[0m and \e[32m${nodeName}.node-${latestKESnumber}.opcert\e[0m files ready for upload to the server."
echo

echo -e "\e[0m\n"
