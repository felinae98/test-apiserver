#!/usr/bin/env bash

#  Copyright 2021 The IOMesh Authors.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

set -o errexit
set -o pipefail

function install_etcd() {
  local version=${1}
  local download_url=https://github.com/etcd-io/etcd/releases/download
  local -r tmp_file_name="etcd-${version}-linux-${ARCH}"
  local -r download_path="$(mktemp -d)/${tmp_file_name}.tar.gz"
  if [[ $(command -v etcd) ]]; then
    return 0
  fi
  curl -L ${download_url}/${version}/${tmp_file_name}.tar.gz -o ${download_path}
  tar xf ${download_path} -C /usr/local/bin --strip-components=1 --extract ${tmp_file_name}/etcd ${tmp_file_name}/etcdctl
}

function install_kube_plugin() {
  local version=${1}
  local plugin=${2}
  local download_url=https://storage.googleapis.com/kubernetes-release/release
  if [[ $(command -v ${plugin}) ]]; then
    return 0
  fi
  curl -L ${download_url}/${version}/bin/linux/${ARCH}/${plugin} -o /usr/local/bin/${plugin}
  chmod +x /usr/local/bin/${plugin}
}

function start_etcd() {
  if [[ $(pidof etcd) ]]; then
    printf "etcd has already run on pid %s, please run reset-controlplane.sh first\n" "$(pidof etcd)"
    return 1
  fi
  nohup etcd --data-dir /var/lib/etcd > /var/log/kube-apiserver.log 2>&1 &
}

function start_apiserver() {
  local cert_path=${1}
  local apiserver_addr=${2}
  if [[ $(pidof kube-apiserver) ]]; then
    printf "kube-apiserver has already run on pid %s, please run reset-controlplane.sh first\n" "$(pidof kube-apiserver)"
    return 1
  fi
  generate_certs ${cert_path} ${apiserver_addr}
  local apiserver_args="--advertise-address=0.0.0.0 --secure-port=6443"
  local apiserver_service_account="--service-account-key-file=${cert_path}/service-account.pem --service-account-signing-key-file=${cert_path}/service-account-key.pem --service-account-issuer=api"
  local apiserver_cert_args="--client-ca-file=${cert_path}/ca.crt --cert-dir=${cert_path}"
  local apiserver_extra_args="--service-cluster-ip-range=10.0.0.0/24 --allow-privileged=true --authorization-mode RBAC --etcd-servers=http://127.0.0.1:2379"
  local apiserver_aggragated_apiserver_args="--proxy-client-cert-file=${cert_path}/front-proxy-client.crt --proxy-client-key-file=${cert_path}/front-proxy-client.key --requestheader-allowed-names=front-proxy-client --requestheader-client-ca-file=${cert_path}/front-proxy-ca.crt --requestheader-extra-headers-prefix=X-Remote-Extra- --requestheader-group-headers=X-Remote-Group --requestheader-username-headers=X-Remote-User --enable-aggregator-routing=true"
  nohup kube-apiserver ${apiserver_args} ${apiserver_extra_args} ${apiserver_service_account} ${apiserver_cert_args} ${apiserver_aggragated_apiserver_args} > /var/log/kube-apiserver.log 2>&1 &
}

function generate_ca_certs() {
  local cert_path=${1}
  local name=${2}
  local cn=${3:-kubernetes}

  local cakey_path=${cert_path}/${name}.key
  local cacert_path=${cert_path}/${name}.crt

  if [[ -f ${cakey_path} || -f ${cacert_path} ]]; then
    return 0
  fi
  (
    openssl req -x509 -newkey rsa:2048 -keyout ${cakey_path} -out ${cacert_path} -days 365 -nodes -subj "/CN=${cn}"
  ) 1>/dev/null 2>/dev/null
}

function generate_key_and_sign_by_ca() {
  local cert_path=${1}
  local name=${2}
  local ca_name=${3}
  local san=${4}
  local cn=${5:-kube-apiserver}

  local cakey_path=${cert_path}/${ca_name}.key
  local cacert_path=${cert_path}/${ca_name}.crt

  (
    openssl genrsa -out ${cert_path}/${name}.key
    openssl req -new -key ${cert_path}/${name}.key -out ${cert_path}/${name}.csr -subj "/CN=${cn}"
    if [ -n "${san}" ]; then
      openssl x509 -req -in ${cert_path}/${name}.csr -CA ${cacert_path} -CAkey ${cakey_path} -CAcreateserial -out ${cert_path}/${name}.crt -days 36500 -extfile <(printf "subjectAltName=%s" ${san})
    else
      openssl x509 -req -in ${cert_path}/${name}.csr -CA ${cacert_path} -CAkey ${cakey_path} -CAcreateserial -out ${cert_path}/${name}.crt -days 36500
    fi
   ) 1>/dev/null 2>/dev/null
}

function generate_certs() {
  local cert_path=${1}
  local apiserver_addr=${2:-127.0.0.1}
  mkdir -p ${cert_path}

  generate_ca_certs $cert_path ca kubernetes-ca
  generate_key_and_sign_by_ca $cert_path apiserver ca "IP:${apiserver_addr}" kube-apiserver

  # generate certs for proxy-*
  generate_ca_certs $cert_path front-proxy-ca front-proxy-ca
  generate_key_and_sign_by_ca $cert_path front-proxy-client front-proxy-ca "" frontend-proxy-client

  (
    openssl genrsa -out ${cert_path}/service-account-key.pem 4096
    openssl rsa -in ${cert_path}/service-account-key.pem -pubout -out ${cert_path}/service-account.pem
   ) 1>/dev/null 2>/dev/null
}

function generate_kubeconfig() {
  local cert_path=${1}
  local user=${2}
  local org=${3}
  local kubeconfig_path=${4}
  local kube_apiserver_endpoint=${5:-127.0.0.1}
  if [[ -f ${kubeconfig_path} ]]; then
    return 0
  fi
  local cakey_path=${cert_path}/ca.key
  local cacert_path=${cert_path}/ca.crt
  local kubernetes_entrypoint="https://${kube_apiserver_endpoint}:6443"
  local -r cert_tmp_dir=$(mktemp -d)
  (
    openssl genrsa -out ${cert_tmp_dir}/${user}.key
    openssl req -new -key ${cert_tmp_dir}/${user}.key -out ${cert_tmp_dir}/${user}.csr -subj "/CN=${user}/O=${org}"
    openssl x509 -req -in ${cert_tmp_dir}/${user}.csr -CA ${cacert_path} -CAkey ${cakey_path} -CAcreateserial -out ${cert_tmp_dir}/${user}.crt -days 36500
  ) 1>/dev/null 2>/dev/null
  mkdir -p "$(dirname ${kubeconfig_path})"
cat > ${kubeconfig_path} << EOF
apiVersion: v1
kind: Config
current-context: ${user}@kubernetes
clusters:
  - name: kubernetes
    cluster:
      certificate-authority-data: $(base64 -w0 < ${cacert_path})
      server: ${kubernetes_entrypoint}
contexts:
  - name: ${user}@kubernetes
    context:
      cluster: kubernetes
      user: ${user}
users:
  - name: ${user}
    user:
      client-certificate-data: $(base64 -w0 < ${cert_tmp_dir}/${user}.crt)
      client-key-data: $(base64 -w0 < ${cert_tmp_dir}/${user}.key)
EOF
}

ARCH=$(go env get GOARCH | xargs)
ETCD_VERSION="v3.5.0"
KUBE_VERSION="v1.21.4"
CERT_PATH=/etc/kubernetes/pki
APISERVER_ADDR=${APISERVER_ADDR:-'127.0.0.1'}
echo "install etcd and kube-apiserver on localhost"
install_etcd ${ETCD_VERSION}
install_kube_plugin ${KUBE_VERSION} kube-apiserver
install_kube_plugin ${KUBE_VERSION} kubectl
echo "start controlplane (etcd and apiserver)"
start_etcd
start_apiserver ${CERT_PATH} ${APISERVER_ADDR}
echo "generate kubeconfig for kubectl"

##                    cert path      user name   org name           kubeconfig save path   kube-apiserver address
generate_kubeconfig   ${CERT_PATH}   kubectl     "system:masters"   ~/.kube/config         ${APISERVER_ADDR}
