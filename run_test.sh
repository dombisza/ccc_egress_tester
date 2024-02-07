#!/bin/bash
SOURCE_NS="source"
DEST_NS="dest"
DEST_SVC="${DEST_NS}.${DEST_NS}.svc.cluster.local"
SVC_CIDR="10.247.0.0/16"
function sc() {
  "$@" > /dev/null 2>&1
}
echo_o() {
  echo -e "\033[1;33m$1\033[0m"
}
# simple network policy
# this is how you would expect an egress netpol to look like
set_normal_netpol () {
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: ${SOURCE_NS}
spec:
  podSelector: {}
  policyTypes:
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  labels:
    app.kubernetes.io/name: ${SOURCE_NS}
  name: normal-network-policy
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${DEST_NS}
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  podSelector: {}
  policyTypes:
  - Egress
EOF
}

# egress netpol which should allow communication with coredns
set_normal_netpol_with_kube-system() {
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 5353
    - protocol: TCP
      port: 5353
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  podSelector:
    matchLabels: {}
  policyTypes:
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  labels:
    app.kubernetes.io/name: ${SOURCE_NS}
  name: normal-network-policy
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${DEST_NS}
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  podSelector: {}
  policyTypes:
  - Egress
EOF
}

# allow coredns and clusterIP's for coredns
set_normal_netpol_with_kube-system_n_ipblock() {
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    - ipBlock:
        cidr: ${SVC_CIDR} 
    ports:
    - protocol: UDP
      port: 5353
    - protocol: TCP
      port: 5353
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  podSelector:
    matchLabels: {}
  policyTypes:
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  labels:
    app.kubernetes.io/name: ${SOURCE_NS}
  name: normal-network-policy
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${DEST_NS}
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  podSelector: {}
  policyTypes:
  - Egress
EOF
}
# netpol which allows communication with clusterIP's
# coredns communication is left out intentionnaly
set_ipblock_netpol() {
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: ${SOURCE_NS}
spec:
  podSelector: {}
  policyTypes:
  - Egress

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  labels:
    app.kubernetes.io/name: ${SOURCE_NS}
  name: normal-network-policy
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${DEST_NS}
    - ipBlock:
        cidr: ${SVC_CIDR} 
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  podSelector: {}
  policyTypes:
  - Egress
EOF
}
# this is an egress netpol which actually works with cce
# allows comm to clusterIP's and to coredns
set_ipblock_netpol_with_kube-system() {
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    - ipBlock:
        cidr: ${SVC_CIDR} 
    ports:
    - protocol: UDP
      port: 5353
    - protocol: TCP
      port: 5353
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  podSelector:
    matchLabels: {}
  policyTypes:
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  labels:
    app.kubernetes.io/name: ${SOURCE_NS}
  name: normal-network-policy
  namespace: ${SOURCE_NS}
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${DEST_NS}
    - ipBlock:
        cidr: ${SVC_CIDR} 
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  podSelector: {}
  policyTypes:
  - Egress
EOF

}
run_init() {
  echo "Running init"
  set -e
  sc kubectl create ns $1
  sc kubectl create ns $2
  sc kubectl delete netpol --all -A
  sc kubectl run nginx --image=nginx --expose --port=80
  set +e
  echo "Init done"
}

run_cleanup() {
  echo "Running cleanup"
  sc kubectl delete netpol --all -A
  sc kubectl delete pod $2 -n $2
  sc kubectl delete svc $2 -n $2
  sc kubectl delete pod nginx
  sc kubectl delete svc nginx
  sc kubectl delete ns $1
  sc kubectl delete ns $2
  echo "Cleanup done"
}

test_url() {
  timestamp=$(date '+%s')
  echo "########## $1 #########"
  http_return=$(kubectl run --rm --restart=Never --image=nginx \
    --labels="app.kubernetes.io/name=${SOURCE_NS}" \
    -i -t ${SOURCE_NS}-${timestamp} -n ${SOURCE_NS} \
    --command -- bash -c "sleep 2; curl -k -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 $1 2>/dev/null" \
    2>/dev/null | grep -v deleted)
  if [ -z "$http_return" ]; then
    echo -e "\033[1;31mERROR http_return is empty\033[0m"
  elif [[ ${http_return} == *000* ]]; then
    echo -e "\033[1;31mFAIL TCP or DNS timeout\033[0m"
  else
    echo -e "\033[1;32mOK HTTP:$http_return\033[0m"
  fi
  echo "########## END ########"
  echo ""
}

check_pod_status() {
    echo "$(kubectl get pod -n $1 -o jsonpath='{.items[0].status.phase}')"
}

run_test() {
  #kubectl run ${DEST_NS} --labels="app.kubernetes.io/name=${DEST_NS}" --image=nginx -n ${DEST_NS}
  set -e 
  cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEST_NS}
  namespace: ${DEST_NS}
  labels:
    app.kubernetes.io/name: ${DEST_NS}
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: ${DEST_NS}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${DEST_NS}
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
EOF
  sc kubectl expose deploy ${DEST_NS} --labels="app.kubernetes.io/name=${DEST_NS}" --type=ClusterIP --port=80 --target-port=80 -n ${DEST_NS}
  set +e
  while true; do
    pod_status=$(check_pod_status ${DEST_NS})
    if [[ ${pod_status} == "Running" ]]; then
      echo "Pod is ${pod_status}"
      break
    else
      echo "Waiting for destination pod to start... ${pod_status}"
      sleep 1
    fi
  done
  
  pod_ip=$(kubectl get pod -n ${DEST_NS} -o jsonpath='{.items[0].status.podIP}')
  cluster_ip=$(kubectl get svc ${DEST_NS} -n ${DEST_NS} -o jsonpath='{.spec.clusterIP}')
  if [ -z "$pod_ip" ] || [ -z "$cluster_ip" ]; then
    echo "Error: cannot get pod or cluster ip" 
    exit 1
  else
    echo -e "\033[1;34mPod IP: $pod_ip\033[0m"
    echo -e "\033[1;34mCluster IP: $cluster_ip\033[0m"
    echo ""
  fi
  echo "Testing target svc in the other namespace"
  test_url ${DEST_SVC}
  echo "Testing the clusterIP of the target svc in the other namespace"
  test_url ${cluster_ip}
  echo "Testing the pod ip of the target svc in the other namespace"
  test_url ${pod_ip}
  echo "Testing kube-api endpoint in default namespace"
  test_url "https://kubernetes.default.svc.cluster.local/api"
  echo "Testing an other service in the default namespace"
  test_url "nginx.default.svc.cluster.local"
  echo "Testing external communication"
  test_url "google.com"

  run_cleanup ${SOURCE_NS} ${DEST_NS}
}

### test without egress
run_cleanup ${SOURCE_NS} ${DEST_NS}
run_init ${SOURCE_NS} ${DEST_NS}

echo "#######################################################"
echo_o "Testing connection without netpols"
echo "expected results: all OK"
echo "#######################################################"
run_test
echo "#######################################################"
echo_o "Done testing without netpols"
echo "#######################################################"
echo ""
### creating normal egress
run_init ${SOURCE_NS} ${DEST_NS}
set_normal_netpol

echo "#######################################################"
echo_o "Running tests with a normal looking egress"
echo "expected results:"
echo "${DEST_SVC}=FAIL/000/DNS"
echo "cluster_ip=ALLOW/200"
echo "pod_ip=ALLOW/200"
echo "kube-svc=DROP/000"
echo "nginx-svc=DROP/000"
echo "internet=DROP/000"
echo "#######################################################"
kubectl describe netpol -n ${SOURCE_NS}
run_test
echo "#######################################################"
echo_o "Done running tests with normal looking egress"
echo "#######################################################"
echo ""

### normal ingress with kube-system allowed
run_init ${SOURCE_NS} ${DEST_NS}
set_normal_netpol_with_kube-system

echo "#######################################################"
echo_o "Running tests with a normal looking egress and kube-system allowed"
echo "${DEST_SVC}=ALLOW/200"
echo "cluster_ip=ALLOW/200"
echo "pod_ip=ALLOW/200"
echo "kube-svc=DROP/000"
echo "nginx-svc=DROP/000"
echo "internet=DROP/000"
echo "#######################################################"
kubectl describe netpol -n ${SOURCE_NS}
run_test
echo "#######################################################"
echo_o "Done running tests with normal looking egress with kube-system allowed"
echo "#######################################################"
echo ""

### egress with kube-system + ipBlock allowed
run_init ${SOURCE_NS} ${DEST_NS}
set_normal_netpol_with_kube-system_n_ipblock
echo "#######################################################"
echo_o "Running tests with a normal looking egress and kube-system + clusterIP allowed"
echo "${DEST_SVC}=ALLOW/200"
echo "cluster_ip=ALLOW/200"
echo "pod_ip=ALLOW/200"
echo "kube-svc=DROP/000"
echo "nginx-svc=DROP/000"
echo "internet=DROP/000"
echo "#######################################################"
kubectl describe netpol -n ${SOURCE_NS}
run_test
echo "#######################################################"
echo_o "Done running tests with normal looking egress with kube-system + clusterIP allowed"
echo "#######################################################"
echo ""

### egress with ipblock
run_init ${SOURCE_NS} ${DEST_NS}
set_ipblock_netpol

echo "#######################################################"
echo_o "Running tests with ipBlock type egress"
echo "${DEST_SVC}=FAIL/000/DNS"
echo "cluster_ip=ALLOW/200"
echo "pod_ip=ALLOW/200"
echo "kube-svc=DROP/000"
echo "nginx-svc=DROP/000"
echo "internet=DROP/000"
echo "#######################################################"
kubectl describe netpol -n ${SOURCE_NS}
run_test
echo "#######################################################"
echo_o "Done running tests with ipBlock type egress"
echo "#######################################################"
echo ""

### ipblock egress with kube-system
run_init ${SOURCE_NS} ${DEST_NS}
set_ipblock_netpol_with_kube-system

echo "#######################################################"
echo_o "Running tests with ipBlock type egress with kube-system allowed"
echo "${DEST_SVC}=OK/200"
echo "cluster_ip=ALLOW/200"
echo "pod_ip=ALLOW/200"
echo "kube-svc=DROP/000"
echo "nginx-svc=DROP/000"
echo "internet=DROP/000"
echo "#######################################################"
kubectl describe netpol -n ${SOURCE_NS}
run_test
echo "#######################################################"
echo_o "Done running tests with ipBlock type egress with kube-system allowed"
echo "#######################################################"
echo ""

