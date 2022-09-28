KUBERNETES_SERVICE_HOST=127.0.0.1 KUBERNETES_SERVICE_PORT=6443 bin/apiserver \
    --etcd-servers= --secure-port=8443 --feature-gates=APIPriorityAndFairness=false \
    --cert-dir=config/certificates --client-ca-file=config/certificates/apiserver_ca.crt \
    --kubeconfig ~/.kube/config --authorization-kubeconfig ~/.kube/config --authentication-kubeconfig ~/.kube/config \
    --requestheader-allowed-names="" --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt
