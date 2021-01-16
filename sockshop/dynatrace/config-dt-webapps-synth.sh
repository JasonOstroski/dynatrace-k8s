#!/bin/bash

YLW='\033[1;33m'
NC='\033[0m'


DT_API_URL=https://$(grep "DT_ENVIRONMENT_ID=" ../dynatrace.conf | sed 's~DT_ENVIRONMENT_ID=[ \t]*~~').sprint.dynatracelabs.com/api
DT_CONFIG_TOKEN=$(grep "DT_CONFIG_TOKEN=" ../dynatrace.conf | sed 's~DT_CONFIG_TOKEN=[ \t]*~~')
SOCKSHOP_WEBAPP_CONFIG=$(cat ./sockshop_webapp_template.json | sed "s/<SOCK_SHOP_WEBAPP_NAME>/Sock Shop - Production/")

AUTOTAG_PRODUCT_CONFIG=$(cat ./tagging_rule_product.json)
AUTOTAG_STAGE_CONFIG=$(cat ./tagging_rule_stage.json)

RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Api-Token $DT_CONFIG_TOKEN" -d "$AUTOTAG_PRODUCT_CONFIG" $DT_API_URL/config/v1/autoTags) 
echo $RESPONSE
RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Api-Token $DT_CONFIG_TOKEN" -d "$AUTOTAG_STAGE_CONFIG" $DT_API_URL/config/v1/autoTags)
echo $RESPONSE 

RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Api-Token $DT_CONFIG_TOKEN" -d "$SOCKSHOP_WEBAPP_CONFIG" $DT_API_URL/config/v1/applications/web) 

if [[ $RESPONSE == *"error"* ]]; then
    echo $RESPONSE
else
    PRODUCTION_APPLICATION_ID=$(echo $RESPONSE | grep -oP '(?<="id":")[^"]*')

    #create web app for dev and get id
    SOCKSHOP_WEBAPP_CONFIG=$(cat ./sockshop_webapp_template.json | sed "s/<SOCK_SHOP_WEBAPP_NAME>/Sock Shop - Dev/")

    RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Api-Token $DT_CONFIG_TOKEN" -d "$SOCKSHOP_WEBAPP_CONFIG" $DT_API_URL/config/v1/applications/web)
    
    if [[ $RESPONSE == *"error"* ]]; then
    	echo $RESPONSE
    else
        DEV_APPLICATION_ID=$(echo $RESPONSE | grep -oP '(?<="id":")[^"]*')

        #create app detection rules

        PROD_FRONTEND_URL=$(grep "PROD_FRONTEND_URL=" ../dynatrace.conf | sed 's~PROD_FRONTEND_URL=[ \t]*~~')

        if [ ! -z "$1" ] && [ "$1" == "-istio" ]
          then
            PROD_FRONTEND_DOMAIN=$(kubectl describe svc istio-ingressgateway -n istio-system | grep "LoadBalancer Ingress:" | sed 's/LoadBalancer Ingress:[ \t]*//')
          else
            PROD_FRONTEND_DOMAIN=$(kubectl describe svc front-end -n sockshop-production | grep "LoadBalancer Ingress:" | sed 's/LoadBalancer Ingress:[ \t]*//')
 
        #production
        APP_DETECTION_RULE=$(cat ./application_detection_rules_template.json | sed "s/<SOCKSHOP_APP_ID>/$PRODUCTION_APPLICATION_ID/" | \
            sed "s/<SOCKSHOP_FRONTEND_DOMAIN>/$PROD_FRONTEND_DOMAIN/")

        RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Api-Token $DT_CONFIG_TOKEN" -d "$APP_DETECTION_RULE" $DT_API_URL/config/v1/applicationDetectionRules)

        if [[ $RESPONSE == *"error"* ]]; then
            echo $RESPONSE
        else
            #create synthetic tests (4)

            USERNAME_PRE=$(grep "SOCKSHOP_USERNAME_PRE=" ../dynatrace.conf | sed 's~SOCKSHOP_USERNAME_PRE=[ \t]*~~')

            SYNTHETIC_CONFIG=$(cat ./sockshop_synthetic_template.json | sed "s/<SOCKSHOP_FRONTEND_URL>/http:\/\/$PROD_FRONTEND_DOMAIN:8080/" | sed "s/<SOCKSHOP_WEB_APP_ID>/$PRODUCTION_APPLICATION_ID/" )
	     
            for i in {1..4}
            do
                sleep 30s
		SYNTHETIC_CONFIG_NEW=$(echo $SYNTHETIC_CONFIG | sed "s/<SOCKSHOP_TEST_NAME>/Sock Shop - $i/" | sed "s/<SOCKSHOP_USERNAME>/$USERNAME_PRE$i/")

                RESPONSE=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Api-Token $DT_CONFIG_TOKEN" -d "$SYNTHETIC_CONFIG_NEW" $DT_API_URL/v1/synthetic/monitors)

            done

            if [[ $RESPONSE == *"error"* ]]; then
                echo $RESPONSE
            fi
        fi
    fi
fi


