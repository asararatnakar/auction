#!/bin/bash

#
echo "    _      _   _    ____   _____   ___    ___    _   _"
echo "   / \    | | | |  / ___| |_   _| |_ _|  / _ \  | \ | |"
echo "  / _ \   | | | | | |       | |    | |  | | | | |  \| |"
echo " / ___ \  | |_| | | |___    | |    | |  | |_| | | |\  |"
echo "/_/   \_\  \___/   \____|   |_|   |___|  \___/  |_| \_|"

CHANNEL_NAME="$1"
: ${CHANNEL_NAME:="mychannel"}
: ${TIMEOUT:="60"}
COUNTER=1
MAX_RETRY=5
LOG_LEVEL="error"
CHAINCODE_NAME="mycc"
ORDERER_IP=orderer.example.com:7050
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

echo "Channel name : "$CHANNEL_NAME

verifyResult () {
	if [ $1 -ne 0 ] ; then
		echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
                echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
		echo
   		exit 1
	fi
}

checkOSNAvailability() {
	#Use orderer's MSP for fetching system channel config block
	CORE_PEER_LOCALMSPID="OrdererMSP"
	CORE_PEER_TLS_ROOTCERT_FILE=$ORDERER_CA
	CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp

	local rc=1
	local starttime=$(date +%s)

	# continue to poll
	# we either get a successful response, or reach TIMEOUT
	while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
	do
		 sleep 3
		 echo "Attempting to fetch system channel 'testchainid' ...$(($(date +%s)-starttime)) secs"
		 if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
			 peer channel fetch 0 -o $ORDERER_IP -c "testchainid" >&log.txt
		 else
			 peer channel fetch 0 0_block.pb -o $ORDERER_IP -c "testchainid" --tls --cafile $ORDERER_CA >&log.txt
		 fi
		 test $? -eq 0 && VALUE=$(cat log.txt | awk '/Received block/ {print $NF}')
		 test "$VALUE" = "0" && let rc=0
	done
	cat log.txt
	verifyResult $rc "Ordering Service is not available, Please try again ..."
	echo "===================== Ordering Service is up and running ===================== "
	echo
}

createChannel() {
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer channel create -o $ORDERER_IP -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx >&log.txt
	else
		peer channel create -o $ORDERER_IP -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls --cafile $ORDERER_CA >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Channel creation failed"
	echo "===================== Channel \"$CHANNEL_NAME\" is created successfully ===================== "
	echo
}

joinChannel () {
	peer channel join -b $CHANNEL_NAME.block  >&log.txt
	res=$?
	cat log.txt
	if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "PEER0 failed to join the channel, Retry after 2 seconds"
		sleep 2
		joinChannel
	else
		COUNTER=1
	fi
	verifyResult $res "After $MAX_RETRY attempts, PEER has failed to Join the Channel"
		echo "===================== PEER joined on the channel \"$CHANNEL_NAME\" ===================== "
		echo
}

installChaincode () {
	peer chaincode install -n $CHAINCODE_NAME -v 1 -p auction >&log.txt
	res=$?
	cat log.txt
        verifyResult $res "Chaincode installation on remote peer PEER  has Failed"
	echo "===================== Chaincode is installed on remote peer PEER ===================== "
	echo
}

instantiateChaincode () {
	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode instantiate -o $ORDERER_IP -C $CHANNEL_NAME -n $CHAINCODE_NAME -v 1 -c '{"Args":["init"]}' >&log.txt
	else
		peer chaincode instantiate -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -v 1 -c '{"Args":["init"]}' >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Chaincode instantiation on PEER on channel '$CHANNEL_NAME' failed"
	echo "===================== Chaincode Instantiation on PEER on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

chaincodeQuery () {
  PEER=$1
  echo "===================== Querying on PEER$PEER on channel '$CHANNEL_NAME'... ===================== "
  # setGlobals $PEER
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
     sleep 3
     echo "Attempting to Query PEER$PEER ...$(($(date +%s)-starttime)) secs"
     peer chaincode query -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["query","a"]}' >&log.txt
     test $? -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
     test "$VALUE" = "$2" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0 ; then
	echo "===================== Query on PEER$PEER on channel '$CHANNEL_NAME' is successful ===================== "
  else
	echo "!!!!!!!!!!!!!!! Query result on PEER$PEER is INVALID !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
	echo
	exit 1
  fi
}

chaincodeInvoke () {
	PEER=$1
	# setGlobals $PEER
	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode invoke -o $ORDERER_IP -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["invoke","a","b","10"]}' >&log.txt
	else
		peer chaincode invoke -o $ORDERER_IP  --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["invoke","a","b","10"]}' >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Invoke execution on PEER$PEER failed "
	echo "===================== Invoke transaction on PEER$PEER on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

## Check for orderering service availablility
echo "Check orderering service availability..."
# checkOSNAvailability

## Once Orderer service is available , reset global env to peer admin
CORE_PEER_LOCALMSPID="Org1MSP"
CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
CORE_PEER_ADDRESS=peer0.org1.example.com:7051

## Create channel
echo "Creating channel ..."
createChannel

## Join all the peers to the channel
echo "Having the peer join the channel ..."
joinChannel

## Install chaincode on peer
echo "Installing chaincode on org1/peer0 ..."
installChaincode 0

## Instantitae chaincode on peer
echo "Instantiate chaincode on org1/peer0 ..."
instantiateChaincode 0

echo "Wait for 10 secs"
sleep 10

echo "Post Users ---> Creating 5 Users"
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostUser","100", "USER", "Ashley Hart", "TRD",  "Morrisville Parkway, #216, Morrisville, NC 27560", "9198063535", "ashley@itpeople.com", "SUNTRUST", "0001732345", "0234678", "2017-01-02 15:04:05"]}' --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostUser","200", "USER", "Sotheby", "AH",  "One Picadally Circus , #216, London, UK ", "9198063535", "admin@sotheby.com", "Standard Chartered", "0001732345", "0234678", "2017-01-02 15:04:05"]}' --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostUser","300", "USER", "Barry Smith", "TRD",  "155 Regency Parkway, #111, Cary, 27518 ", "9198063535", "barry@us.ibm.com", "RBC Centura", "0001732345", "0234678", "2017-01-02 15:04:05"]}' --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostUser","400", "USER", "Cindy Patterson", "TRD",  "155 Sunset Blvd, Beverly Hills, CA, USA ", "9058063535", "cpatterson@hotmail.com", "RBC Centura", "0001732345", "0234678", "2017-01-02 15:04:05"]}' --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostUser","500", "USER", "Tamara Haskins", "TRD",  "155 Sunset Blvd, Beverly Hills, CA, USA ", "9058063535", "tamara@yahoo.com", "RBC Centura", "0001732345", "0234678", "2017-01-02 15:04:05"]}' --logging-level=$LOG_LEVEL

echo "Query Users"
sleep 10
for (( USER_ID = 100; USER_ID <= 500; USER_ID = $USER_ID + 100 )); do
		peer chaincode query -C $CHANNEL_NAME -n $CHAINCODE_NAME -c "{\"Args\": [\"qGetUser\", \"$USER_ID\"]}"
		verifyResult $? "getUsers() transaction on PEER failed"
done

## post images
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostItem", "100", "ARTINV", "Shadows by Asppen", "Asppen Messer", "20140202", "Original", "landscape", "Canvas", "15 x 15 in", "art1.png","600", "100", "2017-01-23 14:04:05"]}' --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostItem", "200", "ARTINV", "modern Wall Painting", "Scott Palmer", "20140202", "Reprint", "landscape", "Acrylic", "10 x 10 in", "art2.png","2600", "200", "2017-01-23 14:04:05"]}' --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostItem", "300", "ARTINV", "Splash of Color", "Jennifer Drew", "20160115", "Reprint", "modern", "Water Color", "15 x 15 in", "art3.png","1600", "300", "2017-01-23 14:04:05"]}' --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["iPostItem", "400", "ARTINV", "Female Water Color", "David Crest", "19900115", "Original", "modern", "Water Color", "12 x 17 in", "art4.png","9600", "400", "2017-01-23 14:04:05"]}' --logging-level=$LOG_LEVEL

sleep 10
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c "{\"Args\":[\"iPostAuctionRequest\", \"1000\", \"AUCREQ\", \"100\", \"200\", \"100\", \"04012016\", \"1000\", \"1000\", \"INIT\", \"2017-02-13 09:05:00\", \"2017-02-13 09:05:00\", \"2017-02-13 09:10:00\"]}" --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c "{\"Args\":[\"iPostAuctionRequest\", \"1001\", \"AUCREQ\", \"200\", \"200\", \"200\", \"04012016\", \"1001\", \"1001\", \"INIT\", \"2017-02-13 09:05:00\", \"2017-02-13 09:05:00\", \"2017-02-13 09:10:00\"]}" --logging-level=$LOG_LEVEL
peer chaincode invoke -o $ORDERER_IP --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -c "{\"Args\":[\"iPostAuctionRequest\", \"1002\", \"AUCREQ\", \"300\", \"200\", \"300\", \"04012016\", \"1002\", \"1002\", \"INIT\", \"2017-02-13 09:05:00\", \"2017-02-13 09:05:00\", \"2017-02-13 09:10:00\"]}" --logging-level=$LOG_LEVEL
# submitBids $ch $chain $(((RANDOM % 3))) $auctionindex $bidNumber $userid $biduserid $bidPrice
# 							bidNumber=$(expr $bidNumber + 1)
# 							bidPrice=$(expr $bidPrice + 1)

echo
echo "============ All GOOD, Auction End-2-End test completed ============= "
echo

echo
echo " _____   _   _   ____            _____   ____    _____ "
echo "| ____| | \ | | |  _ \          | ____| |___ \  | ____|"
echo "|  _|   |  \| | | | | |  _____  |  _|     __) | |  _|  "
echo "| |___  | |\  | | |_| | |_____| | |___   / __/  | |___ "
echo "|_____| |_| \_| |____/          |_____| |_____| |_____|"
echo

exit 0
