up:
	colima start -c 8 -m 12
	minikube start --cpus 6 --memory 10000

install:
	# brew install istioctl
	# istioctl install --set profile=demo -y
	# istioctl verify-install
	# minikube addons enable ingress
	curl -L https://istio.io/downloadIstio | sh -
	cd istio-*
	export PATH=$PWD/bin:$PATH
	istioctl install --set profile=demo -y
	istioctl verify-install
	minikube tunnel

example:
	kubectl label namespace default istio-injection=enabled
	kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml -n default
	kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml -n default
	kubectl apply -f samples/addons
	kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml
	kubectl apply -f virtual-service1.yaml

delete:
	minikube delete 
	colima delete

restart: delete up

cleanup:
	./samples/bookinfo/platform/kube/cleanup.sh

authentication: cleanup
	kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml -n default
	kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml -n default
	kubectl create ns bar
	kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml) -n bar
	# this command should works and send back 200 http code
	kubectl exec -it "$(kubectl get pod -l app=httpbin -n bar -o jsonpath={.items..metadata.name})" -c istio-proxy -n bar -- curl "http://productpage.default:9080" -s -o /dev/null -w "%{http_code}\n"
	kubectl apply -f security/peerauthentication.yaml
	# Now it should fail because we request mutual TLS mode strict
	kubectl exec -it "$(kubectl get pod -l app=httpbin -n bar -o jsonpath={.items..metadata.name})" -c istio-proxy -n bar -- curl "http://productpage.default:9080" -s -o /dev/null -w "%{http_code}\n"

authorization:
	kubectl apply -f security/authorizationpolicy.yaml
	while sleep 0.01; do curl -sS 'http://127.0.0.1/productpage' ; done
	kubectl apply -f security/authorizationpolicy_allow.yaml

ca-cert:
	mkdir ca-certs
	cd ca-certs
	make -f ../istio-1.17.2/tools/certs/Makefile.selfsigned.mk root-ca
	make -f ../istio-1.17.2/tools/certs/Makefile.selfsigned.mk localcluster-cacerts
	kubectl delete namespace istio-system
	../samples/bookinfo/platform/kube/cleanup.sh
	kubectl create namespace istio-system
	mkdir localcluster
	cd localcluster
	kubectl create secret generic cacerts -n istio-system --from-file=ca-cert.pem --from-file=ca-key.pem --from-file=root-cert.pem --from-file=cert-chain.pem
	istioctl install --set profile=demo
	cd ../..
	kubectl apply -f samples/addons
	kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml -n default
	kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml -n default
	istioctl analyze
	kubectl apply -f ../security/authentication_ca_strict.yaml
	kubectl exec "$(kubectl get pod -l app=details -o jsonpath={.items..metadata.name})" -c istio-proxy -- openssl s_client -showcerts -connect productpage:9080 > httpbin-proxy-cert.txt
	sed -ne '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' httpbin-proxy-cert.txt | sed 's/^\s*//' > certs.pem
	split -p "/-----BEGIN CERTIFICATE-----/" certs.pem proxy-cert-
	openssl x509 -in ../security/ca-certs/localcluster/root-cert.pem -text -noout > /tmp/root-cert.crt.txt
	openssl x509 -in ./proxy-cert-3.pem -text -noout > /tmp/pod-root-cert.crt.txt
	diff -s /tmp/root-cert.crt.txt /tmp/pod-root-cert.crt.txt