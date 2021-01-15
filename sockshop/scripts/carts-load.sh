#!/bin/bash

export CARTS_URL=$(kubectl describe svc carts -n sockshop-dev | grep "LoadBalancer Ingress:" | sed 's/LoadBalancer Ingress:[ \t]*//')  

i=0 
while true 
do     
	curl -X POST -H "Content-Type: application/json" -d "{\"itemId\":\"03fef6ac-1896-4ce8-bd69-b798f85c6e0b\", \"unitPrice\":\"99.99\"}" http://$CARTS_URL/carts/1/items

	sleep 2      
	i=$((i+1))     
	if [ $i -ge 100 ]     
	then         
		curl -X DELETE http://$CARTS_URL/carts/1     
	fi 
done
